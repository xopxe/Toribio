local M = {}

local toribio = require 'toribio'

M.init = function()
	local sched = require 'sched'
	
	return sched.run(function(conf)
		local accelxo = toribio.wait_for_device('accelxo')
		while true do
			print (accelxo.get_accel())
			sched.sleep(conf.interval or 0.5)
		end
	end)
end

return M