local M = {}
local toribio = require 'toribio'
local sched = require 'lumen.sched'
local log = require 'lumen.log'
local selector = require 'lumen.tasks.selector'

local encoder_lib = require ('lumen.lib.dkjson')
local encode_f = encoder_lib.encode
local decode_f = encoder_lib.decode

local event_client_keeplive = {}

local start_date = tostring(os.date('%d-%m-%y_%H:%M:%S'))
local start_ts = sched.get_time()

local assert, tonumber, io_open, tostring, ipairs = assert, tonumber, io.open, tostring, ipairs
local cos, sin, tan, abs = math.cos, math.sin, math.tan, math.abs

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
  
  local dm3 = toribio.wait_for_device('dm3')
  
  assert(tonumber(conf.size.width) and tonumber(conf.size.length), 
    'No valid size.width / size.length found in conf')
  local d_p = conf.size.width / conf.size.length
  local gpsd
  
  local gpsd_logger = sched.run(function()
    gpsd = toribio.wait_for_device('gpsd')
    log('DM3', 'INFO', 'gpsd service found %s', tostring(gpsd))
    
    if not conf.data_dump_gps then return end
    
    local gps_file = io_open((conf.data_dump.path or './') .. start_date .. '_gps.log', 'w')
    gps_file:setvbuf ('line')
    toribio.register_callback(gpsd, 'TPV', function(v)
      local mode, speed, lat, lon, track = v.mode, v.speed, v.lat, v.lon, v.track 
      if gps_file and mode and speed and lat and lon and track then
        local s = (sched.get_time()-start_ts)
          ..' '..mode..' '..speed..' '..lat..' '..lon..' '..track..'\n'
        gps_file:write(s)
      end
    end)
    sched.sleep(1)
    gpsd.set_watch(true)
  end)

  
  
  for i, chassis in ipairs(conf.motors) do
    log('DM', 'INFO', 'Initializing chassis %i', i)
      
    local sig_angle = {}
    sigs_drive[i] = {}
    local pot_angle_reader --will be assigned if needed (when i>1)
    local pot_angle_calibrator --will be assigned if needed (when i>1)
    
    if i>1 then  
      --task to poll the pot
      sched.run(function()
        local ipot=i-1
        
        conf.pots = conf.pots or {}; conf.pots[ipot] = conf.pots[ipot] or {}
        conf.pot = conf.pot or {}
        local filepot = conf.pots[ipot].file or conf.pot.file
        log('DM3', 'INFO', 'Using %s as potentiometer input', tostring(filepot))
        if filepot then
          pot_angle_reader = function()
            local fdpot = assert(io_open(filepot, 'rb'))
            local data, err = fdpot:read('*l')
            fdpot:close()
            return assert(tonumber(data), err)
          end
          
          local pot_calibration = assert(conf.pots[ipot].calibration or conf.pot.calibration, 
            'Missing calibration for '..filepot  )
          log('DM', 'INFO', 'Calibrating potentiometer as %s -> %s, %s -> %s, %s -> %s', 
          tostring(pot_calibration[1][1]), tostring(pot_calibration[1][2]),
          tostring(pot_calibration[2][1]), tostring(pot_calibration[2][2]),
          tostring(pot_calibration[3][1]), tostring(pot_calibration[3][2]))
          pot_angle_calibrator = require 'tasks.dm3control.calibrator'(pot_calibration)
          
          local rate, threshold = conf.pot.rate, conf.pot.threshold
          local last_pot = -1000000
          while true do
            local pot_reading = pot_angle_reader()
            if abs(pot_reading-last_pot) > threshold then
              last_pot = pot_reading
	      if conf.pot.calibration_dump then 
                 log('DM3', 'INFO', 'Pot reading %i %s %d', i, filepot, pot_reading)
              end
              sched.signal(sig_angle, pot_angle_calibrator(pot_reading))
            end
            sched.sleep(rate)
          end
        end
      end)--:set_as_attached()
    end
    
    local chassis_out_file
    if conf.data_dump.chassis_enable and (i==1 or conf.articulated) then
      chassis_out_file = io_open((conf.data_dump.path or './') .. start_date..'_chassis_'..i..'.log', 'w')
      chassis_out_file:setvbuf ('line')
    end
    
    sched.run(function()
      log('DM3', 'INFO', 'Chassis %i Motors: left %s, right %s', i, chassis.left, chassis.right)
      local motor_left = toribio.wait_for_device(chassis.left)
      local motor_right = toribio.wait_for_device(chassis.right)
      local left_mult, right_mult = chassis.left_mult or 1, chassis.right_mult or 1
      log('DM3', 'INFO', 'Chassis %i Motors multipliers: left %s, right %s', i, left_mult, right_mult)
      motor_left.set.rotation_mode('wheel')
      motor_right.set.rotation_mode('wheel')
      
      local sig_drive_in
      
      -- when articulated, read drive commands from previous trains, input commands otherwise
      if conf.articulated then
        sig_drive_in = sigs_drive[i-1]
      else
        sig_drive_in = sigs_drive[0]
      end
      
      local sig_drive_out = sigs_drive[i]
      local pangle, fmodulo, fangle = 0, 0, 0
      if pot_angle_reader then 
        pangle = pot_angle_calibrator(pot_angle_reader())
      end
      
      sched.sigrun( {sig_drive_in, sig_angle, buff_mode='keep_last'}, function(sig,par1,par2)
        if sig==sig_drive_in then 
          fmodulo, fangle = par1, par2 
        elseif sig==sig_angle then 
          pangle = par1 
        end
        
        local fangle_local = fangle+pangle
             
        local fx = fmodulo * cos(fangle_local)
        local fy = fmodulo * sin(fangle_local)
        
        local out_r = fx - d_p*fy
        local out_l = fx + d_p*fy
        
        ---[[
        log('DM3', 'DEBUG', 'Drive %s: IN modulo %s, drive %s, angle %s, pot %s, OUT left %s, right %s', 
          tostring(i), tostring(fmodulo), tostring(sig==sig_drive_in), tostring(fangle), 
          tostring(pangle), tostring(out_l), tostring(out_r))
        --]]
        
        motor_left.set.moving_speed( left_mult*out_l )
        motor_right.set.moving_speed( right_mult*out_r )
        
        if chassis_out_file then 
          local s = (sched.get_time()-start_ts)..' '
            ..fmodulo..' '..fangle_local..' '..pangle..' '..out_l..' '..out_r..'\n'
          chassis_out_file:write(s)
        end
        
        sched.signal(sig_drive_out, fmodulo, -fangle_local)
      end)
      log('DM3', 'INFO', 'Motors left %s and right %s ready', chassis.left, chassis.right)
    end)
  end

  --[[
  sched.run(function()
      sched.sleep(3)
      sched.signal(sig_drive_control, 20, 0)
  end)
  --]]
  if conf.script then 
    local last_ts = start_ts
    local accum_ts = 0
    sched.run(function ()
      log('DM3', 'INFO', 'Script started with %i steps', #conf.script)
      dm3.set.power(true)
      for i, reg in ipairs(conf.script) do
        local t, modulo, angle = reg[1], reg[2], reg[2]
        accum_ts = accum_ts + t
        sched.sleep( (accum_ts+start_ts)-sched.get_time() )
        log('DM3', 'INFO', 'Scripted action #%i mod=%d ang=%d', i, modulo, angle)
        sched.signal( sig_drive_control, modulo, angle )
      end
      dm3.set.power(false)
      log('DM3', 'INFO', 'Script finished')
    end)
  end

  -- HTTP RC
  if conf.http_server then
    local http_server = require "lumen.tasks.http-server"
    --http_server.serve_static_content_from_stream('/docs/', './docs')
    http_server.serve_static_content_from_ram('/', './tasks/dm3control/www')
    local watchdog
    local gpsd
    
    http_server.set_websocket_protocol('dm3-rc-protocol', function(ws)
      
      dm3.set.power(false) --always start powered down
      
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
      local gpsd_sender = sched.run(function()
        gpsd = toribio.wait_for_device('gpsd')
        log('DM3', 'INFO', 'gpsd service found %s', tostring(gpsd))
        local gps_mode
        local gps_speed
        toribio.register_callback(gpsd, 'TPV', function(v)
          local mode, speed, lat, lon, track = v.mode, v.speed, v.lat, v.lon, v.track 
          if mode ~= gps_mode then
            assert(ws:send('{ "action":"gps", "mode":' .. tostring(mode) ..'}'))
            gps_mode = mode
          end
          if speed ~= gps_speed then 
            assert(ws:send('{ "action":"gps", "speed":' .. tostring(speed) ..'}'))
            gps_speed = speed
          end
        end)
        sched.sleep(1)
        gpsd.set_watch(true)
      end)
      local build_environment = function()
        local e = {
          sched = sched,
          sleep = sched.sleep,
          go = function(m, a) sched.signal(sig_drive_control, m, a) end,
          stop = function() sched.signal(sig_drive_control, 0, 0  ) end,
        }
        for k,v in pairs (_G) do e[k] = e[k] or v end
        return e
      end
      sched.run(function()
        local script
        while true do
          local message,opcode = ws:receive()
          log('DM3', 'DEBUG', 'websocket traffic "%s"', tostring(message))
          if not message then
            sched.signal(sig_drive_control, 0, 0)
            log('DM3', 'INFO', 'Connection closed, Powering down')
            dm3.set.power(false)
            gpsd_sender:kill(); gpsd_sender=nil; if gpsd then gpsd.set_watch(false) end
            stat_sender:kill(); stat_sender = nil
            if script then script:kill(); script=nil; end
            watchdog:kill()
            ws:close()
            return
          end
          if opcode == ws.TEXT then        
            local decoded, index, e = decode_f(message)
            if decoded then 
              if decoded.action == 'drive' then
                local modulo, angle, left, right = 
                  tonumber(decoded.modulo), tonumber(decoded.angle), 
                  tonumber(decoded.left), tonumber(decoded.right)
                log('DM3', 'DETAIL', 'Drive: M:%s a:%s L:%s R:%s', 
                  tostring(modulo), tostring(angle), tostring(left), tostring(right))
                if left then 
                  for _, chassis in ipairs(conf.motors) do
                    local motor = toribio.wait_for_device(chassis.left)
                    local mult = chassis.left_mult or 1
                    motor.set.moving_speed( mult*left )
                  end
                end
                if right then 
                  for _, chassis in ipairs(conf.motors) do
                    local motor = toribio.wait_for_device(chassis.right)
                    local mult = chassis.right_mult or 1
                    motor.set.moving_speed( mult*right )
                  end
                end
                if modulo and angle then 
                  sched.signal(sig_drive_control, modulo, angle)
                end
              elseif decoded.action == 'keepalive' then
                sched.signal(event_client_keeplive)
              elseif decoded.action == 'brake' then
                log('DM3', 'INFO', 'Brake enable: %s', tostring(decoded.enable))
                if script then 
                  script:kill()
                  script = nil
                end
                dm3.set.brake(decoded.enable)
              elseif decoded.action == 'power' then
                log('DM3', 'INFO', 'Power enable: %s', tostring(decoded.enable))
                dm3.set.power(decoded.enable)
              elseif decoded.action == 'horn' then
                log('DM3', 'INFO', 'Horn enable: %s', tostring(e))
                dm3.set.horn(decoded.enable)
              elseif decoded.action == 'run' then
                if script then script:kill() end
                script = sched.run(function()
                  local my_path = debug.getinfo(1, "S").source:match[[^@?(.*[\/])[^\/]-$]]
                  --local filename = conf.script.path .. decoded.script .. '.lua'
                  local filename = my_path .. 'dm3control/myscripts/'..decoded.script .. '.lua'
                  log('DM3', 'INFO', 'Starting script: %s', tostring(filename))
                  local s = assert(loadfile(filename))
                  setfenv(s, build_environment())
                  s()
                end)
              end  
            else
              log('DM3', 'ERROR', 'failed to decode message with length %s with error "%s"', 
                tostring(#message), tostring(index).." "..tostring(decoded))
            end
          end
        end
      end) --:set_as_attached()
      watchdog = watchdog or sched.run(function()
        local waitd = {event_client_keeplive, timeout=3}
        while true do
          repeat 
            local ev = sched.wait(waitd)
          until ev==nil
          log('DM3', 'WARN', 'HTTP RC Keepalive missed, Powering down')
          dm3.set.power(false)
        end
      end)
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
      sched.signal(sig_drive_control, tonumber(fmodulo), tonumber(fangle))
    end)
  end

  -- /UDP RC

end


return M
