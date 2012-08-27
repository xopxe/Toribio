local M = {}

local debugprint = _G.debugprint
local toribio = require 'toribio'
local devices = toribio.devices
local sched = require "sched"
local catalog = require 'catalog'
local bobot = nil --require('comms/bobot').bobot

table.pack=table.pack or function (...)
	return {n=select('#',...),...}
end

local function split_words(s)
	local words={}

	for p in string.gmatch(s, "%S+") do
		words[#words+1]=p
	end
	
	return words
end

process = {}

process["INIT"] = function () --to check the new state of hardware on the fly
	--server_init()
	toribio.init(nil)
	return 'ok'
end
process["REFRESH"] = function () --to check the new state of hardware on the fly
	--server_refresh()
	sched.signal('do_bobot_refresh')
	return 'ok'
end


process["LIST"] = function ()
print("listing devices", devices)
	local ret,comma = "", ""
	for name, _ in pairs(devices) do
		ret = ret .. comma .. name
		comma=","
	end
	return ret
end

--[[
process["LISTI"] = function ()
    if baseboards then
        debugprint("listing instanced modules...")
        for _, bb in ipairs(bobot.baseboards) do
    	    local handler_size=bb:get_handler_size()
            for i=1, handler_size do
                t_handler = bb:get_handler_type(i)
                debugprint("handler=", i-1 ," type=" ,t_handler)
            end
        end
    end
end
--]]

process["OPEN"] = function (parameters)
	local d  = parameters[2]
	local ep1= tonumber(parameters[3])
	local ep2= tonumber(parameters[4])

	if not d then
		debugprint("ls:Missing 'device' parameter")
		return
	end

	return "ok"

end
process["DESCRIBE"] = function (parameters)
	local d  = parameters[2]
	local ep1= tonumber(parameters[3])
	local ep2= tonumber(parameters[4])

	if not d then
		debugprint("ls:Missing \"device\" parameter")
		return
	end
	
	local device = devices[d]

	--if not device.api then
	--	return "missing driver"
	--end

	local  skip_fields = {remove=true, name=true, register_callback=true, signals=true,
		task=true, filename=true, module=true}
	
	local ret = "{"
	for fname, fdef in pairs(device) do
			if not skip_fields[fname] then 
			ret = ret .. fname .. "={"
			ret = ret .. " parameters={"
			for i,pars in ipairs({}) do
				ret = ret .. "[" ..i.."]={"
				for k, v in pairs(pars) do
					ret = ret .."['".. k .."']='"..tostring(v).."',"
				end
				ret = ret .. "},"
			end
			ret = ret .. "}, returns={"
			for i,rets in ipairs({}) do
				ret = ret .. "[" ..i.."]={"
				for k, v in pairs(rets) do
					ret = ret .."['".. k .."']='"..tostring(v).."',"
				end
				ret = ret .. "},"
			end
			ret = ret .. "}}," 
		end
	end
	ret=ret.."}"

	return ret
end
process["CALL"] = function (parameters)
	local d  = parameters[2]
	local call  = parameters[3]

	if not (d and call) then
		debugprint("ls:Missing parameters", d, call)
		return
	end

	local device = devices[d]
	
	local api_call=device[call];
	if not api_call then return "missing call" end
	
	--local tini=socket.gettime()
	--local ok, ret = pcall (api_call.call, unpack(parameters,4))
	--if not ok then debugprint ("Error calling", ret) end
	
	local ret = table.pack(pcall (api_call, unpack(parameters,4)))
	local ok = ret[1]
	if ok then 
		return table.concat(ret, ',', 2)
	else 
		print ("error calling", table.concat(ret, ',', 2))
	end
end
process["CLOSEALL"] = function ()
	if bobot and bobot.baseboards then
		for _, bb in ipairs(bobot.baseboards) do
            --this command closes all the open user modules
            --it does not have sense with plug and play
			bb:force_close_all() --modif andrew
		end
	end
	return "ok"
end
process["BOOTLOADER"] = function ()
	if bobot and bobot.baseboards then
		for _, bb in ipairs(bobot.baseboards) do
			bb:switch_to_bootloader()
		end
	end
	return "ok"
end
process["DEBUG"] = function (parameters) --disable debug mode Andrew code!
	local debug = parameters[2]
	if not debug then return "missing parameter" end
	if debug=="ON" then
		debugprint = print --function(...) print (...) end  --enable printing
	elseif debug=="OFF" then
		debugprint = function() end  --do not print anything
	end
	return "ok"
end
process["QUIT"] = function () 
	debugprint("Requested EXIT...")
	os.exit()
	return "ok"
end


M.init = function(conf)
	local nixiorator = require 'tasks/nixiorator'
	local nixio = nixiorator.nixio
	print ('nixiorator found:', nixiorator.task)
	
	local ip = conf.ip or '127.0.0.1'
	local port = conf.port or 2009
	local tcprecv = assert(nixio.bind(ip, port, 'inet', 'stream'))
	nixiorator.register_server(tcprecv, 'line')

	local handler_task = function(_, inskt, line, err)
		--print("bobot server:", inskt, line, err or '')
		if not line then return end

		local words=split_words(line)
		local command=words[1]
		if not command then
			debugprint("bs:Error parsing line:", line, command)
		else
			if not process[command] then
				debugprint("bs:Command not supported:", command)
			else
				local ret = process[command](words) or ""
				if ret then 
					inskt:send(ret.."\n")
				else
					debugprint ("Error calling", command)
					inskt:send("\n")
				end
			end
		end
		
	end
	
	--accept connections
	return sched.sigrun( {emitter=nixiorator.task, events={tcprecv}},
		function(_, _, msg, inskt)
			catalog.register("bobot-server-accepter")

			print ("new bobot server client", tcprecv, msg, inskt )
			if msg=='accepted' then
				sched.sigrun({emitter=nixiorator.task, events={inskt}}, handler_task)
			end
		end
	)
end

return M
