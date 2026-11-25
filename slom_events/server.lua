-- تهيئة جسر vRP 1 والخدمة المشتركة بين التابلت والجوال
local Tunnel = module("vrp", "lib/Tunnel")
local Proxy = module("vrp", "lib/Proxy")
local vRP = Proxy.getInterface("vRP")
local vRPclient = Tunnel.getInterface("vRP", GetCurrentResourceName())
local E = {vrp=vRP, client=vRPclient}
local R = 'slom_events:'

-- قاعدة البيانات وواجهات الإطار والتنبيهات وسجل ديسكورد
do
    local queue, sending = {}, false

    function E.logHook(category, message)
        local url = ServerConfig.Webhooks[category]
        if not url or url == '' then url = ServerConfig.Webhooks.Default end
        if url == '' or #queue >= ServerConfig.WebhookQueue then return end
        queue[#queue + 1] = { url = url, attempts = 0, body = json.encode({
            username = Config.Name, allowed_mentions = {parse = {}},
            embeds = {{title='سجل الفعاليات', description=message, color=8388640, timestamp=os.date('!%Y-%m-%dT%H:%M:%SZ')}}
        }) }
        if sending then return end
        sending = true
        local function send()
            local entry = queue[1]
            if not entry then sending = false return end
            entry.attempts = entry.attempts + 1
            PerformHttpRequest(entry.url, function(status, _, headers)
                status = tonumber(status) or 0
                local delay = ServerConfig.WebhookInterval
                if status == 429 and entry.attempts < 3 then
                    local retry = tonumber(headers and (headers['retry-after'] or headers['Retry-After'])) or 2
                    delay = math.max(delay, math.min(60000, retry * 1000))
                else
                    if status < 200 or status >= 300 then print('[slom_events] تعذر إرسال سجل ديسكورد (' .. status .. ')') end
                    table.remove(queue, 1)
                end
                SetTimeout(delay, send)
            end, 'POST', entry.body, {['Content-Type']='application/json'})
        end
        send()
    end

    function E.diagnostic(message, details)
        print('[slom_events] ' .. message)
        if ServerConfig.Debug and details then print(details) end
        E.logHook('System', message)
    end

    local function awaitSQL(run)
        local response = promise.new()
        local settled = false
        SetTimeout(10000, function()
            if settled then return end
            settled = true
            response:resolve(false)
        end)
        run(function(value)
            if settled then return end
            settled = true
            response:resolve(value or false)
        end)
        return Citizen.Await(response)
    end

    function E.persist(nextState)
        local affected = awaitSQL(function(callback)
            MySQL.Async.execute(
                'UPDATE slom_events_state SET payload=@payload, revision=revision+1 WHERE id=1 AND revision=@revision',
                {['@payload']=json.encode(nextState), ['@revision']=E.revision}, callback)
        end)
        if affected ~= 1 then
            E.ready = false
            E.diagnostic('توقف الحفظ. تحقق من اتصال قاعدة البيانات وأعد تشغيل المورد بعد المراجعة.')
            return false
        end
        E.state = nextState
        E.revision = E.revision + 1
        return true
    end

    function E.copy(value)
        if type(value) ~= 'table' then return value end
        local result = {}
        for key, child in pairs(value) do result[key] = E.copy(child) end
        return result
    end

    function E.uid(player)
        local id = player and E.vrp.getUserId({player})
        if type(id) == 'number' and id > 0 then return tostring(id) end
    end

    function E.source(id)
        local user = tonumber(id)
        if not user then return end
        local player = tonumber(E.vrp.getUserSource({user}))
        if player and E.uid(player) == id then return player end
    end

    function E.has(id, key)
        return id and E.vrp.hasPermission({tonumber(id), Server.Permissions[key]}) == true
    end

    function E.notify(player, message, kind)
        if Server.Notify.Adapter == 'pNotify' then
            TriggerClientEvent('pNotify:SendNotification', player, {type=kind or 'info', text=message:gsub('&','&amp;'):gsub('<','&lt;'):gsub('>','&gt;'), timeout=Server.Notify.Duration})
        else
            TriggerClientEvent('slom_events:notice', player, message)
        end
    end

    local function validConfig()
        local seen = {}
        for key, value in pairs(Server.Permissions) do
            if type(value) ~= 'string' or value == '' or seen[value] then return false end
            seen[value] = key
        end
        local defaults, limits = Server.Defaults, Server.Limits
        if defaults.minimum < 1 or defaults.maximum < defaults.minimum or defaults.maximum > limits.Participants
            or defaults.registration < 30 or defaults.registration > limits.Registration
            or defaults.duration < 10 or defaults.duration > limits.Duration or defaults.countdown < 1
            or defaults.countdown > 120 or Server.Progress.PerLevel < 1 or Server.Progress.SeasonDays < 1
            or Server.Progress.Daily < 1 or limits.Tick < 250 or #ServerConfig.Quiz == 0 then return false end
        local performance = Config.Performance
        if performance.LiveRefresh < 1500 or performance.TabletRequestCooldown < 100
            or performance.ControlCooldown < 100 or performance.IdleClient < 250 or performance.ActiveClient < 100 then
            return false
        end
        for _, question in ipairs(ServerConfig.Quiz) do
            if type(question.text) ~= 'string' or type(question.options) ~= 'table'
                or #question.options < 2 or not question.options[question.correct] then return false end
        end
        for key, item in pairs(Server.Store.Items) do
            if type(key) ~= 'string' or type(item.label) ~= 'string' or not math.tointeger(item.price)
                or item.price < 1 or not math.tointeger(item.stock) or item.stock < 1
                or not math.tointeger(item.limit) or item.limit < 1 then return false end
        end
        local schedules = {}
        for _, entry in ipairs(Server.Automatic.Entries) do
            if type(entry.key) ~= 'string' or schedules[entry.key] or not Server.Games[entry.mode]
                or entry.mode == 'manual' or not math.tointeger(entry.hour) or entry.hour < 0 or entry.hour > 23
                or not math.tointeger(entry.minute) or entry.minute < 0 or entry.minute > 59
                or not math.tointeger(entry.weekday) or entry.weekday < 0 or entry.weekday > 7
                or not math.tointeger(entry.online) or entry.online < 0 or type(entry.name) ~= 'string' then return false end
            schedules[entry.key] = true
        end
        return true
    end

    MySQL.ready(function()
        CreateThread(function()
            local valid, result = pcall(validConfig)
            if not valid or not result then E.diagnostic('إعدادات النظام غير صالحة.') return end
            local rows = awaitSQL(function(callback)
                MySQL.Async.fetchAll('SELECT revision,payload FROM slom_events_state WHERE id=1', {}, callback)
            end)
            local row = rows and rows[1]
            local ok, state = pcall(json.decode, row and row.payload or '')
            if not ok or type(state) ~= 'table' or state.version ~= 1 or not tonumber(row.revision) then
                E.diagnostic('تعذر تحميل البيانات. تحقق من تنفيذ install.sql.')
                return
            end
            state.templates = state.templates or {}
            state.news = state.news or {}
            E.revision = tonumber(row.revision)
            if state.created == 0 then
                state.created, state.automatic = os.time(), Server.Automatic.Enabled
                if not E.persist(state) then return end
            else
                E.state = state
            end
            E.ready = true
            E.diagnostic('نظام الفعاليات جاهز.')
        end)
    end)

    AddEventHandler('onResourceStop', function(resource)
        if resource == GetCurrentResourceName() then
            print('[slom_events] تم إيقاف الخدمة.')
        end
    end)
end

-- الأنماط اليدوية والقرعة والأسئلة
do
    E.games = {}

    E.games.manual = {
        resolve = function(event, eligible)
            for _, id in ipairs(eligible) do
                if id == event.selected then return id end
            end
        end
    }

    E.games.draw = {
        resolve = function(_, eligible)
            if #eligible > 0 then return eligible[math.random(#eligible)] end
        end
    }

    function E.question(event, now)
        if event.mode ~= 'quiz' or event.state ~= 'running' then return end
        return math.floor((now - event.started) * #ServerConfig.Quiz / event.duration) + 1
    end

    E.games.quiz = {
        answer = function(event, participant, data, now)
            local index = E.question(event, now)
            local question = ServerConfig.Quiz[index]
            local option = tonumber(data.option)
            participant.answers = participant.answers or {}
            if not question or tonumber(data.question) ~= index or participant.answers[tostring(index)]
                or not option or not question.options[option] then return false end
            participant.answers[tostring(index)] = option
            if option == question.correct then participant.score = (participant.score or 0) + 1 end
            return true
        end,
        resolve = function(event, eligible)
            local winner, best = nil, 0
            for _, id in ipairs(eligible) do
                local score = event.members[id].score or 0
                if score > best then winner, best = id, score end
            end
            return winner
        end
    }
end

-- دورة الفعالية والمشاركون والفرق والاقتصاد والجدولة والصلاحيات
do
    local permissions = {
        create='Create', clone='Create', saveTemplate='Create', useTemplate='Create', deleteTemplate='Delete', edit='Edit', publish='Edit', extend='Edit', lock='Edit', unlock='Edit', delete='Delete',
        start='Start', stop='Stop', cancel='Cancel', kick='Kick', move='ManageTeams', ban='Ban',
        winner='SetWinner', admit='ManagePlayers', announce='Announce', refund='Refund', schedule='Schedule',
        automatic='Automatic', review='Rewards'
    }
    E.permissions = permissions

    local function integer(value, minimum, maximum)
        if type(value) ~= 'number' and type(value) ~= 'string' then return nil end
        local number = math.tointeger(tonumber(value))
        if number and number >= minimum and number <= maximum then return number end
        return nil
    end

    local function short(value, size, required)
        if type(value) ~= 'string' or #value > size or not utf8.len(value) or value:find('%c') then return end
        value = value:match('^%s*(.-)%s*$')
        if required and value == '' then return end
        return value
    end

    local function isActive(event)
        return event.state == 'registration' or event.state == 'countdown' or event.state == 'running'
    end

    local function activeCount(state)
        local count = 0
        for _, event in pairs(state.events) do if isActive(event) then count = count + 1 end end
        return count
    end

    local function countMembers(event, status)
        local count = 0
        for _, member in pairs(event.members) do if member.status == status then count = count + 1 end end
        return count
    end
    E.countMembers = countMembers

    local function newProfile()
        return {xp=0, points=0, games=0, wins=0, streak=0, daily=0, weekly=0, seasonXP=0, titles={}}
    end
    E.newProfile = newProfile

    local function profile(state, id)
        state.players[id] = state.players[id] or newProfile()
        return state.players[id]
    end

    function E.periods(state, now)
        local offset = now + Server.Automatic.OffsetMinutes * 60
        return math.floor(offset / 86400), math.floor((offset + 3 * 86400) / 604800),
            math.floor((now - state.created) / (Server.Progress.SeasonDays * 86400)) + 1
    end

    local function eligible(event)
        local list = {}
        for id, member in pairs(event.members) do
            if member.status == 'joined' and E.source(id) then list[#list+1] = id end
        end
        table.sort(list, function(a,b)
            if event.members[a].order == event.members[b].order then return tonumber(a) < tonumber(b) end
            return event.members[a].order < event.members[b].order
        end)
        return list
    end

    function E.canSee(event, id, admin)
        if admin then return true end
        if event.state == 'draft' or (event.state == 'scheduled' and event.private) then return false end
        local allowed = not event.private or event.members[id] or event.invites[id]
        return allowed and (event.permission == '' or E.vrp.hasPermission({tonumber(id), event.permission}) == true)
    end

    local function audit(state, id, action, event, target)
        local log = { at=os.time(), actor=id, action=L.actions[action] or action, event=event and event.id,
            name=event and event.name, target=target }
        local player = id and E.source(id)
        if player then log.actorName = short(E.vrp.getPlayerName({player}), 100) end
        table.insert(state.logs, 1, log)
        while #state.logs > Server.Limits.Logs do table.remove(state.logs) end
        return log
    end

    local function ledger(state, key, id, event, reward)
        state.ledger[key] = {id=id, event=event.id, label=reward.label, kind=reward.kind,
            amount=reward.amount, item=reward.item, status='pending'}
    end

    local function refund(state, event, id)
        local member = event.members[id]
        if not member or not member.paid or member.refunded then return false end
        ledger(state, ('refund:%s:%s'):format(event.id, id), id, event,
            {label='استرداد رسوم المشاركة',kind='cash',amount=member.paid})
        member.refunded = true
        return true
    end

    local function finish(state, event, now, cancelled)
        event.finished = now
        event.state = cancelled and 'cancelled' or 'completed'
        event.deadline = nil
        if cancelled then
            for id in pairs(event.members) do refund(state,event,id) end
            return
        end
        local list = eligible(event)
        local winner = E.games[event.mode].resolve(event, list)
        event.winner = winner
        local day, week, season = E.periods(state, now)
        for _, id in ipairs(list) do
            local p = profile(state, id)
            if p.day ~= day then p.day, p.daily = day, 0 end
            if p.week ~= week then p.week, p.weekly = week, 0 end
            if p.season ~= season then
                p.archives = p.archives or {}
                if p.season then p.archives[tostring(p.season)] = p.seasonXP end
                p.season, p.seasonXP = season, 0
            end
            p.games, p.weekly = p.games + 1, p.weekly + 1
            p.daily = p.daily + 1
            local won = id == winner
            p.streak = won and p.streak + 1 or 0
            if won then p.wins = p.wins + 1 end
            if p.daily <= Server.Progress.Daily then
                local xp = Server.Progress.XP + (won and Server.Progress.WinXP or 0)
                p.xp, p.seasonXP = p.xp + xp, p.seasonXP + xp
                if won then p.points = p.points + Server.Progress.Points end
            end
        end
        if winner and event.prize.kind ~= 'none' then
            ledger(state, 'prize:' .. event.id, winner, event, event.prize)
        end
    end

    local function teamFor(event)
        if event.teams == 0 then return end
        local counts, best = {}, 1
        for i = 1, event.teams do counts[i] = 0 end
        for _, member in pairs(event.members) do
            if member.status == 'joined' and member.team then
                counts[member.team] = counts[member.team] + 1
            end
        end
        for i = 2, event.teams do if counts[i] < counts[best] then best = i end end
        return best
    end

    local function promote(event)
        if event.locked or event.fee > 0 or countMembers(event, 'joined') >= event.maximum then return end
        local candidate
        for id, member in pairs(event.members) do
            if member.status == 'wait' and E.source(id) and (not candidate or member.order < candidate.order) then
                candidate = member
            end
        end
        if candidate then
            candidate.team, candidate.status = teamFor(event), 'joined'
            return true
        end
    end

    local function form(data)
        local defaults = Server.Defaults
        local name = short(data.name, 90, true)
        local description = short(data.description or '', 320)
        local rules = short(data.rules or '', 320)
        local category = short(data.category or '', 65)
        local permission = short(data.permission or '', 80)
        local mode = type(data.mode) == 'string' and data.mode or 'manual'
        local minimum = integer(data.minimum or defaults.minimum, 1, Server.Limits.Participants)
        local maximum = integer(data.maximum or defaults.maximum, 1, Server.Limits.Participants)
        local registration = integer(data.registration or defaults.registration, 30, Server.Limits.Registration)
        local duration = integer(data.duration or defaults.duration, 10, Server.Limits.Duration)
        local countdown = integer(data.countdown or defaults.countdown, 1, 120)
        local fee = integer(data.fee or 0, 0, Server.Economy.Enabled and Server.Limits.Fee or 0)
        local teams = integer(data.teams or 0, 0, 8)
        local reward = Server.Economy.Rewards[data.reward or 'none']
        if not name or not description or not rules or not category or not permission or not Server.Games[mode]
            or not E.games[mode] or not minimum or not maximum or minimum > maximum or not registration
            or not duration or not countdown or not fee or not teams or teams == 1 or not reward
            or (mode == 'quiz' and duration < #ServerConfig.Quiz * 3) then return end
        if reward.kind ~= 'none' and (not Server.Economy.Enabled or not integer(reward.amount,1,Server.Economy.Max)
            or (reward.kind ~= 'cash' and reward.kind ~= 'bank' and reward.kind ~= 'item')
            or (reward.kind == 'item' and type(reward.item) ~= 'string')) then return end
        if permission ~= '' and not permission:match('^[%w_.%-]+$') then return end
        return {name=name, description=description, rules=rules, category=category, permission=permission,
            mode=mode, minimum=minimum, maximum=maximum, registration=registration, duration=duration,
            countdown=countdown, fee=fee, teams=teams, private=data.private == true,
            autostart=data.autostart == true, reward=data.reward or 'none', prize=E.copy(reward)}
    end

    local function insertEvent(state, options, now)
        local count = 0
        for _ in pairs(state.events) do count = count + 1 end
        if count >= Server.Limits.EventCount then return end
        state.nextEvent = state.nextEvent + 1
        local id = tostring(state.nextEvent)
        options.id, options.created, options.state = id, now, 'draft'
        options.members, options.invites, options.sequence = {}, {}, 0
        state.events[id] = options
        return options
    end

    local function recordNews(state, message, now)
        state.news = state.news or {}
        table.insert(state.news,1,{message=message,at=now})
        while #state.news > 50 do table.remove(state.news) end
    end

    local function announce(message)
        for _, sourceId in pairs(GetPlayers()) do
            local player = tonumber(sourceId)
            local id = E.uid(player)
            local p = id and E.state.players[id]
            if id and (not p or not p.muteAnnouncements) then E.notify(player,Config.Name .. ' | ' .. message) end
        end
    end

    local function openRegistration(event, now)
        event.state = 'registration'
        event.deadline = now + event.registration
    end

    local function initialized(id)
        return type(E.vrp.getUserDataTable({tonumber(id)})) == 'table'
            and type(E.vrp.getUserTmpTable({tonumber(id)})) == 'table'
    end

    local function canGrant(id, entry)
        if not Server.Economy.Enabled or not initialized(id) or not integer(entry.amount,1,Server.Economy.Max) then return false end
        if entry.kind == 'cash' or entry.kind == 'bank' then return true end
        if entry.kind ~= 'item' or type(entry.item) ~= 'string' then return false end
        local name = E.vrp.getItemDefinition({entry.item})
        local weight = E.vrp.getItemWeight({entry.item})
        local carried = E.vrp.getInventoryWeight({tonumber(id)})
        local capacity = E.vrp.getInventoryMaxWeight({tonumber(id)})
        return name and type(weight) == 'number' and weight >= 0 and type(carried) == 'number'
            and type(capacity) == 'number' and carried + entry.amount * weight <= capacity
    end

    local function claim(state, id, player, key)
        local entry = state.ledger[key]
        if not entry or entry.id ~= id or entry.kind == 'fee' then return false, L.invalid end
        if entry.status == 'applying' then return false, L.review end
        if entry.status ~= 'pending' then return false, L.invalid end
        if not canGrant(id, entry) then return false, L.space end
        entry.status = 'applying'
        if not E.persist(state) then return false, L.offline end
        local final = E.copy(E.state)
        entry = final.ledger[key]
        if E.uid(player) ~= id or not canGrant(id, entry) then
            entry.status = 'pending'
            E.persist(final)
            return false, L.space
        end
        if entry.kind == 'cash' then E.vrp.giveMoney({tonumber(id),entry.amount})
        elseif entry.kind == 'bank' then E.vrp.giveBankMoney({tonumber(id),entry.amount})
        else E.vrp.giveInventoryItem({tonumber(id),entry.item,entry.amount,true}) end
        entry.status = 'done'
        return final
    end

    local function charge(state, event, id, player, member)
        local key = ('fee:%s:%s'):format(event.id, id)
        if state.ledger[key] or not initialized(id) then return false, L.review end
        if (tonumber(E.vrp.getMoney({tonumber(id)})) or 0) < event.fee then return false, L.poor end
        local reserved = E.copy(E.state)
        ledger(reserved, key, id, event, {label='رسوم المشاركة',amount=event.fee,kind='fee'})
        reserved.ledger[key].status = 'applying'
        if not E.persist(reserved) then return false, L.offline end
        if E.uid(player) ~= id or os.time() >= event.deadline or not initialized(id)
            or not E.vrp.tryPayment({tonumber(id),event.fee}) then
            local final = E.copy(E.state)
            final.ledger[key] = nil
            E.persist(final)
            return false, L.poor
        end
        state.ledger[key] = E.copy(reserved.ledger[key])
        state.ledger[key].status = 'done'
        member.paid = event.fee
        return true
    end

    local function apply(state, action, data, player, id, now)
        local event = state.events[tostring(integer(data.event, 1, 2147483647))]
        local target = tostring(integer(data.target, 1, 2147483647))
        local member = event and event.members[id]
        local message, broadcast, recipient, notifyMessage
        if action == 'create' or action == 'clone' then
            local options
            if action == 'create' then options = form(data)
            elseif event then options = form(event) end
            if not options then return false, L.invalid end
            event = insertEvent(state, options, now)
            if not event then return false, L.invalid end
        elseif action == 'saveTemplate' then
            if not event then return false,L.invalid end
            local name = short(data.label,90,true)
            local options = form(event)
            if not name or not options then return false,L.invalid end
            local count = 0
            for _ in pairs(state.templates) do count = count + 1 end
            if count >= Server.Limits.Templates then return false,L.invalid end
            local key = tostring(state.nextTemplate or 1)
            state.nextTemplate = tonumber(key) + 1
            state.templates[key] = {label=name,options=options}
        elseif action == 'useTemplate' or action == 'deleteTemplate' then
            local key = short(data.key,12)
            local template = key and state.templates[key]
            if not template then return false,L.invalid end
            if action == 'deleteTemplate' then
                state.templates[key] = nil
            else
                local options = form(template.options)
                if not options then return false,L.invalid end
                event = insertEvent(state,options,now)
                if not event then return false,L.invalid end
            end
        elseif action == 'preferences' then
            if type(data.mute) ~= 'boolean' then return false,L.invalid end
            profile(state,id).muteAnnouncements = data.mute
        elseif action == 'automatic' then
            state.automatic = not state.automatic
        elseif action == 'claim' then
            local result, errorMessage = claim(state,id,player,short(data.key,70))
            if not result then return false,errorMessage end
            state = result
        elseif action == 'review' then
            local entry = state.ledger[short(data.key,70) or '']
            if not entry or entry.status ~= 'applying' then return false,L.invalid end
            if entry.kind == 'fee' then
                if data.outcome == 'charged' then
                    local linked = state.events[entry.event]
                    if not linked then return false,L.invalid end
                    ledger(state, 'review:' .. entry.event .. ':' .. entry.id, entry.id, linked,
                        {label='استرداد رسوم بعد المراجعة',kind='cash',amount=entry.amount})
                    entry.status = 'done'
                elseif data.outcome == 'clear' then
                    state.ledger[data.key] = nil
                else return false,L.invalid end
            elseif data.outcome == 'done' then entry.status = 'done'
            elseif data.outcome == 'clear' then entry.status = 'pending'
            else return false,L.invalid end
        elseif action == 'buy' then
            local key = short(data.key,40)
            local item = key and Server.Store.Enabled and Server.Store.Items[key]
            local p = profile(state,id)
            local day = E.periods(state,now)
            local stock = key and (state.purchases[key] or {count=0})
            if not item or p.points < item.price or p.titles[key] or stock.count >= item.stock then return false,L.invalid end
            p.bought = p.bought or {}
            local purchase = p.bought[key]
            if purchase and purchase.day == day and purchase.count >= item.limit then return false,L.invalid end
            p.bought[key] = {day=day,count=(purchase and purchase.day == day and purchase.count or 0)+1,at=now,price=item.price}
            p.points, p.titles[key] = p.points-item.price, item.label
            stock.count = stock.count + 1
            state.purchases[key] = stock
        elseif action == 'ban' then
            local hours = integer(data.hours,0,720)
            if target == 'nil' or not hours then return false,L.invalid end
            profile(state,target).ban = hours > 0 and now + hours*3600 or nil
            if hours > 0 then
                for _, other in pairs(state.events) do
                    local participant = other.members[target]
                    if isActive(other) and participant and (participant.status == 'joined' or participant.status == 'wait') then
                        participant.status = 'kicked'
                        refund(state,other,target)
                        if other.state == 'registration' then promote(other) end
                    end
                end
            end
        elseif not event or (not permissions[action] and not E.canSee(event,id,false)) then
            return false,L.invalid
        elseif action == 'edit' and event.state == 'draft' then
            local options = form(data)
            if not options then return false,L.invalid end
            for key,value in pairs(options) do event[key] = value end
        elseif action == 'delete' and (event.state == 'draft' or event.state == 'scheduled') then
            state.events[event.id] = nil
        elseif action == 'schedule' and (event.state == 'draft' or event.state == 'scheduled') then
            local minutes = integer(data.minutes,1,43200)
            if not minutes then return false,L.invalid end
            event.scheduled, event.state = now + minutes*60, 'scheduled'
        elseif action == 'publish' and (event.state == 'draft' or event.state == 'scheduled') then
            if activeCount(state) >= Server.Limits.Concurrent then return false,L.invalid end
            openRegistration(event,now)
            if not event.private and event.permission == '' then broadcast = 'فتح التسجيل: ' .. event.name end
        elseif action == 'start' and event.state == 'registration' and now < event.deadline then
            if #eligible(event) < event.minimum then return false,L.invalid end
            event.state, event.deadline = 'countdown', now + event.countdown
        elseif action == 'stop' and event.state == 'running' then
            finish(state,event,now,false)
        elseif action == 'cancel' and (isActive(event) or event.state == 'scheduled') then
            finish(state,event,now,true)
        elseif action == 'lock' and event.state == 'registration' and not event.locked and now < event.deadline then
            event.locked = true
        elseif action == 'unlock' and event.state == 'registration' and event.locked and now < event.deadline then
            event.locked = nil
            for _ = 1, event.maximum do
                if not promote(event) then break end
            end
        elseif action == 'extend' and event.state == 'registration' then
            local minutes = integer(data.minutes,1,120)
            if not minutes then return false,L.invalid end
            event.deadline = math.min(math.max(now,event.deadline)+minutes*60,now+Server.Limits.Registration)
        elseif action == 'announce' and isActive(event) and not event.private and event.permission == '' then
            broadcast = 'فعالية: ' .. event.name
        elseif action == 'join' and event.state == 'registration' and not event.locked and now < event.deadline then
            if (state.players[id] and (state.players[id].ban or 0) > now) or (member and member.status == 'kicked') then return false,L.blocked end
            if member and (member.status == 'joined' or member.status == 'wait' or member.paid) then return false,L.invalid end
            for _, other in pairs(state.events) do
                local participation = other.members[id]
                if isActive(other) and participation and (participation.status == 'joined' or participation.status == 'wait') then return false,L.invalid end
            end
            if not member then
                local accounts = 0
                for _ in pairs(event.members) do accounts = accounts + 1 end
                if accounts >= Server.Limits.EventAccounts then return false,L.invalid end
            end
            local full = countMembers(event,'joined') >= event.maximum
            if full and (event.fee > 0 or countMembers(event,'wait') >= Server.Limits.Waiting) then return false,L.invalid end
            event.sequence = event.sequence + 1
            member = {status=full and 'wait' or 'joined', order=event.sequence, name=short(E.vrp.getPlayerName({player}),100) or id}
            if event.fee > 0 then
                local paid, errorMessage = charge(state,event,id,player,member)
                if not paid then return false,errorMessage end
            end
            if not full then member.team = teamFor(event) end
            event.members[id] = member
            message = full and L.waiting or L.joined
        elseif action == 'promote' and event.state == 'registration' and not event.locked and now < event.deadline
            and member and member.status == 'wait' and countMembers(event,'joined') < event.maximum then
            promote(event)
        elseif action == 'leave' and isActive(event) and member and (member.status == 'joined' or member.status == 'wait') then
            member.status = 'left'
            if event.state == 'registration' then refund(state,event,id) promote(event) end
        elseif (action == 'invite' or action == 'admit') and event.state == 'registration'
            and (action == 'admit' or (member and member.status == 'joined')) then
            local invited = E.source(target)
            if not invited or target == id or event.invites[target]
                or (event.permission ~= '' and not E.vrp.hasPermission({tonumber(target),event.permission})) then return false,L.invalid end
            local invitations = 0
            for _ in pairs(event.invites) do invitations = invitations + 1 end
            if invitations >= Server.Limits.EventAccounts then return false,L.invalid end
            event.invites[target] = true
            recipient, notifyMessage = target, 'دعوة للمشاركة في ' .. event.name
        elseif (action == 'team' or action == 'move') and event.state == 'registration' then
            local selected = action == 'team' and member or event.members[target]
            local team = integer(data.team,1,event.teams)
            if not selected or selected.status ~= 'joined' or not team then return false,L.invalid end
            local count, cap = 0, math.ceil(event.maximum / event.teams)
            for _, candidate in pairs(event.members) do
                if candidate ~= selected and candidate.status == 'joined' and candidate.team == team then count = count + 1 end
            end
            if count >= cap then return false,L.invalid end
            selected.team = team
        elseif action == 'kick' and isActive(event) and event.members[target]
            and (event.members[target].status == 'joined' or event.members[target].status == 'wait') then
            event.members[target].status = 'kicked'
            refund(state,event,target)
            recipient, notifyMessage = target, 'تم استبعادك من ' .. event.name
            if event.state == 'registration' then promote(event) end
        elseif action == 'refund' and event.state ~= 'draft' and event.state ~= 'scheduled' then
            if not refund(state,event,target) then return false,L.invalid end
        elseif action == 'winner' and event.state == 'running' and event.mode == 'manual'
            and event.members[target] and event.members[target].status == 'joined' and E.source(target) then
            event.selected = target
        elseif action == 'answer' and event.state == 'running' and now < event.deadline and member and member.status == 'joined' then
            local game = E.games[event.mode]
            if not game.answer or not game.answer(event,member,data,now) then return false,L.invalid end
        else
            return false,L.invalid
        end
        if broadcast then recordNews(state,broadcast,now) end
        local log
        if action ~= 'answer' and action ~= 'preferences' then log = audit(state,id,action,event,target ~= 'nil' and target or nil) end
        return state,message or L.ok,broadcast,recipient,notifyMessage,log
    end

    local dispatcherBusy = false
    local rate = {}
    AddEventHandler('playerDropped', function() rate[source] = nil end)

    function E.perform(player, action, data)
        if not E.ready then return false,L.offline end
        if type(action) ~= 'string' or #action > 24 or type(data) ~= 'table' then return false,L.invalid end
        local id = E.uid(player)
        if not id then return false,L.denied end
        if dispatcherBusy then return false,L.busy end
        local time = GetGameTimer()
        local entry = rate[player] or {all=-100000,actions={}}
        local previous = entry.actions[action]
        if time - entry.all < Server.Limits.Cooldown or (previous and time - previous < Server.Limits.ActionCooldown) then return false,L.busy end
        entry.all = time
        if permissions[action] or L.actions[action] then entry.actions[action] = time end
        rate[player] = entry
        if permissions[action] and (not E.has(id,'OpenAdmin') or not E.has(id,permissions[action])) then
            E.logHook('Security','رفض إجراء إداري للحساب ' .. id)
            return false,L.denied
        end
        dispatcherBusy = true
        local ok, success, message = xpcall(function()
            local state, result, broadcast, recipient, notifyMessage, log = apply(E.copy(E.state),action,data,player,id,os.time())
            if not state then return false,result end
            if not E.persist(state) then return false,L.offline end
            if broadcast then announce(broadcast) end
            local target = recipient and E.source(recipient)
            if target then E.notify(target,notifyMessage) end
            if log then
                local category = (action == 'claim' or action == 'refund' or action == 'buy' or action == 'review') and 'Economy'
                    or ((action == 'join' or action == 'leave' or action == 'kick' or action == 'move' or action == 'team' or action == 'invite' or action == 'ban') and 'Participants' or 'Lifecycle')
                E.logHook(category, ('%s | %s (%s) | %s | %s | %s'):format(log.action,log.actorName or 'لاعب',id,
                    log.event or '—',log.name or '—',log.target or '—'))
            end
            return true,result
        end,debug.traceback)
        dispatcherBusy = false
        if not ok then E.diagnostic('خطأ في تنفيذ إجراء.',success) return false,L.offline end
        return success,message
    end

    local nextScheduleCheck = 0
    local function tick()
        local now = os.time()
        local checkSchedule = E.state.automatic and now >= nextScheduleCheck
        if checkSchedule then nextScheduleCheck = now + 10 end
        local needed = checkSchedule
        for _, event in pairs(E.state.events) do
            if (event.deadline and event.deadline <= now) or (event.state == 'scheduled' and event.scheduled <= now) then
                needed = true
                break
            end
        end
        if not needed then return end
        local state, changed, news, results = E.copy(E.state), false, {}, {}
        for _, event in pairs(state.events) do
            if event.deadline and event.deadline <= now then
                if event.state == 'registration' then
                    if event.autostart and #eligible(event) >= event.minimum then
                        event.state,event.deadline = 'countdown', now+event.countdown
                    else
                        finish(state,event,now,true)
                        audit(state,nil,'cancel',event)
                    end
                    changed = true
                elseif event.state == 'countdown' then
                    if #eligible(event) >= event.minimum then
                        event.state,event.started,event.deadline = 'running',now,now+event.duration
                    else finish(state,event,now,true) audit(state,nil,'cancel',event) end
                    changed = true
                elseif event.state == 'running' then
                    finish(state,event,now,false)
                    audit(state,nil,'stop',event)
                    results[#results+1] = event
                    changed = true
                end
            elseif event.state == 'scheduled' and event.scheduled <= now and activeCount(state) < Server.Limits.Concurrent then
                openRegistration(event,now)
                if not event.private and event.permission == '' then news[#news+1] = 'فتح التسجيل: ' .. event.name end
                audit(state,nil,'publish',event)
                changed = true
            end
        end
        if checkSchedule then
            local clock = os.date('!*t',now+Server.Automatic.OffsetMinutes*60)
            local day = E.periods(state,now)
            for _, schedule in ipairs(Server.Automatic.Entries) do
                if clock.hour == schedule.hour and clock.min == schedule.minute and
                    (schedule.weekday == 0 or schedule.weekday == clock.wday) and state.schedules[schedule.key] ~= day
                    and #GetPlayers() >= schedule.online and activeCount(state) < Server.Limits.Concurrent then
                    local event = insertEvent(state,form({name=schedule.name,mode=schedule.mode,autostart=true}),now)
                    if event then
                        openRegistration(event,now)
                        state.schedules[schedule.key] = day
                        audit(state,nil,'publish',event)
                        news[#news+1] = 'فتح التسجيل: ' .. event.name
                        changed = true
                    end
                end
            end
        end
        for _, message in ipairs(news) do recordNews(state,message,now) end
        if changed and E.persist(state) then
            for _, message in ipairs(news) do announce(message) end
            for _, event in ipairs(results) do
                local winner = event.winner and E.source(event.winner)
                if winner then E.notify(winner,'فزت في ' .. event.name,'success') end
            end
        end
    end

    CreateThread(function()
        while true do
            Wait(Server.Limits.Tick)
            if E.ready and not dispatcherBusy then
                dispatcherBusy = true
                local ok, err = xpcall(tick,debug.traceback)
                dispatcherBusy = false
                if not ok then E.diagnostic('تعذر تحديث الفعاليات المجدولة.',err) end
            end
            if E.pushHud then E.pushHud() end
        end
    end)
end

-- طلبات التابلت والأوامر ومؤشر الفعالية
do
    local viewRate, controlRate = {}, {}
    local hud = {}

    function E.tabletAllowed(id, mode)
        if not Config.Tablet.Enabled or not id then return false end
        if mode == 'admin' then return Config.Tablet.AdminAccess and E.has(id,'OpenAdmin') end
        return mode == 'player' and Config.Tablet.PlayerAccess
    end

    function E.tabletOpen(player, mode)
        if E.tabletAllowed(E.uid(player),mode) then
            TriggerClientEvent(R .. 'openTablet',player,mode)
        else
            E.notify(player,L.denied,'error')
        end
    end

    function E.view(id, admin)
        local state, now = E.state, os.time()
        local all, rewards, market, ranking, reviews = {}, {}, {}, {}, {}
        local day, week, season = E.periods(state,now)
        local p = E.copy(state.players[id] or E.newProfile())
        p.level = math.floor(p.xp / Server.Progress.PerLevel) + 1
        p.daily = p.day == day and p.daily or 0
        p.weekly = p.week == week and p.weekly or 0
        if p.season and p.season ~= season then
            p.archives = p.archives or {}
            p.archives[tostring(p.season)] = p.seasonXP
            p.seasonXP = 0
        end
        p.badges = {}
        if p.games > 0 then p.badges[#p.badges+1] = 'أول مشاركة' end
        if p.wins > 0 then p.badges[#p.badges+1] = 'أول فوز' end
        if p.streak >= 3 then p.badges[#p.badges+1] = 'ثلاثة انتصارات متتالية' end
        p.dailyGoal, p.weeklyGoal = Server.Progress.DailyGoal, Server.Progress.WeeklyGoal
        p.ban, p.day, p.week = nil, nil, nil

        for _, event in pairs(state.events) do
            if E.canSee(event,id,admin) then
                local item = {
                    id=event.id, name=event.name, description=event.description, category=event.category, rules=event.rules,
                    state=event.state, mode=event.mode, count=E.countMembers(event,'joined'), maximum=event.maximum,
                    minimum=event.minimum, fee=event.fee, teams=event.teams, deadline=event.deadline,
                    scheduled=event.scheduled, locked=event.locked, winner=event.winner, prize=event.prize.label, actions={}
                }
                local member = event.members[id]
                item.status = member and member.status
                local function action(name, condition)
                    if condition and (not E.permissions[name] or (admin and E.has(id,E.permissions[name]))) then
                        item.actions[#item.actions+1] = name
                    end
                end
                local joined = member and member.status == 'joined'
                local open = event.state == 'registration'
                local running = event.state == 'running'
                local active = open or running or event.state == 'countdown'
                local draft = event.state == 'draft'
                local scheduled = event.state == 'scheduled'
                if not admin then
                    action('join',open and not event.locked and now < event.deadline and (not member or (member.status=='left' and not member.paid)))
                    action('promote',open and not event.locked and member and member.status == 'wait' and item.count < event.maximum)
                    action('leave',active and member and (joined or member.status == 'wait'))
                    action('invite',open and joined)
                    action('team',open and joined and event.teams > 0)
                    local questionIndex = running and E.question(event,now)
                    if joined and questionIndex and ServerConfig.Quiz[questionIndex] and
                        not (member.answers and member.answers[tostring(questionIndex)]) then
                        local question = ServerConfig.Quiz[questionIndex]
                        item.question = {index=questionIndex,text=question.text,options=question.options}
                    end
                    item.score = member and member.score
                else
                    action('edit',draft)
                    action('delete',draft or scheduled)
                    action('publish',draft or scheduled)
                    action('schedule',draft or scheduled)
                    action('clone',true)
                    action('saveTemplate',true)
                    action('start',open)
                    action('stop',running)
                    action('cancel',active or scheduled)
                    action('extend',open)
                    action('lock',open and not event.locked and now < event.deadline)
                    action('unlock',open and event.locked and now < event.deadline)
                    action('announce',active and not event.private and event.permission == '')
                    action('admit',open)
                    if draft and E.has(id,'Edit') then
                        item.form = {name=event.name, description=event.description, rules=event.rules, category=event.category,
                            mode=event.mode, minimum=event.minimum, maximum=event.maximum, registration=event.registration,
                            duration=event.duration, countdown=event.countdown, fee=event.fee, teams=event.teams,
                            permission=event.permission, private=event.private, autostart=event.autostart, reward=event.reward}
                    end
                    if E.has(id,'ManagePlayers') then
                        item.members = {}
                        for target, participant in pairs(event.members) do
                            local allowed = {}
                            if active and (participant.status == 'joined' or participant.status == 'wait') and E.has(id,'Kick') then allowed[#allowed+1] = 'kick' end
                            if open and participant.status == 'joined' and event.teams > 0 and E.has(id,'ManageTeams') then allowed[#allowed+1] = 'move' end
                            if running and participant.status == 'joined' and event.mode == 'manual' and E.has(id,'SetWinner') then allowed[#allowed+1] = 'winner' end
                            if participant.paid and not participant.refunded and E.has(id,'Refund') then allowed[#allowed+1] = 'refund' end
                            item.members[#item.members+1] = {id=target,name=participant.name,status=participant.status,
                                team=participant.team,score=participant.score,actions=allowed}
                        end
                        table.sort(item.members,function(a,b) return tonumber(a.id)<tonumber(b.id) end)
                    end
                end
                all[#all+1] = item
            end
        end
        table.sort(all,function(a,b) return tonumber(a.id)>tonumber(b.id) end)
        for key, reward in pairs(state.ledger) do
            if reward.id == id and reward.kind ~= 'fee' then
                rewards[#rewards+1] = {key=key,event=reward.event,label=reward.label,status=reward.status,amount=reward.amount}
            end
            if admin and E.has(id,'Rewards') and reward.status == 'applying' then
                reviews[#reviews+1] = {key=key,event=reward.event,label=reward.label,id=reward.id,amount=reward.amount,kind=reward.kind}
            end
        end
        for key, item in pairs(Server.Store.Enabled and Server.Store.Items or {}) do
            market[#market+1] = {key=key,label=item.label,price=item.price,stock=item.stock-(state.purchases[key] or {count=0}).count,
                owned=p.titles[key] ~= nil}
        end
        for user, other in pairs(state.players) do
            if other.games > 0 then ranking[#ranking+1] = {id=user,xp=other.xp,wins=other.wins,seasonXP=other.season == season and other.seasonXP or 0} end
        end
        table.sort(ranking,function(a,b)
            if a.seasonXP ~= b.seasonXP then return a.seasonXP>b.seasonXP end
            if a.xp ~= b.xp then return a.xp>b.xp end
            return tonumber(a.id)<tonumber(b.id)
        end)
        local leaders = {}
        if Config.Pages.leaders then
            leaders = E.copy(ranking)
            table.sort(leaders,function(a,b)
                if a.xp ~= b.xp then return a.xp>b.xp end
                if a.wins ~= b.wins then return a.wins>b.wins end
                return tonumber(a.id)<tonumber(b.id)
            end)
            while #leaders > 100 do table.remove(leaders) end
        end
        while #ranking > 100 do table.remove(ranking) end
        local page = {}
        for key,value in pairs(Config.Pages) do page[key] = value end
        page.create = page.create and admin and E.has(id,'Create')
        page.manage = page.manage and admin
        page.participants = page.participants and admin and E.has(id,'ManagePlayers')
        page.teams = page.teams and admin and E.has(id,'ManagePlayers') and E.has(id,'ManageTeams')
        page.schedule = page.schedule and admin and (E.has(id,'Schedule') or E.has(id,'Automatic'))
        page.templates = page.templates and admin and (E.has(id,'Create') or E.has(id,'Delete'))
        page.logs = page.logs and admin and E.has(id,'Logs')
        page.system = page.system and admin and E.has(id,'Diagnostics')
        local modes, prizes = {}, {}
        for key,value in pairs(Server.Games) do if value then modes[key] = L.mode[key] end end
        for key,value in pairs(Server.Economy.Rewards) do
            if key == 'none' or Server.Economy.Enabled then prizes[key] = value.label end
        end
        local templates, schedules = {}, {}
        if page.templates then
            for key, template in pairs(state.templates) do
                templates[#templates+1] = {key=key,label=template.label,name=template.options.name,mode=template.options.mode}
            end
        end
        if page.schedule then
            for _, entry in ipairs(Server.Automatic.Entries) do
                schedules[#schedules+1] = {name=entry.name,hour=entry.hour,minute=entry.minute,
                    weekday=entry.weekday,online=entry.online,mode=entry.mode}
            end
        end
        return {leaders=leaders,news=page.announcements and state.news or {},templates=templates,schedules=schedules, scheduleOffset=page.schedule and Server.Automatic.OffsetMinutes,
            useTemplate=page.templates and E.has(id,'Create'),deleteTemplate=page.templates and E.has(id,'Delete'),events=all,profile=p,rewards=rewards,market=market,ranking=ranking,reviews=reviews,pages=page,
            logs=page.logs and state.logs or {}, system=page.system and {revision=E.revision,automatic=state.automatic} or nil,
            controlAutomatic=admin and E.has(id,'Automatic'), automatic=admin and E.has(id,'Automatic') and state.automatic,
            controlBan=admin and E.has(id,'Ban'), defaults=Server.Defaults, modes=modes, prizes=prizes,
            states=L.state, statuses=L.status, actions=L.actions, name=Config.Name,
            logo=Config.Logo:match('^[%w_.%-]+$') and Config.Logo or '', credit=Config.Credit,
            economy=Server.Economy.Enabled, colors=Config.Colors, refresh=Config.Performance.LiveRefresh, animations=Config.Tablet.Animations, now=now, season=season, admin=admin,
            otherTablet=E.tabletAllowed(id,admin and 'player' or 'admin')}
    end

    RegisterNetEvent(R .. 'rpc',function(token,mode,action,data)
        local player = source
        if type(token) ~= 'number' or token < 1 or token > 2147483647 or token%1 ~= 0 then return end
        local id = E.uid(player)
        if not id then return end
        local now = GetGameTimer()
        if viewRate[player] and now-viewRate[player] < Config.Performance.TabletRequestCooldown then
            TriggerClientEvent(R .. 'result',player,token,false,L.busy)
            return
        end
        viewRate[player] = now
        local ok, message, view
        if not E.tabletAllowed(id,mode) then
            TriggerClientEvent(R .. 'forceClose',player)
            ok,message = false,L.denied
        elseif not E.ready then ok,message = false,L.offline
        elseif action == 'view' then ok = true
        elseif mode ~= 'admin' and type(action) == 'string' and E.permissions[action] then ok,message = false,L.denied
        else ok,message = E.perform(player,action,data) end
        if id ~= E.uid(player) then return end
        if ok and E.ready and E.tabletAllowed(id,mode) then
            local built,result = pcall(E.view,id,mode == 'admin')
            if built then view = result else E.diagnostic('تعذر إنشاء بيانات الواجهة.',result) ok,message = false,L.offline end
        end
        TriggerClientEvent(R .. 'result',player,token,ok == true,message,view)
    end)

    local function registerTabletCommand(command, mode)
        RegisterCommand(command,function(player)
            if player > 0 then E.tabletOpen(player,mode) end
        end,false)
    end
    registerTabletCommand(Config.Tablet.Command,'player')
    registerTabletCommand(Config.Tablet.AdminCommand,'admin')
    local function canControl(player)
        local now = GetGameTimer()
        if controlRate[player] and now - controlRate[player] < Config.Performance.ControlCooldown then return false end
        controlRate[player] = now
        return true
    end
    RegisterNetEvent(R .. 'switchTablet',function(mode)
        if not canControl(source) then return end
        if mode == 'player' then E.tabletOpen(source,'admin')
        elseif mode == 'admin' then E.tabletOpen(source,'player') end
    end)
    RegisterNetEvent(R .. 'settingsRequest',function()
        if not canControl(source) then return end
        TriggerClientEvent(R .. 'settings',source,Config.Tablet.Command,Config.Tablet.Key,Config.Tablet.CloseOnDeath,
            Config.Performance.IdleClient,Config.Performance.ActiveClient)
    end)

    RegisterCommand(Config.Tablet.DiagnosticsCommand,function(player)
        local message = ('الخدمة: %s | قاعدة البيانات: %s'):format(GetCurrentResourceName(),E.ready and 'متصلة' or 'غير متاحة')
        if player == 0 then print(message) return end
        local id = E.uid(player)
        if E.has(id,'OpenAdmin') and E.has(id,'Diagnostics') then E.notify(player,message) end
    end,false)

    function E.pushHud()
        local nextHud = {}
        if Config.Tablet.Hud and E.ready then
            for _, event in pairs(E.state.events) do
                if event.state == 'countdown' or event.state == 'running' then
                    local count = E.countMembers(event,'joined')
                    for id, member in pairs(event.members) do
                        local player = member.status == 'joined' and E.source(id)
                        if player then
                            nextHud[player] = id
                            local seconds = math.max(0,event.deadline-os.time())
                            TriggerClientEvent(R .. 'hud',player,{name=event.name,state=L.state[event.state],
                                seconds=seconds,score=member.score or 0,team=member.team,
                                count=count})
                        end
                    end
                end
            end
        end
        for player,id in pairs(hud) do
            if not nextHud[player] and E.uid(player) == id then TriggerClientEvent(R .. 'hud',player,false) end
        end
        hud = nextHud
    end

    AddEventHandler('playerDropped',function()
        viewRate[source],hud[source],controlRate[source] = nil,nil,nil
    end)
end

-- قوائم جوال vRP الأصلية
do
    local openRoot, openEvent
    local resource = GetCurrentResourceName()
    local handingOff = {}
    local function escape(value)
        return tostring(value or ''):gsub('&','&amp;'):gsub('<','&lt;'):gsub('>','&gt;'):gsub('"','&quot;'):gsub("'",'&#39;')
    end

    local function permitted(player,id,admin)
        return Config.Phone.Enabled and E.uid(player) == id and
            ((admin and Config.Phone.AdminEnabled and E.has(id,'OpenAdmin'))
            or (not admin and Config.Phone.PlayerEnabled))
    end

    local function menuFor(player,id,admin,key,title,back,build)
        if not id or not permitted(player,id,admin) then return end
        if not E.ready then E.notify(player,L.offline,'error') return end
        vRP.buildMenu({key,{player=player},function(menu)
            if not E.ready or not permitted(player,id,admin) then return end
            local ok, err = pcall(function()
                local view = E.view(id,admin)
                menu.name = escape(title)
                menu.css = {top=Config.Phone.Position,header_color=Config.Phone.Color}
                menu.onclose = function(closing)
                    if handingOff[closing] then handingOff[closing] = nil return end
                    if E.uid(closing) == id then back(closing) end
                end
                menu['↩ رجوع'] = {function(current)
                    if E.uid(current) == id then back(current) end
                end,'العودة إلى القائمة السابقة'}
                build(menu,view)
                vRP.openMenu({player,menu})
            end)
            if not ok then E.diagnostic('تعذر فتح قائمة الجوال.',err) end
        end})
    end

    local function operation(player,id,admin,action,data,fields,confirm,after)
        if not permitted(player,id,admin) then return end
        local function submit()
            if not permitted(player,id,admin) then return end
            local ok,message = E.perform(player,action,data)
            if E.uid(player) ~= id then return end
            E.notify(player,message,ok and 'success' or 'error')
            if after then after(player) end
        end
        local function collect(index)
            if not permitted(player,id,admin) then return end
            local field = fields and fields[index]
            if field then
                vRP.prompt({player,field[2],field[3] == 'flag' and (data[field[1]] and '1' or '0') or tostring(data[field[1]] or ''),function(who,value)
                    if who ~= player or not permitted(who,id,admin) or type(value) ~= 'string' then return end
                    if field[3] == 'flag' then data[field[1]] = value == '1' else data[field[1]] = value end
                    collect(index+1)
                end})
            elseif confirm then
                vRP.request({player,'تأكيد: ' .. L.actions[action] .. '؟',20,function(who,accepted)
                    if who == player and accepted then submit() end
                end})
            else submit() end
        end
        collect(1)
    end

    local actionFields = {
        saveTemplate={{'label','اسم القالب'}},
        schedule={{'minutes','الوقت حتى فتح التسجيل بالدقائق'}}, extend={{'minutes','دقائق التمديد'}},
        invite={{'target','رقم حساب اللاعب'}}, admit={{'target','رقم حساب اللاعب'}},
        team={{'team','رقم الفريق'}}, move={{'team','رقم الفريق'}},
        ban={{'target','رقم حساب اللاعب'},{'hours','مدة التقييد بالساعات، 0 للإزالة'}},
        review={{'outcome','done = تم التسليم، charged = تم الخصم، clear = لم ينفذ'}}
    }
    local confirm = {delete=true,stop=true,cancel=true,kick=true,refund=true,claim=true,buy=true,ban=true,review=true,automatic=true}
    local function eventFields(view)
        local modes,prizes = {},{}
        for key,label in pairs(view.modes) do modes[#modes+1] = key .. ' = ' .. label end
        for key,label in pairs(view.prizes) do prizes[#prizes+1] = key .. ' = ' .. label end
        local fields = {{'name','اسم الفعالية'}, {'description','الوصف'}, {'rules','شروط وقواعد المشاركة'},
            {'category','التصنيف'}, {'mode',table.concat(modes,'، ')}, {'minimum','الحد الأدنى للمشاركين'},
            {'maximum','الحد الأقصى للمشاركين'}, {'registration','مدة التسجيل بالثواني'},
            {'duration','مدة اللعب بالثواني'}, {'countdown','مدة العد التنازلي بالثواني'},
            {'teams','عدد الفرق، 0 لتعطيل الفرق'}, {'permission','صلاحية المشاركة، اتركها فارغة للجميع'},
            {'private','خاصة بالدعوات؟ 1 نعم، 0 لا','flag'}, {'autostart','تشغيل تلقائي؟ 1 نعم، 0 لا','flag'}}
        if view.economy then
            fields[#fields+1] = {'fee','الرسوم النقدية'}
            fields[#fields+1] = {'reward',table.concat(prizes,'، ')}
        end
        return fields
    end

    local function eventDescription(event)
        return escape(event.locked and event.state == 'registration' and 'استقبال التسجيلات متوقف' or L.state[event.state]) .. ' | ' .. escape(L.mode[event.mode]) .. '<br>' ..
            escape(event.description) .. '<br>الشروط: ' .. escape(event.rules) ..
            '<br>المشاركون: ' .. event.count .. '/' .. event.maximum .. ' | الرسوم: ' .. event.fee ..
            '<br>الجائزة: ' .. escape(event.prize)
    end

    openEvent = function(player,id,admin,eventId,back)
        menuFor(player,id,admin,'slom_events_event','تفاصيل الفعالية',back,function(menu,view)
            local event
            for _, row in ipairs(view.events) do if row.id == eventId then event = row break end end
            if not event then return end
            local function refresh(who) openEvent(who,id,admin,eventId,back) end
            menu['#' .. event.id .. ' ' .. escape(event.name)] = {refresh,eventDescription(event)}
            for _, action in ipairs(event.actions) do
                menu[L.actions[action]] = {function(who)
                    local data = action == 'edit' and E.copy(event.form) or {}
                    data.event = event.id
                    operation(who,id,admin,action,data,action == 'edit' and eventFields(view) or actionFields[action],
                        confirm[action],action == 'delete' and back or refresh)
                end,eventDescription(event)}
            end
            if event.question then
                for index, option in ipairs(event.question.options) do
                    menu['إجابة ' .. index .. ' | ' .. escape(option)] = {function(who)
                        operation(who,id,admin,'answer',{event=event.id,question=event.question.index,option=index},nil,false,refresh)
                    end,escape(event.question.text)}
                end
            end
            for _, member in ipairs(event.members or {}) do
                menu['مشارك #' .. member.id .. ' | ' .. escape(member.name)] = {function(who)
                    menuFor(who,id,admin,'slom_events_member','إدارة المشارك',refresh,function(sub)
                        for _, action in ipairs(member.actions) do
                            sub[L.actions[action]] = {function(current)
                                operation(current,id,admin,action,{event=event.id,target=member.id},actionFields[action],confirm[action],refresh)
                            end,'حساب المشارك #' .. member.id}
                        end
                    end)
                end,(L.status[member.status] or '') .. '<br>الفريق: ' .. (member.team or '—') .. ' | النتيجة: ' .. (member.score or 0)}
            end
        end)
    end

    local function submenu(player,id,admin,title,back,build)
        menuFor(player,id,admin,'slom_events_section',title,back,build)
    end

    openRoot = function(player,admin,origin)
        local id = E.uid(player)
        local title = admin and Config.Phone.AdminTitle or Config.Phone.PlayerTitle
        local function home(who) vRP.openMainMenu({who}) end
        local function root(who) openRoot(who,admin,origin) end
        menuFor(player,id,admin,admin and 'slom_events_admin' or 'slom_events_player',title,home,function(menu,view)
            if E.tabletAllowed(id,admin and 'admin' or 'player') then
                menu['فتح التابلت'] = {function(who)
                    if not permitted(who,id,admin) or not E.tabletAllowed(id,admin and 'admin' or 'player') then return end
                    handingOff[who] = true
                    SetTimeout(1500,function() handingOff[who] = nil end)
                    vRP.closeMenu({who})
                    E.tabletOpen(who,admin and 'admin' or 'player')
                end,'عرض الواجهة الموسعة'}
            end
            local function list(label, predicate, help)
                local function section(who)
                    submenu(who,id,admin,label,root,function(sub,current)
                        for _, event in ipairs(current.events) do
                            if predicate(event) then
                                sub['#' .. event.id .. ' ' .. escape(event.name)] = {function(target)
                                    openEvent(target,id,admin,event.id,section)
                                end,eventDescription(event)}
                            end
                        end
                    end)
                end
                menu[label] = {section,help}
            end
            if admin then
                list('إدارة الفعاليات',function() return true end,'إدارة المسودات والتسجيل والفرق والنتائج')
                if E.has(id,'Create') then
                    menu['إنشاء فعالية'] = {function(who)
                        local data = E.copy(view.defaults)
                        data.mode,data.teams,data.fee,data.reward = view.modes.manual and 'manual' or next(view.modes),0,0,'none'
                        operation(who,id,true,'create',data,eventFields(view),false,root)
                    end,'حفظ فعالية جديدة كمسودة'}
                end
                if view.pages.templates then
                    menu['القوالب المحفوظة'] = {function(who)
                        submenu(who,id,true,'القوالب المحفوظة',root,function(sub,current)
                            for _, template in ipairs(current.templates) do
                                if current.useTemplate then
                                    sub['استخدام #' .. template.key .. ' | ' .. escape(template.label)] = {function(p)
                                        operation(p,id,true,'useTemplate',{key=template.key},nil,true,root)
                                    end,'إنشاء مسودة من القالب'}
                                end
                                if current.deleteTemplate then
                                    sub['حذف #' .. template.key .. ' | ' .. escape(template.label)] = {function(p)
                                        operation(p,id,true,'deleteTemplate',{key=template.key},nil,true,root)
                                    end,'حذف القالب المحفوظ'}
                                end
                            end
                        end)
                    end,'إنشاء مسودة من إعدادات محفوظة'}
                end
                if view.controlBan then
                    menu['تقييد المشاركة'] = {function(who) operation(who,id,true,'ban',{},actionFields.ban,true,root) end,'تقييد حساب لمدة محددة'}
                end
                if view.controlAutomatic then
                    menu['الجدولة التلقائية'] = {function(who) operation(who,id,true,'automatic',{},nil,true,root) end,
                        view.automatic and 'مفعلة' or 'متوقفة'}
                end
                if E.has(id,'Rewards') then
                    menu['مراجعة عمليات الجوائز'] = {function(who)
                        submenu(who,id,true,'مراجعة عمليات الجوائز',root,function(sub,current)
                            for _, row in ipairs(current.reviews) do
                                sub[escape(row.label) .. ' | ' .. row.key] = {function(p)
                                    operation(p,id,true,'review',{key=row.key},actionFields.review,true,root)
                                end,'الحساب #' .. row.id .. ' | القيمة: ' .. row.amount}
                            end
                        end)
                    end,'تسوية العمليات المعلقة بعد التحقق من السجلات'}
                end
                if E.has(id,'Logs') then
                    menu['السجلات الإدارية'] = {function(who)
                        submenu(who,id,true,'السجلات الإدارية',root,function(sub,current)
                            for i,row in ipairs(current.logs) do
                                if i > 25 then break end
                                sub[i .. ' | ' .. escape(row.action)] = {function() end,
                                    os.date('!%Y-%m-%d %H:%M',row.at) .. ' UTC<br>المنفذ: ' .. escape(row.actor or 'النظام') ..
                                    '<br>الفعالية: ' .. escape(row.name or '—')}
                            end
                        end)
                    end,'عرض أحدث 25 عملية'}
                end
            else
                list('الفعاليات المتاحة',function(e) return e.state == 'registration' end,'التسجيل أو اختيار الفريق أو دعوة لاعب')
                list('الفعاليات الجارية',function(e) return e.state == 'countdown' or e.state == 'running' end,'عرض الحالة والإجابة عن الأسئلة')
                list('فعالياتي والفعاليات القادمة',function(e) return e.state == 'scheduled' or e.status ~= nil end,'عرض التسجيلات والمواعيد')
                list('سجل مشاركاتي',function(e) return e.status and (e.state == 'completed' or e.state == 'cancelled') end,'عرض المشاركات السابقة والنتائج')
                local p = view.profile
                menu['الإعدادات الشخصية'] = {function(who)
                    operation(who,id,false,'preferences',{mute=not p.muteAnnouncements},nil,true,root)
                end,p.muteAnnouncements and 'الإعلانات مكتومة. اختر لإعادة تشغيلها.' or 'الإعلانات مفعلة. اختر لكتمها.'}
                menu['نقاطي ومستواي'] = {root,('نقاط: %s | مستوى: %s | خبرة: %s<br>فوز: %s | مشاركات: %s'):format(p.points,p.level,p.xp,p.wins,p.games)}
                menu['الجوائز المتاحة'] = {function(who)
                    submenu(who,id,false,'الجوائز',root,function(sub,current)
                        for _, row in ipairs(current.rewards) do
                            sub[escape(row.label) .. ' | ' .. row.key] = {function(p)
                                if row.status == 'pending' then operation(p,id,false,'claim',{key=row.key},nil,true,root) end
                            end,L.status[row.status] .. ' | ' .. row.amount}
                        end
                    end)
                end,'عرض واستلام الجوائز'}
                menu['متجر النقاط'] = {function(who)
                    submenu(who,id,false,'متجر النقاط',root,function(sub,current)
                        for _, row in ipairs(current.market) do
                            sub[escape(row.label)] = {function(p)
                                if not row.owned and row.stock > 0 then operation(p,id,false,'buy',{key=row.key},nil,true,root) end
                            end,('السعر: %s | المتبقي: %s'):format(row.price,row.stock)}
                        end
                    end)
                end,'استبدال النقاط بالألقاب'}
                menu['ترتيب اللاعبين'] = {function(who)
                    submenu(who,id,false,'ترتيب الموسم',root,function(sub,current)
                        for i,row in ipairs(current.ranking) do
                            if i > 25 then break end
                            sub[i .. ' | حساب #' .. row.id] = {function() end,'خبرة الموسم: ' .. row.seasonXP .. ' | الانتصارات: ' .. row.wins}
                        end
                    end)
                end,'عرض أفضل 25 لاعباً'}
            end
        end)
    end

    local parents = {}
    local function attach(parent, mode)
        parents[parent] = parents[parent] or {}
        parents[parent][mode] = true
    end
    attach(Config.Phone.PlayerParent,'player')
    attach(Config.Phone.AdminParent,'admin')
    if Config.Phone.Fallback then attach('main','admin') end

    for parent,modes in pairs(parents) do
        local marker = 'slom_events:phone:' .. parent
        if Config.Phone.Enabled and GetConvar(marker,'') == '' then
            vRP.registerMenuBuilder({parent,function(add,data)
                local choices = {}
                local player = data and data.player
                local id = E.uid(player)
                if GetResourceState(resource) == 'started' and id then
                    if modes.player and permitted(player,id,false) then
                        choices[Config.Phone.PlayerTitle] = {function(who) openRoot(who,false,parent) end,'عرض الفعاليات والتسجيل والجوائز'}
                    end
                    if modes.admin and permitted(player,id,true) then
                        choices[Config.Phone.AdminTitle] = {function(who) openRoot(who,true,parent) end,'إدارة نظام الفعاليات'}
                    end
                end
                add(choices)
            end})
            SetConvar(marker,'installed')
        end
    end
end
