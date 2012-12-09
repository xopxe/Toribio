--- Library for accesing gpsd.
-- The device will be named "gpsd", module "gpsd". 
-- @module gpsd
-- @alias device

local M = {}

M.init = function(conf)
	local toribio = require 'toribio'
	local selector = require 'tasks/selector'
	local sched = require 'sched'
	local json = require 'lib/dkjson'
	local log = require 'log'
	
	local ip = conf.ip or '127.0.0.1'
	local port = conf.port or 2947
	
	local device={
		name = 'gpsd',
		module = 'gpsd',
		task = selector.task, 
		events = { --singletons
			VERSION = {}, 
			WATCH = {}, 
			DEVICES = {},
			DEVICE = {},
			TPV = {}, 
			AIS = {},
		},
	}
	local events=device.events
	
	local function get_incomming_handler()
		local buff = ''
		return function(sktd, data, err) 
			if not data then sched.running_task:kill() end
			buff = buff .. data
			--print ('incomming', buff)
			local decoded, index, e = json.decode(buff)
			if decoded then 
				buff = buff:sub(index)
				sched.signal(events[decoded.class], decoded) 
			else
				log('GPSD', 'ERROR', 'failed to jsondecode buff  with length %s with error "%s"', tostring(#buff), tostring(index).." "..tostring(e))
			end
		end
	end
	local sktd_gpsd = selector.new_tcp_client(ip, port, nil, nil, 10000, get_incomming_handler())
	
	device.set_watch = function(enable)
		if enable then 
			sktd_gpsd:send_sync('?WATCH={"enable":true,"json":true}')
		else
			sktd_gpsd:send_sync('?WATCH={"enable":false}')
		end
	end
	
	toribio.add_device(device)
end

return M
