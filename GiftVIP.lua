-- GiftVIP (FIX SetAttribute nil)

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local Pending = DataStoreService:GetDataStore("PendingGift")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local GiftSomething = Remotes:WaitForChild("GiftSomething")

local ListGamepass = {
	["104638826"]  = 3466870250, -- VIP
	["104895674"]  = 3466870613, -- Vestidor++
	["104895700"]  = 3466871030, -- Pocion Enana
	["116664098"]  = 3466871867, -- Pocion Alta
	["946199287"]  = 3466872214, -- Free Camera
	["1059986260"] = 3466872459, -- Letrero
	["1059066111"] = 3466872795, -- LetreroXL
	["1059494047"] = 3466877440, -- Bazooka
	["1675727857"] = 3517857631, -- Puntosx2
	["1683786291"] = 3519028572, -- Petsx2
	["1683894302"] = 3519028970, -- Cloncito
	["1700586823"] = 3531544782,  -- Syp
}

local function clearPending(plr)
	plr:SetAttribute("GiftTargetUserId", 0)
	pcall(function()
		Pending:RemoveAsync("pending_" .. plr.UserId)
	end)
end

GiftSomething.OnServerEvent:Connect(function(plr, selectedIDUser, idGamepass, kind)
	-- Este script solo maneja regalos de gamepass (no "Points")
	if kind == "Points" then
		return
	end

	local productId = ListGamepass[tostring(idGamepass)]
	if not productId then return end

	local targetId = tonumber(selectedIDUser)
	if not targetId or targetId <= 0 then return end
	if targetId == plr.UserId then return end

	-- Guardar Pending primero (fallback para ProcessReceipt)
	pcall(function()
		Pending:SetAsync("pending_" .. plr.UserId, targetId)
	end)

	-- Atributo (usa 0 como "vacío", nunca nil)
	plr:SetAttribute("GiftTargetUserId", targetId)

	MarketplaceService:PromptProductPurchase(plr, productId)
end)

MarketplaceService.PromptProductPurchaseFinished:Connect(function(plr, productId, wasPurchased)
	if not wasPurchased then
		clearPending(plr)
	end
end)
