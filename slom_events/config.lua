-- الهوية والواجهات
Config = {
    Name = 'اسم السيرفر', -- اسم السيرفر في التابلت والإعلانات
    Logo = '', -- اسم ملف الشعار، مثل logo.png، يوضع داخل html/assets
    Credit = 'MADE BY SLOM', -- حقوق البرمجة
    Tablet = {
        Enabled = true, -- تمكين التابلت
        PlayerAccess = true, -- تمكين واجهة اللاعبين
        AdminAccess = true, -- تمكين واجهة الإدارة
        Command = 'events', -- أمر تابلت اللاعب
        AdminCommand = 'eventsadmin', -- أمر تابلت الإدارة
        Key = 'F7', -- الاختصار الافتراضي لأمر events في إعدادات FiveM
        Animations = true, -- تشغيل حركة فتح التابلت
        CloseOnDeath = true, -- إغلاق التابلت عند الموت
        Hud = true -- عرض حالة الفعالية أثناء العد التنازلي واللعب
    },
    Phone = {
        Enabled = true, -- تمكين قوائم الجوال
        PlayerEnabled = true, -- إظهار قائمة اللاعبين
        AdminEnabled = true, -- إظهار قائمة الإدارة
        PlayerParent = 'main', -- قائمة اللاعب الأم
        AdminParent = 'admin', -- قائمة الإدارة الأم
        Fallback = true, -- عرض مدخل الإدارة أيضاً في القائمة الرئيسية
        PlayerTitle = 'الفعاليات', -- عنوان مدخل اللاعبين
        AdminTitle = 'إدارة الفعاليات', -- عنوان مدخل الإدارة
        Position = '75px', -- المسافة من أعلى الشاشة
        Color = 'rgba(128,0,32,0.95)' -- لون رأس القائمة
    },
    Pages = {
        dashboard = true, -- لوحة الملخص
        available = true, -- الفعاليات المفتوحة
        live = true, -- الفعاليات الجارية
        upcoming = true, -- الفعاليات المجدولة
        history = true, -- سجل المشاركات
        ranking = true, -- ترتيب اللاعبين
        rewards = true, -- الجوائز المعلقة والمستلمة
        store = true, -- متجر النقاط
        settings = true, -- تفضيلات العرض
        create = true, -- إنشاء الفعاليات
        manage = true, -- إدارة الفعاليات والمشاركين والفرق
        logs = true, -- السجل الإداري
        system = true, -- حالة الخدمة
        games = true, -- دليل أنماط اللعب المفعلة
        seasons = true, -- تقدم الموسم الحالي والأرشيف
        daily = true, -- هدف المشاركة اليومي
        weekly = true, -- هدف المشاركة الأسبوعي
        achievements = true, -- شارات اللاعب وألقابه
        winners = true, -- نتائج الفعاليات المنشورة
        mine = true, -- تسجيلاتي الحالية
        participants = true, -- شاشة إدارة المشاركين
        teams = true, -- توزيع الفرق
        schedule = true, -- متابعة جداول الإدارة
        templates = true, -- حفظ قوالب الفعاليات وإعادة استخدامها
        announcements = true, -- الإعلانات العامة وآخر مواعيد فتح التسجيل
        statistics = true, -- الإحصائيات الشخصية
        leaders = true -- المتصدرون بحسب الخبرة الإجمالية
    }
}

-- ألوان التابلت. استخدم رمز لون سداسي من ست خانات.
Config.Colors = {
    background = '#080808', -- لون خلفية التابلت
    panel = '#151515', -- لون خلفية البطاقات
    line = '#800020', -- لون الحدود والأزرار الرئيسية
    active = '#a51c45', -- لون التحديد والتقدم
    soft = '#350c19', -- لون عناصر التنقل عند التحديد
    muted = '#a1a1aa', -- لون النص الثانوي
    gold = '#e7b94b' -- لون الإبراز والتركيز
}

-- إعدادات واجهة اللاعب واستهلاكها.
Config.Performance = {
    LiveRefresh = 3000, -- فاصل تحديث تفاصيل الفعالية الجارية بالمللي ثانية
    TabletRequestCooldown = 180, -- حد أدنى بين طلبات التابلت لكل لاعب بالمللي ثانية
    ControlCooldown = 350, -- حد أدنى لطلبات تبديل التابلت وإعدادات لوحة المفاتيح
    IdleClient = 1500, -- فاصل فحص حالة التابلت عندما يكون مغلقاً
    ActiveClient = 300 -- فاصل فحص الموت عندما يكون التابلت مفتوحاً
}
Config.Tablet.DiagnosticsCommand = 'eventsdiag' -- أمر تشخيص المورد

-- قواعد الفعاليات والاقتصاد والتشغيل
Server = {
    Limits = {
        Templates = 40, -- الحد الأعلى للقوالب المحفوظة
        EventCount = 400, -- سقف السجلات ويشمل الفعاليات المنتهية
        Concurrent = 5, -- أقصى عدد فعاليات مفتوحة أو جارية معاً
        Participants = 80, -- سقف التسجيل الفعلي لكل فعالية
        EventAccounts = 300, -- سقف الحسابات المسجلة أو المدعوة لكل فعالية
        Waiting = 40, -- أقصى عدد في قائمة الانتظار
        Fee = 10000, -- الحد الأعلى لرسوم التسجيل النقدية
        Duration = 3600, -- الحد الأعلى لمدة اللعب بالثواني
        Registration = 7200, -- الحد الأعلى لمدة التسجيل بالثواني
        Cooldown = 250, -- مهلة بين طلبات اللاعب بالمللي ثانية
        ActionCooldown = 700, -- مهلة إعادة الإجراء نفسه بالمللي ثانية
        Tick = 1000, -- فاصل معالجة المواعيد بالمللي ثانية
        Logs = 180 -- عدد السجلات الإدارية المحتفظ بها
    },
    Defaults = {
        registration = 300, -- مدة التسجيل الافتراضية بالثواني
        duration = 120, -- مدة اللعب الافتراضية بالثواني
        countdown = 15, -- مدة العد التنازلي الافتراضية
        minimum = 2, -- الحد الأدنى الافتراضي للمشاركين
        maximum = 20 -- الحد الأعلى الافتراضي للمشاركين
    },
    Games = {
        manual = true, -- إدارة النتيجة يدوياً
        draw = true, -- قرعة بين المشاركين المتصلين
        quiz = true -- احتساب الإجابات على الخادم
    },
    Permissions = {
        OpenAdmin = 'events.admin', -- عرض واجهة الإدارة
        Create = 'events.create', -- إنشاء المسودات ونسخها
        Edit = 'events.edit', -- التعديل وفتح التسجيل وتمديده
        Delete = 'events.delete', -- حذف المسودات
        Start = 'events.start', -- بدء العد التنازلي
        Stop = 'events.stop', -- إنهاء الفعالية
        Cancel = 'events.cancel', -- إلغاء الفعالية
        ManagePlayers = 'events.players', -- عرض قائمة المشاركين
        ManageTeams = 'events.teams', -- تعديل فرق المشاركين
        Kick = 'events.kick', -- استبعاد مشارك
        Ban = 'events.ban', -- تقييد مشاركة حساب
        Rewards = 'events.rewards', -- تسوية عمليات التسليم المعلقة
        Refund = 'events.refund', -- إصدار مستحق استرداد
        SetWinner = 'events.winner', -- تعيين فائز لفعالية يدوية
        Announce = 'events.announce', -- إرسال إعلان عام
        Schedule = 'events.schedule', -- جدولة فعالية
        Automatic = 'events.automatic', -- تبديل الجدولة المتكررة
        Logs = 'events.logs', -- مراجعة السجل الإداري
        Diagnostics = 'events.diagnostics' -- عرض مراقبة الخدمة
    },
    Economy = {
        Enabled = false, -- تمكين رسوم التسجيل والجوائز المرتبطة باقتصاد الإطار
        Max = 50000, -- الحد الأعلى لقيمة الجائزة من نوع نقد أو بنك أو عنصر
        Rewards = {
            none = { label = 'بدون جائزة إضافية', kind = 'none', amount = 0 }, -- خيار بلا جائزة
            cash = { label = 'جائزة نقدية', kind = 'cash', amount = 1000 }, -- جائزة للمحفظة
            bank = { label = 'جائزة بنكية', kind = 'bank', amount = 1500 } -- جائزة للحساب البنكي
            -- مثال عنصر: item = { label = 'ماء', kind = 'item', amount = 2, item = 'water' }
        }
    },
    Progress = {
        XP = 25, -- خبرة لكل مشاركة مؤهلة
        WinXP = 50, -- خبرة إضافية للفائز
        Points = 20, -- نقاط الفائز
        PerLevel = 100, -- الخبرة اللازمة للمستوى
        Daily = 5, -- عدد المشاركات التي تمنح خبرة خلال يوم خادم واحد
        SeasonDays = 30, -- طول الموسم بالأيام
        DailyGoal = 2, -- هدف المشاركات اليومي
        WeeklyGoal = 5 -- هدف المشاركات الأسبوعي
    },
    Store = {
        Enabled = true, -- تمكين شراء الألقاب بالنقاط
        Items = {
            champion = { label = 'بطل الفعاليات', price = 40, stock = 100, limit = 1 } -- اللقب والسعر والمخزون وحد الشراء اليومي
        }
    },
    Automatic = {
        Enabled = false, -- تشغيل الجداول المتكررة عند التثبيت الأول
        OffsetMinutes = 180, -- فرق توقيت الجداول عن UTC بالدقائق
        Entries = {
            { key='evening', hour=20, minute=0, weekday=0, online=5, name='قرعة المساء', mode='draw' } -- توقيت محلي، ٠ يومياً أو ١ الأحد حتى ٧ السبت
        }
    },
    Notify = {
        Adapter = 'pNotify', -- pNotify أو nui
        Duration = 3800 -- مدة ظهور تنبيه pNotify بالمللي ثانية
    }
}

-- النصوص العربية المستخدمة في الخادم والواجهات
L = {
    busy = 'النظام مشغول، حاول بعد لحظات.',
    offline = 'الخدمة غير متاحة حالياً.',
    denied = 'لا تملك صلاحية تنفيذ هذا الإجراء.',
    invalid = 'البيانات أو حالة الفعالية غير صالحة لهذا الإجراء.',
    ok = 'تم تنفيذ الإجراء.',
    waiting = 'أضيف اسمك إلى قائمة الانتظار.',
    joined = 'تم تسجيلك في الفعالية.',
    poor = 'رصيد المحفظة غير كافٍ.',
    blocked = 'المشاركة غير متاحة لحسابك حالياً.',
    review = 'تحتاج العملية إلى مراجعة إدارية قبل أي محاولة أخرى.',
    space = 'تحقق من مساحة الحقيبة أو صلاحية تعريف العنصر.',
    mode = { manual = 'فعالية يدوية', draw = 'قرعة', quiz = 'مسابقة أسئلة' },
    state = { draft = 'مسودة', scheduled = 'مجدولة', registration = 'التسجيل مفتوح',
        countdown = 'العد التنازلي', running = 'جارية', completed = 'مكتملة', cancelled = 'ملغاة' },
    status = { joined = 'مسجل', wait = 'انتظار', left = 'منسحب', kicked = 'مستبعد',
        pending = 'جاهزة للاستلام', applying = 'قيد المراجعة', done = 'تم التسليم', void = 'ملغاة' },
    actions = {
        create='إنشاء', edit='تعديل', delete='حذف المسودة', publish='فتح التسجيل',
        schedule='جدولة', lock='إيقاف استقبال التسجيلات', unlock='إعادة فتح التسجيلات', clone='نسخ كمسودة', start='بدء العد التنازلي', stop='إنهاء',
        cancel='إلغاء', extend='تمديد التسجيل', join='تسجيل', promote='طلب ترقية التسجيل من الانتظار', leave='انسحاب',
        team='اختيار الفريق', move='تغيير فريق مشارك', kick='استبعاد',
        ban='تقييد المشاركة', winner='تحديد الفائز', claim='استلام',
        refund='استرداد الرسوم', announce='إعلان', answer='إرسال الإجابة',
        invite='دعوة لاعب', admit='إرسال دعوة إدارية', buy='شراء', automatic='تبديل الجدولة التلقائية',
        review='تسوية عملية', win='نتيجة الفعالية',
        saveTemplate='حفظ قالب', useTemplate='إنشاء مسودة من القالب',
        deleteTemplate='حذف قالب', preferences='تحديث تفضيلات التنبيهات'
    }
}
