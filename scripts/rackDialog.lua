--[[
Copyright (c) MaddyPhi, 2021

Author: MaddyPhi (Madison)
Date: 07-20-2021
Version: 1.0.0.0
]]

RackDialog = {} --Rack Dialog UI
RackDataItem = {} --RackDataItem used in rackDataSource

RackDialog_mt = Class(RackDialog, YesNoDialog)
InitObjectClass(RackDialog, "RackDialog")

RackDataItem_mt = Class(RackDataItem)
InitObjectClass(RackDataItem, "RackDataItem")

-------------- RackDataItem Class ----------------------------
function RackDataItem:new(item, shelfId)
	local self = setmetatable({}, RackDataItem_mt)
	local itemObj = g_currentMission:getNodeObject(item)
	self.shelfId = shelfId
	self.itemId = item
	local hasFillUnits = false
	for _, spec in pairs(itemObj.specializationNames) do
		if spec == "fillUnit" then
			hasFillUnits = true
			break
		end
	end
	if hasFillUnits then
		local fillTypeTitle = g_fillTypeManager:getFillTypeByIndex(itemObj:getFillUnitFillType(1)).title
		if fillTypeTitle == "Unknown" then
			self.fillTypeName = "Empty " .. itemObj:getName()
			self.fillLevel = nil
		else
			self.fillTypeName = fillTypeTitle
			self.fillLevel = itemObj:getFillUnitFillLevel(1)
		end
	else
		self.fillTypeName = itemObj:getName()
		self.fillLevel = nil
	end
	return self
end
-------------- End RackDataItem Class ------------------------

--UI elements which have ids assigned
RackDialog.CONTROLS = {
	SHELF_ITEMS 			= "shelfItems",
	SHELF_ITEMS_TITLE		= "shelfItemsTitle",
	SHELF_ITEMS_SPACE 		= "shelfItemsSpaceText",
	SHELF_ITEM_TEMPLATE		= "shelfItemTemplate",
	OUTBOUND_ITEMS 			= "outboundItems",
	OUTBOUND_ITEMS_TITLE	= "outboundItemsTitle",
	OUTBOUND_ITEMS_SPACE	= "outboundItemsSpaceText",
	OUTBOUND_ITEM_TEMPLATE	= "outboundItemTemplate"
}

-------------- RackDIalog Class ------------------------------
function RackDialog:new(target, custom_mt)
	local self = YesNoDialog:new(target, custom_mt or RackDialog_mt)
	
	self:registerControls(RackDialog.CONTROLS)
	
	self.rackDataSource = GuiDataSource:new() --data source for shelf items
	self.outboundDataSource = GuiDataSource:new() --data source for outbound items
	
	self.rackSpace = 0 --total spaces available on the rack
	self.outputSpace = 0 --total free output spaces
	
	return self
end

function RackDialog:loadCallback(callback, target)
	self.target = target
	self.callback = callback
end

--Sets the initial items on the rack provided
function RackDialog:loadShelfItems(shelves)
	local data = {}
	self.rackSpace = 0 --reset shelf spaces, to be sure
	
	for _, shelf in ipairs(shelves) do
		self.rackSpace = self.rackSpace + 1 --add one shelf space
		if shelf:isOccupied() then --add item to data source if shelf contains an item
			table.insert(data, RackDataItem:new(shelf.itemId, shelf.triggerId))
		end
	end
	self.rackDataSource:setData(data)
end

--Sets the free spaces for the outbound area
function RackDialog:loadOutputAreaItems(outputSpaces)
	local data = {} --create the empty dataset for outbound data
	self.outputSpace = outputSpaces --set free spaces
	self.outboundDataSource:setData(data)
end

--Sets the miscellaneous text labels on the dialog
function RackDialog:setCustomText()
	self.shelfItemsTitle:setText(g_i18n:getText("menu_shelf_contents"))
	self.outboundItemsTitle:setText(g_i18n:getText("menu_outbound_contents"))
end

function RackDialog:onGuiSetupFinished()
	RackDialog:superClass().onGuiSetupFinished(self)

	--set the data sources and their callbacks
	self.shelfItems:setDataSource(self.rackDataSource)
	self.shelfItems:setAssignItemDataFunction(function (...) self:assignShelfData(...) end)
	self.rackDataSource:addChangeListener(self, self.onShelfDataSourceChanged)
	
	self.outboundItems:setDataSource(self.outboundDataSource)
	self.outboundItems:setAssignItemDataFunction(function (...) self:assignShelfData(...) end)
	self.outboundDataSource:addChangeListener(self, self.onOutboudDataSourceChanged)
	
	self:setCustomText()
end

--Sets the UI Shelf item text
function RackDialog:assignShelfData(listItem, shelfData)
	local nameText = listItem:getDescendantByName("name")
	nameText:setText(shelfData.fillTypeName)
	
	local levelText = listItem:getDescendantByName("level")
	if shelfData.fillLevel then
		levelText:setText(g_i18n:formatVolume(shelfData.fillLevel, 0))
	else
		levelText:setText("~")
	end
end

--Sets the IU free spaces values
function RackDialog:setCountsText(textElement, itemCount, itemSpace)
	textElement:setText(string.format("%d/%d", itemCount, itemSpace))
end	

--Updates the UI free space values
function RackDialog:updateCounts()
	self:setCountsText(self.outboundItemsSpaceText, self.outboundDataSource:getCount(), self.outputSpace)
	self:setCountsText(self.shelfItemsSpaceText, self.rackDataSource:getCount(), self.rackSpace)
end

--Updates the UI list of the related data source
function RackDialog:onDataSourceChanged(dataSource, dataList)
	local selectedIndex = dataList:getSelectedDataIndex()
	dataList:updateAlternatingBackground()
	dataList:updateItemPositions()
	dataList:setSelectedIndex(selectedIndex, true)
	self:updateCounts()
end

--Callback for rackDataSource change
function RackDialog:onShelfDataSourceChanged()
	self:onDataSourceChanged(self.rackDataSource, self.shelfItems)
end

--Callback for outboundDataSource change
function RackDialog:onOutboudDataSourceChanged()
	self:onDataSourceChanged(self.outboundDataSource, self.outboundItems)
end

--Moves item between from and to list at itemIndex in from dataSource
function RackDialog:moveItem(from, to, itemIndex)
	if from:getCount() > 0 then
		local fromData = from.data
		local toData = to.data
		local item = table.remove(fromData, itemIndex)
		table.insert(toData, item)
		--reset the dataSources to trigger onDataSourceChanged callback
		from:setData(fromData)
		to:setData(toData)
	end
end

--Callback for button press to move from outbound to rack
function RackDialog:onRackInClick()
	if self.rackDataSource:getCount() >= self.rackSpace then
		printDebug("Rack is full")
	else
		self:moveItem(self.outboundDataSource, self.rackDataSource, self.outboundItems:getSelectedDataIndex())
	end 
end

--Callback for button press to move from rack to outbound
function RackDialog:onRackOutClick()
	if self.outboundDataSource:getCount() >= self.outputSpace then
		printDebug("Output area is full")
	else
		self:moveItem(self.rackDataSource, self.outboundDataSource, self.shelfItems:getSelectedDataIndex())
	end
end

--Callback for dialog ok press
function RackDialog:onClickOk()
	if self.callback == nil then
		return true
	end
	
	if self.target ~= nil then
		self.callback(self.target, self.outboundDataSource.data)
	else
		printError("Target s missing.")
	end
	
	self:close()
end

--Callback for dialog cancel press
function RackDialog:onClickBack()
	self:close()
end
-------------- End RackDIalog Class --------------------------