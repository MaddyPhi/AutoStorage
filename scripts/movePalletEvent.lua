--[[
Copyright (c) MaddyPhi, 2021

Author: MaddyPhi (Madison)
Date: 09-13-2021
Version: 1.0.2.0
]]

MovePalletEvent = {}
local MovePalletEvent_mt = Class(MovePalletEvent, Event)

InitEventClass(MovePalletEvent, "MovePalletEvent")

function MovePalletEvent:emptyNew()
	local self = Event:new(MovePalletEvent_mt)
	return self
end

function MovePalletEvent:new(storage, space, pallet)
	local self = MovePalletEvent:emptyNew()
	
	self.storage = storage --the autowarehouse instance
	self.space = space.spaceId --the id of space trigger
	self.pallet = pallet --the pallet being moved
	
	return self
end

function MovePalletEvent:writeStream(streamId, connection)
	--send information of the moving pallet.
	NetworkUtil.writeNodeObject(streamId, self.storage)
	NetworkUtil.writeNodeObjectId(streamId, self.space)
	NetworkUtil.writeNodeObject(streamId, self.pallet)
end

function MovePalletEvent:readStream(streamId, connection)
	--read information of the moving pallet
	self.storage = NetworkUtil.readNodeObject(streamId)
	self.space = NetworkUtil.readNodeObjectId(streamId)
	self.pallet = NetworkUtil.readNodeObject(streamId)

    self:run(connection)
end

function MovePalletEvent:run(connection)
	if not connection:getIsServer() then
		g_server:broadcastEvent(self, false, connection, self.storage)
	end
	if self.storage then
		--look-up space
		local space = self.storage:getSpaceFromId(self.space)
		if space then
			--move the pallet
			self.storage:movePallet(space, self.pallet, true)
		end
	end
end

function MovePalletEvent.sendEvent(storage, space, pallet, noEventSend)
	if not noEventSend then
		local event = MovePalletEvent:new(storage, space, pallet)
		if g_server then
			g_server:broadcastEvent(event, nil, nil, storage)
		else
			g_client:getServerConnection():sendEvent(event)
		end
	end
end