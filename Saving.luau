--[[
    By: @LocalOneX  1/4/2025
    The original Saving module from BIG Games official files are buggy,
    for this game file, probably because of decompilers,
    so my solution was to make an entirely safe
    Saving module, think of this module as just SecureSaving.luau
    
    The most hacky but (somehow) secure way data is stored, recievied, and saved. Not very pretty, but it gets the job done.
	Most specific 'saving' issues are taken acount for - and have been tested to work in real scenerios. If data fails to save, recieve, etc.
	server and client will get warning and messages accordingly. Very efficient on datastore requests.
	
	Default stats are found under _L.Settings on Server.
	===========
		\\\ Get player's data
		Saving.Get(
			player,					<-- |REQ|	Player instance
		)
		
		\\\ Returns true if player is loaded (past intro)
		Saving.IsLoaded(
			player,					<-- |REQ|	Player instance
		)
		
		\\\ Save player's data to DataStore
		Saving.Save(
			player,					<-- |REQ|	Player instance
		)
		
		\\\ Load player's data from DataStore
		Saving.Retrieve(
			player,					<-- |REQ|	Player instance
		)
		
		\\\ Reset the player's data back to default stats
		Saving.Reset(
			player,					<-- |REQ|	Player instance
		)
		
		\\\ Clears player's data from local server manually
		Saving.Remove(
			player,					<-- |REQ|	Player instance
		)
		
		\\\ Initialize player's data. [For internal use only! Don't use this pls]
		Saving.Init(
			player,					<-- |REQ|	Player instance
		)
	===========
--]]

assert(game:GetService("RunService"):IsServer())
local Settings = require(game.ServerScriptService.Library.Settings)
local Network = require(game.ServerScriptService.Library.Network)
local Migration = require(game.ServerScriptService.Library.Migration)
local Functions = require(game.ReplicatedStorage.Library.Functions)
local Shared = require(game.ReplicatedStorage.Library.Shared)
local Signal = require(game.ReplicatedStorage.Library.Signal)
local Variables = require(game.ReplicatedStorage.Library.Variables)
local Event = require(game.ReplicatedStorage.Library.Modules.Event)
local PlaceFile = require(game.ReplicatedStorage.Library.Modules.PlaceFile)
local wcall = require(game.ReplicatedStorage.Library.Functions.wcall)
local Randoms = require(game.ReplicatedStorage.Library.Randoms)
local Asserts = require(game.ReplicatedStorage.Library.Asserts)

--- Reference
local DatastoreService = game:GetService("DataStoreService") 
local DatastoreOptions = Instance.new("DataStoreOptions")
DatastoreOptions:SetExperimentalFeatures({v2 = true})

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local isStudio = RunService:IsStudio()
local rng = Randoms.UniqueMT19937()

--- Events
local PlayerSaved = Event.new(function() end)
local PlayerAdded = Event.new(function() end)
local StatChanged = Event.new(function() end)
local PlayerSaveRemoved = Event.new(function() end)
local PlayerFullyRemoved = Event.new(function() end) 

--- Settings
local sessionLocks = false
local saveDuration = 120
local sessionLockBuffer = 120
local autoSaveBuffer = (60)*10
local StudioSaving = true
local Debug = false
local WaitLoaded = true -- If enabled, it will wait until player is loaded before PlayerAdded event is fired.
local SavePlayerID = Settings.SavePlayerID
local DefaultStats = Settings.DefaultStats
local ReplicateStatsBuffer = (Settings.ReplicateOtherStatsInstantly) and 0 or Settings.ReplicateOtherStatsBuffer or 0.33
local StatsNetworkingBlacklist = Settings.StatsNetworkingBlacklist
local StatsNetworkingUpdateBlacklist = Settings.StatsNetworkingUpdateBlacklist
local StatsNetworkingLocalOnly = Settings.StatsNetworkingLocalOnly
if not isStudio or SavePlayerID == 0 then
	SavePlayerID = nil
end

--- Globals
local wait = task.wait
local spawn = task.spawn
local delay = task.delay
local wrap = coroutine.wrap
local clock = os.clock
local time = os.time
local profilebegin = debug.profilebegin
local profileend = debug.profileend
local random = math.random
local unpack = table.unpack
local max = math.max

--- Variables
local storage = {}
local leavingStorage = {}
local loadedStorage = {}

--- Internal

--local function optionalAssert(value, callback, message) --- Moved to _L.Asserts
--	if value == nil then
--		return
--	end
--	
--	assert(callback(value), message)
--end

------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--[[ 
    Vanilla datastores are horrible. They suffer from random throttling, unexplained errors, and several other issues that normally go undiagnosed.
	Because of this, get/set/update invokes may go ignored or even reset datastore keys. To fix this, you should funnel all datastore requests
	through this module. Specifically, this:
	- Avoids initial failures
	- Prevents overriding keys with nil/blank
	- Queues similar requests to avoid throttling
	- Re-attempts failed invokes
	- Wraps invokes in pcalls for worst case scenerios
	- Returns proper arguments
	
	===========
		\\\ Alternative to GetAsync(). Returns: result, success
		SecureDatastore.Get(
			key,					<-- |REQ|	Async key (str)
			yield,					<-- 		How many attempts/tries (number)							[defaults to: 1]
			scope,					<-- 		Scope of datastore (str)									[defaults to: nil]
		)
		
		\\\ Alternative to SetAsync(). Returns: success
		SecureDatastore.Set(
			key,					<-- |REQ|	Async key (str)
			value,					<-- |REQ|	New value for async
			yield,					<-- 		How many attempts/tries (number)							[defaults to: 1]
			scope,					<-- 		Scope of datastore (str)									[defaults to: nil]
		)
		
		\\\ Alternative to UpdateAsync(). Returns: success
		SecureDatastore.Update(
			key,					<-- |REQ|	Async key (str)
			function,				<-- |REQ|	Update function
			yield,					<-- 		How many attempts/tries (number)							[defaults to: 1]
			scope,					<-- 		Scope of datastore (str)									[defaults to: nil]
		)
			EX:  SecureDatastore.Update(datastore, "player1", function(oldValue)  return oldValue*2  end)
	===========
--]]
local datastore = DatastoreService:GetDataStore(Settings.StatsVersion or "NonSave0", nil, DatastoreOptions)
local SecureDatastore = {}
SecureDatastore.MEMORY_STORE_SORTED_MAP_MAX_EXPIRATION = 3888000

local function keyFor(key: string|number): string
	if typeof(key) == "string" then
		return key
	end

	assert(typeof(key) == "number", "[Saving.Datastore] key must be a string|number")
	return tostring(key)
end

local delays = {1, 6, 15, 30, 60}
local function computeDelay(yield)
	return delays[math.clamp(math.round(yield), 1, #delays)]
end

function SecureDatastore.Get(key: string|number, yield: number?, scope: string): (any, boolean, any)
	--- Variables
	local key = keyFor(key)
	assert(datastore:IsA("GlobalDataStore"), "[Saving.Datastore] datastore must be a GlobalDataStore or string [1]")
	--
	yield = (yield or 1)

	--- Attempt It
	for attempt = 1, yield::number do
		if attempt > 1 then
			wait(computeDelay(attempt - 1))
		end

		local success, returnedValue, metaData = pcall(function()
			return datastore:GetAsync(key)
		end)

		if not success then
			warn(`[Saving.Datastore] Get Failed '{tostring(key)}': {(tostring(returnedValue))}`) 
			continue
		end

		return returnedValue, true, metaData
	end

	warn(`[Saving.Datastore] Failed to Get '{tostring(key)}'`)
	return nil, false, nil
end

function SecureDatastore.Set(key: string|number, value: any, yield: number?, scope: string?): (boolean, any)
	--- Variables
	local key = keyFor(key)
	assert(datastore:IsA("GlobalDataStore"), "[Saving.Datastore] datastore must be a GlobalDataStore or string [1]")
	--
	yield = (yield or 1)

	--- Attempt It
	for attempt = 1, yield::number do
		if attempt > 1 then
			wait(computeDelay(attempt - 1))
		end

		local success, result = pcall(function()
			return datastore:SetAsync(key, value)
		end)

		if not success then
			warn(`[Saving.Datastore] Set Failed '{tostring(key)}': {(tostring(result))}`) 
			continue
		end

		return true, result
	end

	warn(`[Saving.Datastore] Failed to Set '{tostring(key)}'`)
	return false, nil
end

function SecureDatastore.Update(key: string|number, updateFunction, yield: number?, scope: string?): (boolean, any, any)
	assert(typeof(updateFunction) == "function", "[Datastore] updateFunction must be a function")

	--- Variables
	local key = keyFor(key)
	assert(datastore:IsA("GlobalDataStore"), "[Saving.Datastore] datastore must be a GlobalDataStore or string [1]")
	--
	yield = (yield or 1)

	--- Attempt It
	for attempt = 1, yield::number do
		if attempt > 1 then
			wait(computeDelay(attempt - 1))
		end

		local new = false
		local success, result, metaData = pcall(function()
			return datastore:UpdateAsync(key, function(oldValue, keyInfo)
				local innerSuccess, returnedValue, a, b = pcall(updateFunction, oldValue, keyInfo)
				if not innerSuccess then
					warn(`[Saving.Datastore] Update Failed INNER '{tostring(key)}': {(tostring(returnedValue))}`)
					return nil
				end

				if returnedValue == nil then
					new = true
					return nil
				end

				return returnedValue, a, b
			end)
		end)

		if new then
			return false, nil, nil
		end

		if not success then
			warn(`[Saving.Datastore] Update Failed '{tostring(key)}': {(tostring(result))}`) 
			continue
		end

		return true, result, metaData
	end

	warn(`[Saving.Datastore] Failed to Update '{tostring(key)}'`)
	return false, nil
end

------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

local function _player(player: Player|string|number): (number, string)
	if typeof(player) == "string" then
		player = tonumber(player) or player
	end

	if typeof(player) == "Instance" and player:IsA("Player") then
		return player.UserId, player.Name
	end

	if typeof(player) == "number" then
		return player, tostring(player)
	end

	error("[SAVING] Unknown player type: "..typeof(player))
end

--- External
local module = {
	PlayerSaved = PlayerSaved,
	PlayerAdded = PlayerAdded,
	StatChanged = StatChanged,
	PlayerSaveRemoved = PlayerSaveRemoved,
	PlayerFullyRemoved = PlayerFullyRemoved
}


function module.Save(player, playerLeaving, customSave)
	if typeof(player) == "string" then
		player = tonumber(player) or player
	end

	assert(typeof(player) == "number" or typeof(player) == "Instance" and player:IsA("Player"), "[Saving] player must be a Player or number")
	Asserts.optional.boolean(playerLeaving, "[Saving] playerLeaving must be a boolean or nil")
	Asserts.optional.table(customSave, "[Saving] customSave must be a table or nil")

	local userId, strId = _player(player)
	local stats = customSave or storage[userId]
	if isStudio and not StudioSaving then
		task.wait()
		pcall(function()
			PlayerSaved:FireAsync(typeof(player) == "Instance" and player or nil, userId, true, playerLeaving == true, stats)
		end)
		return true
	end

	if stats ~= nil then
		local trackback = debug.traceback()
		local success = SecureDatastore.Update(SavePlayerID or userId, function(oldSave: any)
			if not oldSave then
				warn("[SAVING] Save FAILED: oldSave was nil! User:", SavePlayerID or userId, trackback);
				return nil; 
			end

			assert(oldSave)
			if oldSave.PlayingSession == nil then 
				warn("[SAVING] Save FAILED: PlayingSession was nil! User:", SavePlayerID or userId, trackback);
				return nil 
			end

			if sessionLocks then
				if not oldSave.SessionId and stats.SessionId then
					print("[SAVING] Save FAILED: Session lock was tampered with. User:", SavePlayerID or userId, trackback);
					return nil;
				end

				if oldSave.SessionId and stats.SessionId and oldSave.SessionId ~= stats.SessionId then
					warn("[SAVING] Save FAILED: Session ID does not match. User:", SavePlayerID or userId, trackback);
					return nil; 
				end; 
			end 

			stats.LastSaveTimestamp = clock()

			if playerLeaving then
				stats.PlayingSession = false
				stats.SessionId = nil
			else
				stats.PlayingSession = true
				if typeof(player) == "Instance" and player:IsA("Player") then
					stats.SessionId = module.GetSessionId(player)
				end
			end

			local newStats = Functions.DeepCopyUnsafe(stats)
			newStats.Age = Shared.ComputeSaveAge(newStats)
			newStats.LoginTime = nil

			return newStats
		end)

		if success then
			if Debug then
				warn("[SAVING] Successfully saved " .. tostring(userId) .. "'s stats");
			end

			pcall(function() 
				PlayerSaved:FireAsync(typeof(player) == "Instance" and player or nil, userId, true, playerLeaving == true, stats);
			end)
			return success
		end
	end

	warn("[SAVING] Failed to save " .. tostring(userId) .. "'s stats");
	spawn(function()
		local instance;
		if typeof(player) == "Instance" and player:IsA("Player") then
			instance = player
		else
			instance = Players:GetPlayerByUserId(userId)
		end

		if instance then
			instance:Kick("Saving failed. Please rejoin!")
		end
	end)

	pcall(function()
		PlayerSaved:FireAsync(typeof(player) == "Instance" and player or nil, userId, false, playerLeaving == true, stats)
	end)

	return false
end

function module.GetSafe(player, yield)
	if player == nil then
		return nil
	end

	assert(typeof(player) == "Instance" and player:IsA("Player"))

	if player ~= Players:GetPlayerByUserId(player.UserId) then
		return nil
	end

	if not player.Parent then
		return nil
	end

	if not player:GetAttribute("__LOADED") then
		return nil
	end

	if player:GetAttribute("__LEAVING") then
		return nil
	end

	local save = module.Get(player, yield)
	return save
end

function module.GetUnsafe(player, yield)
	return module.Get(player, yield)
end

function module.TrySafeSaveAll(players, yield)
	if Variables.ServerClosing then
		return false
	end

	for _, player in ipairs(players) do
		if not module.GetSafe(player) then
			return false
		end
	end

	local saveCount = 0
	local safeFailed = false
	for _, player in ipairs(players) do
		spawn(function()
			if module.SafeSave(player) then
				saveCount = saveCount + 1
			else
				safeFailed = true
			end
		end)
	end

	yield = yield or 20
	local _s = clock()
	while true do
		if safeFailed then
			return false
		end

		if Variables.ServerClosing then
			return false
		end

		if #players > saveCount then
			if yield <= clock() - _s then
				return false
			end

			wait(0.1)
		end

		return true
	end
end

function module.SafeSave(player, yield)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "[Saving] player must be a Player")

	yield = yield or 3
	local userId = player.UserId

	if isStudio and not StudioSaving then
		return true
	end

	if Variables.ServerClosing then
		return false
	end

	local stats = module.GetSafe(player)
	if not stats then
		return
	end

	assert(stats)
	local token = Functions.GenerateUID()

	stats.SafeSaveToken = token
	if not module.Save(player, false) then
		return false
	end

	for i = 1, yield do
		if Variables.ServerClosing then
			break
		end

		local save = SecureDatastore.Get(userId)
		if save and save.SafeSaveToken == token then
			return true
		end
	end

	warn("[SAVING] Failed to verify " .. tostring(userId) .. "'s stats saved");
	return false
end

function module.Retrieve(player)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "[Saving] player must be a Player")

	local savedStats
	local attempts = 0
	local retrievedStats = false
	local newPlayer = false
	--
	local userId = player.UserId
	local sessionId = module.GetSessionId(player)

	while attempts < 6 and player ~= nil and player.Parent and not Variables.ServerClosing do
		local userId = SavePlayerID or userId
		local sessionLock = false
		--
		local success = SecureDatastore.Update(userId, function(stats) 
			if stats ~= nil and typeof(stats) ~= "table" then
				if 
					not pcall(function() 
						warn(`[SAVING] Invalid save for '{userId}': {HttpService:JSONEncode(stats)} ({(typeof(stats))})`);
					end)
						and 
						not pcall(function() 
							warn(`[SAVING] Invalid save for '{userId}' [2]: {HttpService:UrlEncode((tostring(stats)))} ({(typeof(stats))})`);
						end) 
				then
					warn(`[SAVING] Invalid save for '{userId}' [3]: --- ({(typeof(stats))})`);
				end;

				return nil; 
			end

			local save;
			if stats ~= nil then
				save = stats
				newPlayer = false
			else
				save = Functions.DeepCopyUnsafe(DefaultStats)
				newPlayer = true
			end

			if save.HasResetFirstLock ~= nil then
				save.PlayingSession = false
				save.HasResetFirstLock = true
			end

			if not (isStudio and not StudioSaving) and (save.PlayingSession or save.Sessionid and save.SessionId ~= sessionId) then
				if save.LastSaveTimestamp and time() - save.LastSaveTimestamp < sessionLockBuffer or not save.LastSaveTimestamp then  
					sessionLock = true
					return nil
				end

				print("[SAVING] Session lock exceeded max wait time. Letting " .. tostring(userId) .. " play!");
			end

			if not (isStudio and not StudioSaving) then
				save.LastSaveTimestamp = time()
				save.PlayingSession = true
				save.SessionId = sessionId
			end

			savedStats = save
			retrievedStats = true
			return save
		end)

		if not success then
			retrievedStats = false
			warn("[SAVING] Failed to retrieve save for " .. tostring(userId) .. ": SecureDatastores request failed. Trying again (" .. attempts .. "/6)");
		end

		if retrievedStats then
			break
		end

		Functions.Wait(5, 10)
		attempts = attempts + 1
	end

	if not retrievedStats then
		return false, false, nil
	end

	return true, newPlayer, savedStats
end

function module.Init(player)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "[Saving] player must be a Player")

	local userId = player.UserId

	if loadedStorage[userId] then
		return false
	end

	loadedStorage[userId] = true

	local function InitPlayer()
		while (storage[userId] ~= nil) or (leavingStorage[userId] and player and player.Parent) do  RunService.Heartbeat:Wait() end 

		if storage[userId] == nil and not leavingStorage[userId] and player and player.Parent then
			local success, newPlayer, stats = module.Retrieve(player)
			if not success or stats == nil then
				warn("[SAVING] _L.Saving.Init | MAJOR ERROR: Stats returned error for " .. tostring(userId));
				return false
			end

			assert(stats)
			if not player or not player.Parent then
				module.Save(player or userId, true, stats)
				return false
			end

			for k, v in pairs(DefaultStats) do
				if stats[k] == nil then
					stats[k] = Functions.DeepCopyUnsafe(v)
				end
			end

			stats.LoginTime = workspace:GetServerTimeNow()

			local prevLocalSave = Functions.DeepCopyUnsafe(stats)
			local keys = {}

			storage[userId] = stats
			if isStudio and SavePlayerID then
				print("[SAVING] save: ",stats)
			end

			spawn(function()
				if WaitLoaded then
					while not module.IsLoaded(player) do
						wait()
					end
				end

				PlayerAdded:FireAsync(player, newPlayer)
			end)

			player:SetAttribute("NewPlayer", newPlayer == true)
			local _s = clock()  
			local dataToSend = {}
			local cachedStats = {}
			while (player and player.Parent) and (storage[userId]) and (not leavingStorage[userId]) do 
				local newData = {}
				for statName, statValue in pairs(storage[userId]) do
					if not Settings.StatsNetworkingBlacklist[statName] then
						local cachedStatValue = cachedStats[statName]
						local isTable = type(statValue) == "table"
						if cachedStatValue == nil then
							if isTable then
								cachedStats[statName] = Functions.CloneTable(statValue, false)
								table.insert(newData, {statName, Functions.CloneTable(statValue, false)})
								table.insert(dataToSend, {statName, Functions.CloneTable(statValue, false)})
							else 
								cachedStats[statName] = statValue 
								table.insert(newData, {statName, statValue})
								table.insert(dataToSend, {statName, statValue})
							end
							StatChanged:FireAsync(player, statName)
						elseif isTable then
							if not Functions.CompareTable(statValue, cachedStatValue) then 
								cachedStats[statName] = Functions.CloneTable(statValue, false) 
								table.insert(newData, {statName, Functions.CloneTable(statValue, false)})
								table.insert(dataToSend, {statName, Functions.CloneTable(statValue, false)})
								StatChanged:FireAsync(player, statName)
							end
						elseif statValue ~= cachedStatValue then 
							cachedStats[statName] = statValue 
							table.insert(newData, {statName, statValue})
							table.insert(dataToSend, {statName, statValue})
							StatChanged:FireAsync(player, statName)
						end
					end
				end

				if next(newData) then
					Network.Fire("New Stats", player, newData, player)
				end

				if ReplicateStatsBuffer <= os.clock() - _s and Functions.DictionaryLength(dataToSend) > 0 then
					_s = os.clock()
					for _, p in ipairs(game.Players:GetPlayers()) do
						if p ~= player then
							coroutine.wrap(function()
								Network.Fire("New Stats", p, dataToSend, player)
							end)()
						end							
					end
					dataToSend = {}
				end
				RunService.Heartbeat:Wait()	
			end

			return true
		end
	end

	local attempts = 0
	local success = false

	--while (attempts < 3) and (player ~= nil) and (typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent) do
	while (not success and attempts < 3 and player and player.Parent) do
		success = InitPlayer()
		RunService.Heartbeat:Wait()

		if success then
			break
		end

		attempts = attempts + 1
		wait(0.5)
	end

	if not success then
		warn("[SAVING] MAJOR ERROR: Could not init "..tostring(userId).."'s stats!")
		if player then
			player:Kick("[SAVING] Something went wrong. Please rejoin!")
		end
	end

	loadedStorage[userId] = nil

	return false
end

function module.Get(player, yield, bypassRecentlyLeft)
	if player == nil then
		return nil
	end

	assert(typeof(player) == "Instance" and player:IsA("Player"), "[Saving] player must be a Player")
	Asserts.optional.boolean(yield, "[Saving] yield must be a boolean or nil")
	Asserts.optional.boolean(bypassRecentlyLeft, "[Saving] bypassRecentlyLeft must be a boolean or nil")

	local userId = player.UserId
	if not bypassRecentlyLeft and leavingStorage[userId] then
		return nil
	end

	--- Attempt to get session stats
	local stats = storage[userId]

	--- If failed, attempt to get it again (5 tries)
	if not stats then
		pcall(function()
			local _s = clock()
			if yield == true then
				while not stats and clock() - _s <= 5 and player and player.Parent do
					RunService.Heartbeat:Wait()

					stats = storage[userId]
				end
			end
		end)
	end

	--
	return stats
end

function module.GetByUserId(userId, bypassRecentlyLeft)
	assert(typeof(userId) == "number")
	Asserts.optional.boolean(bypassRecentlyLeft, "[Saving] bypassRecentlyLeft must be a boolean or nil")

	if not bypassRecentlyLeft and leavingStorage[userId] then
		return nil
	end

	return storage[userId]
end

function module.GetUserIds()
	local userIds = {}
	for userId in pairs(storage) do
		table.insert(userIds, userId)
	end

	return userIds
end

function module.GetSaves()
	return storage
end

function module.DidRecentlyLeave(userId)
	assert(typeof(userId) == "number")

	return leavingStorage[userId] == true
end

function module.Remove(player)
	if typeof(player) == "string" then
		player = tonumber(player) or player
	end

	assert(typeof(player) == "number" or typeof(player) == "Instance" and player:IsA("Player"), "[Saving] player must be a Player or number")

	local userId, name = _player(player)
	pcall(function()
		PlayerSaveRemoved:FireAsync(typeof(player) == "Instance" and player or nil, userId, storage[userId])
	end)

	--- Remove session stats :(
	local success = pcall(function()
		storage[userId] = nil
		if not isStudio then
			wait(10)
		end
		leavingStorage[userId] = nil
	end)

	pcall(function()
		PlayerFullyRemoved:FireAsync(typeof(player) == "Instance" and player or nil, userId)
	end)

	--- Failed to remove session stats wtf? Should never happen :/
	if not success then
		pcall(function()
			warn("[SAVING] Failed to remove session stats for " .. tostring(userId) .. "!")
		end)
	end
end

function module.Reset(player)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "[Saving] player must be a Player")

	local userId = player.UserId

	--- Reset the player's stats to the default stats
	if storage[userId] then
		storage[userId] = Functions.DeepCopyUnsafe(DefaultStats)
		module.Save(player)
	end
end

function module.IsLoaded(player)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "[Saving] player must be a Player")

	--- Check if player has loaded tag
	return player and player:GetAttribute("__LOADED") ~= nil
end

function module.GetSessionId(player)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "[Saving] player must be a Player")

	local sessionToken = player:GetAttribute("SessionToken")
	if not sessionToken then
		sessionToken = Functions.GenerateUID()
		player:SetAttribute("SessionToken", sessionToken)
	end

	return sessionToken
end


------------------------------------------------------------------------------

local function PlayerAdded(player)
	assert(typeof(player) == "Instance" and player:IsA("Player"), "[Saving] player must be a Player")

	--- Player joined! Initialize their stats.
	spawn(function()
		module.Init(player)
	end)
end

local function PlayerRemoving(player)
	if typeof(player) == "string" then
		player = tonumber(player) or player
	end

	assert(typeof(player) == "number" or typeof(player) == "Instance" and player:IsA("Player"), "[Saving] player must be a Player or number")

	local userId, name = _player(player)
	if storage[userId] and not leavingStorage[userId] then
		leavingStorage[userId] = true

		local _s = clock()
		repeat
			wait(0.1)
			local d = 0
			if not isStudio then
				d = max(d, 8)
			end
		until d <= clock() - _s

		--- Player left! Save their stats (as session ended)
		module.Save(player or userId, true)

		--- Remove their stats after buffer time (to prevent accidental indexes erroring)
		module.Remove(player or userId)
	end
end


------------------------------------------------------------------------------


--- Loop through players in server (just in-case existing players connected too fast)
for _, p in ipairs(game.Players:GetPlayers()) do  
	PlayerAdded(p)  
end   


--- Player added
game.Players.PlayerAdded:Connect(PlayerAdded)  


--- Player removing
game.Players.PlayerRemoving:Connect(function(player)
	spawn(function()
		player:SetAttribute("__LEAVING", true)
	end)

	PlayerRemoving(player)
end)  

spawn(function()
	while true do
		for userId in pairs(storage) do
			local success, result = pcall(function()
				if not leavingStorage[userId] and not Players:GetPlayerByUserId(userId) then
					PlayerRemoving(userId)
				end
			end)

			if not success then
				warn("[SAVING] Failed to remove: " .. tostring(result))
			end
		end

		wait()
	end
end)

--- Attempt to save everyone's stats and show a server close message (TO:DO make update message more professional)
local defaultShutdownGUI = false
game.OnClose = function()
	Variables.ServerClosing = true
	workspace:SetAttribute("ServerClosing", true)
	Signal.Fire("Server Closing")

	--- Save everyone's stats on server
	for _, player in ipairs(game.Players:GetPlayers()) do
		spawn(function()
			module.Save(player, true)
		end)
	end

	--- UPDATE HYPE WOOOOO
	if defaultShutdownGUI then
		local closeMsg = Instance.new("Message")
		closeMsg.Text = "⚠️ This server is closing - please rejoin. Thank you!"
		closeMsg.Parent = game.Workspacelocal  
	end

	if not isStudio then
		for _, player in Players:GetPlayers() do
			pcall(function()
				spawn(function()
					Migration.Migrate(player)
				end)
			end)
		end

		print("[SAVING] Waiting 30s for server to shutdown!");
		wait(30);
	end
end

------------------------------------------------------------------------------


--- Base save loop
local _autots 
spawn(function()
	--- Save loop
	while true do
		_autots = clock()

		--- Save everyone's stats :D
		pcall(function()
			for statsName, statsData in pairs(storage) do
				if statsData then
					_autots = clock()

					--- Wait buffer time :)))
					wait(saveDuration / (#game.Players:GetPlayers() or 1))

					_autots = clock()

					local success, result = pcall(function()
						local player = Players:GetPlayerByUserId(statsName)
						if player and not leavingStorage[statsName] and storage[statsName] then
							spawn(function()
								module.Save(player)
							end)
						end
					end)

					if not success then
						warn("[SAVING] PLAYER AUTO SAVE FAILED: " .. tostring(result))
					end
				end
			end
		end)

		--
		_autots = clock()
		wait(0.1)
	end
end)


task.spawn(function()
	repeat wait(5) until clock() - _autots >= autoSaveBuffer

	warn("[SAVING] AUTO SAVE STOPPED WORKING - OH ####")
	Players.PlayerAdded:Connect(function(player)
		player:Kick()
	end)

	for _, p in ipairs(Players:GetPlayers()) do
		p:Kick("Something went wrong. Please rejoin!")
	end
end)

------------------------------------------------------------------------------


--- Return stats on invoke
local statsCooldown = {}
Network.Invoked("Get Stats").OnInvoke = function(player, target)
	if target == nil then
		return nil
	end

	assert(typeof(target) == "Instance" and target:IsA("Player"))

	if not target.Parent or not player.Parent then
		return nil
	end

	local cooldown = statsCooldown[player]
	if not cooldown then
		cooldown = {}
		statsCooldown[player] = cooldown
	end

	local ts = workspace:GetServerTimeNow()
	local lastTs = cooldown[target] or ts

	cooldown[target] = ts + 0
	local stats = module.Get(target, player == target)
	if not stats then
		cooldown[target] = nil
		return stats
	end

	local cloned = false
	for k in pairs(stats) do
		local blacklist = false
		if StatsNetworkingBlacklist[k] then
			blacklist = true
		elseif StatsNetworkingLocalOnly[k] and player ~= target then
			blacklist = true
		end

		if blacklist then
			if not cloned then
				cloned = true
				stats = table.clone(stats)
			end
			stats[k] = nil
		end
	end

	return stats
end 

Signal.Fired("Clear Get Stats Cooldown"):Connect(function(player, target) 
	local cooldown = statsCooldown[player]
	if cooldown then
		cooldown[target] = nil
	end
end)

Signal.Fired("Disable Default Shutdown GUI"):Connect(function() 
	defaultShutdownGUI = false
end)


------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------


return module
