--- Library for DM3 Platform.
-- @module dm3
-- @alias dm3

----------------------------------------------------------------
local PERIOD = 2000

local motor_ports = {
  'bone_pwm_P9_22',
  'bone_pwm_P9_14',
}

local motor_pwm_path = {
  ['motor:1'] = '/sys/devices/ocp.3/pwm_test_P9_22.16',
  ['motor:2'] = '/sys/devices/ocp.3/pwm_test_P9_14.15',
  ['motor:3'] = '',
  ['motor:4'] = '',
}

-- for gpios, see http://kilobaser.com/blog/2014-07-15-beaglebone-black-gpios
-- or, easier, http://beagleboard.org/Support/bone101
local motor_reverse_gpio = { 
  ['motor:1'] = 48,
  ['motor:2'] = 50,
  ['motor:3'] = 51,
  ['motor:4'] = 60,
}
local motor_enable_gpio = 61
local motor_brake_gpio = 62
----------------------------------------------------------------

local M = {}
local floor = math.floor

local function write_file(f, v)
  local fdpot = assert(io.open(f, 'w'))
  f:write(v..'\n')
  f:close()
end

--- Initialize and starts the module.
-- This is called automatically by toribio if the _load_ attribute for the module in the configuration file is set to
-- true.
-- @param conf the configuration table (see @{conf}).
M.init = function(conf)
	local toribio = require 'toribio'
	local selector = require 'lumen.tasks.selector'
	local sched = require 'lumen.sched'
  local log = require 'lumen.log'
	
  -- pwm module
  write_file('/sys/devices/bone_capemgr.9/slots', 'am33xx_pwm')
      
  -- enables pwm for servo motor control pins
  for _, port_name in ipairs(motor_ports) do
    write_file('/sys/devices/bone_capemgr.9/slots', port_name)
  end
  
  -- reverser pins
  for _, reverser_pin in ipairs(motor_reverse_gpio) do
    write_file('/sys/class/gpio/export', reverser_pin)
  end
  
  -- enable and brake pins
  write_file('/sys/class/gpio/export', motor_enable_gpio)
  write_file('/sys/devices/virtual/gpio/gpio'..motor_enable_gpio..'/direction', 'low')
  local motor_enable_file = '/sys/devices/virtual/gpio/gpio'..motor_enable_gpio..'/value'
  write_file(motor_enable_file, 0)

  -- enable and brake pins
  write_file('/sys/class/gpio/export', motor_brake_gpio)
  write_file('/sys/devices/virtual/gpio/gpio'..motor_brake_gpio..'/direction', 'low')
  local motor_brake_file = '/sys/devices/virtual/gpio/gpio'..motor_brake_gpio..'/value'
  write_file(motor_brake_file, 0)

  
  for motor_name, motor_file in pairs(motor_pwm_path) do
    local motor_device = {
      name = motor_name,
      module = 'dm3motor',
      --filename = motor_file,
      events = {},
      set = {},
    }
    
    local motor_duty_file = motor_file .. '/duty'
    --local motor_reverse_file = '/sys/class/gpio/gpio'..motor_reverse_gpio[motor_name]..'/value'
    local motor_reverse_file = '/sys/devices/virtual/gpio/gpio'..motor_reverse_gpio[motor_name]..'/value'
    
    --configure pwm
    write_file(motor_file .. '/run', 0)
    write_file(motor_file .. '/period', PERIOD)
    write_file(motor_file .. '/polarity', 1)
    write_file(motor_file .. '/value', 0)
    
    --configure reverser pins
    write_file('/sys/devices/virtual/gpio/gpio' .. motor_reverse_gpio[motor_name] .. '/direction', 'low')    
    write_file(motor_reverse_file, 0)
    
    motor_device.set.rotation_mode = function (mode)
      assert(mode =='wheel')
    end
    
    motor_device.set.torque_enable = function (value)
      write_file(motor_enable_file, value and 1 or 0)
      write_file(motor_file .. '/run', value and 1 or 0)
    end
    
    motor_device.set.brake = function (value)
      write_file(motor_brake_file, value and 1 or 0)
      write_file(motor_file .. '/run', value and 0 or 1) --FIXME neccesary?
    end
    
    local reversed = false
    motor_device.set.moving_speed = function (speed)
      if speed < 0 then
        if not reversed then 
          write_file(motor_reverse_file, 1)
          reversed = true
        end
        speed = -speed
      elseif speed > 0 then
        if reversed then 
          write_file(motor_reverse_file, 0)
          reversed = false
        end
      end
      
      local duty = floor(PERIOD * speed / 100)
      write_file(motor_duty_file, duty)
    end
    
    log('DM3MOTOR', 'INFO', 'Device %s created: %s', motor_device.module, motor_device.name)
    toribio.add_device(motor_device)
  end  
end

return M

--- Configuration Table.
-- When the start is done automatically (trough configuration), 
-- this table points to the modules section in the global configuration table loaded from the configuration file.
-- @table conf
-- @field load whether toribio should start this module automatically at startup.
