--[[
	CameraController
	Caméra hybride (document de conception, section 1) :
	- exploration : caméra Roblox classique à la troisième personne ;
	- gestion : quand le menu est ouvert, vue surélevée sur le club.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

local CameraController = {}

local OVERVIEW_OFFSET = Vector3.new(0, 55, 70)
local TWEEN_INFO = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local enabled = true
local inManagementView = false
local activeTween = nil

function CameraController.Init() end

function CameraController.SetEnabled(value: boolean)
	enabled = value
	if not value then
		CameraController.ExitManagementView()
	end
end

function CameraController.EnterManagementView()
	if not enabled or inManagementView then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local camera = workspace.CurrentCamera
	inManagementView = true
	camera.CameraType = Enum.CameraType.Scriptable
	local focus = root.Position
	local target = CFrame.lookAt(focus + OVERVIEW_OFFSET, focus)
	activeTween = TweenService:Create(camera, TWEEN_INFO, { CFrame = target })
	activeTween:Play()
end

function CameraController.ExitManagementView()
	if not inManagementView then
		return
	end
	inManagementView = false
	if activeTween then
		activeTween:Cancel()
		activeTween = nil
	end
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
end

return CameraController
