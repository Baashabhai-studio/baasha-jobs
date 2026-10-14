fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'baasha_delivery'
author 'Baasha Bhai Studio'
version '1.0.0'
description 'Baasha Delivery Driver: parcel routes, van loading puzzle, signatures & fragile cargo | requires baasha_jobcore'
repository 'https://www.baashabhai.com'

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

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
}

dependencies {
    'ox_lib',
    'baasha_jobcore',
}
