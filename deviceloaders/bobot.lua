--- Library for using usb4butia boards.
-- This library interface with bobot library for
-- accessing usb4butia-attached devices. It supports hotplug.
-- There will be one object of this type for each bobot device.
-- Bobot device's methods (it's api in the bobot terms) are 
-- available.
-- @module bobot
-- @alias device

local M = {}

--local my_path = debug.getinfo(1, "S").source:match[[^@?(.*[\/])[^\/]-$]]
--package.path = package.path .. ";"..my_path.."../../bobot/?.lua"

local sched=require 'lumen.sched'
local toribio = require 'toribio'
local bobot  -- = require 'bobot'
local log = require 'lumen.log'

local devices_attached = {}

local function check_open_device(d, ep1, ep2)
	if not d then return end
	if d.handler or d.name=='pnp' then return true end --FIXME bug in usb4butia pnp module

        -- if the device is not open, then open the device
	log('BOBOT', 'INFO', 'Opening %s on %s', tostring(d.name), tostring(d.handler))
 
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
	local bfound
	local devices_attached_now = {}
	for _, bb in ipairs(bobot.baseboards) do
		for _,d in ipairs(bb.devices) do
			local regname = get_device_name(d)
			d.name=regname
			devices_attached_now[regname]=d
		end
		bfound = true
	end

	for regname, d in pairs(devices_attached) do
		if not devices_attached_now[regname] then
			toribio.remove_devices({name=d.name})
			devices_attached[regname]=nil
		end
	end


	for regname, dv in pairs(devices_attached_now) do
		if not devices_attached[regname] then
		--	if check_open_device(d, nil, nil) then
				local device ={
					--- Name of the device.
					-- Starts with 'bb-' and then the name provided
					-- by bobot. For example, "bb-dist:1".
					name='bb-'..dv.name,

					--- Module of the device.
					-- Starts with 'bb-' and then the module provided
					-- by bobot. For example, "bb-dist".
					module="bb-"..dv.module,
				}
				device.bobot_metadata = {}
				for fn, ff in pairs(dv.api or {}) do 
					device.dev = dv
					device[fn]=ff.call 
					device.bobot_metadata[ff.call] = {
						parameters = ff.parameters,
						returns = ff.returns,
					}
				end
				toribio.add_device(device)
				devices_attached[regname]=device
			--else
				--print ('Error opening', d.name)
			--end
		end
	end
	
	if not bfound then log('BOBOT', 'WARNING', 'No Baseboard found') end
end

M.refresh = function ()
	print ('bobot refreshing!')
	if #bobot.baseboards==0 then 
		sched.sleep(0.5)
		bobot.init(M.bobot_params)
		read_devices_list()
	else
		local refreshed
		for i, bb in ipairs(bobot.baseboards) do
			if bb.refresh and bb.hotplug then 
				if not bb:refresh() then
					bobot.baseboards[i]=nil
				end
				refreshed=true
			end
		end
		if refreshed then read_devices_list() end
	end	
end

--- Initialize and starts the module.
-- This is called automatically by toribio if the _load_ attribute for the module in the configuration file is set to
-- true.
-- @param conf the configuration table (see @{conf}).
M.init = function (conf)
	local timeout_refresh = conf.timeout_refresh or -1

	if conf.path then 
		if conf.path:sub(1,1)=='/' then
			package.path = package.path .. ";"..conf.path..'/?.lua'
		else
			local my_path = debug.getinfo(1, "S").source:match[[^@?(.*[\/])[^\/]-$]]
			package.path = package.path .. ";"..my_path..conf.path..'/?.lua'
		end
	end
	
	bobot  = require 'bobot'
	M.bobot_params = conf.comms
	bobot.init(conf.comms)
	local count = 60
	while #bobot.baseboards == 0 and count > 0 do
		log('BOBOT', 'DETAIL', 'Retrying conect: %s', count)

		sched.sleep(1)
		bobot.init(conf.comms)
		count = count-1
	end
	read_devices_list()
	M.refresh()
	sched.sigrun({
		'do_bobot_refresh',
		timeout=timeout_refresh, 
	}, M.refresh)
end

return M

--- Configuration Table.
-- This table is populated by toribio from the configuration file.
-- @table conf
-- @field load whether toribio should start this module automatically at startup.
-- @field comms communitaction parameter to provide to bobot library (such as `{"usb", "serial"}`)
-- @field path where the bobot library is installed.
-- @field timeout_refresh Time before triggering a re-detection of attached modules 
-- (nil or negative disables).
