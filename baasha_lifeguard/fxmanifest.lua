fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'baasha_lifeguard'
author 'Baasha Bhai Studio'
version '1.1.0'
description 'Baasha Lifeguard & Beach Rescue (free): tower watch, water rescues, CPR, first aid, shark alerts | requires baasha_jobcore'
repository 'https://www.baashabhai.com'

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
    'web/cpr.js',
    'web/scope.js',
}

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'locales/*.lua',
    '@baasha_jobcore/shared/utils.lua',
}

client_scripts {
    '@baasha_jobcore/bridge/client.lua',
    'client/*.lua',
}

server_scripts {
    'server/*.lua',
}

dependencies {
    'ox_lib',
    'baasha_jobcore',
}
