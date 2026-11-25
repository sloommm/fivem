fx_version 'adamant'
game 'gta5'
author 'MADE BY SLOM'
description 'نظام الفعاليات'

ui_page 'html/index.html'
files { 'html/index.html', 'html/style.css', 'html/app.js', 'html/assets/*' }

dependencies { 'vrp_mysql', 'mysql-async', 'vrp' }
server_scripts {
    '@vrp/lib/utils.lua',
    '@mysql-async/lib/MySQL.lua',
    'config.lua',
    'server_config.lua',
    'server.lua'
}
client_script 'client.lua'
