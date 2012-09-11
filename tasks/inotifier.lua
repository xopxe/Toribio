local M = {}

local sched=require 'sched'
local nixiorator = require 'tasks/nixiorator'
local nixio = nixiorator.nixio

--executes s on the console and returns the output
local run_shell = function (s)
	local f = io.popen(s) -- runs command
	local l = f:read("*a") -- read output of command
	f:close()
	return l
end
local function run_shell_nixio(command)
    local fdi, fdo = nixio.pipe()
    local pid = nixio.fork()
	if pid > 0 then 
		--parent
		fdo:close()
		return fdi
	else
		--child
		nixio.dup(fdo, nixio.stdout)
		fdi:close()
		fdo:close()
		nixio.exec("/bin/sh", "-c", command)
	end
end

M.init = function(masks_to_watch)
	sched.run(function()
		require 'catalog'.get_catalog('tasks'):register(masks_to_watch, sched.running_task)

		if #run_shell('which inotifywait')==0 then
			error('inotifywait not available')
		end
		local paths_to_watch = {}
		for _, mask in ipairs(masks_to_watch) do
			--print('DDDDDDDDDDDDD+', mask)
			--string.match(mask, '^(.*%/)[^%/]*$')
			local dir = nixio.fs.dirname(mask) 
			paths_to_watch[dir..'/']=true 
			--print('DDDDDDDDDDDDD-', dir)
		end
		
		local command = 'inotifywait -q -c -m -e create,delete'
		for path, _ in pairs(paths_to_watch) do
			command = command..' '..path
		end
		--print('+++++++++INOTIFY:', command)
		local watcherfd = run_shell_nixio(command)
		nixiorator.register_client(watcherfd, 'line')

		local waitd_inotify={emitter=nixiorator.task, events={watcherfd}, buff_len=100}
		
		--generate events for already existing files
		for _, devmask in ipairs(masks_to_watch) do
			for devfile in nixio.fs.glob(devmask) do
				print('existing file', devfile)
				sched.signal('FILE+', devfile, devmask)
			end
		end

		--monitor files
		while true do
			local _, _,line=sched.wait(waitd_inotify)
			if line then 
				local path, action, file = string.match(line, '^([^,]+),(.+),([^,]+)$')
				local fullpath=path..file
				--print('INOTIFY', action, fullpath)
				if action=='CREATE' then
					for _, mask in ipairs(masks_to_watch) do
						for devfile in nixio.fs.glob(mask) do
							if devfile==fullpath then
								print('FILE+', fullpath, mask)
								sched.signal('FILE+', fullpath, mask)
							end
							--print('confline starting', devfile, modulename)
							--local devmodule = require ('../drivers/filedev/'..modulename)
							--devmodule.init(devfile)
						end
					end
				elseif action=='DELETE' then
					print('FILE-', fullpath)
					sched.signal('FILE-', fullpath)
				end
			end
		end
	end)
end

return M