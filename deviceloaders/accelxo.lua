--- Library for accesing the accelerometer of a XO 1.75.
-- The device will be named "accelxo", module "accelxo". 
-- @module accelxo
-- @alias device

local M = {}

M.init = function(conf)
	toribio = require 'toribio'

	local sysfs = conf.filename or '/sys/devices/platform/lis3lv02d'
	local sysfs_position = sysfs .. '/position'
	local sysfs_selftest = sysfs .. '/selftest'
	local sysfs_rate = sysfs .. '/rate'
		
	local device={
		name="accelxo",
		module="accelxo",
		filename=sysfs,
		
		--- Read the acceleration.
		-- @return The x, y and z magnitudes.
		get_accel = function()
			local f=io.open(sysfs_position, 'r')
			if not f then return end
			local l=f:read('*a')
			if not l then return end
			local x, y, z = l:match('^%(([^,]+),([^,]+),([^,]+)%)$')
			f:close()
			return tonumber(x), tonumber(y), tonumber(z)
		end,

		--- Set the sensor sample rate.
		-- This is the intarnal sample rate, and the supported values are
		-- 1, 10, 25, 50, 100, 200, 400, 1600, and 5000 Hz.
		-- The driver has a limit on reading at about 25 Hz.
		-- @param hz The rate in hz.
		set_rate = function(hz)
			local f=io.open(sysfs_rate, 'w')
			if not f then return end
			f.write(hz..'\n')
			f.close()
		end,
		
		--- Run the sensor internal self test.
		-- @return _true_ on success or _false,v1,v2,v3_ on failure.
		check = function()
			local f=io.open(sysfs_selftest, 'r')
			if not f then return end
			local l = f:read('*l')
			f:close()
			local result, v1,v2,v3=l:match('^(%S+)%s(%S+)%s(%S+)%s(%S+)$')
			return result=='OK', v1, v2, v3
		end

	}

	_G.debugprint('device object created', device.name)
	toribio.add_device(device)
end

return M
