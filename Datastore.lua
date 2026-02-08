-- Datastore.server.lua 

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ServerScriptService = game:GetService("ServerScriptService")

-- =========================
-- CONFIG
-- =========================
local DATA_VERSION = "V1.0"
local DATA_STORE = DataStoreService:GetDataStore(DATA_VERSION)

-- Si quieres debugging:
local DEBUG = false
local function dprint(...)
	if DEBUG then
		print("[Datastore]", ...)
	end
end

-- =========================
-- Utilidades base
-- =========================
local function ensureFolder(parent: Instance, name: string): Folder
	local f = parent:FindFirstChild(name)
	if f and f:IsA("Folder") then return f end
	f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function ensureValue(parent: Instance, className: string, name: string)
	local v = parent:FindFirstChild(name)
	if v and v.ClassName == className then return v end
	v = Instance.new(className)
	v.Name = name
	v.Parent = parent
	return v
end

-- =========================
-- Intentar leer Gamepasses "solo para crear BoolValues"
-- (NO ejecutamos Do aquí, eso lo hace Purchases2)
-- =========================
local Gamepasses: {any}? = nil
do
	local ok, res = pcall(function()
		-- buscamos un ModuleScript llamado "Gamepasses" dentro de ServerScriptService,
		-- típicamente como hijo de Purchases2 script (script.Gamepasses).
		local mod = ServerScriptService:FindFirstChild("Gamepasses", true)
		if not mod or not mod:IsA("ModuleScript") then
			return nil
		end
		return require(mod)
	end)

	if ok and type(res) == "table" then
		Gamepasses = res
		dprint("Gamepasses module loaded; count =", #Gamepasses)
	else
		Gamepasses = nil
		warn("[Datastore] Gamepasses module NOT found/loaded. PasesInfo will be created from saved data only.")
	end
end

local function ensurePasesInfo(player: Player): Folder
	local folder = player:FindFirstChild("PasesInfo")
	if folder and folder:IsA("Folder") then
		return folder
	end

	folder = Instance.new("Folder")
	folder.Name = "PasesInfo"
	folder.Parent = player

	-- Si tenemos la lista de Gamepasses, creamos todos los BoolValue desde el inicio.
	if Gamepasses then
		for _, g in pairs(Gamepasses) do
			if g and g.Name then
				local b = Instance.new("BoolValue")
				b.Name = g.Name
				b.Value = false
				b.Parent = folder
			end
		end
	end

	return folder
end

local function setPaseFlag(player: Player, passName: string, value: boolean)
	local PasesInfo = ensurePasesInfo(player)
	local flag = PasesInfo:FindFirstChild(passName)
	if not flag or not flag:IsA("BoolValue") then
		flag = Instance.new("BoolValue")
		flag.Name = passName
		flag.Parent = PasesInfo
	end
	flag.Value = (value == true)
end

-- =========================
-- Estado interno anti-doble-load/safe-save
-- =========================
local loaded: {[number]: boolean} = {}
local saving: {[number]: boolean} = {}

local function defaultData()
	return {
		Donated = 0,
		Points = 0,        -- PuntosOLD
		NewPoints = 0,     -- leaderstats.Puntos
		SkipSongs = 0,
		Vip = false,       -- tu bool GiftVIP (no es ownership real; solo data)
		Settings = {
			Avatar = false,
			Theme = "Default",
			EquippedTag = "Default",
		},
		TagsOwned = {},
		EmotesSaved = "{}",
		Gamepass = {},     -- mapa passName->bool (solo persistencia interna)
	}
end

-- =========================
-- Construir instancia de player con data
-- =========================
local function createPlayerData(player: Player, data: any)
	data = (type(data) == "table") and data or defaultData()

	local leaderstats = ensureFolder(player, "leaderstats")
	local dataFolder = ensureFolder(player, "Datos")
	local settingsFolder = ensureFolder(dataFolder, "Ajustes")
	local tagsFolder = ensureFolder(dataFolder, "Tags")

	-- Valores principales
	local donatedValue = ensureValue(dataFolder, "IntValue", "Donado")
	local favDancesValue = ensureValue(dataFolder, "StringValue", "FavDances")
	local pointsOldValue = ensureValue(dataFolder, "IntValue", "PuntosOLD")
	local pointsValue = ensureValue(leaderstats, "IntValue", "Puntos")
	local copyValue = ensureValue(settingsFolder, "BoolValue", "Copy")
	local themeValue = ensureValue(settingsFolder, "StringValue", "Theme")
	local giftedVIPValue = ensureValue(dataFolder, "BoolValue", "GiftVIP")
	local skipSongsValue = ensureValue(dataFolder, "IntValue", "SkipSongs")

	-- Aplicar data
	donatedValue.Value = tonumber(data.Donated) or 0
	pointsOldValue.Value = tonumber(data.Points) or 0
	pointsValue.Value = tonumber(data.NewPoints) or 0
	skipSongsValue.Value = tonumber(data.SkipSongs) or 0
	giftedVIPValue.Value = (data.Vip == true)

	-- Settings
	local settings = (type(data.Settings) == "table") and data.Settings or {}
	copyValue.Value = (settings.Avatar == true)
	themeValue.Value = (type(settings.Theme) == "string" and settings.Theme ~= "" and settings.Theme) or "Default"
	player:SetAttribute("TAG_STYLE", (type(settings.EquippedTag) == "string" and settings.EquippedTag ~= "" and settings.EquippedTag) or "Default")

	-- Fav dances JSON (si viene mal, usamos "{}")
	local emotes = data.EmotesSaved
	if type(emotes) ~= "string" or emotes == "" then
		emotes = "{}"
	end
	favDancesValue.Value = emotes

	-- Tags
	for _, v in ipairs(tagsFolder:GetChildren()) do
		v:Destroy()
	end
	if type(data.TagsOwned) == "table" then
		for _, tagName in ipairs(data.TagsOwned) do
			if type(tagName) == "string" and tagName ~= "" then
				local Tag = Instance.new("BoolValue")
				Tag.Name = tagName
				Tag.Value = true
				Tag.Parent = tagsFolder
			end
		end
	end

	-- PasesInfo (solo flags persistidos, NO aplica Do, NO ownership checks)
	local PasesInfo = ensurePasesInfo(player)
	local savedMap = (type(data.Gamepass) == "table") and data.Gamepass or {}

	-- Asegura que existan flags para los que vienen guardados
	for passName, passValue in pairs(savedMap) do
		if type(passName) == "string" then
			setPaseFlag(player, passName, passValue == true)
		end
	end

	-- Si tenemos lista oficial, asegúrate que existan todos (aunque no estén en saved)
	if Gamepasses then
		for _, g in pairs(Gamepasses) do
			if g and g.Name then
				if not PasesInfo:FindFirstChild(g.Name) then
					local b = Instance.new("BoolValue")
					b.Name = g.Name
					b.Value = false
					b.Parent = PasesInfo
				end
			end
		end
	end
end

-- =========================
-- Save
-- =========================
local function buildSaveBlob(player: Player)
	local dataFolder = player:FindFirstChild("Datos")
	local leaderstats = player:FindFirstChild("leaderstats")
	local PasesInfo = player:FindFirstChild("PasesInfo")

	local blob = defaultData()

	if dataFolder and dataFolder:IsA("Folder") then
		local donated = dataFolder:FindFirstChild("Donado")
		local pointsOld = dataFolder:FindFirstChild("PuntosOLD")
		local skipSongs = dataFolder:FindFirstChild("SkipSongs")
		local giftVIP = dataFolder:FindFirstChild("GiftVIP")
		local fav = dataFolder:FindFirstChild("FavDances")
		local ajustes = dataFolder:FindFirstChild("Ajustes")
		local tags = dataFolder:FindFirstChild("Tags")

		blob.Donated = (donated and donated:IsA("IntValue")) and donated.Value or 0
		blob.Points  = (pointsOld and pointsOld:IsA("IntValue")) and pointsOld.Value or 0
		blob.SkipSongs = (skipSongs and skipSongs:IsA("IntValue")) and skipSongs.Value or 0
		blob.Vip = (giftVIP and giftVIP:IsA("BoolValue")) and giftVIP.Value or false
		blob.EmotesSaved = (fav and fav:IsA("StringValue")) and fav.Value or "{}"

		blob.Settings = {
			Avatar = false,
			Theme = "Default",
			EquippedTag = player:GetAttribute("TAG_STYLE") or "Default",
		}
		if ajustes and ajustes:IsA("Folder") then
			local copy = ajustes:FindFirstChild("Copy")
			local theme = ajustes:FindFirstChild("Theme")
			blob.Settings.Avatar = (copy and copy:IsA("BoolValue")) and copy.Value or false
			blob.Settings.Theme = (theme and theme:IsA("StringValue") and theme.Value ~= "" and theme.Value) or "Default"
		end

		blob.TagsOwned = {}
		if tags and tags:IsA("Folder") then
			for _, v in ipairs(tags:GetChildren()) do
				table.insert(blob.TagsOwned, v.Name)
			end
		end
	end

	if leaderstats and leaderstats:IsA("Folder") then
		local puntos = leaderstats:FindFirstChild("Puntos")
		blob.NewPoints = (puntos and puntos:IsA("IntValue")) and puntos.Value or 0
	end

	blob.Gamepass = {}
	if PasesInfo and PasesInfo:IsA("Folder") then
		for _, child in ipairs(PasesInfo:GetChildren()) do
			if child:IsA("BoolValue") then
				blob.Gamepass[child.Name] = child.Value == true
			end
		end
	end

	return blob
end

local function savePlayerData(player: Player)
	if saving[player.UserId] then return end
	saving[player.UserId] = true

	local blob = buildSaveBlob(player)

	local ok, err = pcall(function()
		DATA_STORE:UpdateAsync(tostring(player.UserId), function(old)
			-- No dependemos de old aquí, simplemente guardamos el blob actual.
			return blob
		end)
	end)

	if not ok then
		warn("[Datastore] Failed to save for", player.Name, ":", err)
	else
		dprint("Saved for", player.Name)
	end

	saving[player.UserId] = nil
end

-- =========================
-- Load
-- =========================
local function loadPlayerData(player: Player)
	if loaded[player.UserId] then return end
	loaded[player.UserId] = true

	local ok, data = pcall(function()
		return DATA_STORE:GetAsync(tostring(player.UserId))
	end)

	if not ok then
		warn("[Datastore] Failed to load for", player.Name, ":", data)
		data = nil
	else
		dprint("Loaded for", player.Name)
	end

	createPlayerData(player, data)
end

-- =========================
-- Hooks
-- =========================
Players.PlayerAdded:Connect(loadPlayerData)

Players.PlayerRemoving:Connect(function(player)
	savePlayerData(player)
	loaded[player.UserId] = nil
	saving[player.UserId] = nil
end)

-- Para servidores donde ya hay jugadores cuando el script inicia
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(function()
		loadPlayerData(player)
	end)
end

-- Safety net: guardar al cerrar server
game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		pcall(function()
			savePlayerData(player)
		end)
	end
end)
