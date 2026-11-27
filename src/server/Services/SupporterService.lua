--[[
	SupporterService
	Les supporters (PNJ) qui achètent à la Boutique et visitent le Musée du club
	rapportent des FC Coins. Le SERVEUR seul décide de l'argent :
	  - toutes les Npc.VISIT_INTERVAL secondes, pour chaque club dont le
	    président est sur place (SupporterService.IsAtClub),
	    un achat à la Boutique (selon son niveau) et une visite du Musée
	    (mode Création, s'il est construit) ;
	  - chaque visite est annoncée à tous les clients (« SupporterVisit ») pour
	    que les joueurs proches voient le supporter y aller et le « +N » ;
	  - un petit résumé est envoyé au propriétaire de temps en temps.
	Les PNJ eux-mêmes n'existent que côté client (NpcController) : aucun coût réseau.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Npc = require(Shared.Npc)
local WorldConfig = require(Shared.WorldConfig)
local Campus = require(Shared.Campus)
local Locale = require(Shared.Locale)
local Net = require(Shared.Net)

local Services = script.Parent
local PlayerDataService = require(Services.PlayerDataService)
local EconomyService = require(Services.EconomyService)
local ClubService = require(Services.ClubService)

local SupporterService = {}

local tally = setmetatable({}, { __mode = "k" }) -- [Player] = { coins, visits }

-- Achats des supporters pour ce club ce tour-ci : { { kind, coins } }.
function SupporterService.VisitsFor(data): { { kind: string, coins: number } }
	local visits = {}
	if type(data) ~= "table" then
		return visits
	end
	local shopLevel = type(data.buildings) == "table" and data.buildings.Shop or 1
	table.insert(visits, { kind = "shop", coins = Npc.ShopSpend(shopLevel) })
	local museum = Npc.MuseumSpend(Campus.Level(data.campus, "Museum"))
	if museum > 0 then
		table.insert(visits, { kind = "museum", coins = museum })
	end
	return visits
end

-- Les supporters viennent quand le président est à son club (personnage sur
-- son terrain ou sa zone de création, ou tout près) : pas d'argent pour un
-- joueur parti ailleurs dans le quartier.
function SupporterService.IsAtClub(player: Player, slot: number): boolean
	local character = player.Character
	local root = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
	if not root or not root:IsA("BasePart") then
		return false
	end
	local center = WorldConfig.getPlotCFrame(slot) * Vector3.new(0, 0, WorldConfig.CAMPUS_DEPTH / 2)
	local offset = root.Position - center
	return Vector3.new(offset.X, 0, offset.Z).Magnitude <= Npc.CLUB_RADIUS
end

-- Un tour de visites pour un joueur. Renvoie les FC Coins gagnés.
function SupporterService.Tick(player: Player): number
	local data = PlayerDataService.GetData(player)
	local slot = ClubService.GetSlot(player)
	if not data or not slot or not player.Parent or not SupporterService.IsAtClub(player, slot) then
		return 0
	end
	local earned = 0
	for _, visit in SupporterService.VisitsFor(data) do
		if EconomyService.Add(player, visit.coins, "supporters_" .. visit.kind) then
			earned += visit.coins
			Net.FireAllClients("SupporterVisit", slot, visit.kind, visit.coins)
		end
	end
	if earned > 0 then
		local t = tally[player] or { coins = 0, visits = 0 }
		tally[player] = t
		t.coins += earned
		t.visits += 1
		if t.visits >= Npc.SUMMARY_EVERY then
			Net.FireClient("Notify", player, Locale.TP(player, "npc.supportersSummary", { coins = t.coins }), "info")
			t.coins, t.visits = 0, 0
		end
	end
	return earned
end

function SupporterService.Init()
	task.spawn(function()
		while true do
			task.wait(Npc.VISIT_INTERVAL)
			for _, player in PlayerDataService.GetLoadedPlayers() do
				local ok, err = pcall(SupporterService.Tick, player)
				if not ok then
					warn("[Supporters] " .. tostring(err))
				end
			end
		end
	end)
end

return SupporterService
