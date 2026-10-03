-- ====================================================================
-- HEADLESS IDENTITY & AVATAR SPOOFER v2 — RIG + BODYPART EDITION
-- [Context: Roblox Client | Luau VM | Windows x86-64]
-- ====================================================================
-- INVENTORY:
--   Entry point  : task.spawn(swapAvatarLocally) on init + CharacterAdded
--   Rig spoofing : detectRigType() → forceRigTransition() via HumanoidDescription
--   Body parts   : applyBodyParts() — per-limb MeshPart asset swap
--   Body scale   : applyBodyScale() — Humanoid property mirror from target
--   Accessories  : weldAccessory() — attachment-aligned weld engine (unchanged + extended)
--   UI spoof     : replaceCoreElements() — CoreGui text/image intercept
--   Metatable    : __index + __namecall hooks for UserId/Name/DisplayName/Inspect
--   Privileges   : LocalScript-level (executor injection required)
--   Side effects : Character model mutated in-place; server sees original
-- ====================================================================

print("[Daemon] Pulling settings and initializing spoofer v2...")

local Players          = game:GetService("Players")
local GuiService       = game:GetService("GuiService")
local RunService       = game:GetService("RunService")
local localPlayer      = Players.LocalPlayer

local realUsername     = localPlayer.Name
local realDisplayName  = localPlayer.DisplayName

-- ==========================================
-- UTIL
-- ==========================================

local function escapePattern(str)
    return str:gsub("([^%w])", "%%%1")
end

local function getSetting(name, default)
    local env = (type(getgenv) == "function" and getgenv()) or {}
    if env[name] ~= nil then return env[name] end
    return default
end

local function getTargetId()          return tonumber(getSetting("SpoofTargetId", 2611776)) end
local function getSpoofUsername()     return tostring(getSetting("SpoofUsername", "Roblox")) end
local function getSpoofDisplayName()  return tostring(getSetting("SpoofDisplayName", "OfficialRoblox")) end
local function isHeadlessEnabled()
    local val = getSetting("Headless", false)
    return val == true
end

-- ==========================================
-- 1. RIG TYPE DETECTION
-- ==========================================
-- *Detects R6 vs R15 by counting torso parts in a HumanoidDescription-loaded model.*
-- R6  → single "Torso" BasePart, 6 total limb parts
-- R15 → "UpperTorso" + "LowerTorso", 15 total limb parts

local RIG_R6  = "R06"
local RIG_R15 = "R15"

local function detectRigType(model)
    -- *I sniff the skeleton by presence of R15-exclusive parts.*
    if model:FindFirstChild("UpperTorso") and model:FindFirstChild("LowerTorso") then
        return RIG_R15
    elseif model:FindFirstChild("Torso") then
        return RIG_R6
    end
    -- Fallback: count motor6d joints in humanoid root
    local root = model:FindFirstChild("HumanoidRootPart")
    if root then
        local motorCount = 0
        for _, v in ipairs(model:GetDescendants()) do
            if v:IsA("Motor6D") then motorCount = motorCount + 1 end
        end
        return motorCount >= 10 and RIG_R15 or RIG_R6
    end
    return RIG_R15 -- safe default
end

local function getLocalRigType()
    local char = localPlayer.Character
    if not char then return RIG_R15 end
    return detectRigType(char)
end

-- ==========================================
-- 2. BODY SCALE SPOOFING (R15 ONLY)
-- ==========================================
-- Reads Humanoid body scale properties from target description and
-- mirrors them onto the local Humanoid. R6 has no scale props; skip.
--
-- Humanoid scale channels:
--   BodyDepthScale   → Z-axis depth  (chest thickness)
--   BodyHeightScale  → Y-axis height
--   BodyWidthScale   → X-axis width  (shoulder breadth)
--   HeadScale        → uniform head multiplier

local SCALE_CHANNELS = {
    "BodyDepthScale",
    "BodyHeightScale",
    "BodyWidthScale",
    "HeadScale",
}

local function applyBodyScale(targetDescription, localHumanoid)
    -- *Each channel is a NumberValue child of Humanoid; we write directly.*
    if not targetDescription or not localHumanoid then return end
    local rigType = getLocalRigType()
    if rigType == RIG_R6 then
        -- R6 ignores scale entirely; motor positions are fixed in the rig.
        print("[Daemon] R6 rig detected — skipping body scale (not supported).")
        return
    end

    for _, channel in ipairs(SCALE_CHANNELS) do
        local descValue = targetDescription[channel]  -- numeric property on HumanoidDescription
        local scaleValue = localHumanoid:FindFirstChild(channel)
        if scaleValue and descValue then
            -- *Writing to the NumberValue ticks the scale channel immediately.*
            scaleValue.Value = descValue
        elseif descValue then
            -- Humanoid sometimes exposes scale as direct property (newer engine builds)
            pcall(function() localHumanoid[channel] = descValue end)
        end
    end

    print(string.format(
        "[Daemon] Body scale applied — H:%.2f W:%.2f D:%.2f Head:%.2f",
        targetDescription.BodyHeightScale or 1,
        targetDescription.BodyWidthScale  or 1,
        targetDescription.BodyDepthScale  or 1,
        targetDescription.HeadScale       or 1
    ))
end

-- ==========================================
-- 3. BODY PART MESH SPOOFING
-- ==========================================
-- Roblox body parts are MeshPart instances inside the character model.
-- HumanoidDescription carries asset IDs per body part slot.
-- We swap the MeshId + TextureId on each local part.
--
-- R15 part slots → character children names:
local R15_PARTS = {
    Head            = "Head",
    UpperTorso      = "UpperTorso",
    LowerTorso      = "LowerTorso",
    LeftUpperArm    = "LeftUpperArm",
    LeftLowerArm    = "LeftLowerArm",
    LeftHand        = "LeftHand",
    RightUpperArm   = "RightUpperArm",
    RightLowerArm   = "RightLowerArm",
    RightHand       = "RightHand",
    LeftUpperLeg    = "LeftUpperLeg",
    LeftLowerLeg    = "LeftLowerLeg",
    LeftFoot        = "LeftFoot",
    RightUpperLeg   = "RightUpperLeg",
    RightLowerLeg   = "RightLowerLeg",
    RightFoot       = "RightFoot",
}

-- R6 part slots
local R6_PARTS = {
    Head            = "Head",
    Torso           = "Torso",
    ["Left Arm"]    = "Left Arm",
    ["Right Arm"]   = "Right Arm",
    ["Left Leg"]    = "Left Leg",
    ["Right Leg"]   = "Right Leg",
}

-- HumanoidDescription asset ID properties per R15 slot
-- Format: { MeshAsset = "property name", TextureAsset = "property name" }
local DESC_ASSET_MAP = {
    Head          = { mesh = nil,              texture = nil },           -- handled via Decal
    UpperTorso    = { mesh = "TorsoColor",     texture = nil },           -- colors not mesh IDs
    LowerTorso    = { mesh = "WaistColor",     texture = nil },
    LeftUpperArm  = { mesh = "LeftArmColor",   texture = nil },
    RightUpperArm = { mesh = "RightArmColor",  texture = nil },
    LeftUpperLeg  = { mesh = "LeftLegColor",   texture = nil },
    RightUpperLeg = { mesh = "RightLegColor",  texture = nil },
}

-- Body color channel map: HumanoidDescription.HeadColor → "Head", etc.
local BODY_COLOR_MAP = {
    Head          = "HeadColor",
    UpperTorso    = "TorsoColor",
    LowerTorso    = "TorsoColor",
    LeftUpperArm  = "LeftArmColor",
    LeftLowerArm  = "LeftArmColor",
    LeftHand      = "LeftArmColor",
    RightUpperArm = "RightArmColor",
    RightLowerArm = "RightArmColor",
    RightHand     = "RightArmColor",
    LeftUpperLeg  = "LeftLegColor",
    LeftLowerLeg  = "LeftLegColor",
    LeftFoot      = "LeftLegColor",
    RightUpperLeg = "RightLegColor",
    RightLowerLeg = "RightLegColor",
    RightFoot     = "RightLegColor",
    Torso         = "TorsoColor",
    ["Left Arm"]  = "LeftArmColor",
    ["Right Arm"] = "RightArmColor",
    ["Left Leg"]  = "LeftLegColor",
    ["Right Leg"] = "RightLegColor",
}

local function applyBodyParts(targetModel, targetDescription, localCharacter, localRig)
    -- *We're doing a per-limb surgical swap: mesh geometry + surface color.*
    -- MeshPart.MeshId and .TextureID can be written freely from executor context.

    local partMap = localRig == RIG_R6 and R6_PARTS or R15_PARTS

    for partName, _ in pairs(partMap) do
        local localPart   = localCharacter:FindFirstChild(partName)
        local targetPart  = targetModel:FindFirstChild(partName)

        if not localPart or not targetPart then continue end

        -- Swap MeshId if both are MeshParts (R15) or SpecialMesh carriers (R6)
        if localPart:IsA("MeshPart") and targetPart:IsA("MeshPart") then
            -- *MeshId is the raw asset URI — swap the geometry atom.*
            pcall(function() localPart.MeshId    = targetPart.MeshId    end)
            pcall(function() localPart.TextureID = targetPart.TextureID end)
            pcall(function() localPart.Size      = targetPart.Size      end)

        elseif localPart:IsA("BasePart") then
            -- R6: parts may be BasePart+SpecialMesh combo
            local localMesh  = localPart:FindFirstChildOfClass("SpecialMesh")
            local targetMesh = targetPart:FindFirstChildOfClass("SpecialMesh")
            if localMesh and targetMesh then
                pcall(function() localMesh.MeshId    = targetMesh.MeshId    end)
                pcall(function() localMesh.TextureId = targetMesh.TextureId end)
                pcall(function() localMesh.Scale     = targetMesh.Scale     end)
            end
        end

        -- Apply body color from HumanoidDescription
        if targetDescription then
            local colorProp = BODY_COLOR_MAP[partName]
            if colorProp then
                local brickColor = targetDescription[colorProp]
                if brickColor then
                    pcall(function() localPart.BrickColor = brickColor end)
                end
            end
        end
    end

    print("[Daemon] Body part meshes + colors applied for rig: " .. localRig)
end

-- ==========================================
-- 4. RIG TYPE MISMATCH HANDLER
-- ==========================================
-- If local rig ≠ target rig, we can't directly swap the skeleton.
-- Best client-side approach: apply HumanoidDescription directly via
-- Humanoid:ApplyDescription() — this is an official API that mutates
-- the local character's rig geometry and motor layout.
-- Server still sees original; this is pure visual.

local function applyDescriptionToLocal(targetDescription)
    local char = localPlayer.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    local ok, err = pcall(function()
        -- *ApplyDescription() is the nuclear option: it replaces the entire
        -- visual shell of the character. Body parts, clothes, accessories, scale.*
        hum:ApplyDescription(targetDescription)
    end)

    if ok then
        print("[Daemon] HumanoidDescription applied via Humanoid:ApplyDescription().")
    else
        warn("[Daemon] ApplyDescription() failed: " .. tostring(err))
        warn("[Daemon] Falling back to manual part swap.")
    end

    return ok
end

-- ==========================================
-- 5. HEADLESS LOGIC (EXTENDED)
-- ==========================================

local function applyHeadless(character, targetModel)
    local head = character:FindFirstChild("Head")
    if not head then return end

    local makeHeadless = isHeadlessEnabled()

    -- Auto-detect from target model
    if not makeHeadless then
        local targetHead = targetModel and targetModel:FindFirstChild("Head")
        if not targetHead then
            makeHeadless = true
        elseif targetHead.Transparency >= 0.95 then
            makeHeadless = true
        else
            local mesh = targetHead:FindFirstChildOfClass("SpecialMesh")
            if mesh and (mesh.Scale.X == 0 or mesh.MeshId == "" or mesh.MeshId == "rbxassetid://134079802") then
                makeHeadless = true
            end
        end
    end

    if makeHeadless then
        -- *The head goes dark: transparency 1, mesh scale zeroed, face decal nuked.*
        head.Transparency = 1
        local face = head:FindFirstChild("face") or head:FindFirstChildOfClass("Decal")
        if face then face:Destroy() end
        local mesh = head:FindFirstChildOfClass("SpecialMesh") or Instance.new("SpecialMesh", head)
        mesh.Scale = Vector3.new(0, 0, 0)
        print("[Daemon] Headless mode engaged.")
    else
        -- Restore face from target
        if targetModel then
            local targetHead = targetModel:FindFirstChild("Head")
            if targetHead then
                local targetFace = targetHead:FindFirstChild("face") or targetHead:FindFirstChildOfClass("Decal")
                if targetFace then targetFace:Clone().Parent = head end
                local localMesh  = head:FindFirstChildOfClass("SpecialMesh")
                local targetMesh = targetHead:FindFirstChildOfClass("SpecialMesh")
                if localMesh and targetMesh then
                    localMesh.MeshId = targetMesh.MeshId
                    localMesh.Scale  = targetMesh.Scale
                end
            end
        end
    end
end

-- ==========================================
-- 6. ACCESSORY WELD ENGINE (UNCHANGED + R6 PATCH)
-- ==========================================

local function weldAccessory(accessory, character)
    local handle = accessory:FindFirstChild("Handle")
    if not handle or not handle:IsA("BasePart") then return end

    for _, v in ipairs(handle:GetChildren()) do
        if v:IsA("Weld") or v:IsA("ManualWeld") or v:IsA("WeldConstraint") then
            v:Destroy()
        end
    end

    local accAttachment  = handle:FindFirstChildOfClass("Attachment")
    local charAttachment = nil

    if accAttachment then
        for _, part in ipairs(character:GetChildren()) do
            if part:IsA("BasePart") then
                local found = part:FindFirstChild(accAttachment.Name)
                if found and found:IsA("Attachment") then
                    charAttachment = found
                    break
                end
            end
        end
    end

    local attachPart = charAttachment and charAttachment.Parent
    if not attachPart then
        -- R6 fallback: weld to Head or Torso
        attachPart = character:FindFirstChild("Head") or character:FindFirstChild("Torso")
    end

    if attachPart then
        handle.CanCollide = false
        handle.Anchored   = false
        if charAttachment and accAttachment then
            handle.CFrame = charAttachment.WorldCFrame * accAttachment.CFrame:Inverse()
        else
            handle.CFrame = attachPart.CFrame
        end

        local weld  = Instance.new("Weld")
        weld.Name   = "AccessoryWeld"
        weld.Part0  = handle
        weld.Part1  = attachPart
        if charAttachment and accAttachment then
            weld.C0 = accAttachment.CFrame
            weld.C1 = charAttachment.CFrame
        else
            weld.C0 = CFrame.new(0, 0.6, 0)
            weld.C1 = CFrame.new()
        end
        weld.Parent = handle
    end
end

-- ==========================================
-- 7. MAIN AVATAR SWAP ORCHESTRATOR
-- ==========================================

local function swapAvatarLocally()
    local character = localPlayer.Character
    if not character then return end

    local targetId = getTargetId()

    -- Fetch full HumanoidDescription for target
    local descOk, targetDescription = pcall(function()
        return Players:GetHumanoidDescriptionFromUserId(targetId)
    end)
    if not descOk or not targetDescription then
        warn("[Daemon] Failed to fetch HumanoidDescription for ID: " .. tostring(targetId))
        return
    end

    -- Fetch full model for geometry sampling
    local modelOk, targetModel = pcall(function()
        return Players:CreateHumanoidModelFromUserId(targetId)
    end)

    local localRig    = getLocalRigType()
    local targetRig   = (modelOk and targetModel) and detectRigType(targetModel) or localRig

    print(string.format("[Daemon] Local rig: %s | Target rig: %s", localRig, targetRig))

    -- Strip existing clothing/accessories
    for _, child in ipairs(character:GetChildren()) do
        if child:IsA("Accessory") or child:IsA("Clothing")
           or child:IsA("ShirtGraphic") or child:IsA("BodyColors") then
            child:Destroy()
        end
    end

    -- Primary path: ApplyDescription (handles rig mismatch + scale + parts atomically)
    local descApplied = applyDescriptionToLocal(targetDescription)

    if not descApplied and modelOk and targetModel then
        -- Fallback: manual mesh swap + scale + color
        applyBodyParts(targetModel, targetDescription, character, localRig)
        applyBodyScale(targetDescription, character:FindFirstChildOfClass("Humanoid"))

        -- Copy clothing layers
        for _, child in ipairs(targetModel:GetChildren()) do
            if child:IsA("Clothing") or child:IsA("ShirtGraphic") or child:IsA("BodyColors") then
                child:Clone().Parent = character
            end
        end

        -- Weld accessories
        for _, child in ipairs(targetModel:GetChildren()) do
            if child:IsA("Accessory") then
                local clone = child:Clone()
                clone.Parent = character
                weldAccessory(clone, character)
            end
        end
    end

    -- Headless pass (runs after ApplyDescription to override face back to invisible)
    if modelOk and targetModel then
        applyHeadless(character, targetModel)
        targetModel:Destroy()
    end

    print("[Daemon] Avatar swap complete.")
end

-- ==========================================
-- 8. LEADERBOARD / ESC MENU UI SPOOF
-- ==========================================

local function replaceCoreElements()
    local coreSuccess, CoreGui = pcall(function() return game:GetService("CoreGui") end)
    if not coreSuccess or not CoreGui then
        warn("[Daemon] CoreGui blocked — UI rename disabled.")
        return
    end

    local function handleImageLabel(imageLabel)
        local function updateImage()
            local imageStr      = imageLabel.Image
            local realIdStr     = tostring(localPlayer.UserId)
            local targetIdStr   = tostring(getTargetId())
            local base          = "rbxthumb://type="
            if imageStr ~= "" and string.find(imageStr, "id=" .. realIdStr) then
                if string.find(imageStr, "type=Avatar&") then
                    imageLabel.Image = base .. "Avatar&id=" .. targetIdStr .. "&w=352&h=352"
                elseif string.find(imageStr, "type=AvatarBust") then
                    imageLabel.Image = base .. "AvatarBust&id=" .. targetIdStr .. "&w=150&h=150"
                elseif string.find(imageStr, "type=AvatarHeadShot") then
                    imageLabel.Image = base .. "AvatarHeadShot&id=" .. targetIdStr .. "&w=150&h=150"
                end
            end
        end
        pcall(updateImage)
        imageLabel:GetPropertyChangedSignal("Image"):Connect(function() pcall(updateImage) end)
    end

    local function handleTextLabel(textLabel)
        local function updateText()
            local cur = textLabel.Text
            if cur == "" then return end
            local u  = getSpoofUsername()
            local d  = getSpoofDisplayName()
            local t  = cur
            t = string.gsub(t, "@" .. realUsername,           "@" .. u)
            t = string.gsub(t, escapePattern(realDisplayName), d)
            t = string.gsub(t, realUsername,                   u)
            if t ~= cur then textLabel.Text = t end
        end
        pcall(updateText)
        textLabel:GetPropertyChangedSignal("Text"):Connect(function() pcall(updateText) end)
    end

    local function processDescendant(desc)
        if desc:IsA("ImageLabel") then handleImageLabel(desc)
        elseif desc:IsA("TextLabel") then handleTextLabel(desc) end
    end

    pcall(function()
        for _, desc in ipairs(CoreGui:GetDescendants()) do processDescendant(desc) end
    end)
    CoreGui.DescendantAdded:Connect(function(desc) pcall(processDescendant, desc) end)
    print("[Daemon] Core UI listeners mounted.")
end

-- ==========================================
-- 9. METATABLE HOOKS
-- ==========================================

local rawMetatable = getrawmetatable and getrawmetatable(game)
if rawMetatable and makewriteable then
    makewriteable(rawMetatable)
    local oldIndex    = rawMetatable.__index
    local oldNamecall = rawMetatable.__namecall

    rawMetatable.__index = newcclosure(function(self, key)
        -- *Filter: only intercept reads on localPlayer; everything else falls through.*
        if not checkcaller() and self == localPlayer then
            if key == "UserId"      then return getTargetId()         end
            if key == "Name"        then return getSpoofUsername()     end
            if key == "DisplayName" then return getSpoofDisplayName()  end
        end
        return oldIndex(self, key)
    end)

    rawMetatable.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        if self == GuiService and (method == "InspectPlayerFromUserId"
            or method == "InspectPlayerFromHumanoidDescription") then
            local args = {...}
            if args[1] == localPlayer.UserId or args[1] == getTargetId() then
                return oldNamecall(self, getTargetId(), table.unpack(args, 2))
            end
        end
        return oldNamecall(self, ...)
    end)

    print("[Daemon] Metatable hooks active.")
else
    warn("[Daemon] Metatable hooking not supported on this executor.")
end

-- ==========================================
-- 10. BOOT
-- ==========================================

task.spawn(swapAvatarLocally)
task.spawn(replaceCoreElements)

localPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    task.spawn(swapAvatarLocally)
end)

print("[Daemon] Identity Spoofer v2 fully operational.")
