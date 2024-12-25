--!strict
--[[
    By: @LocalOneX -- 12/25/2024
    Vanilla datastores are horrible. They suffer from random throttling, unexplained errors, and several other issues that normally go undiagnosed.
	Because of this, get/set/update invokes may go ignored or even reset datastore keys. To fix this, you should funnel all datastore requests
	through this module. Specifically, this:
	- Avoids initial failures
	- Prevents overriding keys with nil/blank
	- Queues similar requests to avoid throttling
	- Re-attempts failed invokes
	- Wraps invokes in pcalls for worst case scenerios
	- Returns proper arguments
--]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local Datastore = {MEMORY_STORE_SORTED_MAP_MAX_EXPIRATION = 3888000}
local DataStoreOptions = Instance.new("DataStoreOptions")
DataStoreOptions:SetExperimentalFeatures({Datastore = true})

local datastoresCache = {}
function dataStoreFor(datastore: GlobalDataStore | string, scope: string?): GlobalDataStore 
	--- Sanity check
	if typeof(datastore) == "Instance" then
		assert(datastore:IsA("GlobalDataStore"), "[Datastore] datastore must be a GlobalDataStore or string [1]")
		
		return datastore 
	end
	
	assert(typeof(datastore) == "string", "[Datastore] datastore must be a GlobalDataStore or string [2]") 
	
	--- If datastore argument is not a datastore obj - find it, and cache it to save memory
	if not datastoresCache[datastore] then 
		datastoresCache[datastore] = {}
	end
	
	local scope = scope or "global" 
	if not datastoresCache[datastore][scope] then
		datastoresCache[datastore][scope] = DataStoreService:GetDataStore(datastore, scope, DataStoreOptions) 
	end
	 
	return datastoresCache[datastore][scope]
end

function keyFor(key: string | number): string
	if typeof(key) == "string" then
		return key 
	end
	
	assert(typeof(key) == "number", "[Datastore] key must be a string|number")
	return (tostring(key))
end

--[[
    Yield delay for each attempt.
--]]
local delays = {1, 6, 15, 30, 60}
function computeDelay(yield: number): number 
	return delays[math.clamp(math.round(yield), 1, #delays)]
end

function Datastore.Get(datastore: GlobalDataStore | string, key: number | string, yield: number?, scope: string?): (any, boolean, any) 
	--- Variables
	local key = keyFor(key)
	local datastore = dataStoreFor(datastore, scope)
	--
    yield = (yield or 1)

	--- Attempt it
	for attempt = 1, yield :: number do
		if attempt > 1 then
			local delay = computeDelay(attempt - 1)
			task.wait(delay)
		end
		  
		local success, returnedValue, v22 = pcall(function() 
			return datastore:GetAsync(key)
		end)
		
		if not success then
			warn(`[Datastore] Get Failed '{tostring(datastore.Name)}'/'{tostring(key)}': {(tostring(returnedValue))}`) 
		end
		
		return returnedValue, true, v22
	end
	
	warn(`[Datastore] Failed to Get '{tostring(datastore.Name)}'/'{(tostring(key))}'`)
	return nil, false, nil
end

function Datastore.Set(datastore: GlobalDataStore | string, key: number | string, value: any, yield: number?, scope: string): (boolean, any) 
	--- Variables
	local key = keyFor(key)
	local datastore = dataStoreFor(datastore, scope)
	--
	yield = (yield or 1)
	
	--- Attempt it
	for attempt = 1, yield :: number do
		if attempt > 1 then
			local delay = computeDelay(attempt - 1)
			
			task.wait(delay)
		end
		
		local success, result = pcall(function() 
			return datastore:SetAsync(key, value)
		end)
		
		if not success then
			warn(`[Datastore] Set Failed '{tostring(datastore.Name)}'/'{tostring(key)}': {(tostring(result))}`) 
		end
		
		return true, result
	end
	
	warn(`[Datastore] Failed to Set '{tostring(datastore.Name)}'/'{(tostring(key))}'`)
	return false, nil
end

function Datastore.Update(datastore: GlobalDataStore | string, key: number | string, updateFunction: (any,any) -> (any,any,any?), yield: number?, scope: string?): (boolean, any, any) 
	assert(typeof(updateFunction) == "function", "[Datastore] updateFunction must be a function")
	
	--- Variables
	local key = keyFor(key)
	local datastore = dataStoreFor(datastore, scope)
	--
	yield = (yield or 1)

	--- Attempt it
	for attempt = 1, yield :: number do
		if attempt > 1 then
			task.wait(computeDelay(attempt - 1))
		end 
		local returnedNil = false
		local success, result, v50 = pcall(function()
			return datastore:UpdateAsync(key, function(oldValue, keyInfo) 
				local innerSuccess, returnedValue, v46, v47 = pcall(updateFunction, oldValue, keyInfo)
				if not innerSuccess then
					warn(`[Datastore] Update Failed INNER '{tostring(datastore.Name)}'/'{tostring(key)}': {(tostring(returnedValue))}`)
					return nil
				end
				
				if returnedValue == nil then
					returnedNil = true
					return nil 
				end
				
				return returnedValue, v46, v47
			end)
		end)
		
		if returnedNil then
			return false, nil, nil 
		elseif success then
			return true, result, v50 
		end 
		warn(`[Datastore] Update Failed '{tostring(datastore.Name)}'/'{tostring(key)}': {(tostring(result))}`) 
	end 
	warn(`[Datastore] Failed to Update '{tostring(datastore.Name)}'/'{(tostring(key))}'`)
	return false, nil, nil
end

function Datastore.OrderedUpdate(datastore: OrderedDataStore, key: number | string, updateFunction: (any,any) -> (any,any,any,any), yield: number?): (boolean, any, any)
	assert(typeof(updateFunction) == "function", "[Datastore] updateFunction must be a function")
	assert(datastore:IsA("OrderedDataStore"), "[Datastore] datastore must be a OrderedDataStore or string [1]")
	
	--- Variables
	local key = keyFor(key) 
	--
	yield = (yield or 1)

	--- Attempt it
	for attempt = 1, yield :: number do
		if attempt > 1 then
			task.wait(computeDelay(attempt - 1))
		end
		
		local returnedNil = false
		local success, response, v66 = pcall(function()
			return datastore:UpdateAsync(key, function(oldValue, keyInfo) 
				local innerSuccess, returnedValue, v62, v63 = pcall(updateFunction, oldValue, keyInfo)
				if not innerSuccess then
					warn(`[Datastore] Ordered Update Failed INNER '{tostring(datastore.Name)}'/'{tostring(key)}': {(tostring(returnedValue))}`)
					return nil 
				end
				
				if returnedValue == nil then
					returnedNil = true
					return nil 
				end
				
				return returnedValue, v62, v63
			end)
		end)
		
		if returnedNil then
			return false, nil, nil 
		elseif success then
			return true, response, v66
		end 
		warn(`[Datastore] Ordered Update Failed '{tostring(datastore.Name)}'/'{tostring(key)}': {(tostring(response))}`) 
	end
	warn(`[Datastore] Ordered Failed to Update '{tostring(datastore.Name)}'/'{(tostring(key))}'`)
	return false, nil, nil
end

function Datastore.MemoryOrderedUpdate(datastore: MemoryStoreSortedMap, key: number | string, updateFunction: (any) -> (any, any), maxExpiration: number?, yield: number?): (boolean, any) 
	assert(typeof(updateFunction) == "function", "[Datastore] updateFunction must be a function")
	assert(datastore:IsA("MemoryStoreSortedMap"), "[Datastore] datastore must be a MemoryStoreSortedMap or string [1]") 
	assert((maxExpiration == nil) or (typeof(maxExpiration) == "number"))
	
	--- Variables
	local key = keyFor(key) 
	--
	yield = (yield or 1)
	maxExpiration = (maxExpiration or Datastore.MEMORY_STORE_SORTED_MAP_MAX_EXPIRATION)

	--- Attempt it
	for attempt = 1, yield :: number do
		if attempt > 1 then
			task.wait(computeDelay(attempt - 1))
		end
		
		local returnedNil = false
		local success, result = pcall(function() 
			return datastore:UpdateAsync(key, function(oldValue) 
				local innerSuccess, returnedValue = pcall(updateFunction, oldValue)
				if not innerSuccess then
					warn(`[Datastore] MemoryOrdered Update Failed INNER '{tostring(datastore.Name)}'/'{tostring(key)}': {(tostring(returnedValue))}`)
					return nil 
				end
				
				if returnedValue == nil then
					returnedNil = true
					return nil 
				end
				
				return returnedValue
			end, maxExpiration:: number)
		end) 
		
		if returnedNil then
			return false, nil
		elseif success then
			return true, result
		end 
		warn(`[Datastore] MemoryOrdered Update Failed '{tostring(datastore.Name)}'/'{tostring(key)}': {(tostring(result))}`)
	end
	warn(`[Datastore] MemoryOrdered Failed to Update '{tostring(datastore.Name)}'/'{(tostring(key))}'`)
	return false, nil
end

return Datastore
