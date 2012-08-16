# Tutorial.

Here we will build a few programs, step-by-step.


## Data logger

First we will do a data logger, that will save information read from an AX-12 motor to a file. We will call the task "axlogger".

We start by editing the configuration file. We must configure two things: enable the dynamixel device loader,
and register the new task, adding the configuration parameters we might use. We do that by adding the following lines to toribio-go.conf:

    deviceloaders.dynamixel.load = true
    deviceloaders.dynamixel.filename = '/dev/ttyUSB0'
    tasks.axlogger.load=true
    tasks.axlogger.motorname='ax12:3'
    tasks.axlogger.interval=1
    tasks.axlogger.outfile='motor.log'

Then we place the task's code in the tasks/ folder. The tasks/axlogger.lua file:

    local M = {}
    local sched=require 'sched'
    local toribio = require 'toribio'

    M.start = function(conf)
    	sched.run(function()
    		local file = io.open(conf.outfile or 'data.log', 'w')
    		local motor = toribio.wait_for_device(conf.motorname)
    		while true do
    			local l = motor:get_load()
    			file:write(l..'\n')
    			file:flush()
    			sched.sleep(conf.interval or 5)
    		end
    	end)
    end

    return M

The log file will contain motor load readings. The task (the function provided to sched.run) starts opening a file for writing and getting the Device for the specified motor. The wait\_for\_device call will block until the device is detected, so it is important to place that call _inside_ the task (we do not want the main task blocking).

The task then will loop reading data from the motor and logging it, and then sleeping for the specified interval.

Notice how in the program we provide default values for configuration parameters in case they're missing (like a 5 second interval).

Finally, we run the program:

    lua toribio-go.lua

## Remote controlled robot

We will do a remote controlled robot. One instance of toribio will read inputs from the mouse, an generate commands over a UDP link to a Toribio instance in a robot with two motors (left and rigth).

### Remote Control

We will need the mice device, and a task to process mice input and generate commands. We begin with the toribio-go.conf configuration file:

    deviceloaders.mice.load = true
    tasks.rc_control.load=true
    tasks.rc_control.ip='127.0.0.1' --change with the ip adress of the robot
    tasks.rc_control.port=9999

The remote control will behave as follows: it tracks mouse's movements, generates messages of the form "left, right" and sends them over udp. A message is sent at least each 0.5 seconds, so if we stop transmitting the robot can deduce it must stop. The skeleton for the tasks/rc_control.lua file is as follows:

    local M = {}
    local toribio = require 'toribio'
    local sched = require 'sched'
    
    M.start = function(conf)
    
    	local function generate_output(x, y)
    		--calculate velocities and send them over udp
    	end
    
    	sched.run(function()
    		local mice = toribio.wait_for_device('mice:/dev/input/mice')
    		local lastx, lasty = 0, 0
    		mice:register_callback('move', function (x, y)
    			if x then 
    				generate_output(x, y)
    				lastx, lasty = x, y
    			else
    				-- timeout with no mouse movements
    				generate_output(lastx, lasty)
    			end
    		end, 0.5)
    	end)
    end
    
    return M

In this program we use the register\_callback method, instead of the explicit loop with a sched.wait inside as in the first program. This will start yet another task (the one listening for the signal), that will keep runing while the first task (the one started with sched.run) will finish immediatelly. The register\_callback method has a timeout parameter set (the 0.5 at the end). When the timeout runs out wihtout signals, it will wake our function with nil, 'timeout' as parameters: that's why we check for x to see wether we have a new coordinate, or must use the last recorded set of coordinates.

The only part missing is the generate\_output function. We will use nixio to create a UDP socket and use it to send the messages.

    local nixio = require 'nixio'
    local udp = assert(nixio.bind('*', 0, 'inet', 'dgram'))
    udp:connect(conf.ip, conf.port)
    local function generate_output(x, y)
    	local left = (y + x)/2
    	local right = (y - x)/2
    	udp:send(left..','..right)
    end

This program can be easily improved adding a callback that would react to mouse clicks. For example adding the following callback allows to stop the robot clicking the left button.

    mice:register_callback('leftbutton', function (is_pressed)
    	if is_pressed then 
    		generate_output(0, 0)
    		mice.reset_pos(0, 0)
    		lastx, lasty = 0, 0
    	end
    end)

### Controlled bot

The bot listens for UDP packets, parses them and set motor velocities. As allways, the configuration in toribio-go.conf:

    deviceloaders.dynamixel.load = true
    deviceloaders.dynamixel.filename = '/dev/ttyUSB0'
    tasks.rc_bot.load = true
    tasks.rc_bot.ip = '127.0.0.1' --change with the ip adress of the robot
    tasks.rc_bot.port = 9999
    tasks.rc_bot.motor_left = 'ax12:3'
    tasks.rc_bot.motor_right = 'ax12:12'

And the tasks/rc\_bot.lua skeleton:

    local M = {}
    local toribio = require 'toribio'
    local sched = require 'sched'
    
    M.start = function(conf)
    
    	sched.run(function()
    		--initialize motors
    		local motor_left = toribio.wait_for_device(conf.motor_left)
    		local motor_right = toribio.wait_for_device(conf.motor_right)
    		motor_left.init_mode_wheel()
    		motor_right.init_mode_wheel()

    		--initialize socket
    		local nixio = require 'nixio'
    		local udp = assert(nixio.bind(conf.ip, conf.port, 'inet', 'dgram'))
    		local nixiorator = require 'tasks/nixiorator'
    		nixiorator.register_client(udp, 1500)
    
    		--listen for messages
    		sched.sigrun({emitter=nixiorator.task, events={udp}, timeout=1}, 
    			function(_, _, msg) 
    				local left, right = 0, 0
    				if msg then
    					left, right = msg:match('^([^,]+),([^,]+)$')
    				end
    				motor_left.set_speed(left)
    				motor_right.set_speed(right)
    			end
    		)
    	end)
    end
    
    return M

Notice how we feed the socket to the nixiorator service (the nixiorator.register_client call), that will emit signals when data arrives. Then we listen for these signals with a function (registered in the sched.sigrun call). The timeout is set so if we do not receive a command within a second, the robot will stop.

Now we run toribio with rc\_control task enabled on one machine, connected to a second machine with rc\_bot enabled.

    lua toribio-go.lua

Notice that rc\_control might have to be run as sudo, if your distribution request such thing for accesing /dev/input/mice.

## Reactive line follower

TODO
