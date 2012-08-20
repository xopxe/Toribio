--- Toribio application.
-- This application starts the different tasks and device loaders.
-- It is controlled trough a configuration file.
-- @script toribio-go

package.path = package.path .. ";;;Lumen/?.lua"

require 'strict'
_G.debugprint=function() end

local sched = require 'sched'
--require "log".setlevel('ALL')
local toribio = require 'toribio'

local arg = _G.arg or {}
for i, v in ipairs(arg) do
	if v=="DEBUG" then
		debugprint=print --bugprint or print
		debugprint('Debug print enabled')
		table.remove(arg, i)
		break
	end
end

--watches for task die events and prints out
sched.sigrun({emitter='*', events={sched.EVENT_DIE}}, print)

--loads from a configuration file
local function load_configuration(file)
	local func_conf, err = loadfile(file)
	assert(func_conf,err)
	local conf = toribio.configuration
	local meta_create_on_query 
	meta_create_on_query = {
		__index = function (table, key)
			table[key]=setmetatable({}, meta_create_on_query)
			return table[key]
		end,
	}
	setmetatable(conf, meta_create_on_query)
	setfenv(func_conf, conf)
	func_conf()
	meta_create_on_query['__index']=nil
end

load_configuration('toribio-go.conf')

sched.run(function()
	for _, section in ipairs({'deviceloaders', 'tasks'}) do
		for task, conf in pairs(toribio.configuration[section]) do
			print ('processing conf', section, task, (conf and conf.load) or false)

			if conf and conf.load==true then
				--[[
				local taskmodule = require (section..'/'..task)
				if taskmodule.start then
					local ok = pcall(taskmodule.start,conf)
					debugprint('module started:', ok)
				end
				--]]
				toribio.start(section, task)
			end
		end
	end
end)

debugprint('toribio go!')
sched.go()

