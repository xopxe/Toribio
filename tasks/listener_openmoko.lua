local M = {}

local toribio = require 'toribio'

M.init = function(conf)
	local sched = require 'sched'
	
	--sched.run(function()
	
		local om = toribio.wait_for_device('openmoko')
		local accel2 = toribio.wait_for_device('accelerometer.2')

		print('om found', om.name, accel2.name)

		sched.run( function()
			local usb_currlim = om.usb_currlim()
			local battery_status = om.battery_status()
			
			local usb_mode = om.usb_mode()
			if usb_mode~= 'host' then 
				print ('usb_mode', om.usb_mode('host'))
			end

			local usb_power_direction = om.usb_power_direction()
			if usb_power_direction ~= conf.usb_power_direction then 
				print ('usb_power_direction', om.usb_power_direction(conf.usb_power_direction))
			end
			print ('usb_currlim', om.usb_currlim(500))
			print ('battery_status', om.battery_status())
			
			sched.sleep(2)
			
			toribio.start('deviceloaders', 'dynamixel')
		end)

		sched.run(function()
			local motor_left = toribio.wait_for_device('ax12:3')
			local motor_right = toribio.wait_for_device('ax12:12')
			print ('motors found', motor_left.name, motor_right.name)

			sched.sigrun(
				{accel2.events.data},
				function(_,x,y,z)
					--print (100*x/1000,100*y/1000)
					motor_left.spin(100*x/500)
					motor_right.spin(100*y/500)
				end
			)
		end)

		sched.sigrun(
			{accel2.events.data},
			function(_,x,y,z)
				print (100*x/1000,100*y/1000)
			end
		)
		
		accel2.run(true,0.01)
		
	--end)
end

return M
