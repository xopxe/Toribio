local M = {}
local toribio = require 'toribio'
local sched = require 'lumen.sched'
local log = require 'lumen.log'
local selector = require 'lumen.tasks.selector'

local encoder_lib = require ('lumen.lib.dkjson')
local encode_f = encoder_lib.encode
local decode_f = encoder_lib.decode

local assert, tonumber, io_open = assert, tonumber, io.open
local cos, sin, tan, abs = math.cos, math.sin, math.tan, math.abs

local p, d = 0.182, 0.190 --dimensions

local sig_drive = {}

M.init = function(conf)
  
  ----------------------------
  local filepot = conf.pot.file or '/sys/devices/ocp.3/helper.15/AIN1'
  --local filepot = '/sys/devices/ocp.3/44e0d000.tscadc/tiadc/iio:device0/in_voltage1_raw'
  log('DM1', 'INFO', 'Using %s as potentiometer input', filepot)
  
  --os.execute('echo cape-bone-iio > /sys/devices/bone_capemgr.*/slots')
  --sched.sleep(0.5) -- give time to mount device files
  
  local pot_calibration = conf.pot.calibration or {{0,-90}, {2048, 0}, {4096, 90}}
  log('DM1', 'INFO', 'Calibrating potentiometer as %s -> %s, %s -> %s, %s -> %s', 
    tostring(pot_calibration[1][1]), tostring(pot_calibration[1][2]),
    tostring(pot_calibration[2][1]), tostring(pot_calibration[2][2]),
    tostring(pot_calibration[3][1]), tostring(pot_calibration[3][2]))
  local calibrator = require 'tasks.dm1.calibrator'(pot_calibration)

  local function read_pote()
    local fdpot = assert(io_open(filepot, 'rb'))
    local data, err = fdpot:read('*l')
    fdpot:close()
    return data, err
  end
  --assert(read_pote())
  ----------------------------
  --[[
  sched.run(function()
    while true do
      sched.sleep(2)
      local data, err = read_pote()
      print ('POT', type(data), #(data or ''), data, err, '>>>', calibrator(tonumber(data)))
    end
  end)
  --]]

  --drive first pair
  sched.run(function()
    local motor_left = toribio.wait_for_device(conf.motor_id[1].left)
    local motor_right = toribio.wait_for_device(conf.motor_id[1].right)
    motor_left.set.rotation_mode('wheel')
    motor_right.set.rotation_mode('wheel')
    log('DM1', 'INFO', 'Chassis 1 initialized')
    sched.sigrun({sig_drive, buff_mode='keep_last'}, function(_, left, right)
      --print("!U1", left, right) 
      motor_left.set.moving_speed(-left)
      motor_right.set.moving_speed(right)
    end)
  end)

  --drive second pair
  sched.run(function()
    local motor_left = toribio.wait_for_device(conf.motor_id[2].left)
    local motor_right = toribio.wait_for_device(conf.motor_id[2].right)
    motor_left.set.rotation_mode('wheel')
    motor_right.set.rotation_mode('wheel')
    
    local left, right, angle, last_pot = 0, 0, 0, -1000000
    local sig_angle = {}

    --task for poll the pot
    sched.run(function()
      local rate, threshold = conf.pot.rate, conf.pot.threshold
      while true do
<<<<<<< HEAD
        local data = assert(read_pote())
        local a = calibrator(tonumber(data))
        if abs(a-angle) < threshold then
          angle = a
=======
        local pot_reading = tonumber( assert(read_pote()) )
        if abs(pot_reading-last_pot) > threshold then
          last_pot, angle = pot_reading, calibrator(tonumber(pot_reading))
>>>>>>> c73d546e1cbb055a50866c4ef6ffb56ca970c86e
          sched.signal(sig_angle)
        end
        sched.sleep(rate)
      end
    end):set_as_attached()
    
    log('DM1', 'INFO', 'Chassis 2 initialized')
    sched.sigrun( {sig_drive, sig_angle, buff_mode='keep_last'}, function(sig,nleft,nright)
      if sig==sig_drive then left, right = nleft, nright end

      local r2 = 0.5*( (2*cos(angle) + sin(angle)*(d*d+p*p)/(d*p))*left
               + sin(angle)*right*(d*d-p*p)/(d*p) )
             
      local l2 = 0.5*(sin(angle)*left*(p*p-d*d)/(d*p)
               + (2*cos(angle) - sin(angle)*(d*d+p*p)/(d*p))*right)
             
      --print("!U2", l2, r2, angle) 
      
      motor_left.set.moving_speed(-l2)
      motor_right.set.moving_speed(r2)
    end)
  end)

  -- HTTP RC
  
  if conf.http_server then 
    local http_server = require "lumen.tasks.http-server"  
    --http_server.serve_static_content_from_stream('/docs/', './docs')
    http_server.serve_static_content_from_ram('/', './tasks/dm1/www')
    
    http_server.set_websocket_protocol('dm1-rc-protocol', function(ws)
      sched.run(function()
        while true do
          local message,opcode = ws:receive()
          if not message then
            sched.signal(sig_drive, 0, 0)
            ws:close()
            return
          end
          if opcode == ws.TEXT then        
            local decoded, index, e = decode_f(message)
            if decoded then 
              if decoded.action == 'drive' then 
                sched.signal(sig_drive, decoded.left, decoded.right)
              end
            else
              log('DM1', 'ERROR', 'failed to decode message with length %s with error "%s"', 
                tostring(#message), tostring(index).." "..tostring(e))
            end
          end
        end
      end) --:set_as_attached()
    end)
    
    conf.http_server.ws_enable = true
    http_server.init(conf.http_server)
  end

  -- /HTTP RC


  -- UDP RC
  
  if conf.udp then 
    local udp = selector.new_udp(nil, nil, conf.udp.ip, conf.udp.port, -1)

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
  end

  -- /UDP RC

end


return M
