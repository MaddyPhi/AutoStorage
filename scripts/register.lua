--[[
Copyright (c) MaddyPhi, 2021

Author: MaddyPhi (Madison)
Date: 07-16-2021
Version: 1.0.0.0
]]
local VERSION = {
	MAJOR 		= 1,
	MINOR 		= 0,
	BUILD 		= 0,
	REVISION 	= 0
}

local function versionToString(settings)
	return string.format("%d.%d.%d.%d", settings.versionMajor, settings.versionMinor, settings.versionBuild, settings.versionRevision)
end

local function parseVersionString(versionStr)
	local major, minor, build, revision = string.match(versionStr, "^([%d]+).([%d]+).([%d]+).([%d]+)$")
	return tonumber(major), tonumber(minor), tonumber(build), tonumber(revision)
end

local function compareVersion(settings)
	local checkLevel = function(settingLevel, currentLevel)
		if not settingLevel or settingLevel < currentLevel then
			return -1 -- Version is out of date
		elseif settingLevel > currentLevel then
			return 1 -- Verision is newer than current version
		else 
			return 0
		end
	end
	
	local version = {
		{settings.versionMajor, VERSION.MAJOR},
		{settings.versionMinor, VERSION.MINOR},
		{settings.versionBuild, VERSION.BUILD},
		{settings.versionRevision, VERSION.REVISION}
	}
		
	for _, level in ipairs(version) do
		local state = checkLevel(level[1], level[2])
		if state ~= 0 then
			return state
		end
	end
	return 0 -- Version is current
end

local function createSettings(settingsXMLPath, settings)
	local xmlFile = createXMLFile("autowarehouseSettings", settingsXMLPath, "autowarehouseSettings")
	if xmlFile ~= nil then
		local versionStr = versionToString(settings)
		setXMLString(xmlFile, "autowarehouseSettings#version", versionStr)
		setXMLString(xmlFile, "autowarehouseSettings.logLevel", settings.debugMode)
		saveXMLFile(xmlFile)
		delete(xmlFile)
	end
end

local function loadSettings()
	local settingsPath = getUserProfileAppPath() .. "modsSettings/"
	local settingsXMLPath = settingsPath .. "autowarehouse.xml"
	local settings = { -- default settings
		debugMode 		= "error",
		versionMajor 	= VERSION.MAJOR,
		versionMinor 	= VERSION.MINOR,
		versionBuild 	= VERSION.BUILD,
		versionRevision = VERSION.REVISION
	}
	
	createFolder(settingsPath)
	
	--if XML does not exist create it using the default settings provided
	if not fileExists(settingsXMLPath) then
		createSettings(settingsXMLPath, settings)
	end
	
	--read XML settings
	local xmlFile = loadXMLFile("autowarehouseSettings", settingsXMLPath)
	if xmlFile ~= nil then
		major, minor, build, revision = parseVersionString(getXMLString(xmlFile, "autowarehouseSettings#version"))
		settings.versionMajor = major
		settings.versionMinor = minor
		settings.versionBuild = build
		settings.versionRevision = revision
		
		local debugMode = getXMLString(xmlFile, "autowarehouseSettings.logLevel")
		if debugMode ~= nil then
			settings.debugMode = debugMode
		end
		
		delete(xmlFile)
	end
	
	--check if version is current
	if compareVersion(settings) ~= 0 then
		createSettings(settingsXMLPath, settings)
	end
	--set logging level
	setLogLevel(settings.debugMode)
end

local function checkFileExists(path)
	if fileExists(path) then
		return true
	else
		print(string.format("Error: [Autowarehouse] - missing '%s'.", path))
		return false
	end
end

local function init()
	--Load debug utility
	local debugLuaPath = g_currentModDirectory .. "scripts/debug.lua"
	if checkFileExists(debugLuaPath) then
		source(debugLuaPath)
	end
	--Load settings
	loadSettings()
	
	--Load GUI
	local guiLuaPath = g_currentModDirectory .. "scripts/rackDialog.lua"
	local guiXMLPath = g_currentModDirectory .. "gui/rackDialog.xml"
	local guiProfilesPath = g_currentModDirectory .. "gui/guiProfiles.xml"
	if checkFileExists(guiProfilesPath) then
		g_gui:loadProfiles(guiProfilesPath)
	end
	if checkFileExists(guiLuaPath) and checkFileExists(guiXMLPath) then
		source(guiLuaPath)
		local rackDialog = RackDialog:new(nil, nil)
		g_gui:loadGui(guiXMLPath, "RackDialog", rackDialog)
	end
	
	--Load Placeable Warehouse
    local placeablePath = g_currentModDirectory .. "scripts/autowarehouse.lua"
    if checkFileExists(placeablePath) then
        g_placeableTypeManager:addPlaceableType("warehousePlaceable", "Warehouse", placeablePath)
    end
end

-- Init mod source snd configuration
init()