-- حالة التابلت وإدارة تركيز الفأرة
local R = 'slom_events:'
local ready, opened, pendingMode, currentMode = false, false, nil, nil
local requests, sequence = {}, 0
local keyRegistered, closeOnDeath = false, true
local idleInterval, activeInterval = 1500, 300

local function close()
    if opened then SetNuiFocus(false,false) end
    opened, pendingMode, currentMode = false, nil, nil
    SendNUIMessage({type='close'})
    for token, callback in pairs(requests) do
        requests[token] = nil
        callback({ok=false,message='أغلقت الواجهة.'})
    end
end

local function tryOpen()
    if not ready or not pendingMode then return end
    opened,currentMode,pendingMode = true,pendingMode,nil
    SendNUIMessage({type='open',mode=currentMode})
    SetNuiFocus(true,true)
end

-- الاتصال بين صفحة NUI والخادم
RegisterNUICallback('ready',function(_,cb)
    ready = true
    cb({ok=true})
    tryOpen()
end)
RegisterNUICallback('close',function(_,cb)
    cb({ok=true})
    close()
end)
RegisterNUICallback('rpc',function(data,cb)
    if not opened or type(data) ~= 'table' then cb({ok=false,message='الواجهة مغلقة.'}) return end
    if data.action == 'switch' then
        TriggerServerEvent(R .. 'switchTablet',currentMode)
        cb({ok=true})
        return
    end
    if next(requests) then cb({ok=false,message='يوجد طلب قيد المعالجة.'}) return end
    sequence = sequence % 2147483647 + 1
    local token = sequence
    requests[token] = cb
    TriggerServerEvent(R .. 'rpc',token,currentMode,data.action,data.data or {})
    SetTimeout(22500,function()
        local callback = requests[token]
        if callback then
            requests[token] = nil
            callback({ok=false,message='انتهت مهلة طلب الخادم. حدّث البيانات قبل إعادة المحاولة.'})
        end
    end)
end)

-- الاختصار وإعداداته من الخادم
local playerCommand
local function requestSettings(attempt)
    if keyRegistered then return end
    TriggerServerEvent(R .. 'settingsRequest')
    if attempt < 4 then SetTimeout(1500, function() requestSettings(attempt + 1) end) end
end

RegisterNetEvent(R .. 'settings',function(command,key,death,idle,active)
    playerCommand = command
    closeOnDeath = death == true
    idleInterval, activeInterval = idle or idleInterval, active or activeInterval
    if keyRegistered then return end
    keyRegistered = true
    RegisterCommand('slom_events_toggle',function()
        if opened or pendingMode then close() else ExecuteCommand(playerCommand) end
    end,false)
    RegisterKeyMapping('slom_events_toggle','تابلت الفعاليات','keyboard',key)
end)

-- استجابات الخادم والتنبيهات ومؤشر الفعالية
RegisterNetEvent(R .. 'openTablet',function(mode)
    if mode ~= 'player' and mode ~= 'admin' then return end
    if currentMode == mode and opened then return end
    pendingMode = mode
    tryOpen()
    if not ready then
        SetTimeout(5000,function()
            if not ready and pendingMode then
                close()
                TriggerEvent('chat:addMessage',{args={'الفعاليات','تعذر تهيئة التابلت.'}})
            end
        end)
    end
end)
RegisterNetEvent(R .. 'forceClose',close)
RegisterNetEvent(R .. 'result',function(token,ok,message,view)
    local callback = requests[token]
    if not callback then return end
    requests[token] = nil
    callback({ok=ok,message=message,view=view})
end)
RegisterNetEvent(R .. 'notice',function(message) SendNUIMessage({type='notice',message=message}) end)
RegisterNetEvent(R .. 'hud',function(data) SendNUIMessage({type='hud',data=data}) end)

-- التهيئة والتنظيف عند إيقاف المورد
AddEventHandler('onClientResourceStart',function(resource)
    if resource ~= GetCurrentResourceName() then return end
    requestSettings(1)
end)
AddEventHandler('onClientResourceStop',function(resource)
    if resource == GetCurrentResourceName() then close() end
end)

CreateThread(function()
    while true do
        Wait(opened and activeInterval or idleInterval)
        if opened and closeOnDeath and IsEntityDead(PlayerPedId()) then close() end
    end
end)
