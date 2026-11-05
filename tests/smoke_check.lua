local harness = require('tests.harness')
local check = harness.check

harness.load('config.lua')
harness.load('shared/locale.lua')
harness.load('client/eft.lua')

check('config has the snap radius', Config.SnapRadius == 0.035)
check('german text stays as it is', L('Fahrzeug') == 'Fahrzeug')
Config.Locale = 'en'
check('english text is looked up', L('Fahrzeug') == 'Vehicle')
check('namespace exists', type(EFT) == 'table')
