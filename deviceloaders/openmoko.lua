--- Library for managing a OpenMoko smartphone.
-- At the moment, supports FreeRunner under SHR-testing.
-- @module openmoko
-- @alias device

local M = {}

local usb_mode_file = '/sys/devices/platform/s3c-ohci/usb_mode'
local hostmode_file = '/sys/devices/platform/s3c2440-i2c/i2c-adapter/i2c-0/0-0073/neo1973-pm-host.0/hostmode'
local battery_status_file = '/sys/class/power_supply/battery/status'
local usb_currlim_file = '/sys/devices/platform/s3c2440-i2c/i2c-adapter/i2c-0/0-0073/pcf50633-mbc/usb_curlim'

local function read_file(fname)
	local f=io.open(fname, 'r')
	if not f then return end
	local l=f:read('*l')
	f:close()
	return l
end

local function write_file(fname, data)
	local f=io.open(fname, 'w')
	if not f then return end
	f:write(data..'\n')
	f:close()
	return true
end



M.init = function(conf)
	local toribio = require 'toribio'

	local device={
		--- Name of the device.
		-- In this case, "openmoko".
		name="openmoko",
		
		--- Module name.
		-- In this case, "openmoko".
		module="openmoko",
		
		--- Set USB mode.
		-- @param mode Optional, either 'host' or 'device' changes the mode.
		-- @return The mode as set.
		usb_mode = function(mode)
			if mode then
				assert(mode=='host' or mode=='device', "Supported host mode are 'host' and 'device'")
				if mode=='host' then
					os.execute('ifconfig usb0 down')
				end
				write_file(usb_mode_file, mode)
				os.execute('lsusb') --https://docs.openmoko.org/trac/ticket/2166
				if mode=='device' then
					os.execute('ifconfig usb0 up')
				end
			end
			return read_file(usb_mode_file)
		end,
		
		--- Set USB power.
		-- @param direction optional. If 'out', the phone is powering the connected devices. If 'in'
		-- the phone charges from the port.
		-- @return The direction as set.
		usb_power_direction = function(direction)
			if direction then
				assert(direction=='in' or direction=='out', "Supported powerdir are 'in' and 'out'")
				local direction_code
				if direction=='in' then direction_code=0
				elseif direction=='out' then direction_code=1 end
				write_file(hostmode_file, direction_code)
			end
			local direction_code = read_file(hostmode_file)
			if direction_code=='0' then return 'in'
			elseif direction_code=='1' then return 'out' end
			return direction_code
		end,
		
		--- Set the current limit on the USB port.
		-- When powered from an "dumb" device, the phone sets a 100mA limit by default.
		-- @param currlim Optional the current limit in mA. Supported values are 0, 100, 500 and 1000.
		-- @return The current limit as set.
		usb_currlim = function(currlim)
			if currlim then
				assert(currlim==0 or currlim==100 or currlim==500 or currlim==1000, 
					"Supported currlim values are 0, 100, 500 and 1000")
				write_file(usb_currlim_file, currlim)
			end
			return read_file(usb_currlim_file)
		end,
		
		--- Get the battery satus.
		-- @return The battery charging status, suhch as 'Charging' or 'Not charging'.
		battery_status = function()
			return read_file(battery_status_file)
		end
	}

	for _, param in ipairs({'usb_mode', 'usb_power_direction', 'usb_currlim'}) do
		if conf[param] and device[param] then
			device[param](conf[param])
		end
	end
	
	_G.debugprint('device object created', device.name)
	toribio.add_device(device)

end

return M

