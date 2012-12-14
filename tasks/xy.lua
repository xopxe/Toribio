local M = {}

M.init = function(conf)
	local sched=require 'sched'
	sched.run(function()
		print('xy starting')
		local toribio = require 'toribio' 
		
		local mice = toribio.wait_for_device('mice:/dev/input/mice')
		print('xy got mice',mice)
		mice.reset_pos(512,512)
		
		local dynamixelbus = toribio.wait_for_device('dynamixel:/dev/ttyUSB0')
		print('xy got dynamixelbus',dynamixelbus)
		local motor_x = toribio.wait_for_device(conf.motor_x)
		print('xy got motor_x',motor_x)
		local motor_y = toribio.wait_for_device(conf.motor_y)
		print('xy got motor_y',motor_y)

		motor_x.init_mode_joint()
		motor_y.init_mode_joint()
		
		--print ('torqueenable:', dynamixelbus.get_broadcaster().set_torque_enable(false))
		dynamixelbus.get_broadcaster().set_speed(0)

		local pressed=false
		
		toribio.register_callback(mice, 'leftbutton', function(v)
			print('left!',v)
			pressed=v
		end)
		
		toribio.register_callback(mice, 'move', function(x, y)
			--print('move!',x,y)
			if pressed==true then
				motor_x.set_position(x/5)
				motor_y.set_position(y/5)
			end
		end)
	end)
end

return M
