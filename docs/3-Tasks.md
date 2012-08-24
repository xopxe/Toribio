# Tasks.

Developping for toribio consists of writing tasks. Tasks are described in 
the configuration file, and copied in the tasks/ folder.

## Anatomy of a task.

The skeleton of a task file (called say taskname.lua) is as follows:

    local M = {}
    local sched=require 'sched'
    
    function M.start (conf)
    	-- initialize stuff
    	sched.run(function()
		-- do something
    	end)
    end
    
    return M

As the file is called taskname.lua, then there might be an entry
in the toribio-go.conf file as follows

    tasks.taskname.load=true
    tasks.taskname.someparameter='text'
    tasks.taskname.anotherparameter=0

The toribio-go.lua script will start the tasks if the load parameter is
true. All the configuration parameters will be provided in the conf table 
(when starting this task, toribio will invoke `M.start(tasks.taskname)`).
Notice that the full configuration table is available at
toribio.configuration.

The `start()` call must start the Lumen process (there might be several), 
register callbacks, etc. Optionally, the module can provide further methods. 
For example, a task that will print "tick" at a regulable intervals of time 
can be as follows:

    local M = {}
    local sched=require 'sched'

    local interval = 1

    function M.set_interval (v)
    	interval=v
    end
    
    function M.start (conf)
    	sched.run(function()
    		while true do
    			sched.sleep(interval)
    			print('tick')
    		end
    	end)
    end
    
    return M

Another example of an extra method is a `stop()` call. The previous program 
could be modified as follows:

    local M = {}
    local sched=require 'sched'
    
    local interval = 1

    function M.set_interval (v)
    	interval=v
    end
    
    function M.start (conf)
    	M.task = M.task or sched.run(function()
    		while true do
    			sched.sleep(interval)
    			print('tick')
    		end
    	end)
    end

    function M.stop()
    	if M.task then M.task:kill() end
    end
    
    return M


