--[[
Copyright (c) MaddyPhi, 2021

Author: MaddyPhi (Madison)
Date: 07-16-2021
Version: 1.0.2.0
]]

Warehouse = {} -- Placeable Object
PickupSpace = {} -- Spaces where pallets move to from shelf spaces
Rack = {} -- Unit containing a collection of shelf spaces
Shelf = {} -- Shelf spaces for storing pallets
Unload = {} -- Unload Triggers

Warehouse_mt = Class(Warehouse, Placeable)
InitObjectClass(Warehouse, "Warehouse")

PickupSpace_mt = Class(PickupSpace, Object)
InitObjectClass(PickupSpace, "PickupSpace")

Rack_mt = Class(Rack, Object)
InitObjectClass(Rack, "Rack")

Shelf_mt = Class(Shelf, Object)
InitObjectClass(Shelf, "Shelf")

Unload_mt = Class(Unload, Object)
InitObjectClass(Unload, "Unload")

-- Constants to differential the activate options
ACTIVATE = {
	NO_ACTION = 0,
	RACK_ACTION = 1,
	UNLOAD_ACTION = 2
}

-------------- PickupSpace Class ---------------
function PickupSpace:new(isServer, isClient, triggerId, spaceId)
	local self = Object:new(isServer, isClient, PickupSpace_mt)
	self.spaceId = spaceId
	self.triggerId = triggerId
	self.items = {}
	self.occupied = false
	return self
end

--Checks if there are any items registered to this pickup space
function PickupSpace:isOccupied()
	for _ in pairs(self.items) do
		return true
	end
	return false
end

--Registers an item entering the pickup space
function PickupSpace:addItem(itemId)
	if not self.items[itemId] then 
		self.items[itemId] = true
		printInfo("adding item to pickupArea")
	end
end

--Unregisters item leaving the pickup space
function PickupSpace:removeItem(itemId)
	if self.items[itemId] then
		self.items[itemId] = nil
		printInfo("removing item from pickupArea")
	end
end
-------------- End PickupSpace Class ----------

-------------- Rack Class ---------------------
function Rack:new(isServer, isClient, triggerId, name)
	local self = Object:new(isServer, isClient, Rack_mt)
	self.triggerId = triggerId
	self.name = name -- name of the rack as found in l10n
	self.shelves = {} -- collection of shelves for this rack
	return self
end

-- adds a shelf object to this rack and sets shelf.rack
function Rack:addShelf(shelf)
	if shelf.rack ~= nil then
		printError("attempt to assign a shelf to a rack that has already been assigned")
	else
		table.insert(self.shelves, shelf)
		shelf.rack = self
	end
end

function Rack:isEmpty()
	for _, shelf in pairs(self.shelves) do
		if shelf:isOccupied() then
			return false
		end
	end
	return true
end
		
-------------- End Rack Class -----------------

-------------- Unload Class -------------------
function Unload:new(isServer, isClient, unloadTrigger, callTrigger)
	local self = Object:new(isServer, isClient, Unload_mt)
	self.unloadTrigger = unloadTrigger
	self.callTrigger = callTrigger
	self.items = {}
	return self
end

function Unload:pop()
	for itemId, _ in pairs(self.items) do
		self:remove(itemId)
		return itemId
	end
end

function Unload:remove(itemId)
	self.items[itemId] = nil
end

function Unload:push(itemId)
	self.items[itemId] = true
end

function Unload:count()
	local count = 0
	for _ in pairs(self.items) do
		count = count + 1
	end
	return count
end

function Unload:isEmpty()
	for _ in pairs(self.items) do
		return false
	end
	return true
end

-------------- End Unload Class ---------------

-------------- Shelf Class --------------------
function Shelf:new(isServer, isClient, triggerId, spaceId, rack)
	local self = Object:new(isServer, isClient, Shelf_mt)
	self.spaceId = spaceId
	self.triggerId = triggerId
	self.itemId = nil
	rack:addShelf(self)
	return self
end

-- tests if the shelf is occupied with a pallet
function Shelf:isOccupied()
	return self.itemId ~= nil
end

-- adds a pallet to the shelf, returns true if the pallet was added to the shelf; otherwise false
function Shelf:addItem(itemId)
	if itemId == nil then
		printDebug("no itemId provided")
		return false
	end
	
	local isSet = false
	if not self:isOccupied() then
		self.itemId = itemId
		isSet = true
		printInfo("setting item on shelf")
	elseif self.itemId ~= itemId then
		printWarning("attempt to set already occupied shelf")
		isSet = false
	end
	return isSet
end

-- removes the pallet assigned to the shelf iff the pallet id requesting is the same as the pallet on the shelf
-- return true if shelf has been emptied; otherwise false
function Shelf:removeItem(itemId)
	if not self:isOccupied() then
		printWarning("attempt to empty an already empty shelf")
	elseif itemId == self.itemId then
		self.itemId = nil
	else
		printInfo("attempt to remove shelf with invalid itemId")
	end
	return not self:isOccupied()
end	
-------------- End Shelf Class ----------------

-------------- Warehouse Class ----------------
function Warehouse:new(isServer, isClient, customMt)
    local self = Placeable:new(isServer, isClient, customMt or Warehouse_mt)
    registerObjectClassName(self, "Warehouse")
    
    self.unloadTriggers = {} --list of all triggers for unloading zones
	self.pickupAreaTriggers = {} -- list of all pickup space triggers for unloading shelves
	self.shelfTriggers = {} -- table of all shelf triggers
	self.rackTriggers = {} -- table of all rack triggers 
	
	--[[ Maintaining a list of all shelves in addition to the shelfTriggers tabls
		 to iterate, in order found in XML, to find first open shelf]]
	self.shelves = {}
	self.spaces = {}
	self.activateText = "" --text for activating the rack trigger
	self.currentRack = nil --current rack where the player is standing
	self.currentUnloadTrigger = nil --current unload trigger to collect from if activated
	
	self.moveUpdates = {} --list of new pallet moves
	
	self.action = ACTIVATE.NO_ACTION
	
    return self
end

function Warehouse:load(xmlFilename, x, y, z, rx, ry, rz, initRandom)
    if not Warehouse:superClass().load(self, xmlFilename, x, y, z, rx, ry, rz, initRandom) then
        return false
    end
    local isValid = true

    local xmlFile = loadXMLFile("TempXML", xmlFilename)
	local nodeId = self.nodeId
	
	--helper lambda to iterate over the all the XML elements at the provided element.
	local xmlIter = function(element, attribute)
		local i = 0 --iterated by the lambda returned
		--returns the ith XML element's path and the value of element(i)#attribute
		return function()
			-- form the zml path for the ith element
			local elementI = string.format("%s(%d)", element, i)
            i = i + 1
			if hasXMLProperty(xmlFile, elementI) then
				--get the object path and lookup object id
				local attribVal = getXMLString(xmlFile, string.format("%s#%s", elementI, attribute))
				local objectId = I3DUtil.indexToObject(nodeId, attribVal)
				return elementI, objectId
			end
		end
	end

    --Load the unloading triggers
	for unloadElement, unloadTrigger in xmlIter("placeable.warehouse.unloadTriggers.unloadTrigger", "unloadNode") do
		local callTrigger = I3DUtil.indexToObject(nodeId, getXMLString(xmlFile, unloadElement .. "#callNode"))
		self.unloadTriggers[unloadTrigger] = Unload:new(self.isServer, self.isClient, unloadTrigger, callTrigger)
	end
	
	--Load the pickup space triggers
	for _, trigger in xmlIter("placeable.warehouse.pickupArea.space", "node") do
		local pickupSpace = PickupSpace:new(self.isServer, self.isClient, trigger, #self.spaces + 1)
		table.insert(self.pickupAreaTriggers, pickupSpace)
		table.insert(self.spaces, pickupSpace)
	end
	
	--Load the rackSpace and shelf triggers
	for rackElement, rack in xmlIter("placeable.warehouse.storage.rackSpace", "triggerNode") do
		local rackName = g_i18n:getText(getXMLString(xmlFile, rackElement .. "#name"))
		self.rackTriggers[rack] = Rack:new(self.isServer, self.isClient, rack, rackName)
		for _, shelf in xmlIter(rackElement .. ".shelf", "triggerNode") do
			self.shelfTriggers[shelf] = Shelf:new(self.isServer, self.isClient, shelf, #self.spaces + 1, self.rackTriggers[rack])
			table.insert(self.shelves, self.shelfTriggers[shelf])
			table.insert(self.spaces, self.shelfTriggers[shelf])
		end
	end
	
	delete(xmlFile)
    return isValid
end

function Warehouse:finalizePlacement()
    Warehouse:superClass().finalizePlacement(self)
    for _, trigger in pairs(self.unloadTriggers) do
        addTrigger(trigger.unloadTrigger, "unloadTriggerCallback", self)
		addTrigger(trigger.callTrigger, "callTriggerCallback", self)
        printInfo("added unload trigger")
    end
	
	for _, trigger in pairs(self.pickupAreaTriggers) do
		addTrigger(trigger.triggerId, "pickAreaTriggerCallback", self)
		printInfo("added pick area trigger")
	end
	
	for trigger, _ in pairs(self.rackTriggers) do
		addTrigger(trigger, "rackTriggerCallback", self)
		printInfo("added rack trigger")
	end
	
	for trigger, _ in pairs(self.shelfTriggers) do
		addTrigger(trigger, "shelfTriggerCallback", self)
        printInfo("added shelf trigger")
	end
end

function Warehouse:delete()
    if self.unloadTriggers ~= nil then
        for _, trigger in pairs(self.unloadTriggers) do
			removeTrigger(trigger.unloadTrigger)
			removeTrigger(trigger.callTrigger)
        end
        self.unloadTriggers = nil
    end
	
	if self.pickupAreaTriggers ~= nil then
		for _, trigger in pairs(self.pickupAreaTriggers) do
			removeTrigger(trigger.triggerId)
		end
		self.pickupAreaTriggers = nil
	end
	
	if self.rackTriggers ~= nil then
		for trigger, _ in pairs(self.rackTriggers) do
			removeTrigger(trigger)
		end
		self.rackTriggers = nil
	end
	
	if self.shelfTriggers ~= nil then
		for trigger, _ in pairs(self.shelfTriggers) do
			removeTrigger(trigger)
		end
		self.shelfTriggers = nil
	end
	
    unregisterObjectClassName(self)
    Warehouse:superClass().delete(self)
end

function Warehouse:onActivateObject()
	if self.action == ACTIVATE.RACK_ACTION then
		-- open a RackDialog to choose unloading shelf items
		local dialog = g_gui:showDialog("RackDialog")
		if dialog ~= nil then
			dialog.target:setTitle(self.rackTriggers[self.currentRack].name .. " " .. g_i18n:getText("menu_contents"))
			dialog.target:loadCallback(self.rackUnloadCallback, self)
			dialog.target:loadShelfItems(self.rackTriggers[self.currentRack].shelves)
			dialog.target:loadOutputAreaItems(self:countPickupSpaces())
		end
	elseif self.action == ACTIVATE.UNLOAD_ACTION then
		-- collect all the pallets in the unloading area and move them to selves
		local unloadTrigger = self.currentUnloadTrigger
		while not unloadTrigger:isEmpty() do
			local itemId = unloadTrigger:pop()
			local object = g_currentMission:getNodeObject(itemId)
			local shelf = self:nextShelf()
			if shelf ~= nil then
				self:movePallet(shelf, object, false)
			end
		end
	end
	self.action = ACTIVATE.NO_ACTION
	self.activateText = ""
	g_currentMission:removeActivatableObject(self)
end

function Warehouse:drawActivate()
	return
end

function Warehouse:getIsActivatable()
	return g_currentMission.controlPlayer and (self:getOwnerFarmId() == 0 or g_currentMission:getFarmId() == self:getOwnerFarmId())
end

function Warehouse:shouldRemoveActivatable()
	return false
end

-- Callback on ok click of the RackDialog. Moves pallets requested to the available pickup spaces
function Warehouse:rackUnloadCallback(outboundItems)
	for _, item in ipairs(outboundItems) do
		--find an open pickup space to put this item
		local pickupSpace = self:nextPickupSpace()
		if pickupSpace ~= nil then
			--verify and empty that the shelf provided contains the item being moved
			local object = g_currentMission:getNodeObject(item.itemId)
			self:movePallet(pickupSpace, object, false)
		else
			printError("expected free space for pallets but no space found")
		end
	end
end

--Callback for when player enters rack trigger. sets an activation option and sets the currentRack variable
function Warehouse:rackTriggerCallback(triggerId, otherId, onEnter, onLeave, onStay, otherShapeId)
	if g_currentMission.player ~= nil and otherId == g_currentMission.player.rootNode then
		--check if the player's farm id matches tha owner of this warehouse
		if g_currentMission.accessHandler:canFarmAccessOtherId(g_currentMission:getFarmId(), self:getOwnerFarmId()) then
			if onEnter then -- set the currentRack at this trigger and the activation option
				if self.rackTriggers[triggerId]:isEmpty() then -- if the shelf is empty no point in showing the activation option
					return
				end
				self.action = ACTIVATE.RACK_ACTION
				self.currentRack = triggerId
				self.activateText = string.format("%s %s %s",g_i18n:getText("menu_open"), self.rackTriggers[triggerId].name, g_i18n:getText("menu_dialog"))
				g_currentMission:addActivatableObject(self)
			elseif onLeave then -- player has left the rack, reset currentRack and activation option
				self.action = ACTIVATE.NO_ACTION
				self.currentRack = nil
				self.activateText = ""
				g_currentMission:removeActivatableObject(self)
			end
			self:raiseActive()
		end
	end
end

--Callback for when a pallet enters a pickup trigger area. Marks the pickup space (not) occupied to
--prevent a pallet from being moved to this space
function Warehouse:pickAreaTriggerCallback(triggerId, otherId, onEnter, onLeave, onStay, otherShapeId)
	local object = g_currentMission:getNodeObject(otherId)
	if object == nil or object.mountObject ~= nil then 
		return
	end
	
	-- if is pallet then find a free shelf
	if self:isPallet(object) then
		-- find the pickSpace object
		local trigger = nil
		for _, pickupTrigger in pairs(self.pickupAreaTriggers) do
			if pickupTrigger.triggerId == triggerId then
				trigger = pickupTrigger
				break
			end
		end
		-- set the pickSpace occupied status
		if trigger ~= nil then
			if onEnter then
				trigger:addItem(otherId)
                object.space = trigger
			elseif onLeave then
				trigger:removeItem(otherId)
				object.space = nil
			end
		end
	end
end

--Callback for when a shelf trigger is activated bu a pallet entering or leaving the shelf space
--sets/removes the shelf item
function Warehouse:shelfTriggerCallback(triggerId, otherId, onEnter, onLeave, onStay, otherShapeId)
    local object = g_currentMission:getNodeObject(otherId)
	local shelf = self.shelfTriggers[triggerId]
	if onEnter then
		if shelf:addItem(otherId) then
            object.space = shelf
        end
	elseif onLeave then
		shelf:removeItem(otherId)
        object.space = nil
	end
end

--Callback for when a pallet enters the unload trigger. On confirmation that the object is a pallet
--it is moved to the first available shelf
function Warehouse:unloadTriggerCallback(triggerId, otherId, onEnter, onLeave, onStay, otherShapeId)
	local object = g_currentMission:getNodeObject(otherId)
	if object == nil or object.mountObject ~= nil then 
		return
	end
	
	if onEnter then
		printDebug("object detected in the unload zone %s, type=%s", object.rootNode, object.typeName)
	end
	
	-- if is pallet then add/remove it from the pallets in the trigger
	if self:isPallet(object) then
		if onEnter then
			self.unloadTriggers[triggerId]:push(otherId)
		elseif onLeave then
			self.unloadTriggers[triggerId]:remove(otherId)
		end
	end
end

--Callback when user enter the trigger for the unload call button
function Warehouse:callTriggerCallback(triggerId, otherId, onEnter, onLeave, onStay, otherShapeId)
	if g_currentMission.player ~= nil and otherId == g_currentMission.player.rootNode then
		--check if the player's farm id matches tha owner of this warehouse
		if g_currentMission.accessHandler:canFarmAccessOtherId(g_currentMission:getFarmId(), self:getOwnerFarmId()) then
			if onEnter then -- set the currentUnloadTrigger at this trigger and the activation option
				for _, unloadTrigger in pairs(self.unloadTriggers) do
					if unloadTrigger.callTrigger == triggerId then
						if not unloadTrigger:isEmpty() then
							self.action = ACTIVATE.UNLOAD_ACTION
							self.currentUnloadTrigger = unloadTrigger
							self.activateText = string.format("%s (%d %s)", g_i18n:getText("menu_unload"), unloadTrigger:count(), g_i18n:getText("menu_pallet"))
							g_currentMission:addActivatableObject(self)
							break
						end
					end
				end
			elseif onLeave then -- player has left the unload call trigger
				self.action = ACTIVATE.NO_ACTION
				self.currentUnloadTrigger = nil
				self.activateText = ""
				g_currentMission:removeActivatableObject(self)
			end
			self:raiseActive()
		end
	end
end

--finds the next available shelf from all shelves
function Warehouse:nextShelf()
	-- search shelf list for an unoccupied shelf
	for _, shelf in ipairs(self.shelves) do
		if not shelf:isOccupied() then
			return shelf
		end
	end
	
	printInfo("No empty shelf found")
	return nil
end

--finds the next available pickup space from all pickup spaces
function Warehouse:nextPickupSpace()
	-- seach for the first free pickup space
	for _, pickupSpace in ipairs(self.pickupAreaTriggers) do
		if not pickupSpace:isOccupied() then
			return pickupSpace
		end
	end
	
	printWarning("No empty pickup space found")
	return nil
end

--returns the number of pickup spaces available
function Warehouse:countPickupSpaces()
	local count = 0
	for _, pickupSpace in ipairs(self.pickupAreaTriggers) do
		print("found a pickup space")
		if not pickupSpace:isOccupied() then
			count = count + 1
		end
	end
	return count
end

function Warehouse:getSpaceFromId(spaceId)
	--find the space that the pallet is moving to
	return self.spaces[spaceId]
end

--moves a pallet to the location of the spaceId trigger
function Warehouse:movePallet(space, object, noEventSend)
	MovePalletEvent.sendEvent(self, space, object, noEventSend)
	-- move the pallet to the space then unmount it so it can be moved manually.
	object:mount(self, space.triggerId, 0,0,0, 0,0,0)
	object:unmount()
	space:addItem(object.rootNode)
	--adding the space to the object for handling when object leaves space.
	object.space = space
end

function Warehouse:isPallet(object)
	if object:isa(Vehicle) then
		local palletKeys = {"pallet", "Pallet", "gcProductionItem", "gcProductionItemNone"}
		for _, palletKey in ipairs(palletKeys) do
			if string.find(object.typeName, palletKey) then
				return true
			end
		end
	end
end
-------------- End Warehouse Class ------------

Mountable.mount = Utils.appendedFunction(Mountable.mount,
function(object, ...)
	--when a something like an autoload trailer or move to pickup area is called,
	--the onLeave trigger callback does not occur. To solve the no-trigger-call problem, this function
	--detects the mount call and removes the item from the space
	if object.space then
		object.space:removeItem(object.rootNode)
		object.space = nil
	end
end)

FSBaseMission.removeVehicle = Utils.prependedFunction(FSBaseMission.removeVehicle,
function(currentMission, vehicle)
	--when emptying a pallet in a trigger space (pickup area or shelf) the pallet will disappear. 
	--the removal of the pallet in this way does not invoke a onLeave trigger callback
	if vehicle.space then
		vehicle.space:removeItem(vehicle.rootNode)
		vehicle.space = nil
	end
end)