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
local catalog = require 'catalog'
--require "log".setlevel('ALL')

--- Available devices.
-- This is a table containing the name and associated object for all available devices
-- in the system.
-- When toribio adds or removes a device, @{signals} are emitted. For easily 
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
--    {emitter=toribio.task, signals={toribio.signals.new_device}}, 
--    print
--)
-- @field new_device A new device is added. The first parameter is the device object.
-- @field removed_device A device was removed. The first parameter is the device.
-- @table signals
local signals = {
	new_device = {},
	removed_device = {},
}
M.signals = signals

--- Return a device with a given name.
-- If no such device exists, will block until it appears.
-- @param name The name of the device
-- @return device the device with the given name.
-- @usage local mice = toribio.wait_for_device('mice')
M.wait_for_device = function(name)
	assert(sched.running_task, 'Must run in a task')
	if devices[name] then 
		return devices[name] 
	else
		local tortask = catalog.waitfor('toribio')
		local waitd = {emitter=tortask, events={M.signals.new_device}}
		while true do
			local _, _, device = sched.wait(waitd) 
			if device.name==name then
				return device 
			end
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
	assert(device.signals, "Device has no signals associated")
	assert(device.signals[event], "Device has no such signal associated")

	local waitd = {
		emitter=device.task,
		events={device.signals[event]},
		timeout=timeout,
	}
	local mx = require 'mutex'()
	local fsynched = mx.synchronize(f)
	local wrapper = function(_, _, ...)
		return fsynched(...)
	end
	return sched.sigrun(waitd, wrapper)
end

local signal_new_device = {}
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

--- Toribio's task.
-- This is the task that emits toribios @{signals}
-- @return toribio's task
M.task = sched.run( function ()
	catalog.register('toribio')
	local waitd_control={emitter='*', buff_size=10, 
		events={signal_new_device, signal_remove_device}}
	while true do
		local _, event, p = sched.wait(waitd_control)
		if event==signal_new_device then
			local device = p
			sched.signal(signals.new_device, device )
		elseif event == signal_remove_device then 
			local device = p
			sched.signal(signals.removed_device, device )
		end
	end
end)

--- The configuration table.
-- This table contains the configurations specified in toribio-go.conf file.
M.configuration = {}

return M
