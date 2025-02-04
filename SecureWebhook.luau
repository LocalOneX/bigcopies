--!strict 
--[=[
    SecureWebhook.luau: Easy webhook use for studio
    
    It's much easier to use this instead of making a new
    function for webhook in every script, this easily
    encodes the webhook into a proxy aswell! 
    
    Default proxy set to https://webhook.newstargeted.com/
    Embeded builder: https://discohook.org
    
    Usage: (ex) 
    	--@variables
		local __sw = require(game.ServerScriptService.SecureWebhook)
	 	local WEBHOOK_URL = "https://discord.com/api/webhooks/ID/TOKEN"
	 	
	 	---self(...)
		SecureWebhook(WEBHOOK_URL:: string, {content = "Hello World!"}:: SecureWebhook.body, false:: boolean?)
		
		--self.generic(...)
		module.generic(WEBHOOK_URL:: string, {content = "Hello World!"}:: SecureWebhook.body, false:: boolean?)
		
		--self.default(...)
		module.default(WEBHOOK_URL:: string, "Hello World!":: string)
    
    v1.0.1 @LocalOnex
--]=] 

local module = {}
module.__index = module

---@reference
local HttpService = game:GetService"HttpService"
local TEST_URL = "https://discord.com/api/webhooks/ID/TOKEN"

---@types
export type body = {
	content: string?,
	embeds: { 
		{ 
			title: string?, 
			description: string?, 
			url: string?, 
			color: number?, 
			fields: { { name: string, value: string, inline: boolean? } }?, 
			footer: { text: string, icon_url: string? }?, 
			thumbnail: { url: string }?, 
			image: { url: string }?, 
			author: { name: string, url: string?, icon_url: string? }? 
		} 
	}?,
	username: string?,
	avatar_url: string?,
	tts: boolean?
} 

---@config 
local defaultQueue = false
local proxy = true
local proxyUrl = "webhook.newstargeted.com"


---@internal 

local function fetchDetails(url: string): (string?, string?)
	---@param url webhook url string
	---@return str(id, token)

	---@asserts
	assert(typeof(url) == "string") 

	return unpack(url:gsub("https://discord.com/api/webhooks/", ""):split("/")) --url:match("https://discord.com/api/webhooks/(%w+)/(%w+)") 
end

local function toproxy(url: string, postQueue: boolean?): string
	---@param url webhook url string
	---@param postQueue should this post in a queue?
	---@return str (proxy url)

	---@asserts
	assert(typeof(url) == "string")
	assert(typeof(postQueue) == "nil" or typeof(postQueue) == "boolean")

	---if it is already a proxy, return.
	if url:find(proxyUrl) then
		return url
	end 

	---if nil set it to the default val
	if postQueue == nil then
		postQueue = defaultQueue
	end

	---DETAILS Id and Token
	local WEBHOOK_ID, WEBHOOK_TOKEN = fetchDetails(url)
	assert(WEBHOOK_ID and WEBHOOK_TOKEN, "[SecureWebhook.fetchDetails] FAILURE")

	---
	local proxy = table.concat({
		"https://",proxyUrl,"/api/webhooks/",WEBHOOK_ID,"/",WEBHOOK_TOKEN,
		postQueue and "/queue" or ""
	}) 

	return proxy
end 

local function post(url: string, body: any, postQueue: boolean?): (...any)
	---@param url webhook url string
	---@param body the message content (content, embeds, etc)
	---@param postQueue should this post in a queue?
	---@return bool (success) response (status)

	---@asserts
	assert(typeof(url) == "string")
	assert(body ~= nil)

	---@vars
	body = HttpService:JSONEncode(body)
	url = toproxy(url, postQueue) 
	warn(url)
	
	---
	local success, response  = pcall(function()
		return HttpService:RequestAsync {
			Url = url, 
			Method = "POST", 
			Headers = {
				["Content-Type"] = "application/json"
			}, 
			Body = body
		}
	end)

	if success and response .Success then
		return true, response .StatusCode, response .Body
	end

	return false, response and response.StatusMessage or "Unknown error"
end 


---@external 


---@generic this is what's generally used.
function module.generic(url: string, body: any, postQueue: boolean?)
	---@param url webhook url string
	---@param body the message content (content, embeds, etc)
	---@param postQueue should this post in a queue?
	---@return bool (success) response (status)
	return post(url, body, postQueue)
end 

---@default post whenever you just want to send a str to the webhook.
function module.default(url: string, content: any)
	---@param url webhook url string
	---@param content the message content  
	---@return bool (success) response (status)
	return post(url, {content = content})
end  

--@self() this is just the lazy version of .generic(...)
function module.__call(self, url: string, body: any, postQueue: boolean?)
	---@param url webhook url string
	---@param body the message content (content, embeds, etc)
	---@param postQueue should this post in a queue?
	---@return bool (success) response (status)
	return module.generic(url, body, postQueue)
end    

---@tests
print(fetchDetails(TEST_URL))
assert(select(1, fetchDetails(TEST_URL)) == "ID")
assert(select(2, fetchDetails(TEST_URL)) == "TOKEN")
assert(toproxy(TEST_URL)=="https://webhook.newstargeted.com/api/webhooks/ID/TOKEN")

---@return self/SecureWebhook
module = setmetatable(module, module) 
table.freeze(module)
return module
