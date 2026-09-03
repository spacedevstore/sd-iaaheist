fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author '.fobya'
description 'SpaceDev IAA Heist'
version '1.0.0'

shared_scripts {
    'config.lua',
    'local.lua',
    'bridge.lua'
}

client_scripts {
    'client.lua',
    'guards.lua'
}

server_scripts {
    'server.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js'
}

escrow_ignore {
    'config.lua',
    'local.lua',
    'bridge.lua',
    'server.lua',
    'client.lua',
    'guards.lua',
    'html/*'
}

