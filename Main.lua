local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local Players = game:GetService("Players")
local RbxAnalyticsService = game:GetService("RbxAnalyticsService")

local cloneref = cloneref or function(o) return o end
local gethui = gethui or function() return CoreGui end

local CoreGui = cloneref(game:GetService("CoreGui"))
local Players = cloneref(game:GetService("Players"))
local VirtualInputManager = cloneref(game:GetService("VirtualInputManager"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local RunService = cloneref(game:GetService("RunService"))
local TweenService = cloneref(game:GetService("TweenService"))
local LogService = cloneref(game:GetService("LogService"))
local GuiService = cloneref(game:GetService("GuiService"))

local request = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request

local TOGGLE_KEY = Enum.KeyCode.RightControl
local MIN_CPM = 50
local MAX_CPM_LEGIT = 1500
local MAX_CPM_BLATANT = 3000

math.randomseed(os.time())

local THEME = {
    Background = Color3.fromRGB(12, 12, 18),
    ItemBG = Color3.fromRGB(25, 25, 35),
    GlassOverlay = Color3.fromRGB(30, 30, 45),
    Accent = Color3.fromRGB(100, 200, 255),
    AccentSecondary = Color3.fromRGB(150, 100, 255),
    Text = Color3.fromRGB(240, 245, 250),
    SubText = Color3.fromRGB(140, 150, 170),
    Success = Color3.fromRGB(80, 220, 150),
    Warning = Color3.fromRGB(255, 180, 60),
    Slider = Color3.fromRGB(50, 60, 80)
}

local function ColorToRGB(c)
    return string.format("%d,%d,%d", math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255))
end

local ConfigFile = "lrrxware_Config.json"
local Config = {
    CPM = 550,
    Blatant = false,
    Humanize = true,
    FingerModel = true,
    SortMode = "Random",
    SuffixMode = "",
    LengthMode = 0,
    AutoPlay = false,
    AutoJoin = false,
    AutoJoinSettings = {
        _1v1 = true,
        _4p = true,
        _8p = true
    },
    PanicMode = true,
    ShowKeyboard = false,
    ErrorRate = 5,
    ThinkDelay = 0.8,
    RiskyMistakes = false,
    CustomWords = {},
    MinTypeSpeed = 50,
    MaxTypeSpeed = 3000,
    KeyboardLayout = "QWERTY"
}

local function SaveConfig()
    if writefile then
        writefile(ConfigFile, HttpService:JSONEncode(Config))
    end
end

local function LoadConfig()
    if isfile and isfile(ConfigFile) then
        local success, decoded = pcall(function() return HttpService:JSONDecode(readfile(ConfigFile)) end)
        if success and decoded then
            for k, v in pairs(decoded) do Config[k] = v end
        end
    end
end
LoadConfig()

local currentCPM = Config.CPM
local isBlatant = Config.Blatant
local useHumanization = Config.Humanize
local useFingerModel = Config.FingerModel
local sortMode = Config.SortMode
local suffixMode = Config.SuffixMode or ""
local lengthMode = Config.LengthMode or 0
local autoPlay = Config.AutoPlay
local autoJoin = Config.AutoJoin
local panicMode = Config.PanicMode
local showKeyboard = Config.ShowKeyboard
local errorRate = Config.ErrorRate
local thinkDelayCurrent = Config.ThinkDelay
local riskyMistakes = Config.RiskyMistakes
local keyboardLayout = Config.KeyboardLayout or "QWERTY"

local isTyping = false
local isAutoPlayScheduled = false
local lastTypingStart = 0
local runConn = nil
local inputConn = nil
local logConn = nil
local unloaded = false
local isMyTurnLogDetected = false
local logRequiredLetters = ""
local turnExpiryTime = 0
local Blacklist = {}
local UsedWords = {}
local RandomOrderCache = {}
local RandomPriority = {}
local lastDetected = "---"
local lastLogicUpdate = 0
local lastAutoJoinCheck = 0
local lastWordCheck = 0
local cachedDetected = ""
local cachedCensored = false
local LOGIC_RATE = 0.1
local AUTO_JOIN_RATE = 0.5
local UpdateList
local ButtonCache = {}
local ButtonData = {}
local JoinDebounce = {}
local thinkDelayMin = 0.4
local thinkDelayMax = 1.2

local listUpdatePending = false
local forceUpdateList = false
local lastInputTime = 0
local LIST_DEBOUNCE = 0.05
local currentBestMatch = nil

if logConn then logConn:Disconnect() end
logConn = LogService.MessageOut:Connect(function(message, type)
    local wordPart, timePart = message:match("Word:%s*([A-Za-z]+)%s+Time to respond:%s*(%d+)")
    if wordPart and timePart then
        isMyTurnLogDetected = true
        logRequiredLetters = wordPart
        turnExpiryTime = tick() + tonumber(timePart)
    end
end)

local url = "https://raw.githubusercontent.com/skrylor/english-words/refs/heads/main/merged_english.txt"
local fileName = "ultimate_words_v4.txt"

-- Futuristic Loading UI
local LoadingGui = Instance.new("ScreenGui")
LoadingGui.Name = "lrrxwareLoading"
local success, parent = pcall(function() return gethui() end)
if not success or not parent then parent = game:GetService("CoreGui") end
LoadingGui.Parent = parent
LoadingGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local LoadingFrame = Instance.new("Frame", LoadingGui)
LoadingFrame.Size = UDim2.new(0, 350, 0, 140)
LoadingFrame.Position = UDim2.new(0.5, -175, 0.4, 0)
LoadingFrame.BackgroundColor3 = THEME.Background
LoadingFrame.BorderSizePixel = 0
LoadingFrame.BackgroundTransparency = 0.15
Instance.new("UICorner", LoadingFrame).CornerRadius = UDim.new(0, 15)
local LStroke = Instance.new("UIStroke", LoadingFrame)
LStroke.Color = THEME.Accent
LStroke.Transparency = 0.3
LStroke.Thickness = 2.5

-- Glass effect blur illusion
local blurEffect = Instance.new("Frame", LoadingFrame)
blurEffect.Size = UDim2.new(1, 0, 1, 0)
blurEffect.BackgroundColor3 = THEME.GlassOverlay
blurEffect.BackgroundTransparency = 0.8
blurEffect.BorderSizePixel = 0
Instance.new("UICorner", blurEffect).CornerRadius = UDim.new(0, 15)

local LoadingTitle = Instance.new("TextLabel", LoadingFrame)
LoadingTitle.Size = UDim2.new(1, 0, 0, 50)
LoadingTitle.BackgroundTransparency = 1
LoadingTitle.Text = "⚡ lrrxware v1"
LoadingTitle.TextColor3 = THEME.Accent
LoadingTitle.Font = Enum.Font.GothamBold
LoadingTitle.TextSize = 24

local LoadingStatus = Instance.new("TextLabel", LoadingFrame)
LoadingStatus.Size = UDim2.new(1, -40, 0, 30)
LoadingStatus.Position = UDim2.new(0, 20, 0, 60)
LoadingStatus.BackgroundTransparency = 1
LoadingStatus.Text = "Initializing..."
LoadingStatus.TextColor3 = THEME.Text
LoadingStatus.Font = Enum.Font.Gotham
LoadingStatus.TextSize = 13

local function UpdateStatus(text, color)
    LoadingStatus.Text = text
    if color then LoadingStatus.TextColor3 = color end
    game:GetService("RunService").RenderStepped:Wait()
end

-- Startup: Always fetch fresh word list
local function FetchWords()
    UpdateStatus("⟳ Fetching latest word list...", THEME.Warning)
    local success, res = pcall(function()
        return request({Url = url, Method = "GET"})
    end)
    
    if success and res and res.Body then
        writefile(fileName, res.Body)
        UpdateStatus("✓ Fetched successfully!", THEME.Success)
    else
        UpdateStatus("✗ Fetch failed! Using cached.", Color3.fromRGB(255, 100, 100))
    end
    task.wait(0.5)
end

FetchWords()

local Words = {}
local SeenWords = {}

local function LoadList(fname)
    UpdateStatus("✓ Parsing word list...", THEME.Warning)
    if isfile(fname) then
        local content = readfile(fname)
        for w in content:gmatch("[^\r\n]+") do
            local clean = w:gsub("[%s%c]+", ""):lower()
            if #clean > 0 and not SeenWords[clean] then
                SeenWords[clean] = true
                table.insert(Words, clean)
            end
        end
        UpdateStatus("✓ Loaded " .. #Words .. " words!", THEME.Success)
    else
         UpdateStatus("✗ No word list found!", Color3.fromRGB(255, 100, 100))
    end
    task.wait(1)
end

LoadList(fileName)

if LoadingGui then LoadingGui:Destroy() end

table.sort(Words)
Buckets = {}
for _, w in ipairs(Words) do
    local c = w:sub(1,1) or ""
    if c == "" then c = "#" end
    Buckets[c] = Buckets[c] or {}
    table.insert(Buckets[c], w)
end

if Config.CustomWords then
    for _, w in ipairs(Config.CustomWords) do
        local clean = w:gsub("[%s%c]+", ""):lower()
        if #clean > 0 and not SeenWords[clean] then
            SeenWords[clean] = true
            table.insert(Words, clean)
            local c = clean:sub(1,1) or ""
            if c == "" then c = "#" end
            Buckets[c] = Buckets[c] or {}
            table.insert(Buckets[c], clean)
        end
    end
end

-- Clear memory
SeenWords = nil

local function shuffleTable(t)
    local n = #t
    for i = n, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

local HardLetterScores = {
    x = 10, z = 9, q = 9, j = 8, v = 6, k = 5, b = 4, f = 3, w = 3,
    y = 2, g = 2, p = 2
}

local function GetKillerScore(word)
    local lastChar = word:sub(-1)
    return HardLetterScores[lastChar] or 0
end

local function getDistance(s1, s2)
    if #s1 == 0 then
        return #s2
    end
    if #s2 == 0 then
        return #s1
    end
    if s1 == s2 then
        return 0
    end
    local matrix = {}
    for i = 0, #s1 do matrix[i] = {[0] = i} end
    for j = 0, #s2 do matrix[0][j] = j end
    for i = 1, #s1 do
        for j = 1, #s2 do
            local cost = (s1:sub(i,i) == s2:sub(j,j)) and 0 or 1
            matrix[i][j] = math.min(matrix[i-1][j]+1, matrix[i][j-1]+1, matrix[i-1][j-1]+cost)
        end
    end
    return matrix[#s1][#s2]
end

local function Tween(obj, props, time)
    TweenService:Create(obj, TweenInfo.new(time or 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local function GetCurrentGameWord(providedFrame)
    local frame = providedFrame
    if not frame then
        local player = Players.LocalPlayer
        local gui = player and player:FindFirstChild("PlayerGui")
        local inGame = gui and gui:FindFirstChild("InGame")
        frame = inGame and inGame:FindFirstChild("Frame")
    end

    local container = frame and frame:FindFirstChild("CurrentWord")
    if not container then return "", false end
    
    local detected = ""
    local censored = false
    
    local children = container:GetChildren()
    local letterData = {}
    
    for _, c in ipairs(children) do
        if c:IsA("GuiObject") and c.Visible then
            local txt = c:FindFirstChild("Letter")
            if txt and txt:IsA("TextLabel") and txt.TextTransparency < 1 then
                table.insert(letterData, {
                    Obj = c,
                    Txt = txt,
                    X = c.AbsolutePosition.X,
                    Id = tonumber(c.Name) or 0
                })
            end
        end
    end
    
    table.sort(letterData, function(a,b)
        if math.abs(a.X - b.X) > 2 then
            return a.X < b.X
        end
        return a.Id < b.Id
    end)

    for _, data in ipairs(letterData) do
        local t = tostring(data.Txt.Text)
        if t:find("#") or t:find("%*") then censored = true end
        detected = detected .. t
    end
    
    return detected:lower():gsub(" ", ""), censored
end

local function GetTurnInfo(providedFrame)
    if isMyTurnLogDetected then
        if tick() < turnExpiryTime then
            return true, logRequiredLetters
        else
            isMyTurnLogDetected = false
        end
    end

    local frame = providedFrame
    if not frame then
        local player = Players.LocalPlayer
        local gui = player and player:FindFirstChild("PlayerGui")
        local inGame = gui and gui:FindFirstChild("InGame")
        frame = inGame and inGame:FindFirstChild("Frame")
    end

    local typeLbl = frame and frame:FindFirstChild("Type")
    
    if typeLbl and typeLbl:IsA("TextLabel") then
        local text = typeLbl.Text
        local player = Players.LocalPlayer
        if text:sub(1, #player.Name) == player.Name or text:sub(1, #player.DisplayName) == player.DisplayName then
            local char = text:match("starting with:%s*([A-Za-z])")
            return true, char
        end
    end
    return false, nil
end

local function GetSecureParent()
    local success, result = pcall(function()
        return gethui()
    end)
    if success and result then return result end
    
    success, result = pcall(function()
        return CoreGui
    end)
    if success and result then return result end
    
    return Players.LocalPlayer.PlayerGui
end

local ParentTarget = GetSecureParent()
local GuiName = tostring(math.random(1000000, 9999999))

local env = (getgenv and getgenv()) or _G

if env.lrrxwareInstance and env.lrrxwareInstance.Parent then
    env.lrrxwareInstance:Destroy()
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = GuiName
ScreenGui.Parent = ParentTarget
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

env.lrrxwareInstance = ScreenGui

local ToastContainer = Instance.new("Frame", ScreenGui)
ToastContainer.Name = "ToastContainer"
ToastContainer.Size = UDim2.new(0, 300, 1, 0)
ToastContainer.Position = UDim2.new(1, -320, 0, 20)
ToastContainer.BackgroundTransparency = 1
ToastContainer.ZIndex = 100

local function ShowToast(message, type)
    local toast = Instance.new("Frame")
    toast.Size = UDim2.new(1, 0, 0, 45)
    toast.BackgroundColor3 = THEME.ItemBG
    toast.BorderSizePixel = 0
    toast.BackgroundTransparency = 0.2
    toast.Parent = ToastContainer
    
    local stroke = Instance.new("UIStroke", toast)
    stroke.Thickness = 1.5
    stroke.Transparency = 0.4
    
    local color = THEME.Text
    if type == "success" then color = THEME.Success
    elseif type == "warning" then color = THEME.Warning
    elseif type == "error" then color = Color3.fromRGB(255, 100, 100)
    end
    stroke.Color = color
    
    Instance.new("UICorner", toast).CornerRadius = UDim.new(0, 10)
    
    local lbl = Instance.new("TextLabel", toast)
    lbl.Size = UDim2.new(1, -20, 1, 0)
    lbl.Position = UDim2.new(0, 10, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = message
    lbl.TextColor3 = color
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextSize = 13
    lbl.TextWrapped = true
    lbl.TextTransparency = 0.3
    
    Tween(toast, {BackgroundTransparency = 0.15}, 0.3)
    Tween(lbl, {TextTransparency = 0}, 0.3)
    Tween(stroke, {Transparency = 0.2}, 0.3)
    
    task.delay(3, function()
        if toast and toast.Parent then
            Tween(toast, {BackgroundTransparency = 1}, 0.5)
            Tween(lbl, {TextTransparency = 1}, 0.5)
            Tween(stroke, {Transparency = 1}, 0.5)
            task.wait(0.5)
            toast:Destroy()
        end
    end)
end

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 340, 0, 550)
MainFrame.Position = UDim2.new(0.8, -50, 0.4, 0)
MainFrame.BackgroundColor3 = THEME.Background
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.ClipsDescendants = true
MainFrame.Parent = ScreenGui
MainFrame.BackgroundTransparency = 0.2

local function EnableDragging(frame)
    local dragging, dragInput, dragStart, startPos
    local function Update(input)
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
    
    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
            
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    
    frame.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            Update(input)
        end
    end)
end

EnableDragging(MainFrame)

Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 20)
local Stroke = Instance.new("UIStroke", MainFrame)
Stroke.Color = THEME.Accent
Stroke.Transparency = 0.4
Stroke.Thickness = 2.5

local Header = Instance.new("Frame", MainFrame)
Header.Size = UDim2.new(1, 0, 0, 55)
Header.BackgroundColor3 = THEME.GlassOverlay
Header.BorderSizePixel = 0
Header.BackgroundTransparency = 0.3

local HeaderStroke = Instance.new("UIStroke", Header)
HeaderStroke.Color = THEME.AccentSecondary
HeaderStroke.Transparency = 0.5
HeaderStroke.Thickness = 1

Instance.new("UICorner", Header).CornerRadius = UDim.new(0, 20)

local Title = Instance.new("TextLabel", Header)
Title.Text = "⚡ lrrxware <font color=\"rgb(150,100,255)\">v1</font>"
Title.RichText = true
Title.Font = Enum.Font.GothamBold
Title.TextSize = 20
Title.TextColor3 = THEME.Accent
Title.Size = UDim2.new(1, -100, 1, 0)
Title.Position = UDim2.new(0, 15, 0, 0)
Title.BackgroundTransparency = 1
Title.TextXAlignment = Enum.TextXAlignment.Left

local MinBtn = Instance.new("TextButton", Header)
MinBtn.Text = "−"
MinBtn.Font = Enum.Font.GothamBold
MinBtn.TextSize = 24
MinBtn.TextColor3 = THEME.SubText
MinBtn.Size = UDim2.new(0, 45, 1, 0)
MinBtn.Position = UDim2.new(1, -90, 0, 0)
MinBtn.BackgroundTransparency = 1

local CloseBtn = Instance.new("TextButton", Header)
CloseBtn.Text = "✕"
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 20
CloseBtn.TextColor3 = Color3.fromRGB(255, 100, 120)
CloseBtn.Size = UDim2.new(0, 45, 1, 0)
CloseBtn.Position = UDim2.new(1, -45, 0, 0)
CloseBtn.BackgroundTransparency = 1

CloseBtn.MouseButton1Click:Connect(function()
    unloaded = true
    if runConn then runConn:Disconnect() runConn = nil end
    if inputConn then inputConn:Disconnect() inputConn = nil end
    if logConn then logConn:Disconnect() logConn = nil end
    
    for _, btn in ipairs(ButtonCache) do btn:Destroy() end
    table.clear(ButtonCache)

    if ScreenGui and ScreenGui.Parent then ScreenGui:Destroy() end
end)

local StatusFrame = Instance.new("Frame", MainFrame)
StatusFrame.Size = UDim2.new(1, -30, 0, 26)
StatusFrame.Position = UDim2.new(0, 15, 0, 62)
StatusFrame.BackgroundTransparency = 1

local StatusDot = Instance.new("Frame", StatusFrame)
StatusDot.Size = UDim2.new(0, 8, 0, 8)
StatusDot.Position = UDim2.new(0, 0, 0.5, -4)
StatusDot.BackgroundColor3 = THEME.Accent
Instance.new("UICorner", StatusDot).CornerRadius = UDim.new(1, 0)

local StatusText = Instance.new("TextLabel", StatusFrame)
StatusText.Text = "● Idle..."
StatusText.RichText = true
StatusText.Font = Enum.Font.Gotham
StatusText.TextSize = 12
StatusText.TextColor3 = THEME.SubText
StatusText.Size = UDim2.new(1, -15, 1, 0)
StatusText.Position = UDim2.new(0, 15, 0, 0)
StatusText.BackgroundTransparency = 1
StatusText.TextXAlignment = Enum.TextXAlignment.Left

local SearchFrame = Instance.new("Frame", MainFrame)
SearchFrame.Size = UDim2.new(1, -10, 0, 32)
SearchFrame.Position = UDim2.new(0, 5, 0, 95)
SearchFrame.BackgroundColor3 = THEME.ItemBG
SearchFrame.BackgroundTransparency = 0.3
Instance.new("UICorner", SearchFrame).CornerRadius = UDim.new(0, 10)

local SearchStroke = Instance.new("UIStroke", SearchFrame)
SearchStroke.Color = THEME.Accent
SearchStroke.Transparency = 0.6
SearchStroke.Thickness = 1.5

local SearchBox = Instance.new("TextBox", SearchFrame)
SearchBox.Size = UDim2.new(1, -20, 1, 0)
SearchBox.Position = UDim2.new(0, 10, 0, 0)
SearchBox.BackgroundTransparency = 1
SearchBox.Font = Enum.Font.Gotham
SearchBox.TextSize = 14
SearchBox.TextColor3 = THEME.Text
SearchBox.PlaceholderText = "🔍 Search words..."
SearchBox.PlaceholderColor3 = THEME.SubText
SearchBox.Text = ""
SearchBox.TextXAlignment = Enum.TextXAlignment.Left

SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
    if UpdateList then
        UpdateList(lastDetected, lastRequiredLetter)
    end
end)

local ScrollList = Instance.new("ScrollingFrame", MainFrame)
ScrollList.Size = UDim2.new(1, -10, 1, -250)
ScrollList.Position = UDim2.new(0, 5, 0, 135)
ScrollList.BackgroundTransparency = 1
ScrollList.ScrollBarThickness = 4
ScrollList.ScrollBarImageColor3 = THEME.AccentSecondary
ScrollList.CanvasSize = UDim2.new(0,0,0,0)

local UIListLayout = Instance.new("UIListLayout", ScrollList)
UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
UIListLayout.Padding = UDim.new(0, 5)

local SettingsFrame = Instance.new("Frame", MainFrame)
SettingsFrame.BackgroundColor3 = THEME.ItemBG
SettingsFrame.BorderSizePixel = 0
SettingsFrame.ClipsDescendants = true
SettingsFrame.BackgroundTransparency = 0.2

local SlidersFrame = Instance.new("Frame", SettingsFrame)
SlidersFrame.Size = UDim2.new(1, 0, 0, 140)
SlidersFrame.BackgroundTransparency = 1

local TogglesFrame = Instance.new("Frame", SettingsFrame)
TogglesFrame.Size = UDim2.new(1, 0, 0, 330)
TogglesFrame.Position = UDim2.new(0, 0, 0, 140)
TogglesFrame.BackgroundTransparency = 1
TogglesFrame.Visible = false

local sep = Instance.new("Frame", SettingsFrame)
sep.Size = UDim2.new(1, 0, 0, 1)
sep.BackgroundColor3 = Color3.fromRGB(60, 80, 100)
sep.BackgroundTransparency = 0.5

local settingsCollapsed = true
local function UpdateLayout()
    if settingsCollapsed then
        Tween(SettingsFrame, {Size = UDim2.new(1, 0, 0, 140), Position = UDim2.new(0, 0, 1, -140)})
        Tween(ScrollList, {Size = UDim2.new(1, -10, 1, -270)})
        TogglesFrame.Visible = false
    else
        Tween(SettingsFrame, {Size = UDim2.new(1, 0, 0, 470), Position = UDim2.new(0, 0, 1, -470)})
        Tween(ScrollList, {Size = UDim2.new(1, -10, 1, -600)})
        TogglesFrame.Visible = true
    end
end
UpdateLayout()

local ExpandBtn = Instance.new("TextButton", SlidersFrame)
ExpandBtn.Text = "▼ Settings ▼"
ExpandBtn.Font = Enum.Font.GothamBold
ExpandBtn.TextSize = 13
ExpandBtn.TextColor3 = THEME.Accent
ExpandBtn.BackgroundColor3 = THEME.GlassOverlay
ExpandBtn.BackgroundTransparency = 0.4
ExpandBtn.Size = UDim2.new(1, -10, 0, 32)
ExpandBtn.Position = UDim2.new(0, 5, 1, -37)
Instance.new("UICorner", ExpandBtn).CornerRadius = UDim.new(0, 8)

local ExpandStroke = Instance.new("UIStroke", ExpandBtn)
ExpandStroke.Color = THEME.AccentSecondary
ExpandStroke.Transparency = 0.6
ExpandStroke.Thickness = 1.5

ExpandBtn.MouseButton1Click:Connect(function()
    settingsCollapsed = not settingsCollapsed
    ExpandBtn.Text = settingsCollapsed and "▼ Settings ▼" or "▲ Settings ▲"
    UpdateLayout()
end)

local function SetupSlider(btn, bg, fill, callback)
    btn.MouseButton1Down:Connect(function()
        local move, rel
        local function Update()
            local mousePos = UserInputService:GetMouseLocation()
            local relX = math.clamp(mousePos.X - bg.AbsolutePosition.X, 0, bg.AbsoluteSize.X)
            local pct = relX / bg.AbsoluteSize.X
            callback(pct)
            Config.CPM = currentCPM
            Config.ErrorRate = errorRate
            Config.ThinkDelay = thinkDelayCurrent
        end
        Update()
        move = RunService.RenderStepped:Connect(Update)
        rel = UserInputService.InputEnded:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
                if move then move:Disconnect() move = nil end
                if rel then rel:Disconnect() rel = nil end
                SaveConfig()
            end
        end)
    end)
end

local KeyboardFrame = Instance.new("Frame", ScreenGui)
KeyboardFrame.Name = "KeyboardFrame"
KeyboardFrame.Size = UDim2.new(0, 450, 0, 180)
KeyboardFrame.Position = UDim2.new(0.1, 0, 0.5, -90)
KeyboardFrame.BackgroundColor3 = THEME.Background
KeyboardFrame.BackgroundTransparency = 0.2
KeyboardFrame.Visible = showKeyboard
EnableDragging(KeyboardFrame)
Instance.new("UICorner", KeyboardFrame).CornerRadius = UDim.new(0, 15)
local KStroke = Instance.new("UIStroke", KeyboardFrame)
KStroke.Color = THEME.AccentSecondary
KStroke.Transparency = 0.4
KStroke.Thickness = 2.5

local Keys = {}
local function CreateKey(char, pos, size)
    local k = Instance.new("Frame", KeyboardFrame)
    k.Size = size or UDim2.new(0, 35, 0, 35)
    k.Position = pos
    k.BackgroundColor3 = THEME.ItemBG
    k.BackgroundTransparency = 0.2
    Instance.new("UICorner", k).CornerRadius = UDim.new(0, 6)
    
    local stroke = Instance.new("UIStroke", k)
    stroke.Color = THEME.AccentSecondary
    stroke.Transparency = 0.7
    stroke.Thickness = 1
    
    local l = Instance.new("TextLabel", k)
    l.Size = UDim2.new(1,0,1,0)
    l.BackgroundTransparency = 1
    l.Text = char:upper()
    l.TextColor3 = THEME.Text
    l.Font = Enum.Font.GothamBold
    l.TextSize = 12
    
    Keys[char:lower()] = k
    return k
end

local function GenerateKeyboard()
    for _, c in ipairs(KeyboardFrame:GetChildren()) do
        if c:IsA("Frame") or c:IsA("TextLabel") then c:Destroy() end
    end
    Keys = {}
    
    local rows
    if keyboardLayout == "QWERTZ" then
        rows = {
            {"q","w","e","r","t","z","u","i","o","p"},
            {"a","s","d","f","g","h","j","k","l"},
            {"y","x","c","v","b","n","m"}
        }
    elseif keyboardLayout == "AZERTY" then
        rows = {
            {"a","z","e","r","t","y","u","i","o","p"},
            {"q","s","d","f","g","h","j","k","l","m"},
            {"w","x","c","v","b","n"}
        }
    else -- QWERTY
        rows = {
            {"q","w","e","r","t","y","u","i","o","p"},
            {"a","s","d","f","g","h","j","k","l"},
            {"z","x","c","v","b","n","m"}
        }
    end
    
    local startY = 18
    local spacing = 40
    for r, rowChars in ipairs(rows) do
        local rowWidth = #rowChars * 40
        local startX = (450 - rowWidth) / 2
        for i, char in ipairs(rowChars) do
            CreateKey(char, UDim2.new(0, startX + (i-1)*40, 0, startY + (r-1)*40))
        end
    end
    local space = CreateKey(" ", UDim2.new(0.5, -110, 0, startY + 3*40), UDim2.new(0, 220, 0, 35))
    space.FindFirstChild(space, "TextLabel").Text = "SPACE"
end

GenerateKeyboard()

local function CreateDropdown(parent, text, options, default, callback)
    local container = Instance.new("Frame", parent)
    container.Size = UDim2.new(0, 140, 0, 28)
    container.BackgroundColor3 = THEME.Background
    container.ZIndex = 10
    container.BackgroundTransparency = 0.3
    Instance.new("UICorner", container).CornerRadius = UDim.new(0, 6)
    
    local stroke = Instance.new("UIStroke", container)
    stroke.Color = THEME.Accent
    stroke.Transparency = 0.6
    stroke.Thickness = 1
    
    local mainBtn = Instance.new("TextButton", container)
    mainBtn.Size = UDim2.new(1, 0, 1, 0)
    mainBtn.BackgroundTransparency = 1
    mainBtn.Text = text .. ": " .. default
    mainBtn.Font = Enum.Font.GothamMedium
    mainBtn.TextSize = 11
    mainBtn.TextColor3 = THEME.Accent
    mainBtn.ZIndex = 11

    local listFrame = Instance.new("Frame", container)
    listFrame.Size = UDim2.new(1, 0, 0, #options * 28)
    listFrame.Position = UDim2.new(0, 0, 1, 2)
    listFrame.BackgroundColor3 = THEME.ItemBG
    listFrame.BackgroundTransparency = 0.15
    listFrame.Visible = false
    listFrame.ZIndex = 20
    Instance.new("UICorner", listFrame).CornerRadius = UDim.new(0, 6)
    
    local isOpen = false
    
    mainBtn.MouseButton1Click:Connect(function()
        isOpen = not isOpen
        listFrame.Visible = isOpen
    end)
    
    for i, opt in ipairs(options) do
        local btn = Instance.new("TextButton", listFrame)
        btn.Size = UDim2.new(1, 0, 0, 28)
        btn.Position = UDim2.new(0, 0, 0, (i-1)*28)
        btn.BackgroundTransparency = 1
        btn.Text = opt
        btn.Font = Enum.Font.Gotham
        btn.TextSize = 11
        btn.TextColor3 = THEME.Text
        btn.ZIndex = 21
        
        btn.MouseButton1Click:Connect(function()
            mainBtn.Text = text .. ": " .. opt
            isOpen = false
            listFrame.Visible = false
            callback(opt)
        end)
    end
    
    return container
end

local LayoutDropdown = CreateDropdown(TogglesFrame, "Layout", {"QWERTY", "QWERTZ", "AZERTY"}, keyboardLayout, function(val)
    keyboardLayout = val
    Config.KeyboardLayout = keyboardLayout
    GenerateKeyboard()
    SaveConfig()
end)
LayoutDropdown.Position = UDim2.new(0, 150, 0, 160)

UserInputService.InputBegan:Connect(function(input)
    if not showKeyboard then return end
    if input.UserInputType == Enum.UserInputType.Keyboard then
        local char = input.KeyCode.Name:lower()
        if Keys[char] then
            Tween(Keys[char], {BackgroundColor3 = THEME.Accent}, 0.1)
        end
        if input.KeyCode == Enum.KeyCode.Space then
            Tween(Keys[" "], {BackgroundColor3 = THEME.Accent}, 0.1)
        end
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if not showKeyboard then return end
    if input.UserInputType == Enum.UserInputType.Keyboard then
        local char = input.KeyCode.Name:lower()
        if Keys[char] then
            Tween(Keys[char], {BackgroundColor3 = THEME.ItemBG}, 0.2)
        end
        if input.KeyCode == Enum.KeyCode.Space then
            Tween(Keys[" "], {BackgroundColor3 = THEME.ItemBG}, 0.2)
        end
    end
end)

local SliderLabel = Instance.new("TextLabel", SlidersFrame)
SliderLabel.Text = "⚡ Speed: " .. currentCPM .. " CPM"
SliderLabel.Font = Enum.Font.GothamMedium
SliderLabel.TextSize = 12
SliderLabel.TextColor3 = THEME.SubText
SliderLabel.Size = UDim2.new(1, -30, 0, 22)
SliderLabel.Position = UDim2.new(0, 15, 0, 8)
SliderLabel.BackgroundTransparency = 1
SliderLabel.TextXAlignment = Enum.TextXAlignment.Left

local SliderBg = Instance.new("Frame", SlidersFrame)
SliderBg.Size = UDim2.new(1, -30, 0, 8)
SliderBg.Position = UDim2.new(0, 15, 0, 32)
SliderBg.BackgroundColor3 = THEME.Slider
SliderBg.BackgroundTransparency = 0.3
Instance.new("UICorner", SliderBg).CornerRadius = UDim.new(1, 0)

local SliderFill = Instance.new("Frame", SliderBg)
SliderFill.Size = UDim2.new(0.5, 0, 1, 0)
SliderFill.BackgroundColor3 = THEME.Accent
Instance.new("UICorner", SliderFill).CornerRadius = UDim.new(1, 0)

local SliderBtn = Instance.new("TextButton", SliderBg)
SliderBtn.Size = UDim2.new(1,0,1,0)
SliderBtn.BackgroundTransparency = 1
SliderBtn.Text = ""

local ErrorLabel = Instance.new("TextLabel", SlidersFrame)
ErrorLabel.Text = "⚠ Error Rate: " .. errorRate .. "%"
ErrorLabel.Font = Enum.Font.GothamMedium
ErrorLabel.TextSize = 11
ErrorLabel.TextColor3 = THEME.SubText
ErrorLabel.Size = UDim2.new(1, -30, 0, 20)
ErrorLabel.Position = UDim2.new(0, 15, 0, 44)
ErrorLabel.BackgroundTransparency = 1
ErrorLabel.TextXAlignment = Enum.TextXAlignment.Left

local ErrorBg = Instance.new("Frame", SlidersFrame)
ErrorBg.Size = UDim2.new(1, -30, 0, 8)
ErrorBg.Position = UDim2.new(0, 15, 0, 66)
ErrorBg.BackgroundColor3 = THEME.Slider
ErrorBg.BackgroundTransparency = 0.3
Instance.new("UICorner", ErrorBg).CornerRadius = UDim.new(1, 0)

local ErrorFill = Instance.new("Frame", ErrorBg)
ErrorFill.Size = UDim2.new(errorRate/30, 0, 1, 0)
ErrorFill.BackgroundColor3 = Color3.fromRGB(255, 140, 100)
Instance.new("UICorner", ErrorFill).CornerRadius = UDim.new(1, 0)

local ErrorBtn = Instance.new("TextButton", ErrorBg)
ErrorBtn.Size = UDim2.new(1,0,1,0)
ErrorBtn.BackgroundTransparency = 1
ErrorBtn.Text = ""

SetupSlider(ErrorBtn, ErrorBg, ErrorFill, function(pct)
    errorRate = math.floor(pct * 30)
    Config.ErrorRate = errorRate
    ErrorFill.Size = UDim2.new(pct, 0, 1, 0)
    ErrorLabel.Text = "⚠ Error Rate: " .. errorRate .. "% (per-letter)"
end)

local ThinkLabel = Instance.new("TextLabel", SlidersFrame)
ThinkLabel.Text = string.format("⏱ Think: %.2fs", thinkDelayCurrent)
ThinkLabel.Font = Enum.Font.GothamMedium
ThinkLabel.TextSize = 11
ThinkLabel.TextColor3 = THEME.SubText
ThinkLabel.Size = UDim2.new(1, -30, 0, 20)
ThinkLabel.Position = UDim2.new(0, 15, 0, 78)
ThinkLabel.BackgroundTransparency = 1
ThinkLabel.TextXAlignment = Enum.TextXAlignment.Left

local ThinkBg = Instance.new("Frame", SlidersFrame)
ThinkBg.Size = UDim2.new(1, -30, 0, 8)
ThinkBg.Position = UDim2.new(0, 15, 0, 100)
ThinkBg.BackgroundColor3 = THEME.Slider
ThinkBg.BackgroundTransparency = 0.3
Instance.new("UICorner", ThinkBg).CornerRadius = UDim.new(1, 0)

local ThinkFill = Instance.new("Frame", ThinkBg)
local thinkPct = (thinkDelayCurrent - thinkDelayMin) / (thinkDelayMax - thinkDelayMin)
ThinkFill.Size = UDim2.new(thinkPct, 0, 1, 0)
ThinkFill.BackgroundColor3 = THEME.AccentSecondary
Instance.new("UICorner", ThinkFill).CornerRadius = UDim.new(1, 0)

local ThinkBtn = Instance.new("TextButton", ThinkBg)
ThinkBtn.Size = UDim2.new(1,0,1,0)
ThinkBtn.BackgroundTransparency = 1
ThinkBtn.Text = ""

SetupSlider(ThinkBtn, ThinkBg, ThinkFill, function(pct)
    thinkDelayCurrent = thinkDelayMin + pct * (thinkDelayMax - thinkDelayMin)
    Config.ThinkDelay = thinkDelayCurrent
    ThinkFill.Size = UDim2.new(pct, 0, 1, 0)
    ThinkLabel.Text = string.format("⏱ Think: %.2fs", thinkDelayCurrent)
end)

local function CreateToggle(text, pos, callback)
    local btn = Instance.new("TextButton", TogglesFrame)
    btn.Text = text
    btn.Font = Enum.Font.GothamMedium
    btn.TextSize = 11
    btn.TextColor3 = THEME.Success
    btn.BackgroundColor3 = THEME.ItemBG
    btn.BackgroundTransparency = 0.3
    btn.Size = UDim2.new(0, 95, 0, 28)
    btn.Position = pos
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
    
    local stroke = Instance.new("UIStroke", btn)
    stroke.Color = THEME.Accent
    stroke.Transparency = 0.7
    stroke.Thickness = 1
    
    btn.MouseButton1Click:Connect(function()
        local newState, newText, newColor = callback()
        btn.Text = newText
        btn.TextColor3 = newColor
        SaveConfig()
    end)
    return btn
end

local HumanizeBtn = CreateToggle("✓ Humanize: "..(useHumanization and "ON" or "OFF"), UDim2.new(0, 15, 0, 8), function()
    useHumanization = not useHumanization
    Config.Humanize = useHumanization
    return useHumanization, "✓ Humanize: "..(useHumanization and "ON" or "OFF"), useHumanization and THEME.Success or Color3.fromRGB(255, 120, 100)
end)
HumanizeBtn.TextColor3 = useHumanization and THEME.Success or Color3.fromRGB(255, 120, 100)

local FingerBtn = CreateToggle("✋ 10-Finger: "..(useFingerModel and "ON" or "OFF"), UDim2.new(0, 120, 0, 8), function()
    useFingerModel = not useFingerModel
    Config.FingerModel = useFingerModel
    return useFingerModel, "✋ 10-Finger: "..(useFingerModel and "ON" or "OFF"), useFingerModel and THEME.Success or Color3.fromRGB(255, 120, 100)
end)
FingerBtn.TextColor3 = useFingerModel and THEME.Success or Color3.fromRGB(255, 120, 100)

local KeyboardBtn = CreateToggle("⌨ Keyboard: "..(showKeyboard and "ON" or "OFF"), UDim2.new(0, 225, 0, 8), function()
    showKeyboard = not showKeyboard
    Config.ShowKeyboard = showKeyboard
    KeyboardFrame.Visible = showKeyboard
    return showKeyboard, "⌨ Keyboard: "..(showKeyboard and "ON" or "OFF"), showKeyboard and THEME.Success or Color3.fromRGB(255, 120, 100)
end)
KeyboardBtn.TextColor3 = showKeyboard and THEME.Success or Color3.fromRGB(255, 120, 100)

local SortBtn = CreateToggle("▼ Sort: "..sortMode, UDim2.new(0, 15, 0, 41), function()
    if sortMode == "Random" then sortMode = "Shortest"
    elseif sortMode == "Shortest" then sortMode = "Longest"
    elseif sortMode == "Longest" then sortMode = "Killer"
    else sortMode = "Random" end
    
    Config.SortMode = sortMode
