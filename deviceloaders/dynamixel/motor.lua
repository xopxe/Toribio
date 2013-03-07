--- Library for Dynamixel motors.
-- This library allows to manipulate devices that use Dynamixel 
-- protocol, such as AX-12 robotic servo motors.
-- When available, each conected motor will be published
-- as a device in torobio.devices table, named
-- (for example) 'ax12:1', labeled as module 'ax'
-- @module dynamixel-motor
-- @usage local toribio = require 'toribio'
--local motor = toribio.wait_for_device({module='ax', id=5})
--motor.set_led(true)
-- @alias Motor

--local my_path = debug.getinfo(1, "S").source:match[[^@?(.*[\/])[^\/]-$]]

local log = require 'log'

local M = {}

M.get_motor= function (busdevice, id)
	local read_data = busdevice.read_data
	local write_method
	local idb
	if type(id) == 'number' then 
		idb = string.char(id)
		write_method='write_data'
	else
		idb = {}
		for i, anid in ipairs(id) do
			idb[i] = string.char(anid)
		end
		write_method='sync_write'
	end

	local function get2bytes_unsigned(n)
		if n<0 then n=0
		elseif n>1023 then n=1023 end
		local lowb, highb = n%256, math.floor(n/256)
		return lowb, highb
	end
	local function get2bytes_signed(n)
		if n<-1023 then n=-1023
		elseif n>1023 then n=1023 end
		if n < 0 then n = 1024 - n end
		local lowb, highb = n%256, math.floor(n/256)
		return lowb, highb
	end
	
	if type(id) == 'number' and id ~= 0xFE then 
		if not busdevice.ping(idb) then
			return nil
		end
	end
	
	local Motor = {
		--- The id number of the motor.
		id=id,
	}
	

	--- Device file of the bus.
	-- Filename of the bus to which the motor is connected.
	-- For example, _'/dev/ttyUSB0'_
	Motor.filename = busdevice.filename
	
	--- Bus device.
	-- The dynamixel bus Device to which the motor is connected
	Motor.busdevice = busdevice

	-- calls that are only avalable on proper motors (not 'syncs motors')
	if type(id)=='number' then
	
		--- Reset configuration.
		-- This will reset configuration to factory defaults.
		-- @return a dynamixel error code
		Motor.reset = function()
			return busdevice.reset(idb)
		end
		--- Get model.
		-- Returns the model of the actuator
		-- @return Model number, followed by a dynamixel error code
		Motor.get_model = function()
			local ret, err = read_data(idb,0x00,2)
			if ret then return ret:byte(1) + 256*ret:byte(2), err end
		end
		--- Get firmware version.
		-- Get the version of the actuator's firmware
		-- @return Firmware version, followed by a dynamixel error code
		Motor.get_firmware_version = function()
			return read_data(idb,0x02,1)
		end
		--- Get actuator's ID.
		-- This retrieves the ID number from the motor.
		-- @return ID number, followed by a dynamixel error code
		Motor.get_id = function()
			return read_data(idb,0x03,1)
		end
		--- Get the motor mode.
		-- @return either _'wheel'_ or _'joint'_, followed by a dynamixel error code
		Motor.get_rotation_mode =  function()
			local ret, err = read_data(idb,0x06,4)
			if ret==string.char(0x00,0x00,0x00,0x00) then
				Motor.mode = 'wheel'
			else
				Motor.mode = 'joint'
			end
			return Motor.mode, err
		end
		--- Ping the motor.
		-- @return a dynamixel error code
		Motor.ping = function()
			return busdevice.ping(idb)
		end
		--- Get torque mode.
		-- @return _true_ if torque enabled, followed by a dynamixel error code
		Motor.get_torque_enable = function()
			local ret, err = read_data(idb,0x18,1)
			if ret then return ret:byte()==0x01, err end
		end
		--- Get motor speed.
		-- @return If motor in joint mode, speed in deg/sec. If in wheel
		-- mode, as a % of max torque. Followed by a dynamixel error code.
		Motor.get_speed = function()
			local ret, err = read_data(idb,0x26,2)
			local vel = ret:byte(1) + 256*ret:byte(2)
			if vel > 1023 then vel =1024-vel end
			if Motor.mode=='joint' then 
				return vel / 1.496, err --rpm
			elseif  Motor.mode=='wheel' then
				return vel / 10.23, err --% of max torque
			end
		end
		--- Get operating voltage.
		-- @return The voltage in volts, followed by a dynamixel error code
		Motor.get_operating_voltage = function()
			local ret, err = read_data(idb,0x2A,1)
			if ret then return ret:byte() / 10, err end
		end
		--- Get motor position.
		-- Read the axle position from the motor.
		-- @return The angle in deg, followed by a dynamixel error code. 
		-- The reading is only valid in the 0 .. 300deg range
		Motor.get_position = function()
			local ret, err = read_data(idb,0x24,2)
			if ret then 
				local ang=0.29*(ret:byte(1) +256*ret:byte(2))
				return ang, err  -- deg
			end
		end
		--- Get the torque limit.
		-- Returns the torque limit set in the motor.
		-- @return Percentage of max torque (0% .. 100% range), 
		-- followed by a dynamixel error code
		Motor.get_torque_limit = function()
			local ret, err = read_data(idb,0x22,2)
			local torque = ret:byte(1) + 256*ret:byte(2)
			return torque/10.23, err --% of max torque
		end
		--- Get the motor's load.
		-- The torque value returned is an internal torque value, and
		-- should not be used to infer weights or moments.
		-- @return Percentage of max torque, in the -100% .. 100% range,
		-- followed by a dynamixel error code.
		Motor.get_load = function()
			local ret, err = read_data(idb,0x28,2)
			if ret then 
				local load = ret:byte(1) +256*ret:byte(2)
				if load > 1023 then load = 1024-load end
				return load/10.23, err -- % of torque max
			end
		end
		--- Get motor's temperature.
		-- @return Temperature in degrees Celsius, followed by a dynamixel error code.
		Motor.get_temperature = function()
			return read_data(idb,0x2B,1)
		end
		--- Get if motor is moving.
		-- @return If the motor has reached target position, return _false_.
		-- Otherwhise return _true_. Followed by a dynamixel error code.
		Motor.is_moving = function()
			local ret, err = read_data(idb,0x2E,1)
			if ret then return ret:byte()==0x01, err end
		end
	end -- /calls that are only avalable on proper motors (not 'syncs motors')
	


	--- Set wheel mode.
	--Set the motor to continuous rotation mode.
	-- @return a dynamixel error code
	Motor.init_mode_wheel = function()
		local ret = busdevice[write_method](idb,0x06,string.char(0x00,0x00,0x00,0x00))
		Motor.mode='wheel'
		return ret
	end
	--- Set joint mode.
	-- Set the motor to joint mode. Angles are provided in degrees,
	-- in the full servo coverage (0 - 300 degrees arc)
	-- @param min the minimum joint angle (defaults to 0)
	-- @param max the maximum joint angle (defaults to 300)
	-- @return a dynamixel error code
	Motor.init_mode_joint = function(min, max)
		if min then min=math.floor(min/0.29)
		else min=0 end
		if max then max=math.floor(max/0.29)
		else max=1023 end
		local minlowb, maxhighb = get2bytes_unsigned(min)
		local maxlowb, maxnhighb = get2bytes_unsigned(max)
		local ret = busdevice[write_method](idb,0x06,string.char(minlowb, maxhighb, maxlowb, maxnhighb))
		Motor.mode='joint'
		return ret
	end
	--- Control motor's led.
	-- @param value _true_ switches on, _false_ switches off.
	-- @return a dynamixel error code
	Motor.set_led = function(value)
		local parameter
		if value then 
			parameter=string.char(0x01)
		else
			parameter=string.char(0x00)
		end
		return busdevice[write_method](idb,0x19,parameter)
	end
	--- Set the serial speed of the motor.
	-- @param baud baud rate to set, in the 9600 to 1000000 range.
	-- @return a dynamixel error code
	Motor.set_serial_speed = function(baud)
		local n = math.floor(2000000/baud)-1
		if n<1 or n>207 then error ("Attempt to set serial speed: "..n) end
		return busdevice[write_method](idb,0x04,n)
	end
	--- Enables motor torque.
	-- This activates the motor. 
	-- @param value _true_ switches on, _false_ switches off.
	-- @return a dynamixel error code
	Motor.set_torque_enable = function(value)
		--boolean
		local parameter
		if value then 
			parameter=string.char(0x01)
		else
			parameter=string.char(0x00)
		end
		return busdevice[write_method](idb,0x18,parameter)
	end
	--- Set motor speed.
	-- @param value If motor in joint mode, speed in deg/sec in the 1 .. 684 range 
	-- (0 means max unregulated speed). 
	-- If in wheel mode, as a % of max torque (in the -100% .. 100% range).
	-- @return a dynamixel error code
	Motor.set_speed = function(value)
		if Motor.mode=='joint' then
			-- 0 .. 684 deg/sec
			local vel=math.floor(value * 1.496)
			local lowb, highb = get2bytes_unsigned(vel)
			return busdevice[write_method](idb,0x20,string.char(lowb,highb))
		elseif Motor.mode=='wheel' then
			-- -100% ..  +100% max torque
			local vel=math.floor(value * 10.23)
			local lowb, highb = get2bytes_signed(vel)
			return busdevice[write_method](idb,0x20,string.char(lowb,highb))
		end
	end
	--- Set operating voltage range.
	-- If the operating voltage get out of the specified range, an
	-- alarm is set.
	-- @param min Minimum voltage in volts
	-- @param max Maximum voltage in volts
	-- @return a dynamixel error code
	Motor.set_operating_voltage = function(min, max)
		local minb=math.floor(min*10)
		local maxb=math.floor(max*10)
		return busdevice[write_method](idb,0x0C,string.char(minb,maxb))
	end
	--- Set motor position.
	-- Set the target position for the motor's axle. Only works in
	-- joint mode.
	-- @param value Angle in degrees, in the 0 .. 300deg range.
	-- @return a dynamixel error code
	Motor.set_position = function(value)
		local ang=math.floor(value/0.29)
		local lowb, highb = get2bytes_unsigned(ang)
		return busdevice[write_method](idb,0x1E,string.char(lowb,highb))
	end
	--- Set the torque limit.
	-- Sets the torque limit in the motor.
	-- @param value Percentage of max torque (0% ..100% range).
	-- @return a dynamixel error code
	Motor.set_torque_limit = function(value)
		-- 0% ..  100% max torque
		local torque=math.floor(value * 10.23)
		local lowb, highb = get2bytes_unsigned(torque)
		return busdevice[write_method](idb,0x22,string.char(lowb,highb))
	end

	--- Name of the device.
	-- Of the form _'ax12:5'_
	--- Module name (_'ax'_ or _'ax-sync'_ in this case)
	-- _'ax'_ is for actuators, _'ax-sync'_ is for sync-motor objects
	if type(id) == 'number' then
		if id==0xFE then
			Motor.name = 'ax:broadcast'
		else
			
			Motor.name = 'ax'..(Motor.get_model() or '??')..':'..id
			Motor.mode = Motor.get_rotation_mode()
		end
		Motor.module = 'ax'
	else
		Motor.module = 'ax-sync'
		Motor.name = 'ax-sync:'..tostring(math.random(2^30))
	end
	
	log('AXMOTOR', 'INFO', 'device object created: %s', Motor.name)

	--toribio.add_device(busdevice)
	return Motor
end

return M
