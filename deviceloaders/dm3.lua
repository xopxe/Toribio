--- Library for DM3 Platform.
-- @module dm3
-- @alias dm3


local function os_capture(cmd, raw)
  local f = assert(io.popen(cmd, 'r'))
  local s = assert(f:read('*a'))
  f:close()
  if raw then return s end
  s = s:gsub('^%s+', '')
  s = s:gsub('%s+$', '')
  s = s:gsub('[\n\r]+', ' ')
  s = s:gsub('[\n]+', ' ')
  return s
end
local function write_file(f, v)
  print ('!!!!', f, v)
  --do return end
  local fd = assert(io.open(f, 'w'))
  fd:write(v..'\n')
  fd:close()
end
----------------------------------------------------------------


local PERIOD = 2000

local bone_capemgr = os_capture('ls -d /sys/devices/bone_capemgr.*/slots')
-- pwm module
--write_file('/sys/devices/bone_capemgr.9/slots', 'am33xx_pwm')
write_file(bone_capemgr, 'am33xx_pwm')

local motor_ports = {
  'bone_pwm_P9_21',
  'bone_pwm_P9_31',
  'bone_pwm_P8_34',
  'bone_pwm_P8_36',
}
-- enables pwm for servo motor control pins
for _, port_name in ipairs(motor_ports) do
  --write_file('/sys/devices/bone_capemgr.9/slots', port_name)
  write_file(bone_capemgr, port_name)
end

local motor_pwm_path = {
  ['motor:1'] = os_capture('ls -d /sys/devices/ocp.3/pwm_test_P9_21.*'),
  ['motor:2'] = os_capture('ls -d /sys/devices/ocp.3/pwm_test_P9_31.*'),
  ['motor:3'] = os_capture('ls -d /sys/devices/ocp.3/pwm_test_P8_34.*'),
  ['motor:4'] = os_capture('ls -d /sys/devices/ocp.3/pwm_test_P8_36.*'),
}

-- for gpios, see http://kilobaser.com/blog/2014-07-15-beaglebone-black-gpios
-- or, easier, http://beagleboard.org/Support/bone101
local motor_reverse_gpio = { 
  ['motor:1'] = 5,
  ['motor:2'] = 111,
  ['motor:3'] = 44,
  ['motor:4'] = 75,
}
--local motor_power_gpio = 61
local motor_brake_gpio = 87
local motor_horn_gpio = 9

local motor_digital_ports = { 
  [5] = 'bspm_P9_17_f',
  [111] = 'bspm_P9_29_f',
  [44] = 'bspm_P8_12_f',
  [75] = 'bspm_P8_42_f',
  [87] = 'bspm_P8_29_f',
  [9] = 'bspm_P8_33_f',
}

----------------------------------------------------------------


local M = {}
local floor = math.floor


local create_out_pin_0 = function (gpio)
  write_file(bone_capemgr, motor_digital_ports[gpio])
  write_file('/sys/class/gpio/export', gpio)
  write_file('/sys/devices/virtual/gpio/gpio'..gpio..'/direction', 'out') --'low'?
  local filename = '/sys/devices/virtual/gpio/gpio'..gpio..'/value'
  write_file(filename, 0)
  return filename
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
	
  
  for motor_name, motor_file in pairs(motor_pwm_path) do
    local motor_device = {
      name = motor_name,
      module = 'dm3motor',
      --filename = motor_file,
      events = {},
      set = {},
    }
    
    local motor_duty_file = motor_file .. '/duty'
    
    --configure pwm
    write_file(motor_file .. '/run', 0)
    write_file(motor_file .. '/period', PERIOD)
    write_file(motor_file .. '/polarity', 0)
    write_file(motor_file .. '/value', 0)
    
    --configure reverser pins
    local motor_reverse_file = create_out_pin_0(motor_reverse_gpio[motor_name])
    
    motor_device.set.rotation_mode = function (mode)
      assert(mode =='wheel')
    end
    
    motor_device.set.torque_enable = function (value)
      write_file(motor_file .. '/run', value and 1 or 0)
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
    
    log('DM3', 'INFO', 'Device %s created: %s', motor_device.module, motor_device.name)
    toribio.add_device(motor_device)
  end
  
  local dm3platform = {
    name = 'dm3',
    module = 'dm3',
    BEEP_SIGNAL = {},
    set = {}
  }
      
  -- configure out pins
  --local motor_power_file = create_out_pin_0(motor_power_gpio)
  local motor_horn_file = create_out_pin_0(motor_horn_gpio)
  local motor_brake_file = create_out_pin_0(motor_brake_gpio)

  sched.run(function()
    local waitd = sched.new_waitd({dm3platform.BEEP_SIGNAL})
    while true do
      local ev, duration = sched.wait(waitd)
      write_file(motor_horn_file, 1)
      sched.sleep(duration or 0.5)
      write_file(motor_horn_file, 0)
    end
  end)

  dm3platform.set.power = function (value)
    --TODO throttle motors to 0 here?
    --write_file(motor_power_file, value and 1 or 0)
  end 
  
  dm3platform.set.horn = function (value)
    write_file(motor_horn_file,  value and 1 or 0)
  end 
  
  dm3platform.beep = function ( duration )
    sched.signal( dm3platform.BEEP_SIGNAL, duration )
  end
 
  dm3platform.set.brake = function (value)
    --TODO throttle motors to 0 here?
    write_file(motor_brake_file, value and 1 or 0)
  end 
  
  log('DM3', 'INFO', 'Device %s created: %s', dm3platform.module, dm3platform.name)
  toribio.add_device(dm3platform)
  
end

return M

--- Configuration Table.
-- When the start is done automatically (trough configuration), 
-- this table points to the modules section in the global configuration table loaded from the configuration file.
-- @table conf
-- @field load whether toribio should start this module automatically at startup.