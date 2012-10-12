--- Library for Dynamixel protocol.
-- This library allows to manipulate devices that use Dynamixel 
-- protocol, such as AX-12 robotic servo motors.
-- When available, a dynamixel bus will be represented by a Device
-- object in toribio.devices table. The device will be named (as an 
-- example), "dynamixel:/dev/ttyUSB0". 
-- @module dynamixel-bus
-- @alias busdevice

local M = {}

local toribio = require 'toribio'
local sched = require 'sched'
local catalog = require 'catalog'
local mutex = require 'mutex'()
local ax = require 'deviceloaders/dynamixel/motor'

--local my_path = debug.getinfo(1, "S").source:match[[^@?(.*[\/])[^\/]-$]]

local debugprint=_G.debugprint

local NULL_CHAR = string.char(0x00) 
local BROADCAST_ID = string.char(0xFE)
local PACKET_START = string.char(0xFF,0xFF)

local INSTRUCTION_PING = string.char(0x01)
local INSTRUCTION_READ_DATA = string.char(0x02)
local INSTRUCTION_WRITE_DATA = string.char(0x03)
local INSTRUCTION_REG_WRITE = string.char(0x04)
local INSTRUCTION_ACTION = string.char(0x05)
local INSTRUCTION_RESET = string.char(0x06)
local INSTRUCTION_SYNC_WRITE = string.char(0x83)

local ax_errors = {
	[0x00] = 'NO_ERROR',
	[0x01] = 'ERROR_INPUT_VOLTAGE',
	[0x02] = 'ERROR_ANGLE_LIMIT',
	[0x04] = 'ERROR_OVERHEATING',
	[0x08] = 'ERROR_RANGE',
	[0x10] = 'ERROR_CHECKSUM',
	[0x20] = 'ERROR_OVERLOAD',
	[0x40] = 'ERROR_INSTRUCTION',
}
local signal_ax_error = {}

local function generate_checksum(data)
	local checksum = 0
	for i=1, #data do
		checksum = checksum + data:byte(i)
	end
	return 255 - (checksum%256)
end

M.init = function (conf)
	local nixiorator = require 'tasks/nixiorator'
	local nixio = nixiorator.nixio
	
	local filename = assert(conf.filename)
	local fd, erropen = nixio.open(filename, nixio.open_flags('rdwr', 'nonblock'))
	
	local opencount=60
	while not fd and opencount>0 do
		print('retrying open...', opencount)
		sched.sleep(1)
		fd, erropen = nixio.open(filename, nixio.open_flags('rdwr', 'nonblock'))
		opencount=opencount-1
	end
	if not fd then 
		debugprint('usb failed to open',filename, erropen)
		return 
	end
	fd:sync() --flush()
	debugprint(filename,'opened as', fd)
	nixiorator.register_client(fd, 65000) --TODO message usual size?

	local tty_params = '-parenb -parodd cs8 hupcl -cstopb cread -clocal -crtscts -ignbrk -brkint '
	..'-ignpar -parmrk -inpck -istrip -inlcr -igncr -icrnl -ixon -ixoff -iuclc -ixany -imaxbel '
	..'-opost -olcuc -ocrnl -onlcr -onocr -onlret -ofill -ofdel nl0 cr0 tab0 bs0 vt0 ff0 -isig -icanon '
	..'-iexten -echo -echoe -echok -echonl -noflsh -xcase -tostop -echoprt -echoctl -echoke'
	local speed = conf.serialspeed or 1000000
	local init_tty_string ='stty -F ' .. filename .. ' ' .. speed .. ' ' .. tty_params

	os.execute(init_tty_string)
	
	--local message_pipe=sched.pipes.new({}, 10)
	
	local taskf_protocol = function() 
		local nxtask = require 'catalog'.get_catalog('tasks'):waitfor('nixiorator')
		local waitd_traffic = {emitter=nxtask,events={fd}, buff_len=-1}
		local packet=''
		local insync=false
		local packlen=nil -- -1

		local function parseAx12Packet(s)
			--print('parsing', s:byte(1, #s))
			local id = s:sub(3,3)
			--local data_length = s:byte(4)
			local data = s:sub(5, -1)
			if generate_checksum(s:sub(3,-1))~=0 then return nil,'checksum error' end
			local errinpacket = data:sub(1,1)
			if errinpacket ~= NULL_CHAR then
				sched.signal(signal_ax_error, id, ax_errors[errinpacket:byte()])
			end
			local payload = data:sub(2,-2)
			--print('parsed', id:byte(1, #id),'$', err:byte(1, #err),':', payload:byte(1, #payload))
			return id, errinpacket, payload
		end

		while true do
			local _, _, fragment, err_read = sched.wait(waitd_traffic)
			
			if err_read=='closed' then 
				print('dynamixel file closed:', filename)
				return
			end
			if fragment==NULL_CHAR  then 
				error('No power on serial?')
			end

			packet=packet..fragment

			---[[
			while (not insync) and (#packet>2) and (packet:sub(1,2) ~= PACKET_START) do 
				debugprint('resyncA', packet:byte(1,10) )
				--debugprint('resyncB', insync, #packet, packet:byte(1,2), PACKET_START:byte(1,2))
				packet=packet:sub(2, -1)
			end
			--]]
			
			if not insync and #packet>=4 then
				insync = true
				packlen = packet:byte(4)
			end
			
			--print('++++++++++++++++', #packet, packlen)
			while packlen and #packet>=packlen+4 do --#packet >3 and packlen <= #packet - 3 do
				if #packet == packlen+4 then  --fast lane
					local id, errcode, payload=parseAx12Packet(packet)
					if id then 
						--debugprint('dynamixel message parsed (fast):',id:byte(), errcode:byte(),':', payload:byte(1,#payload))
						sched.signal(id, errcode, payload)
					end
					packet = ''
					packlen = nil
				else --slow lane
					local packet_pre = packet:sub( 1, packlen+4 )
					local id, errcode, payload=parseAx12Packet(packet_pre)
					--assert(handler, 'failed parsing (slow)'..packet:byte(1,#packet))
					if id then 
						--debugprint('dynamixel message parsed (slow):',id, errcode:byte(),':', payload:byte(1,#payload))
						sched.signal(id, errcode, payload)
					end

					local packet_remainder = packet:sub(packlen+5, -1 )
					packet = packet_remainder
					packlen =  packet:byte(4)
				end
				insync = false
			end
		end
	end
	local task_protocol = sched.run(taskf_protocol)

	-- -----------------------------------------
	local function buildAX12packet(id, payload)
		local data = id..string.char(#payload+1)..payload
		local checksum = generate_checksum(data)
		local packet = PACKET_START..data..string.char(checksum)
		return packet
	end
	
	local waitd_protocol = {emitter=task_protocol, events='*', timeout = conf.serialtimeout or 0.01}
	
	local ping = mutex.synchronize(function(id)
		id = id or BROADCAST_ID
		local packet_ping = buildAX12packet(id, INSTRUCTION_PING)
		fd:writeall(packet_ping)
		if id ~= BROADCAST_ID then
			local emitter, _, err = sched.wait(waitd_protocol)
			if emitter then 
				return err 
			else
				return
			end
		end
	end)
	local write_data_now = mutex.synchronize(function(id,address,data)
		id = id or BROADCAST_ID
		local packet_write = buildAX12packet(id, 
			INSTRUCTION_WRITE_DATA..string.char(address)..data)
		fd:writeall(packet_write)
		if id ~= BROADCAST_ID then
			local _, _, err = sched.wait(waitd_protocol)
			if type (err)=='string' and #err==1 then
				return err
			end
		end
	end)
	local read_data = mutex.synchronize(function(id,startAddress,length)
		local packet_read = buildAX12packet(id, 
			INSTRUCTION_READ_DATA..string.char(startAddress)..string.char(length))
		fd:writeall(packet_read)
		local _, _, err, data = sched.wait(waitd_protocol)
		--if #data ~= length then return nil, 'read error' end
		return data, err
	end)
	local reg_write_data = mutex.synchronize(function(id,address,data)
		id = id or BROADCAST_ID
		local packet_reg_write = buildAX12packet(id, 
			INSTRUCTION_REG_WRITE..string.char(address)..data)
		fd:writeall(packet_reg_write)
		if id ~= BROADCAST_ID then
			local _, _, err = sched.wait(waitd_protocol)
			if type (err)=='string' and #err==1 then
				return err
			end
		end
	end)
	local action = mutex.synchronize(function(id)
		id = id or BROADCAST_ID
		local packet_action = buildAX12packet(id, INSTRUCTION_ACTION)
		fd:writeall(packet_action)
		if id ~= BROADCAST_ID then
			local _, _, err = sched.wait(waitd_protocol)
			if type (err)=='string' and #err==1 then
				return err
			end
		end
	end)
	local reset = mutex.synchronize(function(id)
		id = id or BROADCAST_ID
		local packet_action = buildAX12packet(id, INSTRUCTION_RESET)
		fd:writeall(packet_action)
		if id ~= BROADCAST_ID then
			local _, _, err = sched.wait(waitd_protocol)
			if type (err)=='string' and #err==1 then
				return err
			end
		end
	end)
	local sync_write = mutex.synchronize(function(ids, address,data) 
		local dataout = string.char(address)..string.char(#data)
		for i=1, #ids do
			local sid = ids[i]
			dataout=dataout..sid..data
		end
		local sync_packet = buildAX12packet(BROADCAST_ID, 
			INSTRUCTION_SYNC_WRITE..dataout)
		fd:writeall(sync_packet)
	end)
	-- -----------------------------------------
	
	local busdevice = {
		ping = ping,
		reset = reset,
		read_data =read_data,
		write_data = write_data_now,
		sync_write = sync_write,
	}

	--- Motors connected to the bus.
	-- The keys are device numbers, the values are Motor objects.
	busdevice.motors = {}
	
	--- Name of the device.
	-- Of the form _'dynamixel:/dev/ttyUSB0'_
	busdevice.name = 'dynamixel:'..filename
	
	--- Module name (in this case, _'dynamixel'_).
	busdevice.module = 'dynamixel'
	
	--- Device file of the bus.
	-- For example, '/dev/ttyUSB0'
	busdevice.filename = filename
	
	--- Task that will emit signals associated to this device.
	busdevice.task = task_protocol
	
	--- Signals emitted by this device.
	-- @field ax_error Error detected. The first parameter is the motor ID, the second is the error description.
	-- @table events
	busdevice.events = {
		ax_error=signal_ax_error,
	}
	-- --- Sync write method.
	-- sync_write=sync_write,
	
	--- Starts a register write mode.
	-- In reg_write mode changes in configuration to devices 
	-- are not applied until a @{reg_write_action} call.
	busdevice.reg_write_start = function()
		busdevice.write_data = reg_write_data
	end
	--- Finishes a register write mode.
	-- All changes in configuration applied after a previous
	-- @{reg_write_start} are commited.
	busdevice.reg_write_action = function()
		action()
		busdevice.write_data = write_data_now
	end

	--- Set the ID of a motor.
	-- Use with caution: all motors connected to the bus will be 
	-- reconfigured to the new ID.
	-- @param id ID number to set.
	busdevice.set_id = function(id)
		local idb=string.char(id)
		busdevice.write_data(BROADCAST_ID,0x03,idb)
	end

	--- Get a broadcasting Motor object.
	-- All commands sent to this motor will be broadcasted
	-- to all motors. 
	-- @return A Motor object.
	busdevice.get_broadcaster = function()
		return busdevice.get_motor(0xFE)
	end
	
	--- Get a Motor object.
	-- @param id The numeric ID of the motor
	-- @return A Motor object, or nil if not such ID found.
	busdevice.get_motor = function(id)
		if busdevice.motors[id] then return busdevice.motors[id] end
		local motor=ax.get_motor(busdevice, id)
		busdevice.motors[id] = motor
		return motor
	end
	
	--- Get a Sync-motor object.
	-- A sync-motor allows to control several actuators with a single command.
	-- The commands will be applied to all actuators it represents. 
	-- The "get" methods are not available. 
	-- @param ... A set of motor Device objects or numeric IDs
	-- @return a sync_motor object
	busdevice.get_sync_motor = function(...)
		local ids = {}
		for i=1, select('#', ...)  do
			local m = select(i, ...)
			if type (m) == 'number' then 
				local motor = busdevice.get_motor(m)
				if motor then ids[#ids+1] = motor.id end
			else 
				ids[#ids+1] = m.id 
			end
		end
		return ax.get_motor(busdevice, ids)
	end
	
	debugprint('device object created', busdevice.name)

	toribio.add_device(busdevice)
	
	sched.run(function()
		--local dm = busdevice.api
		sched.signal('discoverystart')
		for i = 0, 253 do
			local motor = busdevice.get_motor(i)
			--print('XXXXXXXX',i, (motor or {}).name) 
			if motor then 
				busdevice.events[i] = string.char(i)
				toribio.add_device(motor)
			end
			--sched.yield()
		end
		sched.signal('discoveryend')
	end)
end

return M
