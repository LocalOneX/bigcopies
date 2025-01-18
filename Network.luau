--@LocalOneX

--- Reference
local jobId = game.JobId; if #jobId == 0 then jobId = "00000000-0000-0000-0000-000000000000" end
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProfileFunction = require(ReplicatedStorage.Library.Functions.ProfileFunction)
local remotes = ReplicatedStorage:WaitForChild("Network", 99999999)
local Players = game:GetService("Players")
local SHA1 = require(script.SHA1) 

--- Variables
local hashedEvents: {[number]: {[string]: string}} = { {}, {} }
local packetRemotePrefixes: {string} = { "E", "F", "U" }
local hashing = false

------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

local profile = {}
type raw_schema = {
	_tag: string,
	_handle: any
}

type proto_schema = {
	Connect: (self: schema, tag: string) -> any,
	ConnectParallel: (self: schema, tag: string) -> any,
	Once: (self: schema, tag: string) -> any,
	Wait: (self: schema) -> any,
}

export type schema = typeof(setmetatable({} :: raw_schema, {__index = {}:: proto_schema}))

function profile.Connect(self: schema, tag: string)
	return self._handle:Connect(ProfileFunction.Add(self._tag, tag))
end

function profile.ConnectParallel(self: schema, tag: string)
	return self._handle:ConnectParallel(ProfileFunction.Add(self._tag, tag))
end

function profile.Once(self: schema, tag: string)
	return self._handle:Once(ProfileFunction.Add(self._tag, tag))
end

function profile.Wait(self: schema)
	return self._handle:Wait()
end

local function _profileEvent(tag: string, handle: any)
	local rawSelf: raw_schema = {
		_tag = tag,
		_handle = handle
	}

	local self: schema = setmetatable(rawSelf, {__index = profile})

	return self
end

local function _getName(packetType: number, remoteName: string)
	--- Asserts
	assert(typeof(packetType) == "number")
	assert(typeof(remoteName) == "string")

	if not hashing then
		return remoteName
	end

	--- Variables
	local packet = hashedEvents[packetType]
	local name = packet[remoteName]

	if not name then
		--- Create the name 
		name = SHA1(`Network3/{game.GameId}/{game.PlaceId}/{game.PlaceVersion}/{jobId}/{packetType}/{remoteName}`):reverse():sub(5,36)

		packet[remoteName] = name
	end

	return name
end

--- Variables
local events: {[number]: any} = { {}, {}, {} }
local packetInstances: {string} = { 
	"RemoteEvent", --- Fired
	"RemoteFunction",  --- Invoked
	"UnreliableRemoteEvent" --- UnreliableFired
}

--- Get (or create) Remotes by PacketType and name
local function _remote(packetType: number, remoteName: string)
	--- Variables
	local packetEvents = events[packetType]
	local remote = packetEvents[remoteName]

	if not remote then
		--- create remote
		remote = Instance.new(packetInstances[packetType])
		remote.Name = remoteName
		remote.Parent = remotes
		packetEvents[remoteName] = remote
	end

	return remote
end  

--- Get (or create) RemtoeEvent / RemoteFunction
local function _remoteEvent(remoteName) return _remote(1, _getName(1, remoteName)) end 
local function _remoteFunction(remoteName) return _remote(2, _getName(2, remoteName)) end 
local function _unreliableRemoteEvent(remoteName) return _remote(3, _getName(3, remoteName)) end 

local Network = {} 

--- Fire
Network.Fire = function(remoteName: string, player: Player, ...) 
	assert(typeof(player) == "Instance" and player:IsA("Player") or false)
	if not player:GetAttribute("__LOADED") then   
		return 
	end

	local remote = _remoteEvent(remoteName)
	pcall(function(...)  remote:FireClient(player, ...)  end, ...) 
end

--- Fire (everyone)
Network.FireAll = function(remoteName: string, ...)  
	local players = Players:GetPlayers()
	local playersToSend = {}
	for _, player in ipairs(players) do
		if player:GetAttribute("__LOADED") then
			table.insert(playersToSend, player)
		end
	end

	local remote = _remoteEvent(remoteName)

	if #playersToSend >= #players then
		--- Can use optimized FireAllClients
		pcall(function(...) remote:FireAllClients(...) end, ...) 
	else
		--- Some players are in intro, so we gotta fire each manually
		for _, player in ipairs(playersToSend) do pcall(function(...)  remote:FireClient(player, ...) end, ...) end  
	end  
end

--- On Fire
Network.Fired = function(remoteName: string)  
	local remote = _remoteEvent(remoteName)

	return remote.OnServerEvent
end

--- Unreliable Fire
Network.UnreliableFire = function(remoteName: string, player: Player, ...)  
	assert(typeof(player) == "Instance" and player:IsA("Player") or false)
	if not player:GetAttribute("__LOADED") then 
		return 
	end

	local remote = _unreliableRemoteEvent(remoteName)
	pcall(function(...) remote:FireClient(player, ...) end, ...)
end

--- On Unreliable Fire
Network.UnreliableFired = function(remoteName: string)  
	local remote = _unreliableRemoteEvent(remoteName)

	return remote.OnServerEvent
end

--- Unreliable Fire (everyone)
Network.UnreliableFireAll = function(remoteName: string, ...)  
	local players = Players:GetPlayers()
	local playersToSend = {}
	for _, player in ipairs(players) do
		if player:GetAttribute("__LOADED") then
			table.insert(playersToSend, player)
		end
	end

	local remote = _unreliableRemoteEvent(remoteName)

	if #playersToSend >= #players then
		--- Can use optimized FireAllClients
		pcall(function(...) remote:FireAllClients(...) end, ...) 
	else
		--- Some players are in intro, so we gotta fire each manually
		for _, player in ipairs(playersToSend) do pcall(function(...)  remote:FireClient(player, ...) end, ...) end  
	end  
end


--- Invoke
Network.Invoke = function(remoteName: string, player: Player, ...)   
	assert(typeof(player) == "Instance" and player:IsA("Player") or false)
	if not player:GetAttribute("__LOADED") then 
		return 
	end

	--- Get/create remote
	local remote = _remoteFunction(remoteName)

	return remote:InvokeClient(player, ...)
end


--- On Invoke
Network.Invoked = function(remoteName: string)  
	local remote = _remoteFunction(remoteName) 

	local metatable = {}
	metatable.__newindex = function(self, index: string, value: string)  
		if index == "OnInvoke" then
			index = "OnServerInvoke"

		elseif index == "OnServerInvoke" then
			error(`{tostring(index)} is not a valid member of BindableFunction "BindableFunction"`) 
		end

		remote[index] = value
	end

	metatable.__index = function(self, index: string) 
		if index == "OnInvoke" then
			index = "OnServerInvoke"

		elseif index == "OnServerInvoke" then
			error(`{tostring(index)} is not a valid member of BindableFunction "BindableFunction"`) 
		end

		return remote[index]
	end

	return setmetatable({}, metatable)
end

return Network
