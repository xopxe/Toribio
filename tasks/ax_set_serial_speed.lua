local M = {}

M.init =  function(conf)
	local sched = require 'sched'
	local toribio = require 'toribio' 
	
	assert(conf.serial_speed)

	sched.run(function()
		local dynamixelbus = toribio.wait_for_device(conf.devicename or 'dynamixel:/dev/ttyUSB0')
		local bcaster = dynamixelbus.get_broadcaster()
		print ('GOING TO SET SERIAL SPEED ON ALL MOTORS TO', conf.serial_speed, 'IN 5 SECONDS!')
		
		sched.sleep(5)
		print('NOW!')
		bcaster.set.baud_rate(tonumber(conf.serial_speed))
		print('DONE')
	end)
end

return M
