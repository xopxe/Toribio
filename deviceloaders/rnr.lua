--- Library for using a Rnr content based bus.
-- @module rnr
-- @alias device

local M = {}

M.init = function(conf)
	local toribio = require 'toribio'
	local selector = require 'tasks/selector'
	local sched = require 'sched'
	local log = require 'log'
	
	local ip = conf.ip or '127.0.0.1'
	local port = conf.port or 8182
	
	local device={
		--- Name of the device (in this case, 'gpsd').
		name = 'rnr', 
		
		--- Module name (in this case, 'gpsd').
		module = 'rnr', 
		
		--- Task that will emit signals associated to this device.
		task = selector.task,  
		
		--- Events emitted by this device.
		-- @field notification_arrival a new notification has arrived.  The first parameter is a table with the notifications content.
		events = { 
			notification_arrival = {}
		},
	}
	
	local function parse_params(data)
		local params={}
		local k, v
		for _, linea in ipairs(data) do
			k, v =  string.match(linea, "^%s*(.-)%s*=%s*(.-)%s*$")
			if k and v then
				params[k]=v
			end
		end

		--[[
		if configuration.use_sha1 then
			local signstatus=sign_message(params)
			print("SHA1 signature: ", signstatus)
			if signstatus~='ok' then 
				print("WARN: Purging message (signature check failure)")
				params={} 
			end
		end
		--]]
		for k, v in pairs(params) do
			params[k]=v
		end
		return params
	end
	
	local function get_incomming_handler()
		local notification_lines
		return function(sktd, line, err) 
			--print ('', data)
			if not line then return end
			
			if line == 'NOTIFICATION' then
				notification_lines = {}
			elseif line == 'END' then
				if notification_lines then
					local notification = parse_params(notification_lines)
					sched.signal(device.events.notification_arrival, notification)
					notification_lines = nil
				end
			else
				notification_lines[#notification_lines+1]=line
			end
	
			return true
		end
	end
	local skt = selector.new_tcp_client(ip, port, nil, nil, 'line', get_incomming_handler())
	device.skt = skt
	
	--- Add a Subscription.
	-- When subscribed, matching notification will arrive as signals (see @{events})
	-- @param subscrib_id a unique subscription id. If nil, a random one will be generated.
	-- @param filter an array contaning the subscription filter. Each entry in the array is a table
	-- containing 'attr', 'op' and 'value' fields describing an expression.
	-- @usage local rnr = bobot.wait_for_device('rnr')
	--rnr.subscribe( 'subscrib100', {
	--	{attrib='sensor', op='=', value='node1'},
	--	{attrib='temperature', op='>', value='30'},
	--})
	device.subscribe = function (subscrib_id, filter) 
		subscrib_id = subscrib_id or tostring(math.random(2^30))
		local vlines={[1]='SUBSCRIBE', [2]='subscription_id='..subscrib_id, [3] = 'FILTER'}
		for _, r in ipairs(filter) do
			vlines[#vlines+1]= tostring(r.attrib) .. r.op .. tostring(r.value)
		end
		vlines[#vlines+1]= 'END\n'
		local s = table.concat(vlines, '\n')
		skt.send_sync(s)
	end

	--- Remove a Subscription.
	-- @param subscrib_id a unique subscription id.
	device.unsubscribe = function (subscrib_id) 
		local s ='UNSUBSCRIBE\nsubscription_id='..subscrib_id.. '\nEND\n'
		skt.send_sync(s)
	end
	
	
	--- Emit a Notification.
	-- @param notif_id a unique notification id. If nil, a random one will be generated.
	-- @param data a table with the data to be sent.
	-- @usage local rnr = bobot.wait_for_device('rnr')
	--rnr.subscribe( 'notif100', {sensor = 'node2', temperature = 25} )
	device.emit_notification = function (notif_id, data)
		notif_id = notif_id or tostring(math.random(2^30))
		local vlines={[1]='NOTIFICATION', [2]='notification_id='..notif_id}
		for k, v in pairs(data) do
			vlines[#vlines+1]= tostring(k) .. '=' .. tostring(v)
		end
		vlines[#vlines+1]= 'END\n'
		local s = table.concat(vlines, '\n')
		skt.send_sync(s)
	end
	
	log('RNR', 'INFO', 'Device %s created: %s', device.module, device.name)
	toribio.add_device(device)
end

return M

--- Configuration Table.
-- This table is populated by toribio from the configuration file.
-- @table conf
-- @field ip the ip where the Rnr agent listens (defaults to '127.0.0.1')
-- @field port the port where the Rnr agent listens (defaults to 8182)