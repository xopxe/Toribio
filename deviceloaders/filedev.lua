local M = {}

local sched=require 'sched'
local toribio = require 'toribio'
local log = require 'log'

M.init = function( conf )
	local masks_to_watch = {}
	local deviceloadersconf = toribio.configuration.deviceloaders

	for modulename, devmask in pairs(conf.module) do
		log('FILEDEV','INFO', 'watching path %s for module %s', tostring(devmask), tostring(modulename))
		masks_to_watch[devmask] = modulename
		masks_to_watch[#masks_to_watch+1] = devmask
	end

	sched.run(function()
		local inotifier_task = require 'catalog'.get_catalog('tasks'):waitfor(masks_to_watch)
		local waitd_fileevent = {emitter=inotifier_task, events={'FILE+', 'FILE-'}, buff_len=100}
		while true do
			local _, action, devfile, onmask = sched.wait(waitd_fileevent)
			if action=='FILE+' then
				local modulename = masks_to_watch[onmask]
				log('FILEDEV','INFO', 'starting module %s on %s', tostring(modulename), tostring(devfile))
				print('filedev module starting', devfile, modulename)
				deviceloadersconf[modulename] = deviceloadersconf[modulename] or {}
				deviceloadersconf[modulename].filename = devfile
				toribio.start('deviceloaders', modulename)
			elseif action=='FILE-' then
				toribio.remove_devices({filename=devfile})
			end
		end
	end)
	
	local inotifier = require 'tasks/inotifier'
	inotifier.init(masks_to_watch)
end

return M
