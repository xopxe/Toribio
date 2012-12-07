--- Library for managing a OpenMoko smartphone.
-- Uses the omhacks tool.
-- See http://manpages.ubuntu.com/manpages/precise/man1/om.1.html
-- @module openmoko
-- @alias device

local M = {}

local run_shell = function(s)
	local f = io.popen(s) -- runs command
	local l = f:read("*a") -- read output of command
	f:close()
	return l
end

M.init = function(conf)
	local toribio = require 'toribio'
	
	local touchscreen_lock

	local device={
		--- Name of the device.
		-- In this case, "openmoko".
		name="openmoko",
		
		--- Module name.
		-- In this case, "openmoko".
		module="openmoko",
--[[
om sysfs name [name...]
-- om backlight brightness [0-100]
*om backlight
*om backlight get-max
*om backlight <brightness>
-- om touchscreen lock
-- om screen power [1/0]
om screen resolution [normal|qvga-normal]
-- om screen glamo-bus-timings [4-4-4|2-4-2]
-- om bt [--swap] power [1/0]
-- om gsm [--swap] power [1/0]
om gsm flowcontrol [1/0]
-- om gps [--swap] power [1/0]
-- om gps [--swap] keep-on-in-suspend [1/0]
om gps send-ubx <class> <type> [payload_byte0] [payload_byte1] ...
-- om wifi [--swap] power [1/0]
-- om wifi maxperf <iface> [1/0]
-- om wifi keep-bus-on-in-suspend [1/0]
om battery temperature
-- om battery energy
om battery consumption
-- om battery charger-limit [0-500]
om power
om power all-off
om resume-reason
om resume-reason contains <val>
* om  led <name>
* om  led <name> <brightness>
-- om  led <name> <brightness> timer <ontime> <offtime>
om uevent dump
-- om usb mode [device|host]
-- om usb charger-mode [charge-battery|power-usb]
-- om usb charger-limit [0|100|500]
--]]

		usb = {
			--- Set USB mode.
			-- In device mode the phone can  talk  to
			-- USB hosts (PCs or phones in host mode). In host mode the phone
			-- can talk to USB  devices. Also see usb.charge.mode
			-- @function usb.mode
			-- @param mode Optional, either 'host' or 'device' changes the mode.
			-- @return The mode as set.
			mode = function(mode)
				if mode then
					assert(mode=='host' or mode=='device', "Supported host mode are 'host' and 'device'")
					if mode=='host' then
						os.execute('ifconfig usb0 down')
					end
					run_shell('om usb mode '..mode)
					os.execute('lsusb') --https://docs.openmoko.org/trac/ticket/2166
					if mode=='device' then
						os.execute('ifconfig usb0 up')
					end
				end
				return run_shell('om usb mode')
			end,
			
			charger= {
				--- Set USB powering mode.
				-- Normally you want to charge
				-- the battery in device mode and power the USB bus  in  host  mode
				-- but  it is possible to for example use an external battery power
				-- the USB bus so that the phone can be  in  host  mode  and  still
				-- charge itself over USB. Also see usb.mode
				-- @function usb.charger.mode
				-- @param direction optional. Either 'charge-battery' or 'power-usb'
				-- @return The direction as set.
				mode = function(chargermode)
					if chargermode then
						assert(chargermode=='charge-battery' or chargermode=='power-usb', 
							"Supported powermodes are 'charge-battery' and 'power-usb'")
						run_shell('om usb charger-mode '..chargermode)
					end
					return run_shell('om usb charger-mode')
				end,
				
				--- Set the current limit on the USB port.
				-- Control the current that the  phone  will  draw
				-- from  the  USB  bus.  When  the phone is in device mode and some
				-- gadget driver is loaded it will negotiate  the  highest  allowed
				-- charging current automatically. However, if you are using a dumb
				-- external USB battery it might be necessary to force larger limit
				-- than the default of 100 mA. Do not set the limit to be too large
				-- if your charger can not handle it!
				-- When powered from an "dumb" device, the phone sets a 100mA limit by default.
				-- @function usb.charger.limit
				-- @param currlim Optional the current limit in mA. Supported values are 0, 100, 500 and 1000.
				-- @return The current limit as set.
				limit = function(currlim)
					if currlim then
						assert(currlim==0 or currlim==100 or currlim==500 or currlim==1000, 
							"Supported currlim values are 0, 100, 500 and 1000")
						run_shell('om usb charger-limit '..currlim)
					end
					return run_shell('om usb charger-limit ')
				end,
			},
		},
		
		touchscreen = {
			--- Locks the touchsreen.
			-- This is useful  when  you want to keep the phone running in a pocket and
			-- don't want the backlight to turn on every time you  accidentally
			-- touch  the screen. Locking is done in a way that does not depend
			-- on X so if X server crashes and restarts your screen will  still
			-- stay locked.
			-- @function touchscreen.lock
			-- @param on True to lock false to unlock, nil to keep.
			-- @return The current lock mode as set.
			 lock = function (on)
				if on and not touchscreen_lock then 
					local out = run_shell('om touchscreen lock &')
					_, _, touchscreen_lock = out:find('%s(%d+)$')
				elseif on~=nil and touchscreen_lock then
					run_shell('kill '..touchscreen_lock)
					touchscreen_lock = nil
				end
				return touchscreen_lock ~= nil
			 end
		},
		
		battery = {
			charger = {
				--- Set the current limit on the battery charger.
				-- Usually is set equal to usb_charge_limit, but can be lower when powering from USB and only want to keep
				-- battery charged and leave enough power for the rest of the phone.
				-- @function battery.charger.limit
				-- @param currlim Optional the current limit in mA. Supported values are 0, 100, 500.
				-- @return The current limit as set.
				limit = function(currlim)
					if currlim then
						assert(currlim==0 or currlim==100 or currlim==500, 
							"Supported currlim values are 0, 100 and 500")
						run_shell('om battery charger-limit '..currlim)
					end
					return run_shell('om battery charger-limit')
				end,
			},
			
			--- Return the battery charge level.
			-- @function battery.energy
			-- @return a percentage of full charge.
			energy = function ()
				return run_shell('om battery energy')
			end,
		},
		
		bt = {
			--- Power the bluetooth module.
			-- @function bt.power
			-- @param power true to enable, false to disable, nil to keep.
			-- @return the mode as set
			power = function(power)
				if power==true then
					run_shell('om bt power 1')
				elseif power==false then
					run_shell('om bt power 0')
				end
				return run_shell('om bt power')=="1"
			end,
		},
		
		gps = {
			--- Power the gps module.
			-- @function gps.power
			-- @param power true to enable, false to disable, nil to keep.
			-- @param keep_on_in_suspend true to enable, false to disable, nil to keep
			-- @return the power as set, the suspend mode as set.
			power = function(power, keep_on_in_suspend)
				if power==true then
					run_shell('om gps power 1')
				elseif power==false then
					run_shell('om gps power 0')
				end
				if keep_on_in_suspend==true then
					run_shell('om gps keep-on-in-suspend 1')
				elseif keep_on_in_suspend==false then
					run_shell('om gps keep-on-in-suspend 0')
				end
				return run_shell('om gps power')=="1", run_shell('om keep-on-in-suspend power')=="1"
			end,
		},
	
		gsm = {
			--- Power the gsm module.
			-- @function gsm.power
			-- @param power true to enable, false to disable, nil to keep.
			-- @return the mode as set
			power = function(power)
				if power==true then
					run_shell('om gsm power 1')
				elseif power==false then
					run_shell('om gsm power 0')
				end
				return run_shell('om gsm power')=="1"
			end,
		},
		
		wifi = {
			--- Power the wifi module.
			-- @function wifi.power
			-- @param power true to enable, false to disable, nil to keep.
			-- @return the mode as set
			power = function(power)
				if power==true then
					run_shell('om wifi power 1')
				elseif power==false then
					run_shell('om wifi power 0')
				end
				return run_shell('om wifi power')=="1"
			end,
			
			--- Enable the maxperf mode for wifi.
			-- Enabling this  increases
			-- energy consumption but lowers latency.
			-- @function wifi.maxperf
			-- @param iface network interface (usually "eth1")
			-- @param on true to power on, false to power down, nil to keep as is.
			-- @return the mode as set
			maxperf = function(iface, on)
				if on==true then
					run_shell('om wifi maxperf '..iface..' 1')
				elseif on==false then
					run_shell('om wifi maxperf '..iface..' 0')
				end
				return run_shell('om wifi maxperf')=="1"
			end,
			
			--- Keep de wifi bus powered on suspend.
			-- Needed for wake on wlan.
			-- @function wifi.keep_bus_on_in_suspend
			-- @param iface network interface (usually "eth1")
			-- @param on true to power on, false to power down, nil to keep as is.
			-- @return the mode as set
			keep_bus_on_in_suspend = function(on)
				if on==true then
					run_shell('om wifi keep-bus-on-in-suspend 1')
				elseif on==false then
					run_shell('om wifi keep-bus-on-in-suspend 0')
				end
				return run_shell('om wifi keep-bus-on-in-suspend')=="1"
			end,
			
		},
		
		screen = {
			--- Power the screen.
			-- @function screen.power
			-- @param power true to enable, false to disable, nil to keep.
			-- @return the mode as set
			power = function(power)
				if power==true then
					run_shell('om screen power 1')
				elseif power==false then
					run_shell('om screen power 0')
				end
				return run_shell('om screen power')=="1"
			end,
			
			--- Control the glamo timings.
			-- Reads  or sets the timings of the memory bus between the CPU and
			-- the glamo graphics chip. Numbers are SRAM interface  timings  of
			-- the CPU. According to http://lists.openmoko.org/pipermail/community/2010-July/062495.html
			-- using 2-4-2 is more appropriate, view that article and following
			-- discussion for more details.
			-- @function screen.glamo_bus_timings
			-- @param timing either '4-4-4' or '2-4-2', nil to keep.
			-- @return the timing as set
			glamo_bus_timings = function(timing)
				if timing then
					assert(timing=='4-4-4' or timing=='2-4-2', 
						"Supported timing values are '4-4-4' and '2-4-2'")
					run_shell('om screen glamo-bus-timings '..timing)
				end
				return run_shell('om screen glamo-bus-timings')
			end,
		},
		
		backlight = {
			--- Control the backlight brigthness.
			-- Reports true brightness only if the screen
			-- has not been blanked with screen.power
			-- @function backlight.brightness
			-- @param level the percentage of maxbrighness, nil to keep.
			-- @return the level as set.
			brightness = function (level)
				if level then
					run_shell('om backlight brightness '..level)
				end
				return run_shell('om backlight brightness')
			end,
		},
		
		led = {
			vibrator = {
				--- Control the vibrator power.
				-- @function led.vibrator.power
				-- @param level the vibrating power, in the 0..255 range
				-- @param ontime if provided with offtime, will blink at the indicated rate (milliseconds)
				-- @param offtime if provided with ontime, will blink at the indicated rate (milliseconds)
				-- @return the level as set.
				power = function (level,ontime,offtime)
					if level then
						if ontime and offtime then
							run_shell('om led vibrator ' .. level .. 
								' timer ' .. ontime .. ' ' .. offtime)
						else
							run_shell('om led vibrator ' .. level)
						end
					end
					return run_shell('om led vibrator')
				end,
			},
			
			power_orange = {
				--- Control the orange light of the power button.
				-- @function led.power_orange.power
				-- @param level the light power, in the 0..255 range
				-- @param ontime if provided with offtime, will blink at the indicated rate (milliseconds)
				-- @param offtime if provided with ontime, will blink at the indicated rate (milliseconds)
				-- @return the level as set.
				power = function (level,ontime,offtime)
					if level then
						if ontime and offtime then
							run_shell('om led power_orange ' .. level .. 
								' timer ' .. ontime .. ' ' .. offtime)
						else
							run_shell('om led power_orange ' .. level)
						end
					end
					return run_shell('om led power_orange')
				end,
			},
			
			power_blue = {
				--- Control the blue light of the power button.
				-- @function led.power_blue.power
				-- @param level the light power, in the 0..255 range
				-- @param ontime if provided with offtime, will blink at the indicated rate (milliseconds)
				-- @param offtime if provided with ontime, will blink at the indicated rate (milliseconds)
				-- @return the level as set.
				power = function (level,ontime,offtime)
					if level then
						if ontime and offtime then
							run_shell('om led power_blue ' .. level .. 
								' timer ' .. ontime .. ' ' .. offtime)
						else
							run_shell('om led power_blue ' .. level)
						end
					end
					return run_shell('om led power_blue')
				end,
			},
			
			aux_red = {
				--- Control the red light of the aux button.
				-- @function led.aux_red.power
				-- @param level the light power, in the 0..255 range
				-- @param ontime if provided with offtime, will blink at the indicated rate (milliseconds)
				-- @param offtime if provided with ontime, will blink at the indicated rate (milliseconds)
				-- @return the level as set.
				power = function (level,ontime,offtime)
					if level then
						if ontime and offtime then
							run_shell('om led aux_red ' .. level .. 
								' timer ' .. ontime .. ' ' .. offtime)
						else
							run_shell('om led aux_red ' .. level)
						end
					end
					return run_shell('om led aux_red')
				end,
			},
			
		},
	}
	
	local conf_params = {
		usb_charger_mode = device.usb.charger.mode,
		usb_charger_limit = device.usb.charger.limit,
		battery_limit = device.battery.charger.limit,
	}
	
	for k, v in pairs (conf_params) do
		local confvalue = conf[k]
		if confvalue then 
			_G.debugprint('om from configuration', k, confvalue)
			v(confvalue)
		end
	end
	
	_G.debugprint('device object created', device.name)
	toribio.add_device(device)

end

return M

