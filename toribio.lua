--- Embedded Robotics Library.
-- Toribio is a library for developing robotics applications. It is based on Lumen cooperative
-- scheduler, and allows to write coroutine, signal and callback based applications.
-- Toribio provides a mechanism for easily accesing hardware, and is geared towards
-- low end hardware, such as Single-Board Computers.
-- @module toribio
-- @usage local toribio = require 'toribio'
-- @alias M

local M ={}

local sched = require 'sched'
local catalog_tasks = require 'catalog'.get_catalog('tasks')
local log= require 'log'
local mutex = require 'mutex'
--require "log".setlevel('ALL')

--- Available devices.
-- This is a table containing the name and associated object for all available devices
-- in the system.
-- When toribio adds or removes a device, @{events} are emitted. For easily 
-- accesing this table, use @{wait_for_device}
-- @usage for name, _ in pairs(toribio.devices) do
--  print(name)
--end
M.devices = {}

local devices=M.devices

local function get_device_name(n)
	if not devices[n] then
--print('NAME', n, n)
		return n
	end
	local i=2
	local nn=n.."#"..i
	while devices[nn] do
		i=i+1
		nn=n.."#"..i
	end
--print('NAME', n, nn)
	return nn
end


--- Signals that toribio can emit.
-- The emitter of these signals will be the task returned by @{task}
-- @usage local sched = require 'sched'
--sched.sigrun_task(
--    {emitter=toribio.task, events={toribio.events.new_device}}, 
--    print
--)
-- @field new_device A new device was added. The first parameter is the device object.
-- @field removed_device A device was removed. The first parameter is the device.
-- @table events
local events = {
	new_device = {},
	removed_device = {},
}
M.events = events

--- Return a device with a given name or matching a filter.
-- If the parameter provided is a string, will look for a
-- device with it as a name. Alternativelly, it can be a table
-- specifying a criterion a device must match.
-- If no such device exists, will block until it appears.
-- @param devdesc The name of the device or a filter.
-- @param timeout How much time wait for the device.
-- @return The requested device. On timeout, returns _nil,'timeout'_.
-- @usage local mice = toribio.wait_for_device('mice')
--local some_button = toribio.wait_for_device({module='bb-button'})
M.wait_for_device = function(devdesc, timeout)
	assert(sched.running_task, 'Must run in a task')
	
	local wait_until
	if timeout then wait_until=sched.get_time() + timeout end
	
	local device_in_devices, device_matches --matching function
	
	if type (devdesc) == 'string' then 
		device_matches = function (device, dd)
			return device.name == dd
		end
		device_in_devices = function (dd)
			return devices[dd]
		end
	else
		device_matches = function (device, dd)
			local matches = true
			for key, value in pairs(dd) do
				if device[key]~=value then
					matches=false
					break
				end
			end
			return matches
		end
		device_in_devices = function (dd)
			for _, device in pairs(devices) do
				if device_matches(device, dd) then return device end
			end
		end
	end

	local in_devices=device_in_devices(devdesc)
	if in_devices then 
		return in_devices
	else
		local tortask = catalog_tasks:waitfor('toribio')
		local waitd = {emitter=tortask, events={M.events.new_device}}
		if wait_until then waitd.timeout=wait_until-sched.get_time() end
		while true do
			local _, _, device = sched.wait(waitd) 
			if not device then --timeout
				return nil, 'timeout'
			end
			if device_matches (device, devdesc) then
				return device 
			end
			if wait_until then waitd.timeout=wait_until-sched.get_time() end
		end
	end
	
end

--- Register a callback for a device's signal.
-- Only one instance of the callback function will be executed at a time. This means 
-- that if a event happens again while a callback is running, the new callback will 
-- be fired only when the first finishes. Can be invoked also as 
-- device:register_callback(event, f)
-- @param device The device to watch.
-- @param event the name of the event to watch.
-- @param f the callback function. It will be passed the signal's parameters.
-- @param timeout Timeout on wait. On expiration, f will be invoked with 
-- nil, 'timeout' as parameters.
-- @return The callback task
M.register_callback = function(device, event, f, timeout)
	assert(sched.running_task, 'Must run in a task')
	assert(device.task, "Device has no task associated")
	assert(device.events, "Device has no events associated")
	assert(device.events[event], "Device has no such signal associated")

	local waitd = {
		emitter=device.task,
		events={device.events[event]},
		timeout=timeout,
	}
	local mx = mutex.new()
	local fsynched = mx:synchronize(f)
	local wrapper = function(_, _, ...)
		return fsynched(...)
	end
	return sched.sigrun(waitd, wrapper)
end

local signal_new_device = {}
--- Provide a new Device object.
-- Registers the Device object with Toribio. Warning: if the object's name is 
-- already taken, Toribio will rename the object.
-- @param device a Device object.
M.add_device = function (device)
	local devicename=get_device_name(device.name)
	print('NEW DEVICE!', device.name, device.module)
	if device.name~=devicename then print ('WARN!, device renamed!') end
	device.name=devicename
	devices[devicename] = device
	
	 -- for device:register_callback() notation
	device.register_callback = M.register_callback 
	device.remove = M.remove_device
	
	sched.signal(signal_new_device, device )
end

local signal_remove_device = {}
M.remove_devices = function(devdesc)
	if type(devdesc) == 'string' then
		devdesc={name=devdesc}
	end
	for _, device in pairs(devices) do
		local matches = true
		for key, value in pairs(devdesc) do
			if device[key]~=value then
				matches=false
				break
			end
		end
		if matches then M.remove_device(device) end
	end
end

M.remove_device = function(device)
	print('CLOSING DEVICE!', device.name)
	if device.task then sched.kill(device.task) end
	devices[device.name]=nil
	sched.signal(signal_remove_device, device )
end

--- Start a task.
-- @param section The section to which the task belongs
-- (possible values are 'deviceloaders' and 'tasks')
-- @param taskname The name of the task
-- @return true on success.
M.start = function(section, taskname)
	local packagename = section..'/'..taskname
	if package.loaded[packagename] 
	then return package.loaded[packagename] end
	
	local sect = M.configuration[section] or {}
	local conf = sect[taskname] or {}
	local taskmodule = require (packagename)
	_G.debugprint('module loaded:', taskmodule)
	log('TORIBIO', 'INFO', 'module %s loaded', packagename)
	if taskmodule and taskmodule.init then
		sched.run(function()
			taskmodule.init(conf)
			_G.debugprint('module started:', taskmodule)
		end)
	end
	return taskmodule 
end

--- Toribio's task.
-- This is the task that emits toribios @{events}
-- @return toribio's task
M.task = sched.run( function ()
	catalog_tasks:register('toribio', sched.running_task)
	local waitd_control={emitter='*', buff_size=10, 
		events={signal_new_device, signal_remove_device}}
	while true do
		local _, event, p = sched.wait(waitd_control)
		if event==signal_new_device then
			local device = p
			sched.signal(events.new_device, device )
		elseif event == signal_remove_device then 
			local device = p
			sched.signal(events.removed_device, device )
		end
	end
end)

--- A catalog for tasks.
-- This is a catalog used to give well known names to tasks.
M.catalog_tasks = catalog_tasks

--- The configuration table.
-- This table contains the configurations specified in toribio-go.conf file.
M.configuration = {}

return M
