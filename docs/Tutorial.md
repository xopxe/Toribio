# Tutorial.

Here we will build a few programs, step-by-step.

## Install Toribio

First, install nixio:

    # git clone https://github.com/Neopallium/nixio.git
    # cd nixio
    # make
    # sudo make install

If there are errors when compiling, edit the Makefile and change the line:

	$(LINK) $(SHLIB_FLAGS) $(NIXIO_LDFLAGS) -o src/$(NIXIO_SO) $(NIXIO_OBJ) $(NIXIO_LDFLAGS_POST)

with:

    	$(LINK) $(SHLIB_FLAGS) -o src/$(NIXIO_SO) $(NIXIO_OBJ) $(NIXIO_LDFLAGS) $(NIXIO_LDFLAGS_POST)

If you are on OpenWRT, nixio is already installed. You can also crosscompile nixio, for example "make HOST_CC="gcc -m32" CROSS=arm-linux-gnueabi-"


Then, download the [latest version](https://github.com/xopxe/Lumen/tarball/master) of Toribio


## Data logger

First we will do a data logger, that will save information read from an AX-12 motor to a file. We will call the task "axlogger".

We start by editing the configuration file. We must configure two things: enable the dynamixel device loader,
and register the new task, adding the configuration parameters we might use. We do that by adding the following lines to toribio-go.conf:

    deviceloaders.dynamixel.load = true
    deviceloaders.dynamixel.filename = '/dev/ttyUSB0'
    tasks.axlogger.load=true
    tasks.axlogger.motorname='AX12:5'
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



 
