-- Runs every tests/*_check.lua in one process. From the repo root: lua tests/run.lua
package.path = './?.lua;' .. package.path
local harness = require('tests.harness')

local windows = package.config:sub(1, 1) == '\\'
local list = io.popen(windows and 'dir /b tests\\*_check.lua' or 'ls tests/*_check.lua')
for line in list:lines() do
    local file = line:match('[^/\\]+$')
    print('== ' .. file)
    dofile('tests/' .. file)
end
list:close()

local failed = harness.finish()
print(failed == 0 and 'all checks passed' or (failed .. ' check(s) failed'))
os.exit(failed == 0 and 0 or 1)
