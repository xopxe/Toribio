local M = {}

M.init = function(conf)
	toribio = require 'toribio'

	local path = conf.filename or '/sys/devices/platform/lis3lv02d'
	local filename = path .. '/position'	
	local device={
		name="accelxo",
		module="accelxo",
		filename=filename,
		get_accel = function()
			local f=io.open(filename, 'r')
			local l=f:read('*a')
			local x, y, z = l:match('^%(([^,]+),([^,]+),([^,]+)%)$')
			f:close()
			return tonumber(x), tonumber(y), tonumber(z)
		end,
	}

	_G.debugprint('device object created', device.name)
	toribio.add_device(device)
end

return M
