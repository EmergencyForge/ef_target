fx_version 'cerulean'
game 'gta5'

author 'EmergencyForge'
description 'EF Target - third-eye targeting for FiveM'
-- Raise before tagging: the escrow upload and update checks read it from here
version '2026.1.0'

lua54 'yes'

dependency 'ef_lib'

provide 'ox_target'
provide 'qb-target'
provide 'qtarget'

ui_page 'web/dist/index.html'

shared_scripts {
    'config.lua',
    'shared/locale.lua'
}

client_scripts {
    'client/eft.lua',
    'client/geometry.lua',
    'client/registry.lua',
    'client/framework/esx.lua',
    'client/framework/qb.lua',
    'client/framework/ox.lua',
    'client/framework/init.lua',
    'client/filter.lua',
    'client/points.lua',
    'client/menu.lua',
    'client/select.lua',
    'client/nui.lua',
    'client/session.lua',
    'client/accent.lua',
    'client/spring.lua',
    'client/render.lua',
    'client/scan.lua',
    'client/near.lua',
    'client/input.lua',
    'client/defaults.lua',
    'client/compat/ox.lua',
    'client/compat/qb.lua',
    'client/exports.lua'
}

files {
    'web/dist/**/*',
    'assets/*.png'
}

-- Open source under GPL-3.0: nothing gets encrypted on a Cfx escrow upload
escrow_ignore {
    '*.lua',
    '*.md',
    'client/**',
    'server/**',
    'shared/**',
    'tests/**',
    'docs/**',
    'web/**',
}
