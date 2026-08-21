local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local Stats = game:GetService("Stats")
local HttpService = game:GetService("HttpService")
local SoundService = game:GetService("SoundService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local camera = Workspace.CurrentCamera

-- Nettoyage des anciennes instances
local oldGui = playerGui:FindFirstChild("SableHubGui")
if oldGui then oldGui:Destroy() end

local oldOverlay = playerGui:FindFirstChild("SableVisualsOverlay")
if oldOverlay then oldOverlay:Destroy() end

-------------------------------------------------------------------
-- CONFIGURATION GLOBALE
-------------------------------------------------------------------
local colorPresets = {
    {name = "Vert", color = Color3.fromRGB(0, 220, 130)},
    {name = "Rouge", color = Color3.fromRGB(255, 55, 75)},
    {name = "Bleu", color = Color3.fromRGB(30, 120, 255)},
    {name = "Cyan", color = Color3.fromRGB(0, 210, 255)},
    {name = "Violet", color = Color3.fromRGB(170, 70, 255)},
    {name = "Blanc", color = Color3.fromRGB(255, 255, 255)}
}

local config = {
    -- Combat
    aimbot = true,
    aimKeyType = Enum.UserInputType.MouseButton2,
    aimKeyCode = nil,
    isAiming = false,
    fovRadius = 160,
    smoothness = 1.00,
    targetPart = "Head",
    hitChance = 100,
    prediction = false,
    predictionLead = 0.08,
    hitMarker = true,
    hitSound = true,
    wallCheck = true,
    teamCheck = false,
    showFov = true,
    fovFill = false,
    fovThickness = 1.2,
    triggerbot = false,
    triggerbotDelay = 0.05,
    lastTriggerShot = 0,
    rapidFire = false,
    rapidFireDelay = 0.02,
    lastRapidShot = 0,
    autoReload = false,
    crosshair = true,

    -- Visuals
    esp = false,
    espBoxes = false,
    espTracers = false,
    espColorIndex = 2,
    fovColorIndex = 3,
    fpsCounter = true,

    -- Player & Movement
    walkSpeedEnabled = false,
    walkSpeedValue = 45,
    jumpPowerEnabled = false,
    jumpPowerValue = 50,
    infJump = false,
    antiVoid = false,
    noclip = false,
    fly = false,
    flySpeed = 50,
    cameraFov = 70,
    spinbot = false,
    spinSpeed = 30,
    fullbright = false
}

local isRebindingAimKey = false
local savedConfigString = nil
local uiUpdaters = {}
local activeSlider = nil

local originalLighting = {
    Brightness = Lighting.Brightness,
    ClockTime = Lighting.ClockTime,
    FogEnd = Lighting.FogEnd,
    GlobalShadows = Lighting.GlobalShadows,
    Ambient = Lighting.Ambient
}

-------------------------------------------------------------------
-- MOTEUR AUDIO & FEEDBACK
-------------------------------------------------------------------
local hitAudio = Instance.new("Sound")
hitAudio.SoundId = "rbxassetid://4817809188"
hitAudio.Volume = 1
hitAudio.Parent = SoundService

-------------------------------------------------------------------
-- FONCTIONS DU MOTEUR
-------------------------------------------------------------------
local function isPlayerAlive(p)
    if not p or not p.Character then return false end
    local hum = p.Character:FindFirstChildOfClass("Humanoid")
    return hum and hum.Health > 0
end

local function isTeamMate(p)
    if not config.teamCheck then return false end
    return p.Team and localPlayer.Team and p.Team == localPlayer.Team
end

local function isVisibleThroughWall(targetPart)
    if not config.wallCheck then return true end
    local origin = camera.CFrame.Position
    local dir = targetPart.Position - origin
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {localPlayer.Character, camera}
    params.IgnoreWater = true

    local result = Workspace:Raycast(origin, dir, params)
    return not result or result.Instance:IsDescendantOf(targetPart.Parent)
end

local function getClosestTargetToCursor()
    local bestTarget = nil
    local shortestDist = config.fovRadius
    local screenCenter = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= localPlayer and isPlayerAlive(p) and not isTeamMate(p) then
            local part = p.Character:FindFirstChild(config.targetPart) or p.Character:FindFirstChild("Head")
            if part then
                local screenPos, onScreen = camera:WorldToViewportPoint(part.Position)
                if onScreen then
                    local screenVec = Vector2.new(screenPos.X, screenPos.Y)
                    local dist = (screenCenter - screenVec).Magnitude
                    if dist < shortestDist and isVisibleThroughWall(part) then
                        shortestDist = dist
                        bestTarget = p
                    end
                end
            end
        end
    end
    return bestTarget
end

local function setEspState(enabled)
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= localPlayer and p.Character then
            local hl = p.Character:FindFirstChild("ESPHighlight")
            if hl then
                hl.Enabled = enabled
                hl.FillColor = isTeamMate(p) and Color3.fromRGB(30, 120, 255) or colorPresets[config.espColorIndex].color
            end
        end
    end
end

local function setFullbright(active)
    if active then
        Lighting.Brightness = 2
        Lighting.ClockTime = 14
        Lighting.FogEnd = 100000
        Lighting.GlobalShadows = false
        Lighting.Ambient = Color3.fromRGB(255, 255, 255)
    else
        Lighting.Brightness = originalLighting.Brightness
        Lighting.ClockTime = originalLighting.ClockTime
        Lighting.FogEnd = originalLighting.FogEnd
        Lighting.GlobalShadows = originalLighting.GlobalShadows
        Lighting.Ambient = originalLighting.Ambient
    end
end

local flyBodyVelocity, flyBodyGyro
local function updateFly()
    if config.fly and localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart") then
        local root = localPlayer.Character.HumanoidRootPart
        if not flyBodyVelocity then
            flyBodyVelocity = Instance.new("BodyVelocity")
            flyBodyVelocity.MaxForce = Vector3.new(9e9, 9e9, 9e9)
            flyBodyVelocity.Parent = root
        end
        if not flyBodyGyro then
            flyBodyGyro = Instance.new("BodyGyro")
            flyBodyGyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
            flyBodyGyro.P = 9e4
            flyBodyGyro.Parent = root
        end

        local moveDir = Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Z) then
            moveDir = moveDir + camera.CFrame.LookVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then
            moveDir = moveDir - camera.CFrame.LookVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Q) then
            moveDir = moveDir - camera.CFrame.RightVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then
            moveDir = moveDir + camera.CFrame.RightVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
            moveDir = moveDir + Vector3.new(0, 1, 0)
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
            moveDir = moveDir - Vector3.new(0, 1, 0)
        end

        flyBodyVelocity.Velocity = moveDir * config.flySpeed
        flyBodyGyro.CFrame = camera.CFrame
    else
        if flyBodyVelocity then flyBodyVelocity:Destroy(); flyBodyVelocity = nil end
        if flyBodyGyro then flyBodyGyro:Destroy(); flyBodyGyro = nil end
    end
end

-------------------------------------------------------------------
-- INTERFACE UTILISATEUR AVANCÉE (MODERN DARK THEME)
-------------------------------------------------------------------
local visualsOverlay = Instance.new("ScreenGui")
visualsOverlay.Name = "SableVisualsOverlay"
visualsOverlay.ResetOnSpawn = false
visualsOverlay.IgnoreGuiInset = true
visualsOverlay.DisplayOrder = 999998
visualsOverlay.Parent = playerGui

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SableHubGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 999999
screenGui.Parent = playerGui

-- Badge FPS
local fpsBadge = Instance.new("Frame", screenGui)
fpsBadge.Name = "FpsBadge"
fpsBadge.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
fpsBadge.BorderSizePixel = 0
fpsBadge.Position = UDim2.new(0, 15, 0, 65)
fpsBadge.Size = UDim2.new(0, 135, 0, 28)
fpsBadge.Visible = config.fpsCounter
local fbc = Instance.new("UICorner", fpsBadge); fbc.CornerRadius = UDim.new(0, 6)
local fbs = Instance.new("UIStroke", fpsBadge); fbs.Color = Color3.fromRGB(35, 40, 52); fbs.Thickness = 1

local fpsLabel = Instance.new("TextLabel", fpsBadge)
fpsLabel.Text = "60 FPS | 20 ms"
fpsLabel.TextColor3 = Color3.fromRGB(0, 220, 130)
fpsLabel.TextSize = 11
fpsLabel.Font = Enum.Font.GothamBold
fpsLabel.BackgroundTransparency = 1
fpsLabel.Size = UDim2.new(1, 0, 1, 0)

-- Hit Marker Overlay
local hitMarkerGui = Instance.new("Frame", visualsOverlay)
hitMarkerGui.Name = "HitMarkerGui"
hitMarkerGui.AnchorPoint = Vector2.new(0.5, 0.5)
hitMarkerGui.Position = UDim2.new(0.5, 0, 0.5, 0)
hitMarkerGui.Size = UDim2.new(0, 16, 0, 16)
hitMarkerGui.BackgroundTransparency = 1
hitMarkerGui.Visible = false

local function createHitLine(rotation)
    local l = Instance.new("Frame", hitMarkerGui)
    l.BackgroundColor3 = Color3.fromRGB(255, 65, 85)
    l.BorderSizePixel = 0
    l.AnchorPoint = Vector2.new(0.5, 0.5)
    l.Position = UDim2.new(0.5, 0, 0.5, 0)
    l.Size = UDim2.new(0, 10, 0, 2)
    l.Rotation = rotation
    local lc = Instance.new("UICorner", l); lc.CornerRadius = UDim.new(1, 0)
    return l
end
createHitLine(45)
createHitLine(-45)

local function triggerHitMarker()
    if not config.hitMarker then return end
    hitMarkerGui.Visible = true
    if config.hitSound then hitAudio:Play() end
    task.spawn(function()
        task.wait(0.12)
        hitMarkerGui.Visible = false
    end)
end

-- Cercle FOV
local fovCircle = Instance.new("Frame", screenGui)
fovCircle.Name = "FovCircle"
fovCircle.AnchorPoint = Vector2.new(0.5, 0.5)
fovCircle.Position = UDim2.new(0.5, 0, 0.5, 0)
fovCircle.BackgroundColor3 = colorPresets[config.fovColorIndex].color
fovCircle.BackgroundTransparency = config.fovFill and 0.85 or 1
fovCircle.BorderSizePixel = 0
fovCircle.Size = UDim2.new(0, config.fovRadius * 2, 0, config.fovRadius * 2)
fovCircle.Visible = config.showFov
local fovStroke = Instance.new("UIStroke", fovCircle)
fovStroke.Color = colorPresets[config.fovColorIndex].color
fovStroke.Thickness = config.fovThickness
fovStroke.Transparency = 0.35
local fovCorner = Instance.new("UICorner", fovCircle); fovCorner.CornerRadius = UDim.new(1, 0)

-- Crosshair Central
local crosshairCenter = Instance.new("Frame", screenGui)
crosshairCenter.Name = "CustomCrosshair"
crosshairCenter.AnchorPoint = Vector2.new(0.5, 0.5)
crosshairCenter.Position = UDim2.new(0.5, 0, 0.5, 0)
crosshairCenter.Size = UDim2.new(0, 4, 0, 4)
crosshairCenter.BackgroundColor3 = Color3.fromRGB(0, 220, 130)
crosshairCenter.BorderSizePixel = 0
crosshairCenter.Visible = config.crosshair
local chc = Instance.new("UICorner", crosshairCenter); chc.CornerRadius = UDim.new(1, 0)

-- Fenêtre Principale Moderne (620x380)
local mainFrame = Instance.new("Frame", screenGui)
mainFrame.Name = "MainFrame"
mainFrame.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
mainFrame.BorderSizePixel = 0
mainFrame.Position = UDim2.new(0.5, -310, 0.5, -190)
mainFrame.Size = UDim2.new(0, 620, 0, 380)
mainFrame.ClipsDescendants = true
local mc = Instance.new("UICorner", mainFrame); mc.CornerRadius = UDim.new(0, 10)
local ms = Instance.new("UIStroke", mainFrame); ms.Color = Color3.fromRGB(38, 44, 58); ms.Thickness = 1.5

-- Barre de Titre Supérieure
local topBar = Instance.new("Frame", mainFrame)
topBar.Name = "TopBar"
topBar.BackgroundColor3 = Color3.fromRGB(20, 23, 30)
topBar.BorderSizePixel = 0
topBar.Size = UDim2.new(1, 0, 0, 40)
local tbc = Instance.new("UICorner", topBar); tbc.CornerRadius = UDim.new(0, 10)

-- Fix bas des coins arrondis du TopBar
local tbFix = Instance.new("Frame", topBar)
tbFix.BackgroundColor3 = Color3.fromRGB(20, 23, 30)
tbFix.BorderSizePixel = 0
tbFix.Position = UDim2.new(0, 0, 1, -6)
tbFix.Size = UDim2.new(1, 0, 0, 6)

local titleLabel = Instance.new("TextLabel", topBar)
titleLabel.Text = "  rcruel hub  //  v2.5"
titleLabel.TextColor3 = Color3.fromRGB(220, 225, 235)
titleLabel.TextSize = 13
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.BackgroundTransparency = 1
titleLabel.Position = UDim2.new(0, 16, 0, 0)
titleLabel.Size = UDim2.new(0.7, 0, 1, 0)

local closeButton = Instance.new("TextButton", topBar)
closeButton.Text = "✕"
closeButton.TextColor3 = Color3.fromRGB(160, 165, 180)
closeButton.TextSize = 14
closeButton.Font = Enum.Font.GothamBold
closeButton.BackgroundColor3 = Color3.fromRGB(26, 30, 39)
closeButton.BorderSizePixel = 0
closeButton.AnchorPoint = Vector2.new(1, 0.5)
closeButton.Position = UDim2.new(1, -12, 0.5, 0)
closeButton.Size = UDim2.new(0, 26, 0, 26)
local cbc = Instance.new("UICorner", closeButton); cbc.CornerRadius = UDim.new(0, 6)

-- Sidebar Gauche
local sidebar = Instance.new("Frame", mainFrame)
sidebar.Name = "Sidebar"
sidebar.BackgroundColor3 = Color3.fromRGB(20, 23, 30)
sidebar.BorderSizePixel = 0
sidebar.Position = UDim2.new(0, 0, 0, 40)
sidebar.Size = UDim2.new(0, 150, 1, -40)
local sc = Instance.new("UICorner", sidebar); sc.CornerRadius = UDim.new(0, 10)
local scFix = Instance.new("Frame", sidebar)
scFix.BackgroundColor3 = Color3.fromRGB(20, 23, 30)
scFix.BorderSizePixel = 0
scFix.Position = UDim2.new(1, -6, 0, 0)
scFix.Size = UDim2.new(0, 6, 1, 0)

local navHolder = Instance.new("Frame", sidebar)
navHolder.BackgroundTransparency = 1
navHolder.Position = UDim2.new(0, 10, 0, 12)
navHolder.Size = UDim2.new(1, -20, 1, -24)
local navList = Instance.new("UIListLayout", navHolder)
navList.Padding = UDim.new(0, 6)

-- Zone de Contenu Principale
local contentArea = Instance.new("Frame", mainFrame)
contentArea.Name = "ContentArea"
contentArea.BackgroundTransparency = 1
contentArea.Position = UDim2.new(0, 165, 0, 52)
contentArea.Size = UDim2.new(1, -175, 1, -62)

-------------------------------------------------------------------
-- CRÉATION DES PAGES ET NAVIGATION
-------------------------------------------------------------------
local pages = {}
local tabButtons = {}

local function createPage(pageName)
    local page = Instance.new("ScrollingFrame", contentArea)
    page.Name = pageName .. "Page"
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.Size = UDim2.new(1, 0, 1, 0)
    page.ScrollBarThickness = 2
    page.ScrollBarImageColor3 = Color3.fromRGB(50, 60, 80)
    page.CanvasSize = UDim2.new(0, 0, 0, 580)
    page.Visible = false

    local list = Instance.new("UIListLayout", page)
    list.Padding = UDim.new(0, 8)
    list.SortOrder = Enum.SortOrder.LayoutOrder

    pages[pageName] = page
    return page
end

local combatPage = createPage("Combat")
local visualsPage = createPage("Visuals")
local playerPage = createPage("Player")
local settingsPage = createPage("Settings")

local function switchTab(tabName)
    for name, page in pairs(pages) do
        page.Visible = (name == tabName)
    end
    for name, btn in pairs(tabButtons) do
        local isSelected = (name == tabName)
        TweenService:Create(btn, TweenInfo.new(0.2), {
            BackgroundColor3 = isSelected and Color3.fromRGB(30, 120, 255) or Color3.fromRGB(26, 30, 39)
        }):Play()
        local lbl = btn:FindFirstChild("Label")
        if lbl then
            lbl.TextColor3 = isSelected and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 155, 170)
            lbl.Font = isSelected and Enum.Font.GothamBold or Enum.Font.GothamMedium
        end
    end
end

local function addTabButton(name)
    local btn = Instance.new("TextButton", navHolder)
    btn.Name = name .. "Tab"
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.BackgroundColor3 = Color3.fromRGB(26, 30, 39)
    btn.BorderSizePixel = 0
    btn.Size = UDim2.new(1, 0, 0, 36)
    local bc = Instance.new("UICorner", btn); bc.CornerRadius = UDim.new(0, 8)

    local lbl = Instance.new("TextLabel", btn)
    lbl.Name = "Label"
    lbl.Text = name
    lbl.TextColor3 = Color3.fromRGB(150, 155, 170)
    lbl.TextSize = 12
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.BackgroundTransparency = 1
    lbl.Position = UDim2.new(0, 12, 0, 0)
    lbl.Size = UDim2.new(1, -12, 1, 0)

    btn.MouseButton1Click:Connect(function()
        switchTab(name)
    end)

    tabButtons[name] = btn
end

addTabButton("Combat")
addTabButton("Visuals")
addTabButton("Player")
addTabButton("Settings")

-------------------------------------------------------------------
-- CRÉATION DES WIDGETS
-------------------------------------------------------------------
local function addToggleSwitch(parent, configKey, titleText, callback)
    local row = Instance.new("Frame", parent)
    row.BackgroundColor3 = Color3.fromRGB(22, 25, 33)
    row.BorderSizePixel = 0
    row.Size = UDim2.new(1, 0, 0, 36)
    local rc = Instance.new("UICorner", row); rc.CornerRadius = UDim.new(0, 6)

    local lbl = Instance.new("TextLabel", row)
    lbl.Text = titleText
    lbl.TextColor3 = Color3.fromRGB(220, 222, 230)
    lbl.TextSize = 11
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.BackgroundTransparency = 1
    lbl.Position = UDim2.new(0, 12, 0, 0)
    lbl.Size = UDim2.new(0.7, 0, 1, 0)

    local switchBtn = Instance.new("TextButton", row)
    switchBtn.Text = ""
    switchBtn.AutoButtonColor = false
    switchBtn.BackgroundColor3 = config[configKey] and Color3.fromRGB(30, 120, 255) or Color3.fromRGB(38, 44, 58)
    switchBtn.BorderSizePixel = 0
    switchBtn.Position = UDim2.new(1, -44, 0.5, -10)
    switchBtn.Size = UDim2.new(0, 34, 0, 20)
    local sc = Instance.new("UICorner", switchBtn); sc.CornerRadius = UDim.new(1, 0)

    local circle = Instance.new("Frame", switchBtn)
    circle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    circle.BorderSizePixel = 0
    circle.Position = config[configKey] and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7)
    circle.Size = UDim2.new(0, 14, 0, 14)
    local cc = Instance.new("UICorner", circle); cc.CornerRadius = UDim.new(1, 0)

    local function applyVisual(state)
        local targetBg = state and Color3.fromRGB(30, 120, 255) or Color3.fromRGB(38, 44, 58)
        local targetPos = state and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7)

        TweenService:Create(switchBtn, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {BackgroundColor3 = targetBg}):Play()
        TweenService:Create(circle, TweenInfo.new(0.2, Enum.EasingStyle.Quad), {Position = targetPos}):Play()
    end

    switchBtn.MouseButton1Click:Connect(function()
        config[configKey] = not config[configKey]
        applyVisual(config[configKey])
        callback(config[configKey])
    end)

    uiUpdaters[configKey] = function(val)
        config[configKey] = val
        applyVisual(val)
        callback(val)
    end
end

local function addModernSlider(parent, configKey, titleText, minVal, maxVal, isFloat, callback)
    local row = Instance.new("Frame", parent)
    row.BackgroundColor3 = Color3.fromRGB(22, 25, 33)
    row.BorderSizePixel = 0
    row.Size = UDim2.new(1, 0, 0, 42)
    local rc = Instance.new("UICorner", row); rc.CornerRadius = UDim.new(0, 6)

    local lbl = Instance.new("TextLabel", row)
    lbl.Text = titleText
    lbl.TextColor3 = Color3.fromRGB(220, 222, 230)
    lbl.TextSize = 11
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.BackgroundTransparency = 1
    lbl.Position = UDim2.new(0, 12, 0, 0)
    lbl.Size = UDim2.new(0.4, 0, 1, 0)

    local valLbl = Instance.new("TextLabel", row)
    valLbl.Text = isFloat and string.format("%.2f", config[configKey]) or tostring(math.floor(config[configKey]))
    valLbl.TextColor3 = Color3.fromRGB(140, 145, 160)
    valLbl.TextSize = 11
    valLbl.Font = Enum.Font.GothamMedium
    valLbl.TextXAlignment = Enum.TextXAlignment.Right
    valLbl.BackgroundTransparency = 1
    valLbl.Position = UDim2.new(0.4, 0, 0, 0)
    valLbl.Size = UDim2.new(0, 30, 1, 0)

    local track = Instance.new("TextButton", row)
    track.Text = ""
    track.AutoButtonColor = false
    track.BackgroundColor3 = Color3.fromRGB(32, 38, 50)
    track.BorderSizePixel = 0
    track.Position = UDim2.new(1, -165, 0.5, -2)
    track.Size = UDim2.new(0, 150, 0, 4)
    local tc = Instance.new("UICorner", track); tc.CornerRadius = UDim.new(1, 0)

    local initPercent = math.clamp((config[configKey] - minVal) / (maxVal - minVal), 0, 1)
    local fill = Instance.new("Frame", track)
    fill.BackgroundColor3 = Color3.fromRGB(30, 120, 255)
    fill.BorderSizePixel = 0
    fill.Size = UDim2.new(initPercent, 0, 1, 0)
    local fc = Instance.new("UICorner", fill); fc.CornerRadius = UDim.new(1, 0)

    local thumb = Instance.new("Frame", track)
    thumb.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    thumb.BorderSizePixel = 0
    thumb.Position = UDim2.new(initPercent, -6, 0.5, -6)
    thumb.Size = UDim2.new(0, 12, 0, 12)
    local thc = Instance.new("UICorner", thumb); thc.CornerRadius = UDim.new(1, 0)

    local function setSliderVal(currentVal)
        local percent = math.clamp((currentVal - minVal) / (maxVal - minVal), 0, 1)
        fill.Size = UDim2.new(percent, 0, 1, 0)
        thumb.Position = UDim2.new(percent, -6, 0.5, -6)
        valLbl.Text = isFloat and string.format("%.2f", currentVal) or tostring(math.floor(currentVal))
        config[configKey] = currentVal
        callback(currentVal)
    end

    local function updateFromInput(inputX)
        local percent = math.clamp((inputX - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        local currentVal = minVal + (maxVal - minVal) * percent
        setSliderVal(isFloat and currentVal or math.floor(currentVal))
    end

    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            activeSlider = updateFromInput
            updateFromInput(input.Position.X)
        end
    end)

    uiUpdaters[configKey] = function(val)
        setSliderVal(val)
    end
end

local targetBtnRef
local function addDropdownPart(parent)
    local row = Instance.new("Frame", parent)
    row.BackgroundColor3 = Color3.fromRGB(22, 25, 33)
    row.BorderSizePixel = 0
    row.Size = UDim2.new(1, 0, 0, 36)
    local rc = Instance.new("UICorner", row); rc.CornerRadius = UDim.new(0, 6)

    local lbl = Instance.new("TextLabel", row)
    lbl.Text = "Target Part"
    lbl.TextColor3 = Color3.fromRGB(220, 222, 230)
    lbl.TextSize = 11
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.BackgroundTransparency = 1
    lbl.Position = UDim2.new(0, 12, 0, 0)
    lbl.Size = UDim2.new(0.5, 0, 1, 0)

    local btn = Instance.new("TextButton", row)
    btn.Text = config.targetPart == "Head" and "Head  ⌵" or "Torso  ⌵"
    btn.TextColor3 = Color3.fromRGB(210, 215, 225)
    btn.TextSize = 11
    btn.Font = Enum.Font.GothamMedium
    btn.BackgroundColor3 = Color3.fromRGB(28, 32, 42)
    btn.BorderSizePixel = 0
    btn.Position = UDim2.new(1, -90, 0.5, -11)
    btn.Size = UDim2.new(0, 80, 0, 22)
    local bc = Instance.new("UICorner", btn); bc.CornerRadius = UDim.new(0, 5)

    btn.MouseButton1Click:Connect(function()
        if config.targetPart == "Head" then
            config.targetPart = "HumanoidRootPart"
            btn.Text = "Torso  ⌵"
        else
            config.targetPart = "Head"
            btn.Text = "Head  ⌵"
        end
    end)

    targetBtnRef = btn
    uiUpdaters["targetPart"] = function(val)
        config.targetPart = val
        targetBtnRef.Text = val == "Head" and "Head  ⌵" or "Torso  ⌵"
    end
end

local aimBadgeRef
local function addKeybindRow(parent, titleText)
    local row = Instance.new("Frame", parent)
    row.BackgroundColor3 = Color3.fromRGB(22, 25, 33)
    row.BorderSizePixel = 0
    row.Size = UDim2.new(1, 0, 0, 36)
    local rc = Instance.new("UICorner", row); rc.CornerRadius = UDim.new(0, 6)

    local lbl = Instance.new("TextLabel", row)
    lbl.Text = titleText
    lbl.TextColor3 = Color3.fromRGB(220, 222, 230)
    lbl.TextSize = 11
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.BackgroundTransparency = 1
    lbl.Position = UDim2.new(0, 12, 0, 0)
    lbl.Size = UDim2.new(0.6, 0, 1, 0)

    local badge = Instance.new("TextButton", row)
    badge.Text = "MB2"
    badge.TextColor3 = Color3.fromRGB(160, 165, 180)
    badge.TextSize = 11
    badge.Font = Enum.Font.GothamBold
    badge.BackgroundColor3 = Color3.fromRGB(28, 32, 42)
    badge.BorderSizePixel = 0
    badge.Position = UDim2.new(1, -70, 0.5, -11)
    badge.Size = UDim2.new(0, 60, 0, 22)
    local bc = Instance.new("UICorner", badge); bc.CornerRadius = UDim.new(0, 5)

    badge.MouseButton1Click:Connect(function()
        isRebindingAimKey = true
        badge.Text = "..."
        badge.TextColor3 = Color3.fromRGB(255, 200, 0)
    end)

    aimBadgeRef = badge
    uiUpdaters["aimKeyType"] = function(val)
        if val == Enum.UserInputType.MouseButton2 or val == 1 then
            config.aimKeyType = Enum.UserInputType.MouseButton2
            aimBadgeRef.Text = "MB2"
        elseif val == Enum.UserInputType.MouseButton1 or val == 0 then
            config.aimKeyType = Enum.UserInputType.MouseButton1
            aimBadgeRef.Text = "MB1"
        end
    end
end

local function addColorRow(parent, configKey, titleText, callback)
    local row = Instance.new("Frame", parent)
    row.BackgroundColor3 = Color3.fromRGB(22, 25, 33)
    row.BorderSizePixel = 0
    row.Size = UDim2.new(1, 0, 0, 36)
    local rc = Instance.new("UICorner", row); rc.CornerRadius = UDim.new(0, 6)

    local lbl = Instance.new("TextLabel", row)
    lbl.Text = titleText
    lbl.TextColor3 = Color3.fromRGB(220, 222, 230)
    lbl.TextSize = 11
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.BackgroundTransparency = 1
    lbl.Position = UDim2.new(0, 12, 0, 0)
    lbl.Size = UDim2.new(0.6, 0, 1, 0)

    local btn = Instance.new("TextButton", row)
    btn.Text = colorPresets[config[configKey]].name
    btn.TextColor3 = colorPresets[config[configKey]].color
    btn.TextSize = 10
    btn.Font = Enum.Font.GothamBold
    btn.BackgroundColor3 = Color3.fromRGB(28, 32, 42)
    btn.BorderSizePixel = 0
    btn.Position = UDim2.new(1, -85, 0.5, -11)
    btn.Size = UDim2.new(0, 75, 0, 22)
    local bc = Instance.new("UICorner", btn); bc.CornerRadius = UDim.new(0, 5)

    btn.MouseButton1Click:Connect(function()
        config[configKey] = (config[configKey] % #colorPresets) + 1
        btn.Text = colorPresets[config[configKey]].name
        btn.TextColor3 = colorPresets[config[configKey]].color
        callback(config[configKey], colorPresets[config[configKey]].color)
    end)

    uiUpdaters[configKey] = function(idx)
        config[configKey] = idx
        btn.Text = colorPresets[idx].name
        btn.TextColor3 = colorPresets[idx].color
        callback(idx, colorPresets[idx].color)
    end
end

-------------------------------------------------------------------
-- REMPLISSAGE DES PAGES
-------------------------------------------------------------------
-- Combat
addToggleSwitch(combatPage, "aimbot", "Aimbot Lock", function(v) end)
addKeybindRow(combatPage, "Aim Key (Hold)")
addDropdownPart(combatPage)
addModernSlider(combatPage, "hitChance", "Hit Chance %", 1, 100, false, function(v) end)
addToggleSwitch(combatPage, "prediction", "Auto-Prediction (Lead)", function(v) end)
addModernSlider(combatPage, "smoothness", "Aimbot Smoothness", 0.05, 1.00, true, function(v) end)
addToggleSwitch(combatPage, "hitMarker", "Hit Marker Visual", function(v) end)
addToggleSwitch(combatPage, "hitSound", "Hit Marker Audio", function(v) end)
addToggleSwitch(combatPage, "triggerbot", "Triggerbot", function(v) end)
addModernSlider(combatPage, "triggerbotDelay", "Triggerbot Delay", 0.01, 0.20, true, function(v) end)
addToggleSwitch(combatPage, "rapidFire", "Rapid Fire (Hold Click)", function(v) end)
addModernSlider(combatPage, "rapidFireDelay", "Rapid Fire Rate", 0.01, 0.15, true, function(v) end)
addToggleSwitch(combatPage, "autoReload", "Auto-Reload (Empty Mag)", function(v) end)
addToggleSwitch(combatPage, "wallCheck", "Wallcheck", function(v) end)
addToggleSwitch(combatPage, "teamCheck", "Team Check", function(v) setEspState(config.esp) end)
addToggleSwitch(combatPage, "showFov", "Show FOV Circle", function(v) fovCircle.Visible = v end)
addToggleSwitch(combatPage, "fovFill", "Fill FOV Circle", function(v)
    fovCircle.BackgroundTransparency = v and 0.85 or 1
end)
addModernSlider(combatPage, "fovThickness", "FOV Line Thickness", 1, 5, false, function(v)
    fovStroke.Thickness = v
end)
addModernSlider(combatPage, "fovRadius", "FOV Size", 50, 400, false, function(v)
    fovCircle.Size = UDim2.new(0, v * 2, 0, v * 2)
end)
addToggleSwitch(combatPage, "crosshair", "Custom Crosshair", function(v) crosshairCenter.Visible = v end)

-- Visuals
addToggleSwitch(visualsPage, "esp", "ESP Highlights (Chams)", function(v) setEspState(v) end)
addToggleSwitch(visualsPage, "espBoxes", "ESP 2D Boxes", function(v) end)
addToggleSwitch(visualsPage, "espTracers", "ESP Snaplines (Tracers)", function(v) end)
addColorRow(visualsPage, "espColorIndex", "ESP Color", function(idx, color) setEspState(config.esp) end)
addColorRow(visualsPage, "fovColorIndex", "FOV Circle Color", function(idx, color)
    fovStroke.Color = color
    fovCircle.BackgroundColor3 = color
end)
addToggleSwitch(visualsPage, "fpsCounter", "FPS / Ping Display", function(v) fpsBadge.Visible = v end)

-- Player & World
addToggleSwitch(playerPage, "spinbot", "Spinbot", function(v) end)
addModernSlider(playerPage, "spinSpeed", "Spinbot Speed", 5, 100, false, function(v) end)
addToggleSwitch(playerPage, "walkSpeedEnabled", "Speed Hack (Bypass)", function(v) end)
addModernSlider(playerPage, "walkSpeedValue", "Speed Multiplier", 16, 120, false, function(v) end)
addToggleSwitch(playerPage, "jumpPowerEnabled", "High Jump Modifier", function(v) end)
addModernSlider(playerPage, "jumpPowerValue", "Jump Power", 50, 250, false, function(v) end)
addToggleSwitch(playerPage, "antiVoid", "Anti-Void Fall Rescue", function(v) end)
addToggleSwitch(playerPage, "noclip", "NoClip (Wallpass)", function(v) end)
addToggleSwitch(playerPage, "fly", "Fly Hack", function(v) if not v then updateFly() end end)
addModernSlider(playerPage, "flySpeed", "Fly Speed", 20, 150, false, function(v) end)
addModernSlider(playerPage, "cameraFov", "Camera Field of View", 70, 120, false, function(v) end)
addToggleSwitch(playerPage, "infJump", "Infinite Jump", function(v) end)
addToggleSwitch(playerPage, "fullbright", "Fullbright", function(v) setFullbright(v) end)

-- Settings
local function addActionButton(parent, titleText, color, callback)
    local btn = Instance.new("TextButton", parent)
    btn.Text = titleText
    btn.TextColor3 = color
    btn.TextSize = 11
    btn.Font = Enum.Font.GothamBold
    btn.BackgroundColor3 = Color3.fromRGB(22, 25, 33)
    btn.BorderSizePixel = 0
    btn.Size = UDim2.new(1, 0, 0, 36)
    local bc = Instance.new("UICorner", btn); bc.CornerRadius = UDim.new(0, 6)
    local bs = Instance.new("UIStroke", btn); bs.Color = Color3.fromRGB(35, 40, 52); bs.Thickness = 1

    btn.MouseButton1Click:Connect(callback)
end

local function syncAllUIElements(data)
    for key, val in pairs(data) do
        if uiUpdaters[key] then
            uiUpdaters[key](val)
        end
    end
end

-- Sauvegarde complète de TOUTE la table config
addActionButton(settingsPage, "SAUVEGARDER CONFIG", Color3.fromRGB(30, 120, 255), function()
    local cleanConfig = {}
    for k, v in pairs(config) do
        if typeof(v) == "EnumItem" then
            cleanConfig[k] = v.Value
        else
            cleanConfig[k] = v
        end
    end

    savedConfigString = HttpService:JSONEncode(cleanConfig)
    if typeof(writefile) == "function" then
        pcall(function() writefile("rcruel_full_config.json", savedConfigString) end)
    end
end)

-- Chargement complet et synchronisation visuelle immédiate
addActionButton(settingsPage, "CHARGER CONFIG", Color3.fromRGB(0, 220, 130), function()
    local raw = savedConfigString
    if not raw and typeof(readfile) == "function" and isfile and isfile("rcruel_full_config.json") then
        pcall(function() raw = readfile("rcruel_full_config.json") end)
    end

    if raw then
        local success, decoded = pcall(function() return HttpService:JSONDecode(raw) end)
        if success and decoded then
            syncAllUIElements(decoded)
        end
    end
end)

addActionButton(settingsPage, "REINITIALISER CONFIG", Color3.fromRGB(255, 65, 85), function()
    local defaults = {
        aimbot = true,
        fovRadius = 160,
        smoothness = 1.00,
        targetPart = "Head",
        hitChance = 100,
        prediction = false,
        wallCheck = true,
        teamCheck = false,
        hitMarker = true,
        hitSound = true,
        triggerbot = false,
        triggerbotDelay = 0.05,
        rapidFire = false,
        rapidFireDelay = 0.02,
        autoReload = false,
        crosshair = true,
        showFov = true,
        fovFill = false,
        fovThickness = 1.2,
        esp = false,
        espBoxes = false,
        espTracers = false,
        espColorIndex = 2,
        fovColorIndex = 3,
        fpsCounter = true,
        walkSpeedEnabled = false,
        walkSpeedValue = 45,
        jumpPowerEnabled = false,
        jumpPowerValue = 50,
        antiVoid = false,
        noclip = false,
        fly = false,
        flySpeed = 50,
        spinbot = false,
        spinSpeed = 30,
        cameraFov = 70,
        infJump = false,
        fullbright = false
    }
    syncAllUIElements(defaults)
end)

switchTab("Combat")

-------------------------------------------------------------------
-- GESTION DU DRAGGING GLOBAL & DES SLIDERS
-------------------------------------------------------------------
local isDraggingMenu = false
local dragStartPos = nil
local frameStartPos = nil

topBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        isDraggingMenu = true
        dragStartPos = input.Position
        frameStartPos = mainFrame.Position
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if isDraggingMenu and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStartPos
        mainFrame.Position = UDim2.new(
            frameStartPos.X.Scale,
            frameStartPos.X.Offset + delta.X,
            frameStartPos.Y.Scale,
            frameStartPos.Y.Offset + delta.Y
        )
    elseif activeSlider and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        activeSlider(input.Position.X)
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        isDraggingMenu = false
        activeSlider = nil
    end
end)

-------------------------------------------------------------------
-- BOUCLES DU MOTEUR
-------------------------------------------------------------------
-- Aimbot Loop
RunService:BindToRenderStep("SableAimbotLock", Enum.RenderPriority.Camera.Value + 1, function()
    if config.aimbot and config.isAiming then
        if config.hitChance < 100 and math.random(1, 100) > config.hitChance then
            return
        end

        local target = getClosestTargetToCursor()
        if target and target.Character then
            local part = target.Character:FindFirstChild(config.targetPart) or target.Character:FindFirstChild("Head")
            if part then
                local targetPos = part.Position
                if config.prediction then
                    local root = target.Character:FindFirstChild("HumanoidRootPart")
                    if root then
                        targetPos = targetPos + (root.AssemblyLinearVelocity * config.predictionLead)
                    end
                end

                local camPos = camera.CFrame.Position
                local targetCFrame = CFrame.lookAt(camPos, targetPos)
                if config.smoothness >= 1 then
                    camera.CFrame = targetCFrame
                else
                    camera.CFrame = camera.CFrame:Lerp(targetCFrame, config.smoothness)
                end
            end
        end
    end
end)

-- Speed Hack & JumpPower
RunService.Heartbeat:Connect(function()
    if localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart") then
        local hum = localPlayer.Character:FindFirstChildOfClass("Humanoid")
        local root = localPlayer.Character.HumanoidRootPart
        
        if config.walkSpeedEnabled and hum and hum.MoveDirection.Magnitude > 0 then
            local moveVel = hum.MoveDirection * config.walkSpeedValue
            root.AssemblyLinearVelocity = Vector3.new(moveVel.X, root.AssemblyLinearVelocity.Y, moveVel.Z)
        end

        if config.jumpPowerEnabled and hum then
            hum.UseJumpPower = true
            hum.JumpPower = config.jumpPowerValue
        end
    end
end)

-- Anti-Void Fall Rescue
local lastSafePosition = nil
RunService.Heartbeat:Connect(function()
    if localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart") then
        local root = localPlayer.Character.HumanoidRootPart
        if root.Position.Y > -20 then
            lastSafePosition = root.CFrame
        elseif config.antiVoid and root.Position.Y < -50 and lastSafePosition then
            root.Velocity = Vector3.zero
            root.CFrame = lastSafePosition + Vector3.new(0, 5, 0)
        end
    end
end)

-- Moteur de Tir Direct avec Hit Marker Check
local function fireAction()
    local mousePos = UserInputService:GetMouseLocation()
    if typeof(mouse1click) == "function" then
        mouse1click()
    elseif VirtualInputManager then
        VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, 0, true, game, 1)
        task.wait(0.005)
        VirtualInputManager:SendMouseButtonEvent(mousePos.X, mousePos.Y, 0, false, game, 1)
    end

    if localPlayer.Character then
        local tool = localPlayer.Character:FindFirstChildOfClass("Tool")
        if tool then tool:Activate() end
    end
    triggerHitMarker()
end

-- Triggerbot Loop
RunService.RenderStepped:Connect(function()
    if not config.triggerbot then return end
    if tick() - config.lastTriggerShot < config.triggerbotDelay then return end

    local rayOrigin = camera.CFrame.Position
    local rayDir = camera.CFrame.LookVector * 1000

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {localPlayer.Character, camera}
    params.IgnoreWater = true

    local result = Workspace:Raycast(rayOrigin, rayDir, params)
    if result and result.Instance then
        local hitModel = result.Instance:FindFirstAncestorOfClass("Model")
        if hitModel then
            local hitPlayer = Players:GetPlayerFromCharacter(hitModel)
            if hitPlayer and hitPlayer ~= localPlayer and isPlayerAlive(hitPlayer) and not isTeamMate(hitPlayer) then
                config.lastTriggerShot = tick()
                fireAction()
            end
        end
    end
end)

-- Rapid Fire Multi-Trigger Loop
RunService.RenderStepped:Connect(function()
    if config.rapidFire and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
        if tick() - config.lastRapidShot >= config.rapidFireDelay then
            config.lastRapidShot = tick()
            fireAction()
        end
    end
end)

-- Auto-Reload Loop
RunService.Heartbeat:Connect(function()
    if config.autoReload and localPlayer.Character then
        local tool = localPlayer.Character:FindFirstChildOfClass("Tool")
        if tool then
            local ammoVal = tool:FindFirstChild("Ammo") or tool:FindFirstChild("Clip") or tool:FindFirstChild("Mag")
            if ammoVal and ammoVal:IsA("ValueBase") and ammoVal.Value <= 0 then
                if VirtualInputManager then
                    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.R, false, game)
                    task.wait(0.01)
                    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.R, false, game)
                elseif typeof(keypress) == "function" and typeof(keyrelease) == "function" then
                    keypress(0x52)
                    task.wait(0.01)
                    keyrelease(0x52)
                end
            end
        end
    end
end)

-- Visuals Elements Management
local espVisualElements = {}

local function createPlayerVisuals(p)
    if espVisualElements[p] then return end

    local box = Instance.new("Frame", visualsOverlay)
    box.Name = "ESPBox"
    box.BackgroundTransparency = 1
    box.BorderSizePixel = 0
    box.Visible = false

    local boxStroke = Instance.new("UIStroke", box)
    boxStroke.Color = colorPresets[config.espColorIndex].color
    boxStroke.Thickness = 1.2

    local line = Instance.new("Frame", visualsOverlay)
    line.Name = "ESPLine"
    line.BorderSizePixel = 0
    line.AnchorPoint = Vector2.new(0.5, 0.5)
    line.BackgroundColor3 = colorPresets[config.espColorIndex].color
    line.Visible = false

    espVisualElements[p] = {Box = box, BoxStroke = boxStroke, Line = line}
end

local function removePlayerVisuals(p)
    if espVisualElements[p] then
        if espVisualElements[p].Box then espVisualElements[p].Box:Destroy() end
        if espVisualElements[p].Line then espVisualElements[p].Line:Destroy() end
        espVisualElements[p] = nil
    end
end

for _, p in ipairs(Players:GetPlayers()) do
    if p ~= localPlayer then createPlayerVisuals(p) end
end
Players.PlayerAdded:Connect(function(p)
    if p ~= localPlayer then createPlayerVisuals(p) end
end)
Players.PlayerRemoving:Connect(removePlayerVisuals)

-- Highlights Loop
RunService.Heartbeat:Connect(function()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= localPlayer and p.Character then
            local hl = p.Character:FindFirstChild("ESPHighlight")
            if config.esp and not isTeamMate(p) then
                if not hl then
                    hl = Instance.new("Highlight")
                    hl.Name = "ESPHighlight"
                    hl.Adornee = p.Character
                    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                    hl.FillTransparency = 0.5
                    hl.OutlineTransparency = 0
                    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    hl.Parent = p.Character
                end
                hl.Enabled = true
                hl.FillColor = isTeamMate(p) and Color3.fromRGB(30, 120, 255) or colorPresets[config.espColorIndex].color
            else
                if hl then hl.Enabled = false end
            end
        end
    end
end)

-- Rendu Boxes 2D & Snaplines
RunService.RenderStepped:Connect(function()
    local screenBottom = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y)
    local curColor = colorPresets[config.espColorIndex].color

    for p, elements in pairs(espVisualElements) do
        if isPlayerAlive(p) and not isTeamMate(p) then
            local char = p.Character
            local root = char:FindFirstChild("HumanoidRootPart")
            local head = char:FindFirstChild("Head")

            if root and head then
                local rootPos, onScreen = camera:WorldToViewportPoint(root.Position)
                local headPos = camera:WorldToViewportPoint(head.Position + Vector3.new(0, 0.6, 0))
                local legPos = camera:WorldToViewportPoint(root.Position - Vector3.new(0, 3, 0))

                if onScreen then
                    if config.espBoxes then
                        local height = math.abs(headPos.Y - legPos.Y)
                        local width = height * 0.6
                        elements.Box.Size = UDim2.new(0, width, 0, height)
                        elements.Box.Position = UDim2.new(0, rootPos.X - width / 2, 0, headPos.Y)
                        elements.BoxStroke.Color = curColor
                        elements.Box.Visible = true
                    else
                        elements.Box.Visible = false
                    end

                    if config.espTracers then
                        local targetVec = Vector2.new(rootPos.X, legPos.Y)
                        local distance = (screenBottom - targetVec).Magnitude
                        local center = (screenBottom + targetVec) / 2
                        local angle = math.deg(math.atan2(targetVec.Y - screenBottom.Y, targetVec.X - screenBottom.X))

                        elements.Line.Size = UDim2.new(0, distance, 0, 1.2)
                        elements.Line.Position = UDim2.new(0, center.X, 0, center.Y)
                        elements.Line.Rotation = angle
                        elements.Line.BackgroundColor3 = curColor
                        elements.Line.Visible = true
                    else
                        elements.Line.Visible = false
                    end
                else
                    elements.Box.Visible = false
                    elements.Line.Visible = false
                end
            else
                elements.Box.Visible = false
                elements.Line.Visible = false
            end
        else
            elements.Box.Visible = false
            elements.Line.Visible = false
        end
    end
end)

-- Spinbot & FOV
local spinAngle = 0
RunService.RenderStepped:Connect(function()
    if config.spinbot and localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart") then
        local root = localPlayer.Character.HumanoidRootPart
        spinAngle = (spinAngle + config.spinSpeed) % 360
        root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, math.rad(spinAngle), 0)
    end

    if camera.FieldOfView ~= config.cameraFov then
        camera.FieldOfView = config.cameraFov
    end
end)

-- NoClip
RunService.Stepped:Connect(function()
    if config.noclip and localPlayer.Character then
        for _, part in ipairs(localPlayer.Character:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then
                part.CanCollide = false
            end
        end
    end
end)

-- Fly Hack
RunService.RenderStepped:Connect(updateFly)

-- Infinite Jump
UserInputService.JumpRequest:Connect(function()
    if config.infJump and localPlayer.Character then
        local hum = localPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end
end)

-- Compteur FPS
local fpsCount, lastUpdate = 0, tick()
RunService.RenderStepped:Connect(function()
    fpsCount = fpsCount + 1
    if tick() - lastUpdate >= 1 then
        local ping = 0
        pcall(function()
            ping = math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue())
        end)
        fpsLabel.Text = string.format("%d FPS | %d ms", fpsCount, ping)
        fpsCount = 0
        lastUpdate = tick()
    end
end)

-------------------------------------------------------------------
-- CONTRÔLES CLAVIER & OUVERTURE DU MENU
-------------------------------------------------------------------
local isVisible = true
local function setMenuVisible(visible)
    isVisible = visible
    mainFrame.Visible = visible
end

closeButton.MouseButton1Click:Connect(function() setMenuVisible(false) end)

UserInputService.InputBegan:Connect(function(input, processed)
    if isRebindingAimKey then
        if input.UserInputType == Enum.UserInputType.Keyboard then
            config.aimKeyType = Enum.UserInputType.Keyboard
            config.aimKeyCode = input.KeyCode
            aimBadgeRef.Text = input.KeyCode.Name
            aimBadgeRef.TextColor3 = Color3.fromRGB(160, 165, 180)
            isRebindingAimKey = false
        elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
            config.aimKeyType = Enum.UserInputType.MouseButton1
            config.aimKeyCode = nil
            aimBadgeRef.Text = "MB1"
            aimBadgeRef.TextColor3 = Color3.fromRGB(160, 165, 180)
            isRebindingAimKey = false
        elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
            config.aimKeyType = Enum.UserInputType.MouseButton2
            config.aimKeyCode = nil
            aimBadgeRef.Text = "MB2"
            aimBadgeRef.TextColor3 = Color3.fromRGB(160, 165, 180)
            isRebindingAimKey = false
        elseif input.UserInputType == Enum.UserInputType.MouseButton3 then
            config.aimKeyType = Enum.UserInputType.MouseButton3
            config.aimKeyCode = nil
            aimBadgeRef.Text = "MB3"
            aimBadgeRef.TextColor3 = Color3.fromRGB(160, 165, 180)
            isRebindingAimKey = false
        end
        return
    end

    if (input.UserInputType == config.aimKeyType and config.aimKeyType ~= Enum.UserInputType.Keyboard) or
       (config.aimKeyType == Enum.UserInputType.Keyboard and input.KeyCode == config.aimKeyCode) then
        config.isAiming = true
    end

    if processed then return end

    if input.KeyCode == Enum.KeyCode.Tab then
        setMenuVisible(not isVisible)
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if (input.UserInputType == config.aimKeyType and config.aimKeyType ~= Enum.UserInputType.Keyboard) or
       (config.aimKeyType == Enum.UserInputType.Keyboard and input.KeyCode == config.aimKeyCode) then
        config.isAiming = false
    end
end)
