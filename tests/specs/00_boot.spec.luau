-- Démarrage : le vrai Main.server.lua initialise tous les services sans erreur.
local S = H.boot(MODULES)

H.test("le serveur démarre sans erreur ni avertissement", function()
	H.eq(#H.errors, 0, "erreurs au démarrage")
	H.eq(#H.warnings, 0, "avertissements au démarrage : " .. table.concat(H.warnings, " / "))
end)

H.test("les 6 terrains sont visibles dès le départ, même vides", function()
	local WorldBuilder = mock.run(MODULES.WorldBuilder)
	for slot = 1, S.Config.MAX_CLUBS_PER_SERVER do
		local plot = WorldBuilder.getPlot(slot)
		H.ok(plot, "terrain " .. slot)
		H.ok(plot:FindFirstChild("Spawn", true), "point d'apparition du terrain " .. slot)
	end
end)

H.test("tous les RemoteEvents sont créés", function()
	local Net = mock.run(MODULES.Net)
	local folder = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
	for _, list in { Net.Requests, Net.Events, Net.Functions } do
		for _, name in list do
			H.ok(folder:FindFirstChild(name), "remote " .. name)
		end
	end
end)

H.test("l'aperçu de démonstration ne construit rien quand ClubService existe", function()
	H.advance(1)
	local count = 0
	for _, child in workspace:GetChildren() do
		if child:GetAttribute("SlotIndex") then
			count += 1
		end
	end
	H.eq(count, S.Config.MAX_CLUBS_PER_SERVER, "nombre de terrains")
end)
