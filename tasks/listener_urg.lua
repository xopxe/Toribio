local M = {}

M.init = function(conf)
	local sched = require 'lumen.sched'
	
	return sched.run(function()
		local toribio = require 'toribio'
		local urg = toribio.wait_for_device({module='urg'})
		
		---[[
		toribio.register_callback(urg, 'reading', function(cmd, status, ts, measures)
      --[[
			print('+reading')
      print(cmd, status, ts, #measures)
      print(table.concat(measures,' '))
			print('-reading')
      --]]
      local min_i, min_val = 0, math.huge
      for i=1, #measures do
        local v = measures[i]
        --print ('?', i, v)
        if v>19 and v<min_val then
          min_i, min_val = i, v
        end
      end
      if min_i>0 then   
        local angle = (min_i - (#measures/2)) * 240/683
        print ('>', angle, min_val)
      end
		end)
		--]]
    
    urg.get_version()
    sched.sleep(1)
      
    urg.read(120, true)
    sched.sleep(5)
    urg.stop()
    while true do
      --urg.read(120)
      sched.sleep(5)
      urg.stop()
    end
    

		--[[
		local waitd = {
			emitter=mice.task, 
			timeout=conf.timeout or 1, 
			events={mice.events.leftbutton, mice.events.rightbutton, mice.events.middlebutton}
		}
		while true do
			local emitter, ev, v = sched.wait(waitd)
			if emitter then 
				--print('mice:', ev, v) 
			else
				print(mice.get_pos())
			end
		end
		--]]
	end)
end

return M
