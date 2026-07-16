-- ====================================================================
-- HEADLESS IDENTITY, AVATAR & INSPECT SPOOFER (FINALIZED)
-- ====================================================================

print("[Daemon] Pulling settings and initializing spoofer...")

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local localPlayer = Players.LocalPlayer

local realUsername = localPlayer.Name
local realDisplayName = localPlayer.DisplayName
local realUserId = localPlayer.UserId

local function escapePattern(str)
	return str:gsub("([^%w])", "%%%1")
end

local function getSetting(name, default)
	local env = (type(getgenv) == "function" and getgenv()) or {}
	if env[name] ~= nil then return env[name] end
	return default
end

local function getTargetId() return tonumber(getSetting("SpoofTargetId", 2611776)) end
local function getSpoofUsername() return tostring(getSetting("SpoofUsername", "Roblox")) end
local function getSpoofDisplayName() return tostring(getSetting("SpoofDisplayName", "OfficialRoblox")) end
local function isHeadlessEnabled() return (getSetting("Headless", false) == true) end

-- ==========================================
-- 1. CLIENT-SIDE AVATAR MORPH
-- ==========================================
local function swapAvatarLocally()
	local character = localPlayer.Character
	if not character then return end
	local targetId = getTargetId()
	local success, targetModel = pcall(function() return Players:CreateHumanoidModelFromUserId(targetId) end)
	if not success or not targetModel then return end
	
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Accessory") or child:IsA("Clothing") or child:IsA("ShirtGraphic") or child:IsA("BodyColors") then
			child:Destroy()
		end
	end
	
	for _, child in ipairs(targetModel:GetChildren()) do
		if child:IsA("Clothing") or child:IsA("ShirtGraphic") or child:IsA("BodyColors") then
			child:Clone().Parent = character
		end
	end
	
	-- Handle Headless / Accessories
	for _, child in ipairs(targetModel:GetChildren()) do
		if child:IsA("Accessory") then
			local clone = child:Clone()
			clone.Parent = character
		end
	end
	targetModel:Destroy()
end

-- ==========================================
-- 2. UI SPOOFER
-- ==========================================
local function replaceCoreElements()
	local success, CoreGui = pcall(function() return game:GetService("CoreGui") end)
	if not success then return end

	local function processDescendant(desc)
		if desc:IsA("TextLabel") then
			desc.Text = string.gsub(desc.Text, realUsername, getSpoofUsername())
		end
	end

	CoreGui.DescendantAdded:Connect(processDescendant)
end

-- ==========================================
-- 3. STABILIZED INSPECT SPOOFER
-- ==========================================
local successHook, err = pcall(function()
    local function showSpoofedInspect()
        local success, desc = pcall(function() return Players:GetHumanoidDescriptionFromUserId(getTargetId()) end)
        if success and desc then
            GuiService:InspectPlayerFromHumanoidDescription(desc, getSpoofDisplayName())
        end
    end

    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local method = getnamecallmethod()
        local args = {...}
        
        if self == GuiService and method == "InspectPlayerFromUserId" and args[1] == localPlayer.UserId then
            showSpoofedInspect()
            return true -- Return 'true' to signal success to the engine, preventing the ipairs error
        end
        
        return oldNamecall(self, ...)
    end))
end)

-- ==========================================
-- 4. INITIALIZATION
-- ==========================================
task.spawn(swapAvatarLocally)
task.spawn(replaceCoreElements)
localPlayer.CharacterAdded:Connect(function() task.wait(0.5); swapAvatarLocally() end)

print("[Daemon] Identity Spoofer fully operational!")
