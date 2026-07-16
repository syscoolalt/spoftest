-- ====================================================================
-- HEADLESS IDENTITY, AVATAR & INSPECT SPOOFER (EXECUTION CODE)
-- Upload this entire block to your GitHub raw link!
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

-- Resolve dynamic environment settings set by the user's loadstring
local function getSetting(name, default)
	local env = (type(getgenv) == "function" and getgenv()) or {}
	if env[name] ~= nil then
		return env[name]
	end
	return default
end

local function getTargetId() return tonumber(getSetting("SpoofTargetId", 2611776)) end
local function getSpoofUsername() return tostring(getSetting("SpoofUsername", "Roblox")) end
local function getSpoofDisplayName() return tostring(getSetting("SpoofDisplayName", "OfficialRoblox")) end
local function isHeadlessEnabled() return (getSetting("Headless", false) == true) end
local function isEmptyInspectEnabled() return (getSetting("EmptyInspect", false) == true) end

-- ==========================================
-- 1. CLIENT-SIDE AVATAR MORPH
-- ==========================================
local function swapAvatarLocally()
	local character = localPlayer.Character
	if not character then return end
	
	local targetId = getTargetId()
	local success, targetModel = pcall(function()
		return Players:CreateHumanoidModelFromUserId(targetId)
	end)
	
	if not success or not targetModel then 
		warn("[Daemon] Failed to fetch assets for Target ID: " .. tostring(targetId))
		return 
	end
	
	-- Strip current accessories, clothes, body colors, and face elements
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Accessory") or child:IsA("Clothing") or child:IsA("ShirtGraphic") or child:IsA("BodyColors") then
			child:Destroy()
		end
	end
	
	local head = character:FindFirstChild("Head")
	if head then
		local face = head:FindFirstChild("face") or head:FindFirstChildOfClass("Decal")
		if face then face:Destroy() end
		head.Transparency = 0
	end
	
	-- Copy basic character features (Clothing, Colors, T-Shirts)
	for _, child in ipairs(targetModel:GetChildren()) do
		if child:IsA("Clothing") or child:IsA("ShirtGraphic") or child:IsA("BodyColors") then
			child:Clone().Parent = character
		end
	end
	
	-- Determine Headless status
	local targetHead = targetModel:FindFirstChild("Head")
	local makeHeadless = isHeadlessEnabled()
	
	if not makeHeadless and targetHead then
		if targetHead.Transparency >= 0.95 or not targetHead:FindFirstChildOfClass("Decal") then
			local headMesh = targetHead:FindFirstChildOfClass("SpecialMesh")
			if headMesh and (headMesh.Scale.X == 0 or headMesh.MeshId == "" or headMesh.MeshId == "rbxassetid://134079802") then
				makeHeadless = true
			end
		end
	elseif not makeHeadless and not targetHead then
		makeHeadless = true
	end
	
	-- Apply Headless formatting locally
	if makeHeadless and head then
		head.Transparency = 1
		local face = head:FindFirstChild("face") or head:FindFirstChildOfClass("Decal")
		if face then face:Destroy() end
		
		local headMesh = head:FindFirstChildOfClass("SpecialMesh") or Instance.new("SpecialMesh", head)
		headMesh.Scale = Vector3.new(0, 0, 0)
	else
		-- Restore normal head mesh & face texture
		if targetHead and head then
			local targetFace = targetHead:FindFirstChild("face") or targetHead:FindFirstChildOfClass("Decal")
			if targetFace then
				targetFace:Clone().Parent = head
			end
			local headMesh = head:FindFirstChildOfClass("SpecialMesh")
			local targetMesh = targetHead:FindFirstChildOfClass("SpecialMesh")
			if headMesh and targetMesh then
				headMesh.MeshId = targetMesh.MeshId
				headMesh.Scale = targetMesh.Scale
			end
		end
	end
	
	-- Advanced Accessory Attachment Engine
	local function weldAccessory(accessory)
		local handle = accessory:FindFirstChild("Handle")
		if not handle or not handle:IsA("BasePart") then return end
		
		for _, v in ipairs(handle:GetChildren()) do
			if v:IsA("Weld") or v:IsA("ManualWeld") or v:IsA("WeldConstraint") then
				v:Destroy()
			end
		end
		
		local accAttachment = handle:FindFirstChildOfClass("Attachment")
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
		
		local attachPart = charAttachment and charAttachment.Parent or character:FindFirstChild("Head")
		if attachPart then
			handle.CanCollide = false
			handle.Anchored = false
			
			if charAttachment and accAttachment then
				handle.CFrame = charAttachment.WorldCFrame * accAttachment.CFrame:Inverse()
			else
				handle.CFrame = attachPart.CFrame
			end
			
			local weld = Instance.new("Weld")
			weld.Name = "AccessoryWeld"
			weld.Part0 = handle
			weld.Part1 = attachPart
			if charAttachment and accAttachment then
				weld.C0 = accAttachment.CFrame
				weld.C1 = charAttachment.CFrame
			else
				weld.C0 = CFrame.new(0, 0.6, 0)
				weld.C1 = CFrame.new(0, 0, 0)
			end
			weld.Parent = handle
		end
	end

	for _, child in ipairs(targetModel:GetChildren()) do
		if child:IsA("Accessory") then
			local clone = child:Clone()
			clone.Parent = character
			weldAccessory(clone)
		end
	end
	
	targetModel:Destroy()
	print("[Daemon] Local character morphed successfully.")
end

-- ==========================================
-- 2. LEADERBOARD, ESC MENU, & UI SPOOFER
-- ==========================================
local function replaceCoreElements()
	local coreSuccess, CoreGui = pcall(function() return game:GetService("CoreGui") end)
	if not coreSuccess or not CoreGui then 
		warn("[Daemon] CoreGui access blocked. UI renaming disabled.")
		return 
	end

	local function handleImageLabel(imageLabel)
		local function updateImage()
			local imageStr = imageLabel.Image
			local realUserIdStr = tostring(realUserId)
			local targetUserIdStr = tostring(getTargetId())
			
			local targetHeadshot = "rbxthumb://type=AvatarHeadShot&id=" .. targetUserIdStr .. "&w=150&h=150"
			local targetBust = "rbxthumb://type=AvatarBust&id=" .. targetUserIdStr .. "&w=150&h=150"
			local targetFull = "rbxthumb://type=Avatar&id=" .. targetUserIdStr .. "&w=352&h=352"

			if imageStr ~= "" and string.find(imageStr, "id=" .. realUserIdStr) then
				if string.find(imageStr, "type=Avatar") and not string.find(imageStr, "type=AvatarBust") and not string.find(imageStr, "type=AvatarHeadShot") then
					imageLabel.Image = targetFull
				elseif string.find(imageStr, "type=AvatarBust") then
					imageLabel.Image = targetBust
				elseif string.find(imageStr, "type=AvatarHeadShot") then
					imageLabel.Image = targetHeadshot
				end
			end
		end
		pcall(updateImage)
		imageLabel:GetPropertyChangedSignal("Image"):Connect(function() pcall(updateImage) end)
	end

	local function handleTextLabel(textLabel)
		local function updateText()
			local currentText = textLabel.Text
			if currentText == "" then return end
			
			local spoofUser = getSpoofUsername()
			local spoofDisplay = getSpoofDisplayName()
			
			local updatedText = currentText
			updatedText = string.gsub(updatedText, "@" .. realUsername, "@" .. spoofUser)
			updatedText = string.gsub(updatedText, escapePattern(realDisplayName), spoofDisplay)
			updatedText = string.gsub(updatedText, realUsername, spoofUser)
			
			if updatedText ~= currentText then
				textLabel.Text = updatedText
			end
		end
		pcall(updateText)
		textLabel:GetPropertyChangedSignal("Text"):Connect(function() pcall(updateText) end)
	end

	local function processDescendant(desc)
		if desc:IsA("ImageLabel") then
			handleImageLabel(desc)
		elseif desc:IsA("TextLabel") then
			handleTextLabel(desc)
		end
	end

	pcall(function()
		for _, desc in ipairs(CoreGui:GetDescendants()) do
			processDescendant(desc)
		end
	end)

	CoreGui.DescendantAdded:Connect(function(desc)
		pcall(processDescendant, desc)
	end)
	
	print("[Daemon] Core UI listeners mounted.")
end

-- ==========================================
-- 3. INTERCEPT INDEX CORES & INSPECT MENU
-- ==========================================
-- A: Hook Metatable Indexing
local successHook, err = pcall(function()
	local oldIndex
	oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, key)
		if not checkcaller() and self == localPlayer then
			if key == "UserId" then
				return getTargetId()
			elseif key == "Name" then
				return getSpoofUsername()
			elseif key == "DisplayName" then
				return getSpoofDisplayName()
			end
		end
		return oldIndex(self, key)
	end))
end)

if successHook then
	print("[Daemon] Metatable detours applied cleanly via hookmetamethod.")
else
	warn("[Daemon] Hooking failed: " .. tostring(err))
end

-- B: Hook Inspect Menu (GuiService)
if GuiService then
	local successInspectHook, inspectErr = pcall(function()
		local oldInspect
		oldInspect = hookfunction(GuiService.InspectPlayerFromUserId, newcclosure(function(self, userId, ...)
			if not checkcaller() then
				-- If the game/core scripts try to inspect your real ID or your spoofed ID
				if userId == realUserId or userId == getTargetId() then
					if isEmptyInspectEnabled() then
						-- Redirect inspect call to a dummy account that has 0 items (e.g. ID 4)
						return oldInspect(self, 4, ...)
					else
						-- Redirect to the target ID so it inspects their actual avatar/items
						return oldInspect(self, getTargetId(), ...)
					end
				end
			end
			return oldInspect(self, userId, ...)
		end))
	end)
	
	if successInspectHook then
		print("[Daemon] Avatar inspect spoofer hook successfully mounted!")
	else
		warn("[Daemon] Failed to hook Inspect service: " .. tostring(inspectErr))
	end
end

-- ==========================================
-- 4. INITIALIZATION & SPAWN BINDINGS
-- ==========================================
task.spawn(swapAvatarLocally)
task.spawn(replaceCoreElements)

localPlayer.CharacterAdded:Connect(function()
	task.wait(0.5)
	task.spawn(swapAvatarLocally)
end)

print("[Daemon] Identity Spoofer fully operational in the background!")
