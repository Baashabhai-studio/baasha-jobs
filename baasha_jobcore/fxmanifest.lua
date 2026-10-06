fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'baasha_jobcore'
author 'Baasha Bhai Studio'
version '1.0.0'
description 'Baasha Job Core — crews, XP, job tablet & framework bridge for Baasha civilian jobs | ESX / QBCore / Qbox'
repository 'https://www.baashabhai.com'

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
}

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'locales/*.lua',
    'shared/*.lua',
}

client_scripts {
    'bridge/client.lua',
    'editable/client.lua',
    'client/*.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'bridge/server.lua',
    'editable/server.lua',
    'server/*.lua',
}

dependencies {
    'ox_lib',
    'oxmysql',
}
