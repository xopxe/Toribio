local M = {}
local toribio = require 'toribio'
local sched = require 'sched'
local catalog_events = require 'catalog'.get_catalog('events')
local catalog_tasks = require 'catalog'.get_catalog('tasks')

M.init = function(conf)
	toribio.start('tasks', 'proxy')

	local event_move_bot = 'move_bot'
	catalog_events:register('move_bot', event_move_bot)
	
	local function generate_output (x, y)
		local left = tostring( (y + x)/2 )
		local right = tostring( (y - x)/2 )
		sched.signal(event_move_bot, left, right)
	end

	sched.run(function()
		local mice = toribio.wait_for_device('mice:/dev/input/mice')
		assert(catalog_tasks:register('mice', mice.task))
		print ('registering event', 'move', mice.events.move)
		assert(catalog_events:register('move', mice.events.move))
		print ('registered event', 'move', catalog_events:waitfor('move', 0))
		print ('registering event', 'leftbutton', mice.events.leftbutton)
		assert(catalog_events:register('leftbutton', mice.events.leftbutton))

		mice:register_callback('move', function (x, y)
			--print (x, y)
		end)

		
		--[[
		local lastx, lasty = 0, 0
		mice:register_callback('move', function (x, y)
			if not x then 
				-- timeout with no mouse movements
				generate_output(lastx, lasty)
			else
				generate_output(x, y)
				lastx, lasty = x, y
			end
		end, 0.5)
		
		mice:register_callback('leftbutton', function (v)
			if v then 
				generate_output(0, 0)
				mice.reset_pos(0, 0)
				lastx, lasty = 0, 0
			end
		end)
		--]]
	end)
end

return M
