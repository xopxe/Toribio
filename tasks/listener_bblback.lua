local M = {}

M.start = function()
	local sched = require 'sched'
	
	return sched.run(function()
		local toribio = require 'toribio'
		local lback = toribio.wait_for_device('bb-lback')
		
		while true do
			lback.send(sched.get_time())
			--sched.sleep(1)
			print(lback.read())
			--sched.sleep(1)
			sched.yield()
		end
	end)
end

return M
