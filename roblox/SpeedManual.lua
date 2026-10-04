-- Velocidad del personaje
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local player = Players.LocalPlayer

if getgenv and getgenv().SpeedStop then pcall(getgenv().SpeedStop) end

local DEFAULT_SPEED = 16
local currentSpeed = DEFAULT_SPEED
local alive = true

local function applySpeed()
    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then hum.WalkSpeed = currentSpeed end
end

-- Reaplica la velocidad cada vez que renaces (el juego la resetea al respawnear)
player.CharacterAdded:Connect(function(char)
    local hum = char:WaitForChild("Humanoid", 5)
    if hum then hum.WalkSpeed = currentSpeed end
end)
applySpeed()

------------------------------------------------------------------
-- INTERFAZ
------------------------------------------------------------------
local function mk(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    o.Parent = parent
    return o
end

for _, holder in ipairs({function() return gethui() end,
                         function() return game:GetService("CoreGui") end,
                         function() return player.PlayerGui end}) do
    pcall(function()
        local old = holder():FindFirstChild("SpeedUI")
        if old then old:Destroy() end
    end)
end

local gui = Instance.new("ScreenGui")
gui.Name = "SpeedUI"
gui.ResetOnSpawn = false
local okParent = pcall(function()
    gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")
end)
if not okParent or not gui.Parent then gui.Parent = player:WaitForChild("PlayerGui") end

local WHITE = Color3.new(1, 1, 1)
local GREEN = Color3.fromRGB(46, 160, 67)
local GRAY = Color3.fromRGB(70, 70, 80)
local RED = Color3.fromRGB(170, 50, 50)
local BG = Color3.fromRGB(28, 28, 36)

local main = mk("Frame", {
    Size = UDim2.new(0, 230, 0, 170), Position = UDim2.new(0, 20, 0, 60),
    BackgroundColor3 = BG, BorderSizePixel = 0,
}, gui)
mk("UICorner", {CornerRadius = UDim.new(0, 10)}, main)

local title = mk("TextLabel", {
    Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = Color3.fromRGB(18, 18, 24),
    BorderSizePixel = 0, Text = "  Velocidad", TextColor3 = WHITE,
    Font = Enum.Font.GothamBold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left,
}, main)
mk("UICorner", {CornerRadius = UDim.new(0, 10)}, title)

local closeBtn = mk("TextButton", {
    Size = UDim2.new(0, 24, 0, 22), Position = UDim2.new(1, -28, 0, 4),
    Text = "×", BackgroundColor3 = RED, TextColor3 = WHITE,
    Font = Enum.Font.GothamBold, TextSize = 16, BorderSizePixel = 0,
}, title)

local valueLabel = mk("TextLabel", {
    Size = UDim2.new(1, -16, 0, 26), Position = UDim2.new(0, 8, 0, 36),
    BackgroundTransparency = 1, Text = "Velocidad actual: " .. currentSpeed,
    TextColor3 = WHITE, Font = Enum.Font.Gotham, TextSize = 13,
    TextXAlignment = Enum.TextXAlignment.Left,
}, main)

local box = mk("TextBox", {
    Size = UDim2.new(1, -16, 0, 30), Position = UDim2.new(0, 8, 0, 64),
    BackgroundColor3 = GRAY, Text = tostring(currentSpeed),
    TextColor3 = WHITE, Font = Enum.Font.Gotham, TextSize = 14,
    ClearTextOnFocus = false, BorderSizePixel = 0,
}, main)
mk("UICorner", {CornerRadius = UDim.new(0, 6)}, box)

local function setSpeed(v)
    v = math.clamp(tonumber(v) or currentSpeed, 1, 300)
    currentSpeed = v
    box.Text = tostring(v)
    valueLabel.Text = "Velocidad actual: " .. v
    applySpeed()
end

box.FocusLost:Connect(function(enter)
    if enter then setSpeed(box.Text) end
end)

local function stepBtn(text, x, delta)
    local b = mk("TextButton", {
        Size = UDim2.new(0, 68, 0, 30), Position = UDim2.new(0, x, 0, 100),
        Text = text, BackgroundColor3 = GRAY, TextColor3 = WHITE,
        Font = Enum.Font.GothamBold, TextSize = 13, BorderSizePixel = 0,
    }, main)
    mk("UICorner", {CornerRadius = UDim.new(0, 6)}, b)
    b.Activated:Connect(function() setSpeed(currentSpeed + delta) end)
    return b
end
stepBtn("-10", 8, -10)
stepBtn("-1", 81, -1)
stepBtn("+1", 154, 1)

local moreRow = mk("Frame", {
    Size = UDim2.new(1, -16, 0, 30), Position = UDim2.new(0, 8, 0, 134),
    BackgroundTransparency = 1,
}, main)
local plus10 = mk("TextButton", {
    Size = UDim2.new(0, 68, 1, 0), Text = "+10",
    BackgroundColor3 = GRAY, TextColor3 = WHITE,
    Font = Enum.Font.GothamBold, TextSize = 13, BorderSizePixel = 0,
}, moreRow)
mk("UICorner", {CornerRadius = UDim.new(0, 6)}, plus10)
plus10.Activated:Connect(function() setSpeed(currentSpeed + 10) end)

local resetBtn = mk("TextButton", {
    Size = UDim2.new(0, 68, 1, 0), Position = UDim2.new(0, 81, 0, 0),
    Text = "Normal (16)", BackgroundColor3 = GREEN, TextColor3 = WHITE,
    Font = Enum.Font.GothamBold, TextSize = 11, BorderSizePixel = 0,
}, moreRow)
mk("UICorner", {CornerRadius = UDim.new(0, 6)}, resetBtn)
resetBtn.Activated:Connect(function() setSpeed(DEFAULT_SPEED) end)

local godspeed = mk("TextButton", {
    Size = UDim2.new(0, 68, 1, 0), Position = UDim2.new(0, 154, 0, 0),
    Text = "x5", BackgroundColor3 = GRAY, TextColor3 = WHITE,
    Font = Enum.Font.GothamBold, TextSize = 13, BorderSizePixel = 0,
}, moreRow)
mk("UICorner", {CornerRadius = UDim.new(0, 6)}, godspeed)
godspeed.Activated:Connect(function() setSpeed(DEFAULT_SPEED * 5) end)

local function closeAll()
    alive = false
    setSpeed(DEFAULT_SPEED)
    gui:Destroy()
end
closeBtn.Activated:Connect(closeAll)
if getgenv then getgenv().SpeedStop = closeAll end

-- Arrastrar la ventana
local dragging, dragStart, startPos
title.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
        dragging, dragStart, startPos = true, i.Position, main.Position
    end
end)
UIS.InputChanged:Connect(function(i)
    if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement
        or i.UserInputType == Enum.UserInputType.Touch) then
        local d = i.Position - dragStart
        main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
                                  startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)
UIS.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)
