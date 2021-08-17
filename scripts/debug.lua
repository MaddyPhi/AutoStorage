--[[
Copyright (c) MaddyPhi, 2021

Author: MaddyPhi (Madison)
Date: 07-16-2021
Version: 1.0.0.0
]]

local LOG_LEVEL_DEBUG 	= 4
local LOG_LEVEL_INFO 	= 3
local LOG_LEVEL_WARN	= 2
local LOG_LEVEL_ERROR	= 1
local LOG_LEVEL_OFF		= 0
local LOG_LEVEL = LOG_LEVEL_ERROR
local PACKAGE_NAME = "Autowarehouse"

local function printMessage(logLevel, logLevelStr, message, ...)
	if LOG_LEVEL >= logLevel then
		local messageStr = string.format(message, ...)
		print(string.format("%s: [%s] %s", logLevelStr, PACKAGE_NAME, messageStr))
	end
end

function printDebug(message, ...)
	printMessage(LOG_LEVEL_DEBUG, "debug", message, ...)
end

function printInfo(message, ...)
	printMessage(LOG_LEVEL_INFO, "info", message, ...)
end

function printWarning(message, ...)
	printMessage(LOG_LEVEL_WARN, "warn", message, ...)
end

function printError(message, ...)
	printMessage(LOG_LEVEL_ERROR, "error", message, ...)
end

function setLogLevel(level)
	if 		level == "debug" 	then LOG_LEVEL = LOG_LEVEL_DEBUG
	elseif 	level == "info" 	then LOG_LEVEL = LOG_LEVEL_INFO
	elseif 	level == "warn"		then LOG_LEVEL = LOG_LEVEL_WARN
	elseif	level == "error"	then LOG_LEVEL = LOG_LEVEL_ERROR
	elseif	level == "off"		then LOG_LEVEL = LOG_LEVEL_OFF
	else 	LOG_LEVEL =	LOG_LEVEL_ERROR
	end
end