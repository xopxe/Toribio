--- Library for accesing a joystick.
-- This library allows to read data from a joystick,
-- such as it's coordinates and button presses.
-- The device will be named something like "joystick:/dev/input/js0", module "joystick". 
-- @module joystick
-- @alias device

--https://www.kernel.org/doc/Documentation/input/joystick-api.txt

local M = {}

--- Initialize and starts the module.
-- This is called automatically by toribio if the _load_ attribute for the module in the configuration file is set to
-- true.
-- @param conf the configuration table (see @{conf}).
M.init = function(conf)
	local toribio = require 'toribio'
	local selector = require 'lumen.tasks.selector'
	local sched = require 'lumen.sched'

	local filename = conf.filename or '/dev/input/js0'
	local devicename = 'joystick:'..filename

	local evmove, evbutton = {}, {} --events
  
  local axes = {} --holds reading
	
	local device = {}
	
	--- Name of the device (something like 'joystick:/dev/input/js0').
	device.name=devicename

	--- Module name (in this case, 'joystick').
	device.module='joystick'

	--- Device file of the joystick.
	-- For example, '/dev/input/js0'
	device.filename=filename

	--- Events emitted by this device.
	-- @field button Button operated. First parameter is the button number, 
  -- followed by _true_ for pressed or _false_ for released.
	-- @field move Joystick moved. Parameters are the axis readings.
	-- @table events
	device.events={
		move = evmove,
    button = evbutton, 
	}
  
  device.start = function ()
    if device.fd then device.fd:close() end
      
    device.fd = assert(selector.new_fd(filename, {'rdonly', 'sync'}, 8, function(_, data)
      local value = data:byte(5) + 256*data:byte(6)--2 bytes
      if value>32768 then value=value-0xFFFF end
      
      local vtype = data:byte(7)
      local vaxis = data:byte(8)
      
      if vtype == 0x02 then --#define JS_EVENT_AXIS    /* joystick moved */
        axes[vaxis] = value
        --print('AXES', unpack(axes, 0))
        sched.signal(evmove, unpack(axes, 0))
      elseif vtype == 0x01 then --#define JS_EVENT_BUTTON    /* button pressed/released */
        sched.signal(evbutton, vaxis, value == 1 )
      elseif vtype > 0x80 then --#define JS_EVENT_INIT    /* initial state of device */
        vtype = vtype - 0x80
        if vtype == 0x02 then
          axes[vaxis] = value
        elseif vtype == 0x01 then
          sched.signal(evbutton, vaxis, value == 1 )
        end
      end
      
      return true
    end))
  end
  
  device.stop = function ()
    device.fd:close()
    device.fd = nil
  end

	toribio.add_device(device)
end

return M

--- Configuration Table.
-- When the start is done automatically (trough configuration), 
-- this table points to the modules section in the global configuration table loaded from the configuration file.
-- @table conf
-- @field load whether toribio should start this module automatically at startup.
-- @field filename the device file for the joystick (defaults to ''/dev/input/js0'').
