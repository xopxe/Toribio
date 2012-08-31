--- Library for accesing the accelerometer of a XO 1.75.
-- The device will be named "accelxo", module "accelxo". 
-- @module accelxo
-- @alias device

local M = {}

M.init = function()
	toribio = require 'toribio'

	local sysfs1 = '/sys/devices/platform/lis302dl.1'
	local sysfs1_sample_rate = sysfs1 .. '/sample_rate'
	local sysfs1_threshold = sysfs1 .. '/threshold'
	local stream1=assert(io.open('/dev/input/event3', 'rb'))

	local sysfs2 = '/sys/devices/platform/lis302dl.2'
	local sysfs2_sample_rate = sysfs2 .. '/sample_rate'
	local sysfs2_threshold = sysfs2 .. '/threshold'
	local stream2=assert(io.open('/dev/input/event4', 'rb'))
	
	local get_accel = function(stream)
		local x, y, z
		repeat
			local event = stream:read(16)
			--local time=message:sub(1, 4)
			local etype = event:byte(10) -- only last byte
			local ecode = event:byte(12) -- only last byte
			if etype==1 or etype==2 then
				local evalue = event:byte(13, 14) --2 bytes (~65.5 g)
				local value = 256*evalue[1] + evalue[2]
				if ecode==0 then x=value 
				elseif ecode==1 then y=value 
				elseif ecode==2 then z=value end
			--elseif etype==0 and ecode==0 then
			--	return x, y, z
			end
		until x and y and z
		return x, y, z
	end
	
	local device={
		name="accelopenmoko",
		module="accelopenmoko",
		
		--- Read the acceleration from sensor 1.
		-- The acceleration is measured in mg (1/1000th of earth gravity)
		-- the axis are, when looking from the front and the phone laying on a desk:
		-- x (horizontal to the right and away), y (horizontal to the left and away) 
		-- and z (down)
		-- @return The x, y and z magnitudes.
		get_accel1 = function()
			return get_accel(stream1)
		end,

		--- Read the acceleration from sensor 2.
		-- The acceleration is measured in mg (1/1000th of earth gravity)
		-- the axis are, when looking from the front and the phone laying on a desk:
		-- x (horizontal to the right), y (horizontal and away) 
		-- and z (down)
		-- @return The x, y and z magnitudes.
		get_accel2 = function()
			return get_accel(stream2)
		end,		
		
		--- Set the sample rate for sensor 1.
		-- This is the intarnal sample rate, and the known supported values are
		-- 100 and 400 Hz.
		-- @param hz The rate in hz.
		set_rate1 = function(hz)
			local f=io.open(sysfs1_sample_rate, 'w')
			if not f then return end
			f.write(hz..'\n')
			f.close()
		end,

		--- Set the sample rate for sensor 2.
		-- This is the intarnal sample rate, and the known supported values are
		-- 100 and 400 Hz.
		-- @param hz The rate in hz.
		set_rate1 = function(hz)
			local f=io.open(sysfs2_sample_rate, 'w')
			if not f then return end
			f.write(hz..'\n')
			f.close()
		end,

		
		--- Set the threshold for sensor 1.
		-- Values around 10 or 18 are usual.
		-- @param threshold The threshold value 
		set_threshold1 = function(threshold)
			local f=io.open(sysfs1_threshold, 'w')
			if not f then return end
			f.write(threshold..'\n')
			f.close()
		end,

		--- Set the threshold for sensor 2.
		-- Values around 10 or 18 are usual.
		-- @param threshold The threshold value 
		set_threshold1 = function(threshold)
			local f=io.open(sysfs2_threshold, 'w')
			if not f then return end
			f.write(threshold..'\n')
			f.close()
		end,
		
	}

	_G.debugprint('device object created', device.name)
	toribio.add_device(device)
end

return M
