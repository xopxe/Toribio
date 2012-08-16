--- Library for using usb4butia boards.
-- This library interface with bobot library for
-- accessing usb4butia-attached devices. It supports hotplug.
-- There will be one object of this type for each bobot device.
-- Bobot device's methods (it's api in the bobot terms) are 
-- available.
-- @module bobot
-- @alias device

local M = {}

local TIMEOUT_REFRESH = 3 -- -1

--local my_path = debug.getinfo(1, "S").source:match[[^@?(.*[\/])[^\/]-$]]
--package.path = package.path .. ";"..my_path.."../../bobot/?.lua"

local sched=require 'sched'
local toribio = require 'toribio'
local bobot  -- = require 'bobot'

--propagate debug print to bobot
local debugprint = _G.debugprint

local devices_attached = {}

local function check_open_device(d, ep1, ep2)
	if not d then return end
	if d.handler or not d.open then return true end

        -- if the device is not open, then open the device
	debugprint ("Opening", d.name, d.handler)
	return d:open(ep1 or 1, ep2 or 1) --TODO asignacion de ep?
end


local function get_device_name(d)
--print("DEVICENAME", d.module, d.hotplug, d.handler)
	local board_id, port_id = '', ''
	if #bobot.baseboards>1 then
		board_id='@'..d.baseboard.idBoard
	end
	if d.hotplug then 
		port_id = ':'..d.handler
	end
	
	local n=d.module..board_id..port_id

	return n
end

local function read_devices_list()
	--debugprint("=Listing Devices")
	local bfound
	local devices_attached_now = {}
	for _, bb in ipairs(bobot.baseboards) do
		--debugprint("===board ", bb.idBoard)
		for _,d in ipairs(bb.devices) do
			local regname = get_device_name(d)
			d.name=regname
			--debugprint("=====module ",d.module," name",regname)
			devices_attached_now[regname]=d
		end
		bfound = true
	end
	for regname, _ in pairs(devices_attached) do
		if not devices_attached_now[regname] then
			devices_attached[regname]=false
			toribio.remove_devices({name=regname})
		end
	end
	for regname, d in pairs(devices_attached_now) do
		if not devices_attached[regname] then
			if check_open_device(d, nil, nil) then
				local device ={
					--- Name of the device.
					-- Starts with 'bb-' and then the name provided
					-- by bobot. For example, "bb-dist:1".
					name='bb-'..d.name,

					--- Module of the device.
					-- Starts with 'bb-' and then the module provided
					-- by bobot. For example, "bb-dist".
					module="bb-"..d.module,
				}
				for fn, ff in pairs(d.api or {}) do device[fn]=ff.call end
				toribio.add_device(device)
				devices_attached[regname]=device
			else
				print ('Error opening', d.name)
			end
		end
	end
	
	if not bfound then debugprint("bb:WARN: No Baseboard found.") end
end

local function server_refresh ()
	for i, bb in ipairs(bobot.baseboards) do
		if not bb:refresh() then
			bobot.baseboards[i]=nil
		end
	end
	read_devices_list()
end


M.start = function (conf)

	if conf.path then 
		if conf.path:sub(1,1)=='/' then
			package.path = package.path .. ";"..conf.path..'/?.lua'
		else
			local my_path = debug.getinfo(1, "S").source:match[[^@?(.*[\/])[^\/]-$]]
			package.path = package.path .. ";"..my_path..conf.path..'/?.lua'
		end
	end
	
	bobot  = require 'bobot'

	if debugprint then 
		bobot.debugprint = debugprint
	end
	debugprint=debugprint or function() end
	
	bobot.init(conf.comms)
	read_devices_list()
	sched.sigrun({
		emitter='*', 
		buff_size=1, 
		timeout=TIMEOUT_REFRESH, 
		events={'do_bobot_refresh'}
	}, server_refresh)
end

return M
