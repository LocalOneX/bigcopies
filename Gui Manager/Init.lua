--!strict
--[=[
    @LocalOneX BIG Copies
    1/16/2025 Gui Manager.luau 
--]=]

local Variables = require(game.ReplicatedStorage.Library.Variables)
local PlaceFile = require(game.ReplicatedStorage.Library.Modules.PlaceFile)
local GUI = require(game.ReplicatedStorage.Library.Client.GUI)
local LogicTree = require(script.LogicTree)
local UpgradeCmds = require(game.ReplicatedStorage.Library.Client.UpgradeCmds)
local CurrencyCmds = require(game.ReplicatedStorage.Library.Client.CurrencyCmds)
local LoginStreakCmds = require(game.ReplicatedStorage.Library.Client.LoginStreakCmds)
local UpgradeFrontend = require(game.ReplicatedStorage.Library.Client.UpgradeFrontend)
local EggCmds = require(game.ReplicatedStorage.Library.Client.EggCmds)
local Save = require(game.ReplicatedStorage.Library.Client.Save)
local ItemScrollCmds = require(game.ReplicatedStorage.Library.Client.ItemScrollCmds)
local NotificationCmds = require(game.ReplicatedStorage.Library.Client.NotificationCmds)
local EventUtil = require(game.ReplicatedStorage.Library.Util.EventUtil)
local Signal = require(game.ReplicatedStorage.Library.Signal)

--- gui
local mainUI = GUI.Main()
local rankUI = GUI.RankGoals()
local scrollUI = GUI.ItemScroll()
local toolUI = GUI.Tool()

--- logictree util
local AND = LogicTree.AND
local OR = LogicTree.OR
local NOT = LogicTree.NOT
local IS_LOCKED = LogicTree.IS_LOCKED
local NOT_LOCKED = LogicTree.NOT_LOCKED
local HAS_UPGRADE = LogicTree.HAS_UPGRADE
local HAS_ROLLS = LogicTree.HAS_ROLLS
local FUNC = LogicTree.FUNC

--- Reference
local boostsFrame = mainUI.Boosts

local petsButton = mainUI.Bottom.Buttons.Pets
local upgradesButton = mainUI.Bottom.Buttons.Upgrades
local upgradeArrow = mainUI.Bottom.Buttons.UpgradesArrow
local rollButton = mainUI.Bottom.Buttons.Roll
local rollTitle = mainUI.Bottom.Buttons.Roll.Title
local rollArrow = mainUI.Bottom.Buttons.RollArrow
local autoRollButton = mainUI.Bottom.RollButtons.AutoRoll
local hideRollsButton = mainUI.Bottom.RollButtons.HideRolls
local levelsFrame = mainUI.Bottom.Levels

local bottonRightFrame = mainUI.BottomRight 

local desktopCoinsFrame = mainUI.Left["Coins Desktop"]
local desktopDiamondsFrame = mainUI.Left["Diamonds Desktop"]
local desktopFishingFrame = mainUI.Left["Fishing Desktop"]
local desktopEventFrame = mainUI.Left["Event Desktop"]
local coinsFrame = mainUI.Top.Coins
local diamondsFrame = mainUI.Top.Diamonds
local fishingFrame = mainUI.Top.Fishing
local eventFrame = mainUI.Top.Event

local toolsFrame = mainUI.Left.Tools

local ranksFrame = rankUI.RankGoals
local scrollFrame = scrollUI.Main
local toolCloseButton = toolUI.Close

--- Variables
local hideUI = Variables.Locks.HideUI
local hideAllUI = Variables.Locks.HideAllUI
local showCurrencyUI = Variables.Locks.ShowCurrencyUI
local rollingAnimationUI = Variables.Locks.RollingAnimationUI
local pauseEverything = Variables.Locks.PauseEverything

local isMobile = FUNC(function()  return Variables.Mobile end)  --[[ Line: 75 ]] -- upvalues: Variables (copy)
local notMobile = NOT(isMobile)
local hasDiamonds = FUNC(function() return CurrencyCmds.Get("Diamonds") > 0 end) --[[ Line: 77 ]] -- upvalues: CurrencyCmds (copy)
--local _ = FUNC
--local _ = FUNC
--local _ = FUNC  
local isAutoRolling = FUNC(function() return EggCmds.IsAutoRolling() end) --[[ Line: 81 ]] -- upvalues: EggCmds (copy)
local isHiddenRolling = FUNC(function() return EggCmds.IsRollingHidden() end) --[[ Line: 82 ]] -- upvalues: EggCmds (copy)
local isStoppingHiddenRoll = FUNC(function() return EggCmds.IsStoppingHiddenRoll() == true end) --[[ Line: 83 ]] -- upvalues: EggCmds (copy)
local isStillRolling = FUNC(function() return EggCmds.IsStoppingHiddenRoll() == false end) --[[ Line: 84 ]] -- upvalues: EggCmds (copy)
local isRollingVisible = FUNC(function() return EggCmds.IsRollingHidden() == false end) --[[ Line: 85 ]] -- upvalues: EggCmds (copy)
local isBonusRolling = FUNC(function() return Variables.Locks.BonusRolling:IsUnlocked() end) --[[ Line: 86 ]] -- upvalues: Variables (copy)
local upgradesActive = FUNC(function() return UpgradeFrontend.IsActive() == true end) --[[ Line: 87 ]] -- upvalues: UpgradeFrontend (copy)
local upgradesDisabled = FUNC(function() return UpgradeFrontend.IsActive() == false end) --[[ Line: 88 ]] -- upvalues: UpgradeFrontend (copy)
local isCutscenePlaying = FUNC(function() return Variables.CutscenePlaying == true end) --[[ Line: 89 ]] -- upvalues: Variables (copy)
local isTrading = FUNC(function() return Variables.Trading == true end) --[[ Line: 90 ]] -- upvalues: Variables (copy)
local isPlaza = FUNC(function() return PlaceFile.IsTrading end) --[[ Line: 91 ]] -- upvalues: PlaceFile (copy)
local isMain = FUNC(function() return PlaceFile.IsMain end) --[[ Line: 92 ]] -- upvalues: PlaceFile (copy)
local notMain = NOT(isMain)
local neverRolled = NOT(HAS_ROLLS(1))
local upgradesUnlocked = AND(HAS_ROLLS(4), FUNC(function() return not UpgradeCmds.HasClickedUpgrades() end)) --[[ Line: 95 ]] -- upvalues: UpgradeCmds (copy)
local noDiamonds = NOT(hasDiamonds)
local isRolling = FUNC(function() return Variables.Locks.Rolling:IsLocked() end) --[[ Line: 97 ]] -- upvalues: Variables (copy)
local isntRolling = NOT(isRolling)
local notShowRoll = OR(IS_LOCKED(rollingAnimationUI), isAutoRolling)
local shoingRoll = NOT(notShowRoll)
local rollingCurrently = OR(isRolling, notShowRoll)
local notRolling = NOT(rollingCurrently)
local cutsceneInactive = NOT(isCutscenePlaying)
local notificationTopNotShowing = NOT((FUNC(function() return NotificationCmds.IsTopShowing() end))) --[[ Line: 104 ]] -- upvalues: NotificationCmds (copy)
local rebirthPlaying = IS_LOCKED(Variables.Locks.LevelRebirthPlaying)

local shouldShowMisc = OR(
	AND(NOT_LOCKED(hideUI), notRolling, cutsceneInactive), 
	AND(rollingCurrently, isHiddenRolling, upgradesDisabled, NOT_LOCKED(pauseEverything), cutsceneInactive), 
	AND(rollingCurrently, isStoppingHiddenRoll, upgradesDisabled, NOT_LOCKED(pauseEverything), cutsceneInactive)
)

local hideAll = FUNC(function() return hideAllUI:IsLocked() end) --[[ Line: 113 ]] -- upvalues: hideAllUI (copy)
local shouldShowCurrency = AND(HAS_UPGRADE("Root"), NOT(rebirthPlaying), cutsceneInactive, OR(shouldShowMisc, IS_LOCKED(showCurrencyUI), isAutoRolling))
local scrollsInactive = NOT((FUNC(function()  return ItemScrollCmds.IsActive() end))) --[[ Line: 115 ]] -- upvalues: ItemScrollCmds (copy)

local isRiding = IS_LOCKED(Variables.Locks.TitanicRiding)
local isntRiding = NOT(isRiding)

local fishingActive = FUNC(function() --[[ Line: 120 ]] -- upvalues: Signal (copy), UpgradeFrontend (copy)
	return Signal.Invoke("Fishing_IsFishing") 
	or UpgradeFrontend.IsOnGroup("Fishing") 
	or Signal.Invoke("CustomMerchant_IsOpen", "FishingMerchant")
end) 

local eventActive = FUNC(function()   --[[ Line: 126 ]] -- upvalues: EventUtil (copy), UpgradeCmds (copy)
    local rootId = EventUtil.GetEventRootId()
    if rootId == nil then
        return false 
	end 
	return UpgradeCmds.IsUnlocked(rootId)
end)  

local finishedTutorial = FUNC(function() --[[ Line: 134 ]] -- upvalues: Save (copy)
    local save = Save.Get()
    if not save then
        return false 
    end
	return save.TotalRolls >= 4
end)

local LOGIC = {
	[boostsFrame] = OR(shouldShowMisc, isHiddenRolling, isStoppingHiddenRoll), 
	---
	[toolsFrame] = shouldShowMisc, 
	---
	[bottonRightFrame] = AND(shouldShowMisc, finishedTutorial), 
	---
	[ranksFrame] = AND(upgradesDisabled, HAS_UPGRADE("Root"), scrollsInactive, NOT_LOCKED(pauseEverything), cutsceneInactive, isMain), 
	---
    [scrollFrame] = AND(NOT_LOCKED(pauseEverything), cutsceneInactive, NOT(hideAll)), 
    ---
	[levelsFrame] = AND(NOT(hideAll), NOT(upgradesActive), HAS_UPGRADE("Leveling")), 
	---
	[petsButton] = AND(NOT_LOCKED(Variables.Locks.ForceRollingAnimationUI), shouldShowMisc, HAS_UPGRADE("Inventory")), 
	---
	[upgradesButton] = AND(NOT_LOCKED(Variables.Locks.ForceRollingAnimationUI), shouldShowMisc, finishedTutorial, NOT(isPlaza)), 
	---
	[rollButton] = AND(
		NOT_LOCKED(Variables.Locks.ForceRollingAnimationUI),
		NOT(isPlaza), 
		OR(AND(notShowRoll, isHiddenRolling, upgradesDisabled, NOT_LOCKED(pauseEverything)),
		   AND(NOT_LOCKED(hideUI), NOT_LOCKED(rollingAnimationUI),
		   NOT_LOCKED(pauseEverything)),
		   AND(notShowRoll, isStoppingHiddenRoll, upgradesDisabled,
				NOT_LOCKED(pauseEverything)
			)
		)
	), 
	---
	[toolCloseButton] = AND(isRiding, shouldShowMisc), 
	---
	[desktopCoinsFrame] = AND(notMobile, shouldShowCurrency, NOT(isTrading)), 
	---
	[coinsFrame] = AND(isMobile, shouldShowCurrency, NOT(isTrading), notificationTopNotShowing), 
	---
	[desktopDiamondsFrame] = AND(notMobile, hasDiamonds, shouldShowCurrency), 
	---
	[diamondsFrame] = AND(isMobile, hasDiamonds, shouldShowCurrency, notificationTopNotShowing), 
	---
	[desktopFishingFrame] = AND(fishingActive, notMobile, shouldShowCurrency, NOT(isTrading)),
	---
	[fishingFrame] = AND(fishingActive, isMobile, shouldShowCurrency, NOT(isTrading), notificationTopNotShowing), 
	---
	[desktopEventFrame] = AND(notMobile, eventActive, shouldShowCurrency), 
	---
	[eventFrame] = AND(isMobile, eventActive, shouldShowCurrency), 
	---
	[autoRollButton] = AND(HAS_UPGRADE("Auto Roll"), notShowRoll, isRollingVisible, isStillRolling, isBonusRolling, cutsceneInactive), 
	---
	[hideRollsButton] = AND(HAS_UPGRADE("Hide Rolls"), notShowRoll, isRollingVisible, isAutoRolling, isStillRolling, cutsceneInactive), 
	---
	[rollArrow] = AND(shouldShowMisc, neverRolled), 
	---
	[upgradeArrow] = AND(shouldShowMisc, upgradesUnlocked), 
	---
    [rollTitle] = AND(shouldShowMisc, NOT(upgradesUnlocked))
}

LogicTree.Setup(LOGIC)
