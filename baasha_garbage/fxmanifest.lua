fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'baasha_garbage'
author 'Baasha Bhai Studio'
version '1.0.0'
description 'Baasha Garbage Collector — crew routes, compactor, recyclables | requires baasha_jobcore'
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

dependencies {
    'ox_lib',
    'baasha_jobcore',
}
