--- Toribio application.
-- This application starts the different tasks and device loaders.
-- It is controlled trough a configuration file (default toribio-go.conf).
-- @usage	lua toribio-go.lua [-h] [-d] [-c conffile|'none'] 
--		-d Debug mode
--		-h Print help
--		-c Use given configuration file (or none). 
--		   Defaults to 'toribio-go.conf'
-- @script toribio-go

package.path = package.path .. ";;;Lumen/?.lua"

require 'strict'
_G.debugprint=function() end

local sched = require 'sched'
local selector = require "tasks/selector".init({service='nixio'})

--require "log".setlevel('ALL')
local toribio = require 'toribio'

-- From http://lua-users.org/wiki/AlternativeGetOpt
-- getopt_alt.lua
-- getopt, POSIX style command line argument parser
-- param arg contains the command line arguments in a standard table.
-- param options is a string with the letters that expect string values.
-- returns a table where associated keys are true, nil, or a string value.
-- The following example styles are supported
--   -a one  ==> opts["a"]=="one"
--   -bone   ==> opts["b"]=="one"
--   -c      ==> opts["c"]==true
--   --c=one ==> opts["c"]=="one"
--   -cdaone ==> opts["c"]==true opts["d"]==true opts["a"]=="one"
-- note POSIX demands the parser ends at the first non option
--      this behavior isn't implemented.
local function getopt( arg, options )
  local tab = {}
  for k, v in ipairs(arg) do
    if string.sub( v, 1, 2) == "--" then
      local x = string.find( v, "=", 1, true )
      if x then tab[ string.sub( v, 3, x-1 ) ] = string.sub( v, x+1 )
      else      tab[ string.sub( v, 3 ) ] = true
      end
    elseif string.sub( v, 1, 1 ) == "-" then
      local y = 2
      local l = string.len(v)
      local jopt
      while ( y <= l ) do
        jopt = string.sub( v, y, y )
        if string.find( options, jopt, 1, true ) then
          if y < l then
            tab[ jopt ] = string.sub( v, y+1 )
            y = l
          else
            tab[ jopt ] = arg[ k + 1 ]
          end
        else
          tab[ jopt ] = true
        end
        y = y + 1
      end
    end
  end
  return tab
end
-- Test code
--opts = getopt( arg, "ab" )
--for k, v in pairs(opts) do
--  print( k, v )
--end
-- End of: From http://lua-users.org/wiki/AlternativeGetOpt

local opts = getopt( _G.arg, "cd" )

if opts["d"] then
	debugprint=print --bugprint or print
	debugprint('Debug print enabled')
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

if opts["h"] then
	print [[Usage:
	lua toribio-go.lua [-h] [-d] [-c conffile|'none'] 
		-d Debug mode
		-h This help
		-c Use given configuration file (or none). 
		   Defaults to 'toribio-go.conf'
	]]
	os.exit()
end
if not opts["c"] then
	load_configuration('toribio-go.conf')
elseif opts["c"] ~= "none" then
	load_configuration(opts["c"])
end

sched.run(function()
	for _, section in ipairs({'deviceloaders', 'tasks'}) do
		for task, conf in pairs(toribio.configuration[section] or {}) do
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

