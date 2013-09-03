local M = {}
M.init = function(conf)
	local toribio = require 'toribio'
	local mice = toribio.wait_for_device({module='mice'})
	
	toribio.register_callback(mice, 'leftbutton', function(v)
			print('left:',v)
	end)
	--[[
	toribio.register_callback(mice, 'move', function(x, y)
		print('move:',x,y)
	end)
	--]]
end
return M
