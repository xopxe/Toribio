local M = {}

M.init =  function(conf)
	local sched = require 'lumen.sched'
	local toribio = require 'toribio' 
	
	--assert(conf.serial_speed)

	sched.run(function()
		local dynamixelbus = toribio.wait_for_device(conf.devicename or 'dynamixel:/dev/ttyUSB0')
		local bcaster = dynamixelbus.get_broadcaster()
		print ('GOING TO SET SERIAL SPEED ON ALL MOTORS TO', conf.serial_speed, 'IN 5 SECONDS!')
    print ('GOING TO SET ID ON ALL MOTORS TO', conf.new_id, 'IN 5 SECONDS!')

		sched.sleep(5)
		print('NOW!')
		if tonumber(conf.serial_speed) then bcaster.set.baud_rate(tonumber(conf.serial_speed)) end
		if tonumber(conf.new_id) then bcaster.set.id(tonumber(conf.new_id)) end
		print('DONE')
	end)
end

return M
