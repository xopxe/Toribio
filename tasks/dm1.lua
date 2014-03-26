local M = {}
local toribio = require 'toribio'
local sched = require 'lumen.sched'
local log = require 'lumen.log'
local selector = require 'lumen.tasks.selector'

local sig_drive = {}

M.init = function(conf)
  
  ----------------------------
  local filepot = conf.filepot or '/sys/devices/ocp.3/helper.15/AIN1'
  --local filepot = '/sys/devices/ocp.3/44e0d000.tscadc/tiadc/iio:device0/in_voltage1_raw'
  log('DM1', 'INFO', 'Using %s as potentiometer input', filepot)
  
  os.execute('echo cape-bone-iio > /sys/devices/bone_capemgr.*/slots')
  sched.sleep(0.5) -- give time to mount device files
  
  local calibrationpot = conf.calibrationpot or {{0,-90}, {2048, 0}, {4096, 90}}
  log('DM1', 'INFO', 'Calibrating potentiometer as %s -> %s, %s -> %s, %s -> %s', 
    tostring(calibrationpot[1][1]), tostring(calibrationpot[1][2]),
    tostring(calibrationpot[2][1]), tostring(calibrationpot[2][2]),
    tostring(calibrationpot[3][1]), tostring(calibrationpot[3][2]))
  local calibrator = require 'tasks.dm1.calibrator'(calibrationpot)

  local function read_pote()
    local fdpot = assert(io.open(filepot, 'rb'))
    local data, err = fdpot:read('*l')
    fdpot:close()
    return data, err
  end
  assert(read_pote())
  ----------------------------
  
  sched.run(function()
    while true do
      sched.sleep(2)
      local data, err = read_pote()
      print ('POT', type(data), #(data or ''), data, err, '>>>', calibrator(tonumber(data)))
    end
  end)
  
  --drive first pair
  sched.run(function()
    local motor_left = toribio.wait_for_device(conf.motor_id[1].left)
    local motor_right = toribio.wait_for_device(conf.motor_id[1].right)
    motor_left.set.rotation_mode('wheel')
    motor_right.set.rotation_mode('wheel')
    log('DM1', 'INFO', 'Chassis 1 initialized')
    sched.sigrun({sig_drive, buff_mode='keep_last'}, function(_, left, right)
      --print("!U1", left, right) 
      motor_left.set.moving_speed(left)
      motor_right.set.moving_speed(-right)
    end)
  end)

  --drive second pair
  sched.run(function()
    local motor_left = toribio.wait_for_device(conf.motor_id[2].left)
    local motor_right = toribio.wait_for_device(conf.motor_id[2].right)
    motor_left.set.rotation_mode('wheel')
    motor_right.set.rotation_mode('wheel')
    log('DM1', 'INFO', 'Chassis 2 initialized')
    sched.sigrun({sig_drive, buff_mode='keep_last'}, function(_, left, right)
      -- TODO compute left right to follow
      motor_left.set.moving_speed(left)
      motor_right.set.moving_speed(-right)
    end)
  end)

  -- HTTP RC

  local http_server = require "lumen.tasks.http-server"  
  http_server.serve_static_content_from_stream('/docs/', './docs')
  http_server.serve_static_content_from_ram('/', './tasks/dm1/www')
  
  http_server.set_websocket_protocol('dm1-rc-protocol', function(ws)
    sched.run(function()
      while true do
        --print('WS?', ws)
        local message,opcode = ws:receive()
        --print('WS', message,opcode == ws.TEXT)
        if not message then
          sched.signal(sig_drive, 0, 0)
          ws:close()
          return
        end
        if opcode == ws.TEXT then
          local left, right = message:match('^([^,]+),([^,]+)$')
          --print('SIG', sig_drive, left, right)
          sched.signal(sig_drive, left, right)
        end
      end
    end) --:set_as_attached()
  end)


  if conf.http_server then conf.http_server.ws_enable = true end
  http_server.init(conf.http_server)

  -- /HTTP RC


  -- UDP RC
  
  --initialize socket
  local udp = selector.new_udp(nil, nil, conf.ip, conf.port, -1)

  --listen for messages
  sched.sigrun({udp.events.data, buff_mode='keep_last'}, function(_, msg) 
    local left, right
    if msg then
      left, right = msg:match('^([^,]+),([^,]+)$')
      --print("!U", left, right) 
    else
      left, right = 0, 0
    end
    sched.signal(sig_drive, left, right)
  end)

  -- /UDP RC

end


return M
