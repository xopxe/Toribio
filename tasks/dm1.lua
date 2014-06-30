local M = {}
local toribio = require 'toribio'
local sched = require 'lumen.sched'
local log = require 'lumen.log'
local selector = require 'lumen.tasks.selector'

local encoder_lib = require ('lumen.lib.dkjson')
local encode_f = encoder_lib.encode
local decode_f = encoder_lib.decode

local assert, tonumber, io_open, tostring = assert, tonumber, io.open, tostring
local cos, sin, tan, abs = math.cos, math.sin, math.tan, math.abs

local p, d = 0.182, 0.190 --dimensions
local d_p = d/p

local sig_drive_control = {}
local sigs_drive = {
  [0] = sig_drive_control
}

local function read_pote(filepot)
  local fdpot = assert(io_open(filepot, 'rb'))
  local data, err = fdpot:read('*l')
  fdpot:close()
  return data, err
end

M.init = function(conf)
  
  for i, chassis in ipairs(conf.motors) do
    log('DM1', 'INFO', 'Initializing chassis %i', i)
      
    local sig_angle = {}
    sigs_drive[i] = {}
    
    if i>1 then 
      local ipot=i-1
      
      local filepot = conf.pots[ipot].file or conf.pot.file or '/sys/devices/ocp.3/helper.15/AIN1'
      log('DM1', 'INFO', 'Using %s as potentiometer input', filepot)
      
      local pot_calibration = assert(conf.pots[ipot].calibration or conf.pot.calibration, 
        'Missing calibration for '..filepot  )
      log('DM1', 'INFO', 'Calibrating potentiometer as %s -> %s, %s -> %s, %s -> %s', 
      tostring(pot_calibration[1][1]), tostring(pot_calibration[1][2]),
      tostring(pot_calibration[2][1]), tostring(pot_calibration[2][2]),
      tostring(pot_calibration[3][1]), tostring(pot_calibration[3][2]))
      local calibrator = require 'tasks.dm1.calibrator'(pot_calibration)
     
      --task to poll the pot
      sched.run(function()
        local last_pot = -1000000
        local rate, threshold = conf.pot.rate, conf.pot.threshold
        while true do
          local pot_reading = tonumber( assert(read_pote(filepot)) )

          if abs(pot_reading-last_pot) > threshold then
            last_pot = pot_reading
            sched.signal(sig_angle, calibrator(tonumber(pot_reading)))
          end
          sched.sleep(rate)
        end
      end)--:set_as_attached()
    end
    
    sched.run(function()
      log('DM1', 'INFO', 'Motors: left %s, right %s', chassis.left, chassis.right)
      local motor_left = toribio.wait_for_device(chassis.left)
      local motor_right = toribio.wait_for_device(chassis.right)
      local left_mult, right_mult = chassis.left_mult or 1, chassis.right_mult or 1
      log('DM1', 'INFO', 'Motors multipliers: left %s, right %s', left_mult, right_mult)
      motor_left.set.rotation_mode('wheel')
      motor_right.set.rotation_mode('wheel')
      
      local sig_drive_in = sigs_drive[i-1]
      local sig_drive_out = sigs_drive[i]
      local pangle, fmodulo, fangle = 0, 0, 0
      
      sched.sigrun( {sig_drive_in, sig_angle, buff_mode='keep_last'}, function(sig,par1,par2)
        if sig==sig_drive_in then 
          fmodulo, fangle = par1, par2 
        elseif sig==sig_angle then 
          pangle = par1 
        end
             
        local fx = fmodulo * cos(fangle+pangle)
        local fy = fmodulo * sin(fangle+pangle)
        
        local out_r = fx - d_p*fy
        local out_l = fx + d_p*fy
        
        log('DM1', 'DEBUG', 'Drive %s: IN modulo %s, angle %s, pot %s, OUT left %s, right %s', 
          tostring(i), tostring(fmodulo), tostring(fangle), tostring(pangle), tostring(out_l), tostring(out_r))
        
        motor_left.set.moving_speed( left_mult*out_l )
        motor_right.set.moving_speed( right_mult*out_r )
        
        sched.signal(sig_drive_out, fmodulo, -fangle)
      end)
      log('DM1', 'INFO', 'Motors left %s and right %s ready', chassis.left, chassis.right)

    end)
 
  end

  -- HTTP RC
  --[[
  sched.run(function()
      sched.sleep(3)
      sched.signal(sig_drive_control, 20, 0)
  end)
  --]]
  
  if conf.http_server then 
    local http_server = require "lumen.tasks.http-server"  
    --http_server.serve_static_content_from_stream('/docs/', './docs')
    http_server.serve_static_content_from_ram('/', './tasks/dm1/www')
    
    http_server.set_websocket_protocol('dm1-rc-protocol', function(ws)
      local stat_sender = sched.run(function()
          local lastclock = os.clock()
          while true do
            local mem = collectgarbage('count')*1024
            local clock = os.clock()
            local cpu = clock - lastclock
            lastclock = clock
            assert(ws:send('{ "action":"stats", "mem":' .. tostring(mem) .. 
                ', "cpu":' .. tostring(cpu) ..'}'))
            sched.sleep(1)
          end
      end)        
      sched.run(function()
        while true do
          local message,opcode = ws:receive()
          log('DM1', 'DEBUG', 'websocket traffic "%s"', tostring(message))
          if not message then
            sched.signal(sig_drive_control, 0, 0)
            stat_sender:kill()
            ws:close()
            return
          end
          if opcode == ws.TEXT then        
            local decoded, index, e = decode_f(message)
            if decoded then 
              if decoded.action == 'drive' then 
                sched.signal(sig_drive_control, decoded.modulo, decoded.angle)
              end
            else
              log('DM1', 'ERROR', 'failed to decode message with length %s with error "%s"', 
                tostring(#message), tostring(index).." "..tostring(e))
            end
          end
        end
      end) --:set_as_attached()
    
    end)
    
    
    http_server.set_websocket_protocol('dm1-log-protocol', function(ws)
      local log_sender = sched.run(function()
          local lastclock = os.clock()
          while true do
            local mem = collectgarbage('count')*1024
            local clock = os.clock()
            local cpu = clock - lastclock
            lastclock = clock
            assert(ws:send('{ "action":"stats", "mem":' .. tostring(mem) .. 
                ', "cpu":' .. tostring(cpu) ..'}'))
            sched.sleep(1)
          end
      end)        
      sched.run(function()
        while true do
          local message,opcode = ws:receive()
          log('DM1', 'DEBUG', 'websocket traffic "%s"', tostring(message))
          if not message then
            sched.signal(sig_drive_control, 0, 0)
            log_sender:kill()
            ws:close()
            return
          end
          if opcode == ws.TEXT then        
            local decoded, index, e = decode_f(message)
            if decoded then 
              if decoded.action == 'drive' then 
                sched.signal(sig_drive_control, decoded.modulo, decoded.angle)
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
      local fmodulo, fangle
      if msg then
        fmodulo, fangle = msg:match('^([^,]+),([^,]+)$')
        --print("!U", left, right) 
      else
        fmodulo, fangle = 0, 0
      end
      sched.signal(sig_drive_control, fmodulo, fangle)
    end)
  end

  -- /UDP RC

end


return M
