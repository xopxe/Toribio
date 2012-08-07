local M = {}

debugprint=debugprint or print

local sched=require 'sched'
local catalog = require 'catalog'
local toribio = require 'toribio'

M.start = function( conf )
	local masks_to_watch = {}
	local deviceloadersconf = toribio.configuration.deviceloaders

	for modulename, devmask in pairs(conf.module) do
		debugprint ("filedev module:", devmask, modulename)
		masks_to_watch[devmask] = modulename
		masks_to_watch[#masks_to_watch+1] = devmask
	end

	sched.run(function()
		local inotifier_task = catalog.waitfor(masks_to_watch)
		local waitd_fileevent = {emitter=inotifier_task, events={'FILE+', 'FILE-'}, buff_len=100}
		while true do
			local _, action, devfile, onmask = sched.wait(waitd_fileevent)
			if action=='FILE+' then
				local modulename = masks_to_watch[onmask]
				print('filedev module starting', devfile, modulename)
				deviceloadersconf[modulename] = deviceloadersconf[modulename] or {}
				deviceloadersconf[modulename].filename = devfile
				local devmodule = require ('deviceloaders/'..modulename)
				local device=devmodule.start(deviceloadersconf[modulename])
				--if device then 
				--	device.module=device.module or modulename
				--	toribio.add_device(device)
				--end
			elseif action=='FILE-' then
				toribio.remove_devices({filename=devfile})
			end
		end
	end)
	
	local inotifier = require 'tasks/inotifier'
	inotifier.start(masks_to_watch)
end

return M
