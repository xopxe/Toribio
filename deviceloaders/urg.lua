--- Library for accesing a mouse.
-- This library allows to read data from a mouse,
-- such as it's coordinates and button presses.
-- The device will be named "mice", module "mice". 
-- @module mice
-- @alias device

local M = {}

--- Initialize and starts the module.
-- This is called automatically by toribio if the _load_ attribute for the module in the configuration file is set to
-- true.
-- @param conf the configuration table (see @{conf}).
M.init = function(conf)
	local toribio = require 'toribio'
	local selector = require 'lumen.tasks.selector'
	local sched = require 'lumen.sched'
  local nixio = require 'nixio'
  
	local floor = math.floor

	local filename = conf.filename or '/dev/ttyACM0'
	local devicename='urg:'..filename

	local speed = tonumber(conf.serialspeed) or 115200
	local init_tty_string ='stty -F ' .. filename .. ' ' .. speed

	local reading = {}
	
	local device={}
  
  
  local inm = ''
	local filehandler = assert(selector.new_fd(filename, {'rdwr', 'nonblock'}, -1, function(_, data, err)
    assert(data, err)
		--print ('*', #inm, #data) --(data:byte(1,#byte))
    
    inm = inm..data
    local packend = inm:find('\n\n', 1, true)
    
    if packend then
      local packet=inm:sub(1,packend)
      local cmd, status, ts, sum, datablocks = packet:match('^(%w+)\n(%w%w%w)\n(....)(.)\n(.+\n)$')     
      --print ('#####', cmd, status, ts, sum, datablocks)
      
      
      --TODO validate sum      
      
      if (cmd and status and ts and sum and datablocks) then
        if status:sub(1,2)~='99' then
          print ('ERROR STATUS:', status)
        end
        local measures = {}
        local blocks = {}
        for block, bsum in datablocks:gmatch('(%C+)(%C)\n') do
          --TODO validate bsum
          blocks[#blocks+1] = block
          --print ('!!', #block, block)
        end
        local data = table.concat(blocks)
        
        for i=1, #data, 3 do
          local n1, n2, n3 = data:byte(i, i+2)
          --print ('??', n1, n2, n3)
          n1=((n1-0x30)%64)*(2^12)
          n2=((n2-0x30)%64)*(2^6)
          n3=((n3-0x30)%64)
          measures[#measures+1]=n1+n2+n3
        end
        
        --[[
        for n1, n2, n3 in data:gmatch('(.)(.)(.)') do
        end
        --]]
        
        sched.signal(reading, cmd, status, ts, measures)
      end
      
      inm=inm:sub(packend+2, -1)
    end
    
		return true
	end))
	
	--- Name of the device (in this case, 'mice').
	device.name=devicename

	--- Module name (in this case, 'mice').
	device.module='urg'

	--- Device file of the mouse.
	-- For example, '/dev/input/mice'
	device.filename=filename

	--- Events emitted by this device.
	-- Button presses have single parameter: true on press,
	-- false on release.
	-- @field leftbutton Left button click.
	-- @field rightbutton Right button click.
	-- @field middlebutton Middle button click.
	-- @field move Mouse moved. Parameters are _x, y, dx, dy_, where x, y is the coordinate and
  -- dx, dy the coordinate increments from last event.
	-- @table events
	device.events={
		reading=reading,
	}

	--- Trigger a reading.
  -- @field covered arc in º
	device.read=function(arc)   
    local stepmin=math.floor((120-arc/2)*683/240)
    local stepmax=math.floor((120+arc/2)*683/240)
    
    local cmd ='MD'
    local start = string.format('%.4u', stepmin) --'0000'
    local endp = string.format('%.4u', stepmax) --'0750'
    local clustcnt = '01'
    local scanint = '0'
    local scancnt = '00' --'01'
    
    --print ('!', start, endp)
    
    local m = cmd..start..endp..clustcnt..scanint..scancnt..'\n'
    filehandler.fd:write(m)
	end

	device.get_version=function()
    --filehandler.fd:write('VV\n')
	end

	toribio.add_device(device)
end

return M

--- Configuration Table.
-- When the start is done automatically (trough configuration), 
-- this table points to the modules section in the global configuration table loaded from the configuration file.
-- @table conf
-- @field load whether toribio should start this module automatically at startup.
-- @field filename the device file for themouse (defaults to ''/dev/input/mice'').
