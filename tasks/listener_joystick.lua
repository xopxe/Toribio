local M = {}

M.init = function(conf)
	local sched = require 'lumen.sched'
	
	return sched.run(function()
		local toribio = require 'toribio'
		local joystick = toribio.wait_for_device({module='joystick'})
		
		toribio.register_callback(joystick, 'move', function(...)
			print('move',...)
		end)
    
		toribio.register_callback(joystick, 'button', function(...)
			print('button',...)
		end)   
  
    joystick.start()
    sched.sleep(1)
    joystick.stop()
  
	end)
end

return M
