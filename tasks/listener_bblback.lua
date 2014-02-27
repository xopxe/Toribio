local sched = require 'lumen.sched'
local toribio = require 'toribio'

local M = {}

M.init = function()	
	sched.run(function()
		local lback = assert(toribio.wait_for_device('bb-lback'))
		
		while true do
			print(lback.send(sched.get_time()))
			sched.sleep(1)
		end
	end)
	sched.run(function()
		local button = assert(toribio.wait_for_device({module='bb-button'}))
		local v=button.getValue()
		while true do
      local vnew=button.getValue()
      if vnew~=v then 
        v=vnew
        print('button:',v)
      end
 			sched.sleep(0.1)
		end
	end)
end

return M
