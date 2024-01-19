-- Copyright 2024 Siriling <siriling@qq.com>
module("luci.controller.modem", package.seeall)
local http = require "luci.http"
local fs = require "nixio.fs"
local json = require("luci.jsonc")
uci = luci.model.uci.cursor()
local script_path="/usr/share/modem/"

function index()
    if not nixio.fs.access("/etc/config/modem") then
        return
    end

	entry({"admin", "network", "modem"}, alias("admin", "network", "modem", "modem_info"), translate("Modem"), 100).dependent = true

	--模块状态
	entry({"admin", "network", "modem", "modem_info"}, template("modem/modem_info"), translate("Modem Information"),10).leaf = true
	entry({"admin", "network", "modem", "get_modem_info"}, call("getModemInfo"))

	--模块设置
	entry({"admin", "network", "modem", "index"},cbi("modem/index"),translate("Dial Config"),20).leaf = true
	entry({"admin", "network", "modem", "config"}, cbi("modem/config")).leaf = true
	entry({"admin", "network", "modem", "get_modems"}, call("getModems"), nil).leaf = true
	entry({"admin", "network", "modem", "status"}, call("act_status")).leaf = true

	--模块调试
	entry({"admin", "network", "modem", "modem_debug"},template("modem/modem_debug"),translate("Modem Debug"),30).leaf = true
	entry({"admin", "network", "modem", "get_at_port"}, call("getATPort"), nil).leaf = true
	entry({"admin", "network", "modem", "get_quick_commands"}, call("getQuickCommands"), nil).leaf = true
	entry({"admin", "network", "modem", "send_at_command"}, call("sendATCommand"), nil).leaf = true
	entry({"admin", "network", "modem", "get_network_prefer"}, call("getNetworkPrefer"), nil).leaf = true
	entry({"admin", "network", "modem", "set_network_prefer"}, call("setNetworkPrefer"), nil).leaf = true
	entry({"admin", "network", "modem", "get_mode"}, call("getMode"), nil).leaf = true
	entry({"admin", "network", "modem", "set_mode"}, call("setMode"), nil).leaf = true
	
	--AT命令旧界面
	entry({"admin", "network", "modem", "at_command_old"},template("modem/at_command_old")).leaf = true
end

--[[
@Description 判断字符串是否含有字母
@Params
	str 字符串
]]
function hasLetters(str)
    local pattern = "%a" -- 匹配字母的正则表达式
    return string.find(str, pattern) ~= nil
end

--[[
@Description 执行AT命令
@Params
	at_port AT串口
	at_command AT命令
]]
function at(at_port,at_command)
	local odpall = io.popen("cd "..script_path.." && source "..script_path.."modem_debug.sh && at "..at_port.." "..at_command)
	local odp =  odpall:read("*a")
	odpall:close()
	odp=string.gsub(odp, "\r", "")
	return odp
end

--[[
@Description 获取模组连接状态
@Params
	at_port AT串口
	manufacturer 制造商
]]
function getModemConnectStatus(at_port,manufacturer)

	local connect_status="unknown"

	if at_port and manufacturer then
		local odpall = io.popen("cd "..script_path.." && source "..script_path..manufacturer..".sh && get_connect_status "..at_port)
		connect_status = odpall:read("*a")
		connect_status = string.gsub(connect_status, "\n", "")
		odpall:close()
	end

	return connect_status
end

--[[
@Description 获取模组基本信息
@Params
	at_port AT串口
]]
function getModemDeviceInfo(at_port)
	local modem_device_info={}

	uci:foreach("modem", "modem-device", function (modem_device)
		if at_port == modem_device["at_port"] then
			--获取数据接口
			local data_interface=modem_device["data_interface"]:upper()
			--获取连接状态
			local connect_status=getModemConnectStatus(modem_device["at_port"],modem_device["manufacturer"])

			--设置值
			modem_device_info=modem_device
			modem_device_info["data_interface"]=data_interface
			modem_device_info["connect_status"]=connect_status
			return true
		end
	end)

	return modem_device_info
end

--[[
@Description 获取模组更多信息
@Params
	at_port AT串口
	manufacturer 制造商
]]
function getModemMoreInfo(at_port,manufacturer)

	--获取模组信息
	local odpall = io.popen("sh "..script_path.."modem_info.sh".." "..at_port.." "..manufacturer)
	local opd = odpall:read("*a")
	odpall:close()

	--设置值
	local modem_more_info=json.parse(opd)
	return modem_more_info
end

--[[
@Description 模块状态获取
]]
function getModemInfo()

	--获取AT串口
    local at_port = http.formvalue("port")

	--获取信息
	local modem_device_info
	local modem_more_info
	if at_port then
		modem_device_info=getModemDeviceInfo(at_port)
		modem_more_info=getModemMoreInfo(at_port,modem_device_info["manufacturer"])
	end

	--设置信息
	local modem_info={}
	modem_info["device_info"]=modem_device_info
	modem_info["more_info"]=modem_more_info

	--设置翻译
	local translation={}
	--SIM卡信息翻译
	if modem_more_info["sim_info"] then

		local sim_info=modem_more_info["sim_info"]
		for i = 1, #sim_info do
			local info = sim_info[i]
			for key in pairs(info) do
				translation[key]=luci.i18n.translate(key)
				local value=info[key]
				if hasLetters(value) then
					translation[value]=luci.i18n.translate(value)
				end
			end
		end
	end
	--网络信息翻译
	if modem_more_info["network_info"] then
		for key in pairs(modem_more_info["network_info"]) do
			translation[key]=luci.i18n.translate(key)
			local value=modem_more_info["network_info"][key]
			if hasLetters(value) then
				translation[value]=luci.i18n.translate(value)
			end
		end
	end
	--小区信息翻译
	if modem_more_info["cell_info"] then
		for key in pairs(modem_more_info["cell_info"]) do
			translation[key]=luci.i18n.translate(key)
			local network_mode=modem_more_info["cell_info"][key]
			for i = 1, #network_mode do
				local info = network_mode[i]
				for key in pairs(info) do
					translation[key]=luci.i18n.translate(key)
				end
			end
		end
	end

	--整合数据
	local data={}
	data["modem_info"]=modem_info
	data["translation"]=translation
	
	-- 写入Web界面
	luci.http.prepare_content("application/json")
	luci.http.write_json(data)
end

--[[
@Description 获取模组信息
]]
function getModems()
	
	-- 获取所有模组
	local modems={}
	local translation={}
	uci:foreach("modem", "modem-device", function (modem_device)
		-- 获取连接状态
		local connect_status=getModemConnectStatus(modem_device["at_port"],modem_device["manufacturer"])

		-- 获取翻译
		translation[connect_status]=luci.i18n.translate(connect_status)
		translation[modem_device["name"]]=luci.i18n.translate(modem_device["name"])
		translation[modem_device["mode"]]=luci.i18n.translate(modem_device["mode"])

		-- 设置值
		local modem=modem_device
		modem["connect_status"]=connect_status
		modems[modem_device[".name"]]=modem
	end)
	
	-- 设置值
	local data={}
	data["modems"]=modems
	data["translation"]=translation

	-- 写入Web界面
	luci.http.prepare_content("application/json")
	luci.http.write_json(data)
end

--[[
@Description 模块列表状态函数
]]
function act_status()
	local e = {}
	e.index = luci.http.formvalue("index")
	e.status = luci.sys.call(string.format("busybox ps -w | grep -v 'grep' | grep '/var/etc/socat/%s' >/dev/null", luci.http.formvalue("id"))) == 0
	luci.http.prepare_content("application/json")
	luci.http.write_json(e)
end

--[[
@Description 获取模组的备注
@Params
	network 移动网络
]]
function getModemRemarks(network)
	local remarks=""
	uci:foreach("modem", "config", function (config)
		---配置启用，且备注存在
		if network == config["network"] and config["enable"] == "1" then
			if config["remarks"] then
				remarks=" ("..config["remarks"]..")" --" (备注)"
				return true --跳出循环
			end
		end
	end)
	return remarks
end

--[[
@Description 获取AT串口
]]
function getATPort()
	local at_ports={}
	uci:foreach("modem", "modem-device", function (modem_device)
		--获取模组的备注
		local network=modem_device["network"]
		local remarks=getModemRemarks(network)

		--设置模组AT串口
		if modem_device["name"] and modem_device["at_port"] then
			
			local name=modem_device["name"]:upper()..remarks
			if modem_device["name"] == "unknown" then
				-- name=modem_device["at_port"]..remarks
				name=modem_device["name"]..remarks
			end

			local at_port = modem_device["at_port"]
			at_ports[at_port]=name
		end
	end)
	-- 写入Web界面
	luci.http.prepare_content("application/json")
	luci.http.write_json(at_ports)
end

--[[
@Description 获取快捷命令
]]
function getQuickCommands()

	--获取快捷命令选项
	local quick_option = http.formvalue("option")
	--获取AT串口
	local at_port = http.formvalue("port")

	--获取制造商
	local manufacturer
	uci:foreach("modem", "modem-device", function (modem_device)
		--设置模组AT串口
		if at_port == modem_device["at_port"] then
			--获取制造商
			manufacturer=modem_device["manufacturer"]
		end
	end)

	--获取模组AT命令
	local quick_commands={}
	if quick_option and manufacturer then
		local odpall = io.popen("cd "..script_path.." && source "..script_path.."modem_debug.sh && get_quick_commands "..quick_option.." "..manufacturer)
		local opd = odpall:read("*a")
		quick_commands=json.parse(opd)
		odpall:close()
	end

	-- 写入Web界面
	luci.http.prepare_content("application/json")
	luci.http.write_json(quick_commands)
end

--[[
@Description 发送AT命令
]]
function sendATCommand()
    local at_port = http.formvalue("port")
	local at_command = http.formvalue("command")

	local response={}
    if at_port and at_command then
		response["response"]=at(at_port,at_command)
		response["time"]=os.date("%Y-%m-%d %H:%M:%S")
    end

	-- 写入Web界面
	luci.http.prepare_content("application/json")
	luci.http.write_json(response)
end

--[[
@Description 获取网络偏好
]]
function getNetworkPrefer()
    local at_port = http.formvalue("port")

	--获取制造商
	local manufacturer
	uci:foreach("modem", "modem-device", function (modem_device)
		--设置模组AT串口
		if at_port == modem_device["at_port"] then
			--获取制造商
			manufacturer=modem_device["manufacturer"]
		end
	end)

	--获取模组网络偏好
	local network_prefer={}
	if at_port and manufacturer and manufacturer~="unknown" then
		local odpall = io.popen("cd "..script_path.." && source "..script_path..manufacturer..".sh && get_network_prefer "..at_port)
		local opd = odpall:read("*a")
		network_prefer=json.parse(opd)
		odpall:close()
	end

	-- 写入Web界面
	luci.http.prepare_content("application/json")
	luci.http.write_json(network_prefer)
end

--[[
@Description 设置网络偏好
]]
function setNetworkPrefer()
    local at_port = http.formvalue("port")
	local network_prefer_config = json.stringify(http.formvalue("prefer_config"))

	--获取制造商
	local manufacturer
	uci:foreach("modem", "modem-device", function (modem_device)
		--设置模组AT串口
		if at_port == modem_device["at_port"] then
			--获取制造商
			manufacturer=modem_device["manufacturer"]
		end
	end)

	--设置模组网络偏好
	local odpall = io.popen("cd "..script_path.." && source "..script_path..manufacturer..".sh && set_network_prefer "..at_port.." "..network_prefer_config)
	odpall:close()

	--获取设置好后的模组网络偏好
	local network_prefer={}
	if at_port and manufacturer and manufacturer~="unknown" then
		local odpall = io.popen("cd "..script_path.." && source "..script_path..manufacturer..".sh && get_network_prefer "..at_port)
		local opd = odpall:read("*a")
		network_prefer=json.parse(opd)
		odpall:close()
	end

	-- 写入Web界面
	luci.http.prepare_content("application/json")
	luci.http.write_json(network_prefer)
end

--[[
@Description 获取拨号模式
]]
function getMode()
	local at_port = http.formvalue("port")

	--获取制造商和支持的拨号模式
	local manufacturer
	local modes
	uci:foreach("modem", "modem-device", function (modem_device)
		--设置模组AT串口
		if at_port == modem_device["at_port"] then
			--获取制造商
			manufacturer=modem_device["manufacturer"]
			modes=modem_device["modes"]
		end
	end)

	--获取模组拨号模式
	local mode
	if at_port and manufacturer and manufacturer~="unknown" then
		local odpall = io.popen("cd "..script_path.." && source "..script_path..manufacturer..".sh && get_mode "..at_port)
		mode = odpall:read("*a")
		mode=string.gsub(mode, "\n", "")
		odpall:close()
	end

	-- 设置值
	local mode_info={}
	mode_info["mode"]=mode
	mode_info["modes"]=modes

	-- 写入Web界面
	luci.http.prepare_content("application/json")
	luci.http.write_json(mode_info)
end

--[[
@Description 设置拨号模式
]]
function setMode()
    local at_port = http.formvalue("port")
	local mode_config = http.formvalue("mode_config")

	--获取制造商
	local manufacturer
	uci:foreach("modem", "modem-device", function (modem_device)
		--设置模组AT串口
		if at_port == modem_device["at_port"] then
			--获取制造商
			manufacturer=modem_device["manufacturer"]
		end
	end)

	--设置模组拨号模式
	local odpall = io.popen("cd "..script_path.." && source "..script_path..manufacturer..".sh && set_mode "..at_port.." "..mode_config)
	odpall:close()

	--获取设置好后的模组拨号模式
	local mode
	if at_port and manufacturer and manufacturer~="unknown" then
		local odpall = io.popen("cd "..script_path.." && source "..script_path..manufacturer..".sh && get_mode "..at_port)
		mode = odpall:read("*a")
		mode=string.gsub(mode, "\n", "")
		odpall:close()
	end

	-- 写入Web界面
	luci.http.prepare_content("application/json")
	luci.http.write_json(mode)
end