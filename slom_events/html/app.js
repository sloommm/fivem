'use strict';
const byId = id => document.getElementById(id);
const tablet = byId('tablet');
const themeKeys = ['background','panel','line','active','soft','muted','gold'];
const content = byId('content');
const dialog = byId('dialog');
const pages = {
  dashboard: 'لوحة التحكم', available: 'الفعاليات المتاحة', live: 'الفعاليات الجارية',
  upcoming: 'الفعاليات القادمة', history: 'سجل مشاركاتي', ranking: 'ترتيب الموسم',
  rewards: 'الجوائز', store: 'متجر النقاط', settings: 'الإعدادات', create: 'إنشاء فعالية',
  manage: 'إدارة الفعاليات', participants: 'إدارة المشاركين', teams: 'إدارة الفرق',
  schedule: 'الجدولة التلقائية', templates: 'القوالب المحفوظة', games: 'الألعاب والتحديات',
  seasons: 'المواسم', daily: 'المهام اليومية', weekly: 'المهام الأسبوعية',
  announcements: 'الإعلانات والتنبيهات', statistics: 'الإحصائيات', leaders: 'قائمة المتصدرين',
  achievements: 'الإنجازات', winners: 'سجل الفائزين', mine: 'تسجيلاتي الحالية', logs: 'السجل الإداري', system: 'مراقبة النظام'
};
const paths = {
  dashboard: 'M3 3h7v7H3z M14 3h7v7h-7z M3 14h7v7H3z M14 14h7v7h-7z',
  available: 'M4 6h16v14H4z M8 3v6m8-6v6M4 11h16',
  live: 'M3 12h4l3-7 4 14 3-7h4',
  upcoming: 'M12 3a9 9 0 1 0 0 18 9 9 0 1 0 0-18m0 4v5l4 2',
  history: 'M4 4h16v16H4zm4 5h8m-8 5h8',
  ranking: 'M3 15h5v6H3zm6-10h6v16H9zm7 6h5v10h-5z',
  rewards: 'M3 8h18v4H3zm2 4v8h14v-8m-7-4v12m0-12C5 8 6 1 9 4l3 4m0 0c7 0 6-7 3-4z',
  store: 'M5 8h14l2 13H3L5 8zm4 0V5a3 3 0 0 1 6 0v3',
  settings: 'M5 4v16m7-16v16m7-16v16M3 8h4m3 7h4m3-6h4',
  create: 'M3 3h18v18H3zm5 9h8m-4-4v8',
  manage: 'M4 5h16v14H4zm4 5h8m-8 4h5',
  logs: 'M3 4h18v16H3zm5 5h8m-8 5h8',
  system: 'M3 5h18v12H3zm6 15h6'
};
let view, page, selected, mode, opened = false, busy = false, generation = 0;
let dialogAction, noticeTimer, liveTimer;
function preference(key, value) {
  try {
    if (value !== undefined) localStorage.setItem(key,value);
    else return localStorage.getItem(key);
  } catch {
    // تظل التفضيلات الحالية فعالة إذا تعذر التخزين المحلي.
  }
}
let animate = preference('slom_motion') !== 'off';
let showHud = preference('slom_hud') !== 'off';

function el(tag, className, value) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (value !== undefined) node.textContent = value;
  return node;
}
function button(label, action, className) {
  const node = el('button', className, label);
  node.type = 'button';
  node.addEventListener('click', action);
  return node;
}
function icon(name) {
  const ns = 'http://www.w3.org/2000/svg';
  const svg = document.createElementNS(ns, 'svg');
  const path = document.createElementNS(ns, 'path');
  svg.setAttribute('viewBox', '0 0 24 24');
  svg.setAttribute('aria-hidden', 'true');
  path.setAttribute('d', paths[name] || paths.available);
  svg.append(path);
  return svg;
}
async function nui(route, data = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 23500);
  try {
    const response = await fetch('https://' + GetParentResourceName() + '/' + route, {
      method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify(data), signal: controller.signal
    });
    return await response.json();
  } finally { clearTimeout(timer); }
}
function notice(message) {
  if (!message) return;
  const box = byId('notice');
  box.textContent = message;
  box.hidden = false;
  clearTimeout(noticeTimer);
  noticeTimer = setTimeout(() => { box.hidden = true; }, 4200);
}
function scheduleLive() {
  clearTimeout(liveTimer);
  if (!opened || !view || page !== 'live' || !selected) return;
  const event = collection(view.events).find(row => row.id === selected);
  if (!event || !['countdown','running'].includes(event.state)) return;
  liveTimer = setTimeout(async () => {
    if (opened && page === 'live' && !dialog.open) await rpc('view', {}, true);
    scheduleLive();
  }, Math.max(1500, Number(view.refresh) || 3000));
}
async function rpc(action, data = {}, quiet = false) {
  if (!opened || busy) return;
  busy = true;
  const current = generation;
  byId('refresh').disabled = true;
  try {
    const result = await nui('rpc', {action, data});
    if (!opened || current !== generation) return;
    if (result.view) {
      const previous = quiet && collection(view?.events).find(row => row.id === selected);
      view = result.view;
      const currentEvent = quiet && collection(view.events).find(row => row.id === selected);
      if (!quiet) render();
      else if (JSON.stringify(previous) !== JSON.stringify(currentEvent)) renderContent();
    }
    if (!quiet || !result.ok) notice(result.message);
    if (!view && !result.ok) renderContent(result.message);
  } catch {
    if (!quiet && current === generation) {
      notice('تعذر الاتصال بالخادم.');
      if (!view) renderContent('تعذر تحميل البيانات. اضغط تحديث لإعادة المحاولة.');
    }
  } finally {
    if (current === generation) {
      busy = false;
      byId('refresh').disabled = false;
    }
  }
}
function date(epoch) {
  if (!epoch) return '—';
  return new Intl.DateTimeFormat('ar-SA', {
    calendar: 'gregory', dateStyle: 'short', timeStyle: 'short'
  }).format(new Date(epoch * 1000));
}
function collection(value) { return Object.values(value || {}); }
function empty(message = 'لا توجد بيانات لعرضها.') { return el('p', 'empty', message); }
function card(title, line) {
  const node = el('section', 'card');
  node.append(el('h2', '', title));
  if (line) node.append(el('p', '', line));
  return node;
}
function table(headers, rows) {
  if (!rows.length) return empty();
  const wrapper = el('div', 'card table');
  const tableNode = el('table');
  const head = tableNode.createTHead().insertRow();
  for (const header of headers) head.append(el('th', '', header));
  const body = tableNode.createTBody();
  for (const values of rows) {
    const row = body.insertRow();
    for (const value of values) {
      const cell = row.insertCell();
      if (value instanceof Node) cell.append(value);
      else cell.textContent = value ?? '—';
    }
  }
  wrapper.append(tableNode);
  return wrapper;
}
function render() {
  for (const key of themeKeys) {
    const value = view.colors?.[key];
    if (/^#[0-9a-f]{6}$/i.test(value || '')) document.documentElement.style.setProperty('--' + key, value);
    else document.documentElement.style.removeProperty('--' + key);
  }
  byId('brand').textContent = view.name;
  byId('credit').textContent = view.credit;
  byId('mode').textContent = view.admin ? 'واجهة الإدارة' : 'واجهة اللاعب';
  byId('switch').hidden = !view.otherTablet;
  byId('switch').textContent = view.admin ? 'واجهة اللاعب' : 'واجهة الإدارة';
  const logo = byId('logo');
  const source = view.logo ? 'assets/' + view.logo : '';
  if (source !== logo.getAttribute('src')) {
    if (source) logo.src = source;
    else logo.removeAttribute('src');
  }
  if (!source) logo.hidden = true;
  tablet.classList.toggle('no-motion', !animate || !view.animations);
  const navigation = byId('menu');
  navigation.replaceChildren();
  const keys = Object.keys(pages).filter(key => view.pages[key]);
  if (!keys.includes(page)) page = keys[0];
  for (const key of keys) {
    const entry = button('', () => { page = key; selected = null; render(); });
    entry.append(icon(key), el('span', '', pages[key]));
    entry.title = pages[key];
    entry.setAttribute('aria-label', pages[key]);
    if (key === page) entry.setAttribute('aria-current', 'page');
    navigation.append(entry);
  }
  renderContent();
  scheduleLive();
}
function dashboard() {
  const p = view.profile;
  const stats = el('div', 'cards');
  const values = [['نقاط الفعاليات',p.points],['المستوى',p.level],['خبرة الموسم',p.seasonXP],
    ['المشاركات',p.games],['الانتصارات',p.wins],['الانتصارات المتتالية',p.streak]];
  for (const [name, number] of values) {
    const node = card(name);
    node.append(el('strong','stat',number));
    stats.append(node);
  }
  const goals = card('أهداف المشاركة');
  for (const [name, value, maximum] of [['اليوم',p.daily,p.dailyGoal],['الأسبوع',p.weekly,p.weeklyGoal]]) {
    const progress = el('progress');
    progress.max = maximum;
    progress.value = value;
    goals.append(el('p','',name + ' · ' + value + ' / ' + maximum),progress);
  }
  const achievements = card('الإنجازات والألقاب', [...collection(p.badges),...collection(p.titles)].join(' · ') || 'لا توجد إنجازات أو ألقاب بعد.');
  const archives = Object.entries(p.archives || {});
  content.append(stats,goals,achievements);
  if (archives.length) content.append(card('المواسم السابقة'), table(['الموسم','الخبرة'],archives));
}
function optionsField(spec) {
  const label = el('label', '', spec.label);
  const input = el(spec.options ? 'select' : 'input');
  if (spec.options) {
    for (const [key, name] of Object.entries(spec.options)) {
      const option = el('option','',name);
      option.value = key;
      input.append(option);
    }
  } else input.type = spec.type || 'text';
  if (input.type === 'checkbox') input.checked = Boolean(spec.value);
  else if (spec.value !== undefined) input.value = spec.value;
  if (spec.min !== undefined) input.min = spec.min;
  if (spec.max !== undefined) input.max = spec.max;
  if (spec.required) input.required = true;
  if (spec.length) input.maxLength = spec.length;
  label.append(input);
  return {label,input,key:spec.key};
}
function fields(container,specs) {
  for (const spec of specs) {
    if (spec.default !== undefined && spec.value === undefined) spec.value = spec.default;
  }
  const group = el('div','fields');
  const elements = specs.map(optionsField);
  group.append(...elements.map(field => field.label));
  container.append(group);
  return () => Object.fromEntries(elements.map(({input,key}) => [key,input.type==='checkbox' ? input.checked : input.value]));
}
function promptAction(title, specs, action, description) {
  byId('dialogHeading').textContent = title;
  const body = byId('dialogBody');
  body.replaceChildren();
  if (description) body.append(el('p','',description));
  const values = fields(body,specs);
  dialogAction = () => action(values());
  if (!dialog.open) dialog.showModal();
}
function actionButton(action, event, target) {
  const integer = (key,label,min=1,max) => ({key,label,type:'number',min,max,required:true});
  const specification = {
    team:[integer('team','رقم الفريق',1,event.teams)], move:[integer('team','رقم الفريق',1,event.teams)],
    saveTemplate:[{key:'label',label:'اسم القالب',required:true,length:90}],
    invite:[integer('target','رقم حساب اللاعب')], admit:[integer('target','رقم حساب اللاعب')],
    schedule:[integer('minutes','الوقت حتى التسجيل بالدقائق',1,43200)],
    extend:[integer('minutes','مدة التمديد بالدقائق',1,120)]
  };
  const destructive = ['delete','cancel','stop','kick','refund','winner','leave'].includes(action);
  return button(view.actions[action], () => {
    if (action === 'edit') { selected = {form:event}; renderContent(); return; }
    const send = extra => rpc(action,{event:event.id,target,...extra});
    if (destructive || specification[action]) promptAction(view.actions[action],specification[action] || [],send,event.name);
    else send({});
  },destructive ? 'danger' : '');
}
function eventForm(event) {
  const values = event?.form || {};
  const specs = [
    {key:'name',label:'اسم الفعالية',required:true,length:90},
    {key:'description',label:'الوصف',length:320},
    {key:'rules',label:'شروط وقواعد المشاركة',length:320},
    {key:'category',label:'التصنيف',length:65},
    {key:'mode',label:'نوع الفعالية',options:view.modes},
    {key:'minimum',label:'الحد الأدنى للمشاركين',type:'number',min:1,required:true},
    {key:'maximum',label:'الحد الأعلى للمشاركين',type:'number',min:1,required:true},
    {key:'registration',label:'مدة التسجيل بالثواني',type:'number',min:30,required:true},
    {key:'duration',label:'مدة اللعب بالثواني',type:'number',min:10,required:true},
    {key:'countdown',label:'العد التنازلي بالثواني',type:'number',min:1,max:120,required:true},
    {key:'teams',label:'عدد الفرق، 0 لتعطيلها',type:'number',min:0,max:8,required:true,default:0},
    {key:'permission',label:'صلاحية المشاركة',length:80},
    {key:'private',label:'التسجيل بالدعوات',type:'checkbox'},
    {key:'autostart',label:'البدء عند انتهاء التسجيل',type:'checkbox'}
  ];
  if (view.economy) specs.push(
    {key:'fee',label:'رسوم التسجيل النقدية',type:'number',min:0,required:true,default:0},
    {key:'reward',label:'جائزة الفائز',options:view.prizes}
  );
  for (const spec of specs) spec.value = values[spec.key] ?? view.defaults[spec.key];
  const form = el('form','card');
  const readFields = fields(form,specs);
  const save = el('button','primary',event ? 'حفظ التعديل' : 'حفظ المسودة');
  save.type = 'submit';
  form.append(save);
  form.addEventListener('submit', async ev => {
    ev.preventDefault();
    const eventId = event?.id;
    await rpc(event ? 'edit' : 'create',{...readFields(),event:eventId});
  });
  return form;
}
function eventCard(event, detail = false) {
  const node = card(event.name,event.description);
  const status = event.locked && event.state === 'registration' ? 'استقبال التسجيلات متوقف' : view.states[event.state];
  node.append(el('span','tag',status + ' · ' + view.modes[event.mode]));
  node.append(el('p','',event.count + ' / ' + event.maximum + ' مشارك · ' + 'الجائزة: ' + event.prize));
  if (event.deadline) node.append(el('p','', 'انتهاء المرحلة: ' + date(event.deadline)));
  if (event.state === 'scheduled') node.append(el('p','', 'فتح التسجيل: ' + date(event.scheduled)));
  if (event.status) node.append(el('p','', 'مشاركتي: ' + view.statuses[event.status]));
  if (event.winner) node.append(el('p','', 'الفائز: حساب #' + event.winner));
  if (!detail) {
    node.append(button('عرض التفاصيل', () => { selected = event.id; renderContent(); scheduleLive(); }));
    return node;
  }
  if (event.rules) node.append(el('p','','شروط المشاركة: ' + event.rules));
  node.append(el('p','', 'الحد الأدنى: ' + event.minimum + ' · رسوم التسجيل: ' + event.fee));
  const buttons = el('div','row');
  for (const action of collection(event.actions)) buttons.append(actionButton(action,event));
  if (event.question) {
    node.append(el('p','',event.question.text));
    for (const [index,option] of collection(event.question.options).entries()) {
      buttons.append(button(option,() => rpc('answer',{event:event.id,question:event.question.index,option:index+1})));
    }
  }
  node.append(buttons);
  if (event.members) {
    const rows = collection(event.members).map(member => {
      const actions = el('div','row');
      for (const action of collection(member.actions)) actions.append(actionButton(action,event,member.id));
      return [member.name + ' #' + member.id,view.statuses[member.status],member.team,member.score || 0,actions];
    });
    node.append(table(['المشارك','الحالة','الفريق','النتيجة','الإجراءات'],rows));
  }
  return node;
}
function eventList(eligible) {
  const events = collection(view.events).filter(eligible);
  const event = typeof selected === 'object' && selected ? selected.form : events.find(row => row.id === selected);
  if (event) {
    content.append(button('رجوع إلى الفعاليات', () => { selected = null; renderContent(); }));
    if (typeof selected === 'object') {
      const updated = events.find(row => row.id === event.id);
      if (updated?.form) content.append(eventForm(updated));
    } else content.append(eventCard(event,true));
    return;
  }
  const search = el('input','search');
  search.type = 'search';
  search.placeholder = 'ابحث باسم الفعالية أو التصنيف';
  search.setAttribute('aria-label', search.placeholder);
  const list = el('div');
  let offset = 0;
  function draw() {
    const query = search.value.trim().toLocaleLowerCase('ar');
    const filtered = events.filter(row => [row.name,row.category].some(value => value.toLocaleLowerCase('ar').includes(query)));
    const cards = el('div','cards');
    for (const entry of filtered.slice(offset,offset+8)) cards.append(eventCard(entry));
    list.replaceChildren(filtered.length ? cards : empty());
    if (filtered.length <= 8) return;
    const controls = el('div','row paginate');
    const previous = button('السابق',() => { offset -= 8; draw(); });
    const next = button('التالي',() => { offset += 8; draw(); });
    previous.disabled = offset === 0;
    next.disabled = offset + 8 >= filtered.length;
    controls.append(previous,el('span','',Math.floor(offset/8)+1 + ' / ' + Math.ceil(filtered.length/8)),next);
    list.append(controls);
  }
  search.addEventListener('input',() => { offset = 0; draw(); });
  content.append(search,list);
  draw();
}
function adminControls() {
  const tools = el('div','row');
  if (view.controlAutomatic) tools.append(button('الجدولة التلقائية · ' + (view.automatic ? 'مفعلة' : 'متوقفة'),
    () => promptAction('تغيير الجدولة التلقائية',[],() => rpc('automatic'))));
  if (view.controlBan) tools.append(button('تقييد المشاركة',() => promptAction('تقييد المشاركة',[
    {key:'target',label:'رقم الحساب',type:'number',min:1,required:true},
    {key:'hours',label:'الساعات، 0 لإزالة التقييد',type:'number',min:0,max:720,required:true}
  ],values => rpc('ban',values))));
  content.append(tools);
  for (const entry of collection(view.reviews)) {
    const node = card(entry.label,entry.key + ' · حساب #' + entry.id + ' · ' + entry.amount);
    node.append(button('مراجعة وتأكيد',() => promptAction('تسوية عملية معلقة',[
      {key:'outcome',label:'نتيجة المراجعة',options:entry.kind === 'fee'
        ? {charged:'تم الخصم، إصدار استرداد',clear:'لم يتم الخصم'}
        : {done:'تم تسليم الجائزة',clear:'لم يتم التسليم، إعادة فتح الاستلام'}}
    ],values => rpc('review',{key:entry.key,...values}),'طابق العملية مع سجلات اقتصاد الخادم قبل اعتماد النتيجة.')));
    content.append(node);
  }
}
function renderContent(error) {
  byId('heading').textContent = pages[page] || 'الفعاليات';
  content.replaceChildren();
  if (!view) { content.append(empty(error || 'جارٍ تحميل البيانات…')); return; }
  if (page === 'dashboard') dashboard();
  else if (page === 'available') eventList(event => event.state === 'registration');
  else if (page === 'live') eventList(event => ['countdown','running'].includes(event.state));
  else if (page === 'participants') eventList(event => collection(event.members).length > 0);
  else if (page === 'teams') eventList(event => event.teams > 0);
  else if (page === 'mine') eventList(event => ['joined','wait'].includes(event.status) &&
    ['registration','countdown','running'].includes(event.state));
  else if (page === 'winners') eventList(event => event.state === 'completed' && event.winner);
  else if (page === 'games') {
    const rules = {manual:'تحدد الإدارة نتيجة الفعالية من قائمة المشاركين.',
      draw:'يختار الخادم فائزاً عشوائياً من المشاركين المتصلين وقت النهاية.',
      quiz:'تظهر الأسئلة في تفاصيل الفعالية الجارية. تحسب كل إجابة صحيحة نقطة واحدة.'};
    for (const [key,label] of Object.entries(view.modes)) content.append(card(label,rules[key]));
  } else if (page === 'daily' || page === 'weekly') {
    const weekly = page === 'weekly';
    const count = weekly ? view.profile.weekly : view.profile.daily;
    const target = weekly ? view.profile.weeklyGoal : view.profile.dailyGoal;
    const goal = card('المشاركات المكتملة',count + ' / ' + target);
    const progress = el('progress');
    progress.max = target;
    progress.value = count;
    goal.append(progress);
    content.append(goal);
  } else if (page === 'seasons') {
    content.append(card('الموسم ' + view.season,'خبرتك في الموسم: ' + view.profile.seasonXP));
    content.append(table(['الموسم','الخبرة'],Object.entries(view.profile.archives || {})));
  } else if (page === 'achievements') {
    const earned = [...collection(view.profile.badges),...collection(view.profile.titles)];
    content.append(earned.length ? table(['الإنجاز أو اللقب'],earned.map(name => [name])) : empty());
  } else if (page === 'templates') {
    for (const entry of collection(view.templates)) {
      const node = card(entry.label,entry.name + ' · ' + view.modes[entry.mode]);
      if (view.useTemplate) node.append(button('إنشاء مسودة',() => rpc('useTemplate',{key:entry.key})));
      if (view.deleteTemplate) node.append(button('حذف القالب',() => promptAction('حذف القالب',[],
        () => rpc('deleteTemplate',{key:entry.key}),entry.label)));
      content.append(node);
    }
    if (!content.childElementCount) content.append(empty('احفظ قالباً من تفاصيل فعالية في شاشة الإدارة.'));
  } else if (page === 'schedule') {
    if (view.controlAutomatic) content.append(button(view.automatic ? 'إيقاف الجدولة' : 'تشغيل الجدولة',
      () => promptAction('تغيير الجدولة التلقائية',[],() => rpc('automatic'))));
    const days = ['كل يوم','الأحد','الاثنين','الثلاثاء','الأربعاء','الخميس','الجمعة','السبت'];
    content.append(card('توقيت الخادم','فرق التوقيت عن UTC بالدقائق: ' + view.scheduleOffset));
    content.append(table(['الفعالية','النمط','اليوم','الوقت','الحد الأدنى للمتصلين'],
      collection(view.schedules).map(row => [row.name,view.modes[row.mode],days[row.weekday],
        String(row.hour).padStart(2,'0') + ':' + String(row.minute).padStart(2,'0'),row.online])));
    eventList(event => event.state === 'scheduled');
  } else if (page === 'upcoming') eventList(event => event.state === 'scheduled');
  else if (page === 'history') eventList(event => event.status && ['completed','cancelled'].includes(event.state));
  else if (page === 'create') content.append(eventForm());
  else if (page === 'manage') { if (!selected) adminControls(); eventList(() => true); }
  else if (page === 'ranking' || page === 'leaders') content.append(table(['الحساب','خبرة الموسم','الخبرة الكلية','الفوز'],
    collection(page === 'ranking' ? view.ranking : view.leaders).map(row => ['#'+row.id,row.seasonXP,row.xp,row.wins])));
  else if (page === 'announcements') content.append(table(['التوقيت','الإعلان'],
    collection(view.news).map(row => [date(row.at),row.message])));
  else if (page === 'statistics') {
    const p = view.profile;
    const percent = p.games ? new Intl.NumberFormat('ar',{style:'percent',maximumFractionDigits:1}).format(p.wins/p.games) : '—';
    content.append(table(['المقياس','القيمة'],[['المشاركات',p.games],['الفوز',p.wins],['نسبة الفوز',percent],
      ['الانتصارات المتتالية',p.streak],['الخبرة الكلية',p.xp],['النقاط المتاحة',p.points]]));
  }
  else if (page === 'logs') content.append(table(['الوقت','المنفذ','الإجراء','الفعالية','الحساب المتأثر'],
    collection(view.logs).map(row => [date(row.at),row.actor ? (row.actorName || '') + ' #' + row.actor : 'النظام',row.action,row.name,row.target])));
  else if (page === 'system') content.append(card('قاعدة البيانات','متصلة · إصدار البيانات ' + view.system.revision),
    card('الجدولة التلقائية',view.system.automatic ? 'مفعلة' : 'متوقفة'));
  else if (page === 'rewards') {
    for (const entry of collection(view.rewards)) {
      const node = card(entry.label, view.statuses[entry.status] + ' · ' + entry.amount + ' · فعالية #' + entry.event);
      if (entry.status === 'pending') node.append(button('استلام',() => promptAction('استلام الجائزة',[],() => rpc('claim',{key:entry.key}),entry.label)));
      content.append(node);
    }
    if (!content.childElementCount) content.append(empty('لا توجد جوائز.'));
  } else if (page === 'store') {
    for (const item of collection(view.market)) {
      const node = card(item.label,'السعر: ' + item.price + ' نقطة · المتبقي: ' + item.stock);
      const buy = button(item.owned ? 'تم الشراء' : 'شراء',() => promptAction('شراء اللقب',[],
        () => rpc('buy',{key:item.key}),item.label + ' · ' + item.price + ' نقطة'));
      buy.disabled = item.owned || item.stock <= 0 || view.profile.points < item.price;
      node.append(buy);
      content.append(node);
    }
    if (!content.childElementCount) content.append(empty('لا توجد منتجات متاحة.'));
  } else if (page === 'settings') {
    const settings = card('تفضيلات العرض');
    const motion = optionsField({label:'حركات التابلت',type:'checkbox',value:animate && view.animations});
    const hud = optionsField({label:'إظهار حالة الفعالية داخل اللعبة',type:'checkbox',value:showHud});
    motion.input.disabled = !view.animations;
    motion.input.addEventListener('change', () => {
      animate = motion.input.checked;
      preference('slom_motion',animate ? 'on' : 'off');
      tablet.classList.toggle('no-motion',!animate || !view.animations);
    });
    hud.input.addEventListener('change', () => {
      showHud = hud.input.checked;
      preference('slom_hud',showHud ? 'on' : 'off');
      if (!showHud) byId('hud').hidden = true;
    });
    const announcements = optionsField({label:'استقبال إعلانات الفعاليات',type:'checkbox',value:!view.profile.muteAnnouncements});
    announcements.input.addEventListener('change',() => rpc('preferences',{mute:!announcements.input.checked}));
    settings.append(motion.label,hud.label,announcements.label);
    content.append(settings);
  } else content.append(empty('لا توجد أقسام مفعلة.'));
}

byId('logo').addEventListener('load', () => { byId('logo').hidden = false; });
byId('logo').addEventListener('error', () => { byId('logo').hidden = true; });
byId('refresh').addEventListener('click', () => rpc('view'));
byId('switch').addEventListener('click', () => rpc('switch'));
byId('close').addEventListener('click', () => nui('close').catch(() => notice('استخدم زر اختصار التابلت لإغلاقه.')));
byId('dismiss').addEventListener('click', () => dialog.close());
byId('dialogForm').addEventListener('submit', event => {
  event.preventDefault();
  dialog.close();
  if (dialogAction) dialogAction();
});
document.addEventListener('keydown', event => {
  if (event.key === 'Escape' && opened && !dialog.open) {
    event.preventDefault();
    nui('close').catch(() => notice('استخدم زر اختصار التابلت لإغلاقه.'));
  }
});
window.addEventListener('message', ({data}) => {
  if (data.type === 'open') {
    generation++;
    opened = true;
    busy = false;
    mode = data.mode;
    view = undefined;
    page = mode === 'admin' ? 'manage' : 'dashboard';
    selected = null;
    if (dialog.open) dialog.close();
    byId('menu').replaceChildren();
    byId('mode').textContent = '';
    byId('switch').hidden = true;
    tablet.hidden = false;
    tablet.classList.add('animate');
    renderContent();
    rpc('view');
  } else if (data.type === 'close') {
    opened = false;
    generation++;
    clearTimeout(liveTimer);
    tablet.hidden = true;
    if (dialog.open) dialog.close();
  } else if (data.type === 'hud') {
    const hud = byId('hud');
    hud.hidden = !data.data || !showHud;
    if (!hud.hidden) {
      const item = data.data;
      hud.replaceChildren(el('strong','',item.name),el('div','',item.state + ' · ' + item.seconds + ' ث'),
        el('div','', 'النتيجة: ' + item.score + ' · المشاركون: ' + item.count + (item.team ? ' · الفريق: ' + item.team : '')));
    }
  } else if (data.type === 'notice') notice(data.message);
});
async function handshake(attempt = 0) {
  try { await nui('ready'); }
  catch {
    if (attempt < 5) setTimeout(() => handshake(attempt + 1), 700);
  }
}
handshake();
