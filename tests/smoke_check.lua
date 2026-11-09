local harness = require('tests.harness')
local check = harness.check

harness.load('config.lua')
harness.load('shared/locale.lua')
harness.load('client/eft.lua')

check('config has the snap radius', Config.SnapRadius == 0.035)
check('german text stays as it is', L('Motorhaube') == 'Motorhaube')
Config.Locale = 'en'
check('english text is looked up', L('Motorhaube') == 'Hood')
check('namespace exists', type(EFT) == 'table')

harness.natives.GetGameTimer = function() return 1 end
harness.natives.GetGameTimer = function() return 2 end
check('a re-stubbed native replaces the old one', GetGameTimer() == 2)

Config.Locale = 'de'
