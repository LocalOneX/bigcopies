--[=[
    @LocalOneX
    @BIG Copies @1/16/2025
    @LogicTree.luau
--]=]

local module = {}

local CountedLock = require(game.ReplicatedStorage.Library.Modules.CountedLock)
local UpgradeCmds = require(game.ReplicatedStorage.Library.Client.UpgradeCmds)
local EggCmds = require(game.ReplicatedStorage.Library.Client.EggCmds)
local Variables = require(game.ReplicatedStorage.Library.Variables)

--- Reference
local RunService = game:GetService("RunService")

local LOGIC = {
    AND = 1, 
    OR = 2, 
    NOT = 3, 
    VALUE = 4, 
    FUNC = 5
}
local cachedLocks = {}

local function eval(val) --[[ Line: 26 ]] --[[ Name: eval ]] -- upvalues: LOGIC (copy)
	--- extract value
    if val.Type == LOGIC.VALUE then
        return val.Value:IsLocked()
    elseif val.Type == LOGIC.AND then
        local isLocked = true
        for i, value in ipairs(val.Value) do
			if not eval(value) then 
                return false
            end
        end
        return isLocked
    elseif val.Type == LOGIC.OR then
        local isLocked = false
        for i, value in ipairs(val.Value) do
            if eval(value) then
                return true
            end
        end
        return isLocked
    elseif val.Type == LOGIC.NOT then
        return not eval(val.Value)
    elseif val.Type == LOGIC.FUNC then
        return val.Value() 
	end
	
	error("unreachable")
end

local function AND(...) --[[ Line: 55 ]] --[[ Name: AND ]] -- upvalues: LOGIC (copy) 
	return {
		Type = LOGIC.AND, 
		Value = {...}
	}
end 

local function OR(...) --[[ Line: 62 ]] --[[ Name: OR ]] -- upvalues: LOGIC (copy)  
	return {
		Type = LOGIC.OR, 
		Value = {...}
	}
end

function NOT(value) --[[ Line: 69 ]] --[[ Name: NOT ]] -- upvalues: LOGIC (copy)
	return {
		Type = LOGIC.NOT, 
		Value = value
	}
end

local function IS_LOCKED(lock) --[[ Line: 76 ]] --[[ Name: IS_LOCKED ]] -- upvalues: cachedLocks (copy), LOGIC (copy)
    if not cachedLocks[lock] then
        cachedLocks[lock] = true
    end
    return {
        Type = LOGIC.VALUE, 
        Value = lock
    }
end

local function NOT_LOCKED(lock) --[[ Line: 86 ]] --[[ Name: NOT_LOCKED ]] -- upvalues: cachedLocks (copy)
    if not cachedLocks[lock] then
        cachedLocks[lock] = true
	end 
    return NOT(IS_LOCKED(lock))
end

local function FUNC(value) --[[ Line: 93 ]] --[[ Name: FUNC ]] -- upvalues: LOGIC (copy)
    return {
        Type = LOGIC.FUNC, 
        Value = value
    }
end

local function HAS_UPGRADE(upgrade) --[[ Line: 100 ]] --[[ Name: HAS_UPGRADE ]] -- upvalues: UpgradeCmds (copy)
    return FUNC(function() --[[ Line: 101 ]] -- upvalues: UpgradeCmds (ref), upgrade (copy)
        return UpgradeCmds.IsUnlocked(upgrade)
    end)
end

local function HAS_ROLLS(rollsCount) --[[ Line: 106 ]] --[[ Name: HAS_ROLLS ]] -- upvalues: EggCmds (copy)
    return FUNC(function() --[[ Line: 107 ]] -- upvalues: EggCmds (ref), rollsCount (copy)
        return EggCmds.GetTotalRolls() >= rollsCount
    end)
end

function setup(evals) --[[ Line: 112 ]] --[[ Name: setup ]] -- upvalues: Variables (copy), cachedLocks (copy), RunService (copy)
    local hideAllUI = Variables.Locks.HideAllUI
    local function recompute() --[[ Line: 114 ]] --[[ Name: recompute ]] -- upvalues: hideAllUI (copy), evals (copy)
        local hideAll = hideAllUI:IsLocked()
        for frame, val in pairs(evals) do
            frame.Visible = eval(val) and not hideAll
        end
	end 
    recompute()
    local needsRecompute = false
    for frame, val in pairs(cachedLocks) do
        frame.StatusChanged:Connect(function() --[[ Line: 123 ]] -- upvalues: needsRecompute (ref)
            needsRecompute = true
        end)
    end
    local _t = 0
    RunService.RenderStepped:Connect(function(delta) --[[ Line: 128 ]] -- upvalues: _t (ref), needsRecompute (ref), recompute (copy)
        _t = _t + delta
        if _t > 0.05 or needsRecompute then
            recompute()
            _t = 0
            needsRecompute = false
        end
    end)
end

return {
    AND = AND, 
    OR = OR, 
    NOT = NOT, 
    IS_LOCKED = IS_LOCKED, 
    NOT_LOCKED = NOT_LOCKED, 
    HAS_UPGRADE = HAS_UPGRADE, 
    HAS_ROLLS = HAS_ROLLS, 
    FUNC = FUNC, 
    Eval = eval, 
	Setup = setup,
	AND_ = AND_
}
