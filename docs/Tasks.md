# Tasks.

Developping for toribio consists of writing tasks. Tasks are described in 
the configuration file, and copied in the tasks/ folder.

## Anatomy of a task.

The skeleton of a task file (called say taskname.lua) is as follows:

    local M = {}
    
    function M.start (conf)
    	local sched=require 'sched'
    	-- initialize stuff

    	sched.run(function()
		-- do something
    	end)
    end
    
    return M

If the file is called taskname.lua, then there might be an entry
in the toribio-go.conf file as follows

    tasks.taskname.load=true
    tasks.taskname.someparameter='text'
    tasks.taskname.anotherparameter=0

The toribio-go.lua script will start the tasks if the load parameter is
true. All the configuration parameters will be provided in the conf table.
Notice that the full configuration table is available at
toribio.configuration.

The start() call must start the Lumen tasks (there might be several), 
register callbacks, etc. Optionally, the module can provide further tasks
to use the tasks module. For example, a task that will print "tick" at a
regulable intervals of time can be as follows:

    local M = {}

    local interval = 1

    function M.set_interval (v)
    	interval=v
    end
    
    function M.start (conf)
    	local sched=require 'sched'
    	sched.run(function()
    		while true do
    			sched.sleep(interval)
    			print('tick')
    		end
    	end)
    end
    
    return M

