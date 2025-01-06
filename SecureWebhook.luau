--!strict

--[[
    SecureWebhook.luau - Easy webhook use for studio
    
    It's much easier to use this instead of making a new
    function for webhook in every script, this easily
    encodes the webhook into a proxy aswell!
    
    Used in BIG Copies modded games files, optimized for
    PETS GO, but it can easily be made for any other game!
    
    Current proxy set to newstargeted
    Embeded builder: https://discohook.org
    
    v1.0.0 @BIG Copies @LocalOneX
--]]

local module = {}
module.__index = module

--- Reference
local HttpService = game:GetService("HttpService")
local TEST_URL = "https://discord.com/api/webhooks/ID/TOKEN"

--- Config 
local defaultQueue = false
local proxy = true


--- Internal


local function grabWebhookDetails(url: string): (string, string)
	assert(typeof(url) == "string") 
 	
	return unpack(url:gsub("https://discord.com/api/webhooks/", ""):split("/"))
end

local function getProxy(url: string, postQueue: boolean?): string
	assert(typeof(url) == "string")
	assert(typeof(postQueue) == "nil" or typeof(postQueue) == "boolean")
	if url:find("webhook.newstargeted.com") then
		return url
	end 

	--- Defaults to ...
	if postQueue == nil then
		postQueue = defaultQueue
	end
	
	local WEBHOOK_ID, WEBHOOK_TOKEN = grabWebhookDetails(url)
	
	return `https://webhook.newstargeted.com/api/webhooks/{WEBHOOK_ID}/{WEBHOOK_TOKEN}{postQueue and "/queue" or ""}`
end 
 
local function post(url: string, body: any): (...any)
	assert(typeof(url) == "string")
	assert(body ~= nil)
	
	body = HttpService:JSONEncode(body)
	url = getProxy(url) 
	
	local success, response = pcall(function()
		return HttpService:RequestAsync {
			Url = url, 
			Method = "POST", 
			Headers = {
				["Content-Type"] = "application/json"
			}, 
			Body = body
		}
	end);
	
	return success, response
end 


--- External 


function module.generic(url: string, body: any)
	return post(url, body)
end

function module.default(url: string, content: any)
	return post(url, {content = content})
end
 
--[[local function getImageLinkFromAssetId(assetId)
	local responseData = HttpService:GetAsync(`https://thumbnails.roproxy.com/v1/assets?assetIds={assetId}&returnPolicy=PlaceHolder&size=512x512&format=Png&isCircular=false`)
	local response = HttpService:JSONDecode(responseData)

	return response.data[1]["imageUrl"]
end

function module.roembed(url: string, embed: any)
	assert(typeof(embed) == "table")
	
	local encoded = {}
	
	
	return post(url, {content = "", embeds = {encoded}})
end]]--

function module.__call(self, url: string, body: any)
	return module.generic(url, body)
end 

  
--- Tests


 
return setmetatable(module, module) 
