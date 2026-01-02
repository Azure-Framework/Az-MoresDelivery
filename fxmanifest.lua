fx_version 'cerulean'
game 'gta5'

author 'Azure(TheStoicBear)'
description 'Mors Mutual-style vehicle delivery (AI drives your stored vehicle to you)'
version '1.0.0'

lua54 'yes'

ui_page 'html/index.html'

files {
  'html/index.html',
  'html/style.css',
  'html/app.js'
}

shared_scripts {
      '@ox_lib/init.lua',
  'config.lua'
}

client_scripts {
  'client.lua'
}

server_scripts {
  'server.lua'
}
