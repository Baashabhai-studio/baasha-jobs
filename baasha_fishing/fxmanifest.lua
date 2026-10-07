fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'baasha_fishing'
author 'Baasha Bhai Studio'
version '1.0.0'
description 'Baasha Fishing — shore & deep-sea boat fishing, reeling minigame, 25 species, fish market | requires baasha_jobcore'
repository 'https://www.baashabhai.com'

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
    'web/deepdrop.js',
    'web/images/*.png',
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
