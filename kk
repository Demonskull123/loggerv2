-- ═══════════════════════════════════════════════════════════════════════════
-- Universal Animation Logger + Visualizer + Timing Builder
-- No auto-block, no auto-parry, no action dispatch. Pure capture + inspect + save.
-- Works in any game. Captures LocalPlayer and any other entity with an Animator.
-- ═══════════════════════════════════════════════════════════════════════════

local _dzEnv = (getgenv and getgenv()) or _G

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local HttpService       = game:GetService("HttpService")

local RS, PS, UIS, HS = RunService, Players, UserInputService, HttpService
local LP = Players.LocalPlayer

-- ═══ 1. DzLib boot ═══
local getUrl = _dzEnv.DzHub_GetUrl or function(path)
    return "https://raw.githubusercontent.com/Dexz00/DzHub/refs/heads/main/" .. path
end
local DEV_MODE = _dzEnv.DzHub_DevMode
local isMobile = _dzEnv.DzHub_IsMobile
if isMobile == nil then isMobile = UIS.TouchEnabled and not UIS.KeyboardEnabled end

if _dzEnv.Library then pcall(function() _dzEnv.Library:Unload() end) end
local libUrl = DEV_MODE and getUrl("DzLib/DzLibV3.lua") or _dzEnv.DzHub_LibUrl or getUrl("DzLib/DzLib.lua")
local Library = loadstring(game:HttpGet(libUrl))()
assert(type(Library) == "table", "DzLib failed to load.")
_dzEnv.Library = Library
if type(Library.SetMenuKeybind) == "function" then Library:SetMenuKeybind(Enum.KeyCode.LeftControl) end

local Window = Library:CreateWindow({
    Name = "DZ HUB", SubName = "Anim Studio",
    ToggleButtonEnabled = isMobile, KeybindListEnabled = true, SettingsTabEnabled = true,
})
_dzEnv.DzWindow = Window
_dzEnv._UCBUnload = function() pcall(function() Library:Unload() end) end

-- ═══ 2. Tabs ═══
local BuildTab = Window:AddTab({ Name = "Builder", Icon = "clock" })
local LogTab   = Window:AddTab({ Name = "Logger",  Icon = "list" })

local function mk(tab, name)
    if type(tab) == "table" and type(tab.AddSubTab) == "function" then
        local ok, sub = pcall(tab.AddSubTab, tab, { Name = name })
        if ok and type(sub) == "table" then return sub end
    end
    return tab
end
local Sub = {
    Build = mk(BuildTab, "Timings"),
    Log   = mk(LogTab,   "Log"),
}
local Sec = {
    TimingBuilder = Sub.Build:AddSection({ Name = "Timing Builder", Side = 1, Icon = "clock" }),
    Table         = Sub.Build:AddSection({ Name = "Table",         Side = 2, Icon = "list" }),
    Logger        = Sub.Log:AddSection({ Name = "Animation Logger", Side = 1, Icon = "list" }),
    Blacklist     = Sub.Log:AddSection({ Name = "Blacklist",       Side = 2, Icon = "shield-check" }),
}

local function notify(msg, dur)
    task.defer(function() pcall(function() Library:Notification("UCB", tostring(msg), dur or 3) end) end)
end
local function ddRefresh(dd, items) if dd then pcall(function() dd:Refresh(items) end) end end
local function ddSet(dd, value)     if dd then pcall(function() dd:Set(value)     end) end end

-- ═══ 3. Namespace ═══
if not _dzEnv._UCB then _dzEnv._UCB = {} end
local AP = _dzEnv._UCB
AP.Players  = PS
AP.RunSvc   = RS
AP.UIS      = UIS
AP.lp       = LP
AP.CoreGui  = game:GetService("CoreGui")
AP.savedTimings = AP.savedTimings or {}
AP.timings      = AP.timings      or {}
AP.watchedAnims = AP.watchedAnims or {}
AP.loggedAnims  = {}
AP.loggedMap    = {}
AP.conns        = AP.conns        or {}
AP.logBlacklist = AP.logBlacklist or {}
AP.logSelf      = true
AP.TIMING_FILE  = "UCB/ucb_timings.json"
pcall(function() if makefolder then makefolder("UCB") end end)

AP.WHITE = Color3.fromRGB(255, 255, 255)
AP.DIM   = Color3.fromRGB(180, 180, 180)
AP.HINT  = Color3.fromRGB(100, 100, 100)
AP.BORD  = Color3.fromRGB(255, 255, 255)
AP.ACC   = Color3.fromRGB(138, 79, 255)
AP.RED   = Color3.fromRGB(255, 90, 90)
AP.BG    = Color3.fromRGB(15, 15, 15)
AP.CARD  = Color3.fromRGB(22, 22, 22)
AP.FONT_FACE = Font.new("rbxassetid://12187365364")

-- ═══ 4. Save / load ═══
AP.saveTimings = function()
    pcall(function() writefile(AP.TIMING_FILE, HS:JSONEncode(AP.savedTimings)) end)
end
AP.parseTimings = function(raw)
    local ok, data = pcall(function() return HS:JSONDecode(raw) end)
    if not ok or type(data) ~= "table" then return {} end
    local out = {}
    for _, e in ipairs(data) do
        if type(e) == "table" and e.animId and e.name then
            local id = tostring(e.animId)
            local nid = id:match("%?id=(%d+)") or id:match("rbxassetid://(%d+)") or id:match("^(%d+)$")
            if nid then id = "rbxassetid://" .. nid end
            table.insert(out, {
                name = tostring(e.name), animId = id,
                delay = tonumber(e.delay) or 0,
                minDist = tonumber(e.minDist) or 0,
                maxDist = tonumber(e.maxDist) or 25,
                action = tostring(e.action or "Custom"),
                DodgeDirection = tostring(e.DodgeDirection or "None"),
                FullHoldBlock = e.FullHoldBlock == true,
                MovingAttack = e.MovingAttack == true,
                Repeat = tonumber(e.Repeat) or 1,
                RepeatDelay = tonumber(e.RepeatDelay) or 0.35,
                StartDelay = tonumber(e.StartDelay) or 0,
                TriggerDistance = tonumber(e.TriggerDistance) or 12,
                SourceFilter = tostring(e.SourceFilter or "Any"),
                TargetSide = tostring(e.TargetSide or "Any"),
            })
        end
    end
    return out
end
AP.loadTimings = function()
    local ok, raw = pcall(function() return readfile(AP.TIMING_FILE) end)
    if not ok or not raw or raw == "" then
        AP.savedTimings = {}; AP.timings = {}
    else
        AP.savedTimings = AP.parseTimings(raw)
        AP.timings = {}
        for _, e in ipairs(AP.savedTimings) do
            if not AP.timings[e.animId] then AP.timings[e.animId] = {} end
            table.insert(AP.timings[e.animId], e)
        end
    end
    local ns = {}; for _, e in ipairs(AP.savedTimings) do table.insert(ns, e.name) end
    ddRefresh(Opt.APSavedTimings, #ns > 0 and ns or { "--" })
    ddSet(Opt.APSavedTimings, ns[1] or "--")
    pcall(function() AP.countLbl.Text = #AP.savedTimings .. " in table" end)
end

-- ═══ 5. Instance helpers ═══
AP.inst = function(cls, props, parent)
    local obj = Instance.new(cls)
    for k, v in pairs(props or {}) do pcall(function() obj[k] = v end) end
    if parent then obj.Parent = parent end
    return obj
end
AP.makeWin = function(sg, pos, sz, title)
    local win = AP.inst("Frame", { Position = pos, Size = sz, BackgroundColor3 = AP.BG,
        BackgroundTransparency = 0.05, BorderSizePixel = 0, ZIndex = 10, Visible = false, Parent = sg })
    AP.inst("UICorner", { CornerRadius = UDim.new(0, 10) }, win)
    AP.inst("UIStroke", { Color = AP.BORD, Thickness = 1, Transparency = 0.9 }, win)

    local bar = AP.inst("Frame", { Size = UDim2.new(1,0,0,31), BackgroundTransparency = 1, ZIndex = 11, Parent = win })
    local dots = AP.inst("Frame", { Size = UDim2.new(0,56,1,0), BackgroundTransparency = 1, ZIndex = 12, Parent = bar })
    AP.inst("UIListLayout", { Padding = UDim.new(0,5), FillDirection = Enum.FillDirection.Horizontal,
        SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }, dots)
    AP.inst("UIPadding", { PaddingLeft = UDim.new(0,11) }, dots)
    for _, col in ipairs({ Color3.fromRGB(255,96,87), Color3.fromRGB(255,189,46), Color3.fromRGB(30,30,30) }) do
        local d = AP.inst("Frame", { Size = UDim2.fromOffset(8,8), BackgroundColor3 = col, BorderSizePixel = 0, ZIndex = 12, Parent = dots })
        AP.inst("UICorner", { CornerRadius = UDim.new(1,0) }, d)
        local s = Instance.new("UIStroke"); s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        s.Color = Color3.new(1,1,1); s.Transparency = 0.9; s.Parent = d
    end
    local drag = AP.inst("TextLabel", { Position = UDim2.new(0,56,0,0), Size = UDim2.new(1,-56,1,0),
        BackgroundTransparency = 1, Text = title, TextColor3 = AP.WHITE, FontFace = AP.FONT_FACE,
        TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11, Parent = bar })
    AP.inst("Frame", { Position = UDim2.new(0,0,1,0), Size = UDim2.new(1,0,0,1),
        BackgroundColor3 = AP.BORD, BackgroundTransparency = 0.9, BorderSizePixel = 0, ZIndex = 11, Parent = bar })
    local xBtn = AP.inst("TextButton", { Position = UDim2.new(0,3,0.5,-8), Size = UDim2.new(0,16,0,16),
        BackgroundTransparency = 1, Text = "", ZIndex = 13, Parent = bar })

    local dragging, dragStart, startPos = false, Vector2.zero, win.Position
    drag.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true; dragStart = i.Position; startPos = win.Position
        end
    end)
    AP.UIS.InputChanged:Connect(function(i)
        if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
            local d = i.Position - dragStart
            win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    AP.UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)
    return win, xBtn
end

-- ═══ 6. Visualizer ═══
AP.V = {
    cam=nil, model=nil, anim8r=nil, animObj=nil, track=nil, hb=nil,
    paused=false, length=0, loop=true, speed=1,
    speeds={0.25,0.5,1,1.5,2}, spIdx=3,
    rotY=math.pi, rotX=0.3, targetRotY=math.pi, targetRotX=0.3,
    zoom=7.5, targetZoom=7.5,
}
AP.scrubbing = false; AP.scrubWasPaused = false
AP.vpDragging = false; AP.vpLastX = 0; AP.vpLastY = 0

AP.sg = AP.inst("ScreenGui", { Name = "UCBVisualizer", ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Global, IgnoreGuiInset = true })
pcall(function() AP.sg.Parent = AP.CoreGui end)
if not AP.sg.Parent then AP.sg.Parent = LP:WaitForChild("PlayerGui") end

AP.visWin, AP.visX = AP.makeWin(AP.sg, UDim2.new(0, 8, 0.5, -384), UDim2.new(0, 548, 0, 768), "UCB  ·  Visualizer")
AP.visX.MouseButton1Click:Connect(function()
    AP.visWin.Visible = false
    if Tog.APShowViz then Tog.APShowViz:Set(false) end
end)

local vpCtrlBar = AP.inst("Frame", { Position = UDim2.new(0,8,0,37), Size = UDim2.new(1,-16,0,28),
    BackgroundTransparency = 1, ZIndex = 11, Parent = AP.visWin })
local function makeVPBtn(txt, xOff)
    local b = AP.inst("TextButton", { Position = UDim2.new(0, xOff, 0, 0), Size = UDim2.new(0, 56, 1, 0),
        BackgroundColor3 = AP.CARD, Text = txt, TextColor3 = AP.DIM, FontFace = AP.FONT_FACE,
        TextSize = 12, AutoButtonColor = false, ZIndex = 12, Parent = vpCtrlBar })
    AP.inst("UICorner", { CornerRadius = UDim.new(0,5) }, b)
    AP.inst("UIStroke", { Color = AP.BORD, Thickness = 1, Transparency = 0.9 }, b)
    b.MouseEnter:Connect(function() b.BackgroundColor3 = Color3.fromRGB(35,35,35); b.TextColor3 = AP.WHITE end)
    b.MouseLeave:Connect(function() b.BackgroundColor3 = AP.CARD; b.TextColor3 = AP.DIM end)
    return b
end
AP.spinBtn  = makeVPBtn("Spin",  0)
AP.resetBtn = makeVPBtn("Reset", 60)

AP.vpFrame = AP.inst("ViewportFrame", { Position = UDim2.new(0,8,0,71), Size = UDim2.new(1,-16,0,360),
    BackgroundColor3 = Color3.fromRGB(8,8,16), ZIndex = 11, Parent = AP.visWin })
AP.inst("UICorner", { CornerRadius = UDim.new(0,6) }, AP.vpFrame)
AP.inst("UIStroke", { Color = AP.BORD, Thickness = 1, Transparency = 0.9 }, AP.vpFrame)
AP.vpFrame.LightColor = Color3.fromRGB(255,255,255)
AP.vpFrame.LightDirection = Vector3.new(-0.5,-1,-0.5)
AP.vpFrame.Ambient = Color3.fromRGB(85,80,100)
AP.vpWorld = Instance.new("WorldModel"); AP.vpWorld.Parent = AP.vpFrame
AP.vpHint = AP.inst("TextLabel", { Size = UDim2.new(1,0,1,0), BackgroundTransparency = 1,
    Text = "load an animation to preview", TextColor3 = AP.HINT, FontFace = AP.FONT_FACE,
    TextSize = 13, ZIndex = 12, Parent = AP.vpFrame })

AP.vpFrame.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then
        AP.vpDragging = true; AP.vpLastX = i.Position.X; AP.vpLastY = i.Position.Y
    end
end)

AP.visStat = AP.inst("TextLabel", { Position = UDim2.new(0,8,0,437), Size = UDim2.new(0,80,0,16),
    BackgroundTransparency = 1, Text = "Not loaded", TextColor3 = AP.WHITE, FontFace = AP.FONT_FACE,
    TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11, Parent = AP.visWin })
AP.visIdLbl = AP.inst("TextLabel", { Position = UDim2.new(0,92,0,437), Size = UDim2.new(1,-100,0,16),
    BackgroundTransparency = 1, Text = "", TextColor3 = AP.ACC, FontFace = AP.FONT_FACE,
    TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 11, Parent = AP.visWin })

AP.tlLeft  = AP.inst("TextLabel", { Position = UDim2.new(0,8,0,458), Size = UDim2.new(0,62,0,12),
    BackgroundTransparency = 1, Text = "00:00.00", TextColor3 = AP.HINT, FontFace = AP.FONT_FACE,
    TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11, Parent = AP.visWin })
AP.tlRight = AP.inst("TextLabel", { Position = UDim2.new(1,-70,0,458), Size = UDim2.new(0,62,0,12),
    BackgroundTransparency = 1, Text = "00:00.00", TextColor3 = AP.HINT, FontFace = AP.FONT_FACE,
    TextSize = 10, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 11, Parent = AP.visWin })
AP.tlBg = AP.inst("Frame", { Position = UDim2.new(0,8,0,472), Size = UDim2.new(1,-16,0,8),
    BackgroundColor3 = Color3.fromRGB(30,30,30), BorderSizePixel = 0, ZIndex = 11, Parent = AP.visWin })
AP.inst("UICorner", { CornerRadius = UDim.new(1,0) }, AP.tlBg)
AP.inst("UIStroke", { Color = AP.BORD, Thickness = 1, Transparency = 0.9 }, AP.tlBg)
AP.tlFill = AP.inst("Frame", { Size = UDim2.new(0,0,1,0), BackgroundColor3 = AP.ACC,
    BorderSizePixel = 0, ZIndex = 12, Parent = AP.tlBg })
AP.inst("UICorner", { CornerRadius = UDim.new(1,0) }, AP.tlFill)
AP.tlHit = AP.inst("TextButton", { Size = UDim2.new(1,0,4,0), Position = UDim2.new(0,0,-1.5,0),
    BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 14, Parent = AP.tlBg })

local ctrlRow = AP.inst("Frame", { Position = UDim2.new(0,8,0,486), Size = UDim2.new(1,-16,0,34),
    BackgroundTransparency = 1, ZIndex = 11, Parent = AP.visWin })
local function mkCtrl(sym, xOff, w)
    local b = AP.inst("TextButton", { Position = UDim2.new(0, xOff, 0, 0), Size = UDim2.new(0, w or 36, 1, 0),
        BackgroundColor3 = AP.CARD, Text = sym, TextColor3 = AP.WHITE, FontFace = AP.FONT_FACE,
        TextSize = 13, AutoButtonColor = false, ZIndex = 12, Parent = ctrlRow })
    AP.inst("UICorner", { CornerRadius = UDim.new(0,6) }, b)
    AP.inst("UIStroke", { Color = AP.BORD, Thickness = 1, Transparency = 0.9 }, b)
    b.MouseEnter:Connect(function() b.BackgroundColor3 = Color3.fromRGB(35,35,35) end)
    b.MouseLeave:Connect(function() b.BackgroundColor3 = AP.CARD end)
    return b
end
AP.btnRestart = mkCtrl("|◀", 0)
AP.btnPlay    = mkCtrl("▶", 40, 42)
AP.btnStop    = mkCtrl("■", 86)
AP.loopBtn    = mkCtrl("↺", 126)
AP.speedBtn   = mkCtrl("1×", 166, 44)
AP.setPlayState = function(playing)
    AP.btnPlay.Text = playing and "| |" or "▶"
    AP.btnPlay.TextColor3 = AP.WHITE
end

local spdRow = AP.inst("Frame", { Position = UDim2.new(0,8,0,526), Size = UDim2.new(1,-16,0,24),
    BackgroundTransparency = 1, ZIndex = 11, Parent = AP.visWin })
AP.inst("TextLabel", { Size = UDim2.new(0,48,1,0), BackgroundTransparency = 1, Text = "Speed:",
    TextColor3 = AP.DIM, FontFace = AP.FONT_FACE, TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12, Parent = spdRow })
local spdTrack = AP.inst("Frame", { Position = UDim2.new(0,52,0.5,-3), Size = UDim2.new(1,-96,0,6),
    BackgroundColor3 = Color3.fromRGB(30,30,30), BorderSizePixel = 0, ZIndex = 12, Parent = spdRow })
AP.inst("UICorner", { CornerRadius = UDim.new(1,0) }, spdTrack)
AP.inst("UIStroke", { Color = AP.BORD, Thickness = 1, Transparency = 0.9 }, spdTrack)
AP.spdFill = AP.inst("Frame", { Size = UDim2.new(0.5,0,1,0), BackgroundColor3 = AP.ACC,
    BorderSizePixel = 0, ZIndex = 13, Parent = spdTrack })
AP.inst("UICorner", { CornerRadius = UDim.new(1,0) }, AP.spdFill)
AP.spdHandle = AP.inst("Frame", { Position = UDim2.new(0.5,-5,0.5,-5), Size = UDim2.new(0,10,0,10),
    BackgroundColor3 = AP.WHITE, BorderSizePixel = 0, ZIndex = 14, Parent = spdTrack })
AP.inst("UICorner", { CornerRadius = UDim.new(1,0) }, AP.spdHandle)
AP.spdLbl = AP.inst("TextLabel", { Position = UDim2.new(1,-38,0,0), Size = UDim2.new(0,38,1,0),
    BackgroundTransparency = 1, Text = "1.00×", TextColor3 = AP.WHITE, FontFace = AP.FONT_FACE,
    TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 12, Parent = spdRow })

local zoomRow = AP.inst("Frame", { Position = UDim2.new(0,8,0,556), Size = UDim2.new(1,-16,0,24),
    BackgroundTransparency = 1, ZIndex = 11, Parent = AP.visWin })
AP.inst("TextLabel", { Size = UDim2.new(0,48,1,0), BackgroundTransparency = 1, Text = "Zoom:",
    TextColor3 = AP.DIM, FontFace = AP.FONT_FACE, TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12, Parent = zoomRow })
local zoomTrack = AP.inst("Frame", { Position = UDim2.new(0,52,0.5,-3), Size = UDim2.new(1,-96,0,6),
    BackgroundColor3 = Color3.fromRGB(30,30,30), BorderSizePixel = 0, ZIndex = 12, Parent = zoomRow })
AP.inst("UICorner", { CornerRadius = UDim.new(1,0) }, zoomTrack)
AP.inst("UIStroke", { Color = AP.BORD, Thickness = 1, Transparency = 0.9 }, zoomTrack)
local zFill = AP.inst("Frame", { Size = UDim2.new(0.5,0,1,0), BackgroundColor3 = AP.ACC,
    BorderSizePixel = 0, ZIndex = 13, Parent = zoomTrack })
AP.inst("UICorner", { CornerRadius = UDim.new(1,0) }, zFill)
local zHandle = AP.inst("Frame", { Position = UDim2.new(0.5,-5,0.5,-5), Size = UDim2.new(0,10,0,10),
    BackgroundColor3 = AP.WHITE, BorderSizePixel = 0, ZIndex = 14, Parent = zoomTrack })
AP.inst("UICorner", { CornerRadius = UDim.new(1,0) }, zHandle)
AP.zoomLbl = AP.inst("TextLabel", { Position = UDim2.new(1,-38,0,0), Size = UDim2.new(0,38,1,0),
    BackgroundTransparency = 1, Text = "7.5", TextColor3 = AP.WHITE, FontFace = AP.FONT_FACE,
    TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 12, Parent = zoomRow })

local timeRow = AP.inst("Frame", { Position = UDim2.new(0,8,0,586), Size = UDim2.new(1,-16,0,28),
    BackgroundTransparency = 1, ZIndex = 11, Parent = AP.visWin })
AP.inst("TextLabel", { Size = UDim2.new(0,34,1,0), BackgroundTransparency = 1, Text = "Time:",
    TextColor3 = AP.DIM, FontFace = AP.FONT_FACE, TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12, Parent = timeRow })
local function mkInfoBox(txt, xOff, w)
    local f = AP.inst("Frame", { Position = UDim2.new(0, xOff, 0, 3), Size = UDim2.new(0, w, 1, -6),
        BackgroundColor3 = AP.CARD, BorderSizePixel = 0, ZIndex = 12, Parent = timeRow })
    AP.inst("UICorner", { CornerRadius = UDim.new(0,4) }, f)
    AP.inst("UIStroke", { Color = AP.BORD, Thickness = 1, Transparency = 0.9 }, f)
    return AP.inst("TextLabel", { Size = UDim2.new(1,-4,1,0), Position = UDim2.new(0,2,0,0),
        BackgroundTransparency = 1, Text = txt, TextColor3 = AP.WHITE, FontFace = AP.FONT_FACE,
        TextSize = 11, ZIndex = 13, Parent = f })
end
AP.timeFull  = mkInfoBox("0.00 / 0.00", 38, 110)
AP.timeScrub = mkInfoBox("0.000s", 154, 74)

AP.inst("Frame", { Position = UDim2.new(0,8,0,620), Size = UDim2.new(1,-16,0,1),
    BackgroundColor3 = AP.BORD, BackgroundTransparency = 0.9, BorderSizePixel = 0, ZIndex = 11, Parent = AP.visWin })
AP.inst("TextLabel", { Position = UDim2.new(0,8,0,626), Size = UDim2.new(0.5,0,0,18),
    BackgroundTransparency = 1, Text = "Save Mark", TextColor3 = AP.WHITE,
    FontFace = AP.FONT_FACE, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 11, Parent = AP.visWin })
AP.countLbl = AP.inst("TextLabel", { Position = UDim2.new(0.5,0,0,626), Size = UDim2.new(0.5,-8,0,18),
    BackgroundTransparency = 1, Text = "0 in table", TextColor3 = AP.DIM, FontFace = AP.FONT_FACE,
    TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 11, Parent = AP.visWin })

local btnRow1 = AP.inst("Frame", { Position = UDim2.new(0,8,0,648), Size = UDim2.new(1,-16,0,26),
    BackgroundTransparency = 1, ZIndex = 11, Parent = AP.visWin })
AP.inst("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0,4), Parent = btnRow1 })
local btnRow2 = AP.inst("Frame", { Position = UDim2.new(0,8,0,678), Size = UDim2.new(1,-16,0,26),
    BackgroundTransparency = 1, ZIndex = 11, Parent = AP.visWin })
AP.inst("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0,4), Parent = btnRow2 })
local function mkBtn(row, txt, col)
    local b = AP.inst("TextButton", { Size = UDim2.new(0,0,1,0), AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = AP.CARD, Text = txt, TextColor3 = col or AP.WHITE, FontFace = AP.FONT_FACE,
        TextSize = 12, AutoButtonColor = false, ZIndex = 12, Parent = row })
    AP.inst("UICorner", { CornerRadius = UDim.new(0,6) }, b)
    AP.inst("UIStroke", { Color = col or AP.BORD, Thickness = 1, Transparency = col and 0 or 0.9 }, b)
    AP.inst("UIPadding", { PaddingLeft = UDim.new(0,8), PaddingRight = UDim.new(0,8) }, b)
    b.MouseEnter:Connect(function() b.BackgroundColor3 = Color3.fromRGB(35,35,35) end)
    b.MouseLeave:Connect(function() b.BackgroundColor3 = AP.CARD end)
    return b
end
AP.markBtn     = mkBtn(btnRow1, "+ Mark",      nil)
AP.markAltBtn  = mkBtn(btnRow1, "+ Mark Alt",  nil)
AP.clearBtn    = mkBtn(btnRow2, "Clear",       nil)
AP.exportBtn   = mkBtn(btnRow2, "Export",      nil)
AP.exportAllBtn= mkBtn(btnRow2, "Export All",  nil)

AP.inst("TextLabel", { Position = UDim2.new(0,8,0,710), Size = UDim2.new(1,-16,0,36),
    BackgroundTransparency = 1, Text = "Drag viewport to orbit  ·  Scroll to zoom  ·  Click a logger row to load its anim",
    TextColor3 = AP.HINT, FontFace = AP.FONT_FACE, TextSize = 11, TextWrapped = true,
    ZIndex = 11, Parent = AP.visWin })

local _spinEnabled = false
AP.spinBtn.MouseButton1Click:Connect(function()
    _spinEnabled = not _spinEnabled
    AP.spinBtn.BackgroundColor3 = _spinEnabled and Color3.fromRGB(35,35,35) or AP.CARD
    AP.spinBtn.TextColor3 = _spinEnabled and AP.WHITE or AP.DIM
    if _spinEnabled then
        task.spawn(function()
            while _spinEnabled and AP.visWin.Visible do
                AP.V.targetRotY = AP.V.targetRotY + 0.018
                task.wait()
            end
        end)
    end
end)
AP.resetBtn.MouseButton1Click:Connect(function()
    AP.V.targetRotY = 0.3; AP.V.targetRotX = 0.15; AP.V.targetZoom = 6
end)

AP.vSet = function(msg, col) AP.visStat.Text = msg; AP.visStat.TextColor3 = col or AP.DIM end

AP.vClean = function()
    if AP.V.hb then AP.V.hb:Disconnect(); AP.V.hb = nil end
    if AP.V.track then pcall(function() AP.V.track:Stop(0) end); pcall(function() AP.V.track:Destroy() end); AP.V.track = nil end
    if AP.V.animObj then pcall(function() AP.V.animObj:Destroy() end); AP.V.animObj = nil end
    if AP.V.model then pcall(function() AP.V.model:Destroy() end); AP.V.model = nil end
    if AP.V.cam then pcall(function() AP.V.cam:Destroy() end); AP.V.cam = nil end
    for _, c in ipairs(AP.vpWorld:GetChildren()) do pcall(function() c:Destroy() end) end
    AP.V.anim8r = nil; AP.V.length = 0; AP.V.paused = false
    AP.tlFill.Size = UDim2.new(0,0,1,0)
    AP.timeFull.Text = "0.00 / 0.00"; AP.timeScrub.Text = "0.000s"
    AP.tlLeft.Text = "00:00.00"; AP.tlRight.Text = "00:00.00"
    AP.setPlayState(false); AP.vpHint.Visible = true
    AP.visStat.Text = "Not loaded"; AP.visIdLbl.Text = ""
end

-- sourceModel: any Model with an Animator (character, NPC, custom rig).
-- Falls back to LocalPlayer.Character.
AP.vLoad = function(animId, sourceModel)
    AP.vClean()
    local src = (sourceModel and sourceModel.Parent and sourceModel) or LP.Character
    if not src then AP.vSet("no source model", AP.RED); return end

    local restored = {}
    pcall(function()
        for _, d in ipairs(src:GetDescendants()) do
            if not d.Archivable then d.Archivable = true; table.insert(restored, d) end
        end
        if not src.Archivable then src.Archivable = true; table.insert(restored, src) end
    end)
    local clone
    pcall(function() clone = src:Clone() end)
    for _, d in ipairs(restored) do pcall(function() d.Archivable = false end) end
    if not clone then AP.vSet("clone failed", AP.RED); return end

    for _, d in ipairs(clone:GetDescendants()) do
        if d:IsA("Script") or d:IsA("LocalScript") then d:Destroy()
        elseif d:IsA("BasePart") then d.Anchored = false; d.CanCollide = false; d.CastShadow = false end
    end
    local root = clone:FindFirstChild("HumanoidRootPart") or clone.PrimaryPart
    if root then root.Anchored = true; root.CFrame = CFrame.new(0,0,0) end
    clone.Parent = AP.vpWorld; AP.V.model = clone

    local hum = clone:FindFirstChildOfClass("Humanoid")
    if hum then
        pcall(function() for _, t in ipairs(hum:GetPlayingAnimationTracks()) do t:Stop(0) end end)
        pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Running, false) end)
        pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false) end)
    end
    local anim8r
    if hum then
        anim8r = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)
    else
        local ctrl = clone:FindFirstChildWhichIsA("AnimationController", true)
            or Instance.new("AnimationController", clone)
        anim8r = ctrl:FindFirstChildOfClass("Animator") or Instance.new("Animator", ctrl)
    end
    AP.V.anim8r = anim8r

    local cam = Instance.new("Camera")
    if root then
        AP.V.zoom = AP.V.targetZoom
        local ox = math.sin(AP.V.rotY) * math.cos(AP.V.rotX) * AP.V.zoom
        local oy = math.sin(AP.V.rotX) * AP.V.zoom
        local oz = math.cos(AP.V.rotY) * math.cos(AP.V.rotX) * AP.V.zoom
        cam.CFrame = CFrame.new(root.Position + Vector3.new(ox, oy + 1.5, oz), root.Position + Vector3.new(0, 1.5, 0))
    end
    AP.vpFrame.CurrentCamera = cam; AP.V.cam = cam

    local animObj = Instance.new("Animation"); animObj.AnimationId = animId
    local track
    local ok2, err = pcall(function() track = anim8r:LoadAnimation(animObj) end)
    if not ok2 or not track then
        animObj:Destroy(); AP.vSet("load failed: " .. tostring(err), AP.RED); return
    end
    AP.V.animObj = animObj; AP.V.track = track
    track.Looped = AP.V.loop; track:Play(0.1, 1, AP.V.speed)
    AP.V.paused = false; AP.setPlayState(true); AP.vpHint.Visible = false

    task.spawn(function()
        local t0 = os.clock()
        repeat task.wait(0.05) until (AP.V.track and AP.V.track.Length > 0) or (os.clock() - t0 > 0.5)
        if AP.V.track then
            AP.V.length = AP.V.track.Length
            AP.visStat.Text = "Playing ID:"
            AP.visIdLbl.Text = animId:match("(%d+)$") or "?"
        end
    end)

    AP.V.hb = AP.RunSvc.Heartbeat:Connect(function()
        if not AP.V.track then return end
        if AP.V.track.Length > 0 and AP.V.length ~= AP.V.track.Length then AP.V.length = AP.V.track.Length end
        local tp = AP.V.track.TimePosition
        local len = math.max(AP.V.length, 0.001)
        AP.tlFill.Size = UDim2.new(math.clamp(tp / len, 0, 1), 0, 1, 0)
        AP.timeFull.Text = string.format("%.2f / %.2f", tp, len)
        AP.timeScrub.Text = string.format("%.3fs", tp)
        AP.tlLeft.Text  = string.format("%02d:%02d.%02d", math.floor(tp/60), math.floor(tp)%60, math.floor((tp%1)*100))
        AP.tlRight.Text = string.format("%02d:%02d.%02d", math.floor(len/60), math.floor(len)%60, math.floor((len%1)*100))
        if AP.V.cam and AP.V.model then
            local r2 = AP.V.model:FindFirstChild("HumanoidRootPart") or AP.V.model.PrimaryPart
            if r2 then
                AP.V.zoom = AP.V.zoom + (AP.V.targetZoom - AP.V.zoom) * 0.18
                AP.V.rotY = AP.V.rotY + (AP.V.targetRotY - AP.V.rotY) * 0.18
                AP.V.rotX = AP.V.rotX + (AP.V.targetRotX - AP.V.rotX) * 0.18
                local ox = math.sin(AP.V.rotY) * math.cos(AP.V.rotX) * AP.V.zoom
                local oy = math.sin(AP.V.rotX) * AP.V.zoom
                local oz = math.cos(AP.V.rotY) * math.cos(AP.V.rotX) * AP.V.zoom
                AP.V.cam.CFrame = CFrame.new(
                    r2.Position + Vector3.new(ox, oy + 1.5, oz),
                    r2.Position + Vector3.new(0, 1.5, 0))
            end
        end
    end)
end

AP.visOpenWithId = function(id, entityRef)
    if not id:find("rbxassetid://") then id = "rbxassetid://" .. id end
    AP.visWin.Visible = true
    if Tog.APShowViz and not Tog.APShowViz.Value then Tog.APShowViz:Set(true) end
    if Opt.APAnimationID then Opt.APAnimationID:Set(id) end
    AP.vLoad(id, entityRef)
end

AP.scrubSeek = function(xPos)
    if not AP.V.track or AP.V.length <= 0 then return end
    local a = AP.tlBg.AbsolutePosition; local s = AP.tlBg.AbsoluteSize
    local t = math.clamp((xPos - a.X) / s.X, 0, 1) * AP.V.length
    if not AP.V.track.IsPlaying then AP.V.track:Play(0, 1, 0) end
    AP.V.track:AdjustSpeed(0); AP.V.track.TimePosition = t
end
AP.tlHit.MouseButton1Down:Connect(function()
    if not AP.V.track or AP.V.length <= 0 then return end
    AP.scrubbing = true; AP.scrubWasPaused = AP.V.paused; AP.V.paused = true
    AP.scrubSeek(AP.UIS:GetMouseLocation().X)
end)
AP.UIS.InputChanged:Connect(function(i)
    if AP.scrubbing and i.UserInputType == Enum.UserInputType.MouseMovement then
        AP.scrubSeek(i.Position.X)
    end
    if AP.vpDragging and i.UserInputType == Enum.UserInputType.MouseMovement then
        AP.V.targetRotY = AP.V.targetRotY + (i.Position.X - AP.vpLastX) * 0.012
        AP.V.targetRotX = AP.V.targetRotX + (i.Position.Y - AP.vpLastY) * 0.008
        AP.vpLastX = i.Position.X; AP.vpLastY = i.Position.Y
    end
    if i.UserInputType == Enum.UserInputType.MouseWheel and AP.visWin and AP.visWin.Visible then
        local mp = AP.UIS:GetMouseLocation()
        local ap = AP.vpFrame.AbsolutePosition; local as = AP.vpFrame.AbsoluteSize
        if mp.X >= ap.X and mp.X <= ap.X + as.X and mp.Y >= ap.Y and mp.Y <= ap.Y + as.Y then
            AP.V.targetZoom = math.max(0.5, AP.V.targetZoom - i.Position.Z * 1.5)
        end
    end
end)
AP.UIS.InputEnded:Connect(function(i)
    if i.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    if AP.scrubbing then
        AP.scrubbing = false
        if not AP.scrubWasPaused and AP.V.track then
            AP.V.track:AdjustSpeed(AP.V.speed); AP.V.paused = false; AP.setPlayState(true)
        end
    end
    AP.vpDragging = false
end)

AP.btnPlay.MouseButton1Click:Connect(function()
    if not AP.V.track then
        local id = Opt.APAnimationID and Opt.APAnimationID.Value or ""
        if id == "" then AP.vSet("enter id in UI", AP.DIM); return end
        if not id:find("rbxassetid://") then id = "rbxassetid://" .. id end
        AP.vLoad(id); return
    end
    if AP.V.paused then
        AP.V.track:AdjustSpeed(AP.V.speed); AP.V.paused = false
        AP.setPlayState(true); AP.visStat.Text = "Playing ID:"
    else
        AP.V.track:AdjustSpeed(0); AP.V.paused = true
        AP.setPlayState(false); AP.visStat.Text = "Paused"
    end
end)
AP.btnRestart.MouseButton1Click:Connect(function()
    if not AP.V.track then return end
    AP.V.track.TimePosition = 0
    if AP.V.paused then AP.V.track:AdjustSpeed(AP.V.speed); AP.V.paused = false; AP.setPlayState(true) end
    AP.visStat.Text = "Playing ID:"
end)
AP.btnStop.MouseButton1Click:Connect(function() AP.vClean() end)
AP.loopBtn.MouseButton1Click:Connect(function()
    AP.V.loop = not AP.V.loop
    AP.loopBtn.BackgroundColor3 = AP.V.loop and Color3.fromRGB(50,20,90) or AP.CARD
    if AP.V.track then AP.V.track.Looped = AP.V.loop end
end)
AP.speedBtn.MouseButton1Click:Connect(function()
    AP.V.spIdx = (AP.V.spIdx % #AP.V.speeds) + 1
    AP.V.speed = AP.V.speeds[AP.V.spIdx]
    AP.speedBtn.Text = string.format("%.2f×", AP.V.speed)
    if AP.V.track and not AP.V.paused then AP.V.track:AdjustSpeed(AP.V.speed) end
end)

do
    local dragging = false
    spdTrack.InputBegan:Connect(function(i)
        if i.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        dragging = true
        local pct = math.clamp((i.Position.X - spdTrack.AbsolutePosition.X) / spdTrack.AbsoluteSize.X, 0, 1)
        AP.V.speed = 0.1 + pct * 4.9
        AP.spdFill.Size = UDim2.new(pct, 0, 1, 0)
        AP.spdHandle.Position = UDim2.new(pct, -5, 0.5, -5)
        AP.spdLbl.Text = string.format("%.2f×", AP.V.speed)
        if AP.V.track and not AP.V.paused then AP.V.track:AdjustSpeed(AP.V.speed) end
    end)
    AP.UIS.InputChanged:Connect(function(i)
        if not dragging or i.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        local pct = math.clamp((i.Position.X - spdTrack.AbsolutePosition.X) / spdTrack.AbsoluteSize.X, 0, 1)
        AP.V.speed = 0.1 + pct * 4.9
        AP.spdFill.Size = UDim2.new(pct, 0, 1, 0)
        AP.spdHandle.Position = UDim2.new(pct, -5, 0.5, -5)
        AP.spdLbl.Text = string.format("%.2f×", AP.V.speed)
        if AP.V.track and not AP.V.paused then AP.V.track:AdjustSpeed(AP.V.speed) end
    end)
    AP.UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)
end
do
    local dragging = false
    zoomTrack.InputBegan:Connect(function(i)
        if i.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        dragging = true
        local pct = math.clamp((i.Position.X - zoomTrack.AbsolutePosition.X) / zoomTrack.AbsoluteSize.X, 0, 1)
        AP.V.targetZoom = 0.5 + pct * 19.5
        zFill.Size = UDim2.new(pct, 0, 1, 0); zHandle.Position = UDim2.new(pct, -5, 0.5, -5)
        AP.zoomLbl.Text = string.format("%.1f", AP.V.targetZoom)
    end)
    AP.UIS.InputChanged:Connect(function(i)
        if not dragging or i.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        local pct = math.clamp((i.Position.X - zoomTrack.AbsolutePosition.X) / zoomTrack.AbsoluteSize.X, 0, 1)
        AP.V.targetZoom = 0.5 + pct * 19.5
        zFill.Size = UDim2.new(pct, 0, 1, 0); zHandle.Position = UDim2.new(pct, -5, 0.5, -5)
        AP.zoomLbl.Text = string.format("%.1f", AP.V.targetZoom)
    end)
    AP.UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)
end

-- ═══ 7. Save marks from visualizer ═══
local function currentVizId()
    local id = Opt.APAnimationID and Opt.APAnimationID.Value or ""
    if id == "" then return nil end
    if not id:find("rbxassetid://") then id = "rbxassetid://" .. id end
    return id
end

local function mkMark(action)
    if not AP.V.track then notify("Load an animation first", 2); return end
    local tp = AP.V.track.TimePosition
    local id = currentVizId()
    if not id then notify("No animation ID", 2); return end
    local name = Opt.APTimingName and Opt.APTimingName.Value or ""
    if name == "" then name = (id:match("(%d+)$") or "?") .. "_" .. action:lower() end
    if AP.timings[id] then
        for _, e in ipairs(AP.timings[id]) do
            if e.name == name and e.action == action then
                notify("Already saved: " .. name .. " (" .. action .. ")", 2); return
            end
        end
    end
    local e = {
        name = name, animId = id, delay = tp,
        minDist = Opt.APMinDist and Opt.APMinDist.Value or 0,
        maxDist = Opt.APMaxDist and Opt.APMaxDist.Value or 25,
        action = action,
        DodgeDirection = Opt.APDodgeDir and Opt.APDodgeDir.Value or "None",
        FullHoldBlock = (Opt.APFullBlock and Opt.APFullBlock.Value == "true") or false,
        MovingAttack = (Opt.APMovingAtk and Opt.APMovingAtk.Value == "true") or false,
        Repeat = Opt.APRepeat and Opt.APRepeat.Value or 1,
        RepeatDelay = Opt.APRepeatDelay and Opt.APRepeatDelay.Value or 0.35,
        StartDelay = Opt.APStartDelay and Opt.APStartDelay.Value or 0,
        TriggerDistance = Opt.APTriggerDist and Opt.APTriggerDist.Value or 12,
        SourceFilter = Opt.APSourceFilter and Opt.APSourceFilter.Value or "Any",
        TargetSide = Opt.APTargetSide and Opt.APTargetSide.Value or "Any",
    }
    table.insert(AP.savedTimings, e)
    if not AP.timings[id] then AP.timings[id] = {} end
    table.insert(AP.timings[id], e)
    local ns = {}; for _, x in ipairs(AP.savedTimings) do table.insert(ns, x.name) end
    ddRefresh(Opt.APSavedTimings, ns); ddSet(Opt.APSavedTimings, name)
    AP.saveTimings()
    AP.countLbl.Text = #AP.savedTimings .. " in table"
    notify(action .. " saved: " .. name .. " @ " .. string.format("%.3fs", tp), 2)
end

AP.markBtn.MouseButton1Click:Connect(function() mkMark(Opt.APAction and Opt.APAction.Value or "Custom") end)
AP.markAltBtn.MouseButton1Click:Connect(function()
    mkMark((Opt.APAction and Opt.APAction.Value or "Custom") .. "_alt")
end)
AP.clearBtn.MouseButton1Click:Connect(function()
    AP.savedTimings = {}; AP.timings = {}
    AP.saveTimings(); AP.countLbl.Text = "0 in table"
    task.defer(function() ddRefresh(Opt.APSavedTimings, { "--" }); ddSet(Opt.APSavedTimings, "--") end)
    notify("Table cleared", 2)
end)
AP.exportBtn.MouseButton1Click:Connect(function()
    local ls = {}
    for _, e in ipairs(AP.savedTimings) do
        table.insert(ls, string.format(
            '  ["%s"]={name="%s",delay=%.3f,minDist=%d,maxDist=%d,action="%s"}',
            e.animId, e.name, e.delay, e.minDist, e.maxDist, e.action))
    end
    if setclipboard then setclipboard("local TIMINGS={\n" .. table.concat(ls, ",\n") .. "\n}") end
    notify("Exported!", 2)
end)
AP.exportAllBtn.MouseButton1Click:Connect(function()
    if setclipboard then setclipboard(HS:JSONEncode(AP.savedTimings)) end
    notify("Exported All!", 2)
end)

-- ═══ 8. Logger window ═══
AP.logWin, AP.logX = AP.makeWin(AP.sg, UDim2.new(1,-700,0,50), UDim2.new(0,680,0,740), "UCB  ·  Logger")
AP.logX.MouseButton1Click:Connect(function()
    AP.logWin.Visible = false
    if Tog.APEnableLogger then Tog.APEnableLogger:Set(false) end
end)
local loggedRow = AP.inst("Frame", { Position = UDim2.new(0,8,0,38), Size = UDim2.new(1,-16,0,28),
    BackgroundColor3 = AP.CARD, BorderSizePixel = 0, ZIndex = 12, Parent = AP.logWin })
AP.inst("UICorner", { CornerRadius = UDim.new(0,6) }, loggedRow)
AP.inst("UIStroke", { Color = AP.BORD, Thickness = 1, Transparency = 0.9 }, loggedRow)
AP.loggedCountLbl = AP.inst("TextLabel", { Position = UDim2.new(0,10,0,0), Size = UDim2.new(1,-16,1,0),
    BackgroundTransparency = 1, Text = "Logged: 0", TextColor3 = AP.WHITE, FontFace = AP.FONT_FACE,
    TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 13, Parent = loggedRow })
AP.logScroll = AP.inst("ScrollingFrame", { Position = UDim2.new(0,8,0,72), Size = UDim2.new(1,-16,1,-80),
    BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
    ScrollBarImageColor3 = AP.ACC, CanvasSize = UDim2.new(0,0,0,0), ZIndex = 12, Parent = AP.logWin })
AP.logList = AP.inst("UIListLayout", { FillDirection = Enum.FillDirection.Vertical,
    SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0,5), Parent = AP.logScroll })
AP.logList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    AP.logScroll.CanvasSize = UDim2.new(0, 0, 0, AP.logList.AbsoluteContentSize.Y + 8)
end)
AP.inst("UIPadding", { PaddingTop = UDim.new(0,4), PaddingBottom = UDim.new(0,4), Parent = AP.logScroll })
AP.logLineObjs = {}; AP.selObj = nil
local function updCount()
    if AP.loggedCountLbl then AP.loggedCountLbl.Text = "Logged: " .. #AP.logLineObjs end
end

local function mkLogBtn(parent, xOff)
    local b = AP.inst("TextButton", { Position = UDim2.new(1,xOff,0.5,-14), Size = UDim2.new(0,28,0,28),
        BackgroundColor3 = AP.CARD, Text = "", AutoButtonColor = false, ZIndex = 15, Parent = parent })
    AP.inst("UICorner", { CornerRadius = UDim.new(0,6) }, b)
    AP.inst("UIStroke", { Color = AP.BORD, Thickness = 1, Transparency = 0.9 }, b)
    b.MouseEnter:Connect(function() b.BackgroundColor3 = Color3.fromRGB(35,35,35) end)
    b.MouseLeave:Connect(function() b.BackgroundColor3 = AP.CARD end)
    return b
end

AP.addLogLine = function(entry)
    local numId = entry.id:match("(%d+)$") or entry.id
    local animName = entry.animName or numId
    local distTxt = entry.dist and string.format(" · %.0fm", entry.dist) or ""
    local srcTxt = (entry.source and entry.source ~= "Unknown" and entry.source or "?") .. distTxt

    local card = AP.inst("Frame", { Size = UDim2.new(1,0,0,68), BackgroundColor3 = AP.CARD,
        BorderSizePixel = 0, ZIndex = 13, LayoutOrder = #AP.logLineObjs + 1, Parent = AP.logScroll })
    AP.inst("UICorner", { CornerRadius = UDim.new(0,8) }, card)
    AP.inst("UIStroke", { Color = AP.BORD, Thickness = 1, Transparency = 0.9 }, card)

    local nameLbl = AP.inst("TextLabel", { Position = UDim2.new(0,12,0,8), Size = UDim2.new(1,-100,0,20),
        BackgroundTransparency = 1, Text = animName, TextColor3 = AP.WHITE, FontFace = AP.FONT_FACE,
        TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 14, Parent = card })
    AP.inst("TextLabel", { Position = UDim2.new(0,12,0,30), Size = UDim2.new(1,-100,0,14),
        BackgroundTransparency = 1, Text = srcTxt, TextColor3 = AP.DIM, FontFace = AP.FONT_FACE,
        TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 14, Parent = card })
    AP.inst("TextLabel", { Position = UDim2.new(0,12,0,46), Size = UDim2.new(1,-100,0,14),
        BackgroundTransparency = 1, Text = numId, TextColor3 = AP.HINT, FontFace = AP.FONT_FACE,
        TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 14, Parent = card })

    local copyBtn = mkLogBtn(card, -104)
    local addBtn  = mkLogBtn(card, -68)
    AP.inst("TextLabel", { Size = UDim2.new(1,0,1,0), BackgroundTransparency = 1, Text = "+",
        TextColor3 = AP.WHITE, FontFace = AP.FONT_FACE, TextSize = 18,
        TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 16, Parent = addBtn })
    local blockBtn = mkLogBtn(card, -32)

    local obj = { card = card, lbl = nameLbl, id = entry.id,
        source = entry.source or "", entity = entry.entity }
    table.insert(AP.logLineObjs, obj)
    updCount()

    local function onSelect()
        if AP.selObj then
            pcall(function()
                AP.selObj.card.BackgroundColor3 = AP.CARD
                AP.selObj.lbl.TextColor3 = AP.WHITE
            end)
            AP.selObj = nil
        end
        AP.selObj = obj
        card.BackgroundColor3 = Color3.fromRGB(28,15,55)
        nameLbl.TextColor3 = AP.ACC
        if setclipboard then setclipboard(entry.id) end
        if Opt.APAnimationID then Opt.APAnimationID:Set(entry.id) end
        if Opt.APTimingName then Opt.APTimingName:Set(animName) end
        notify("Loaded: " .. numId, 2)
        AP.visOpenWithId(entry.id, entry.entity)
    end
    local function onAdd()
        if AP.timings[entry.id] and #AP.timings[entry.id] > 0 then
            notify("Already in table: " .. animName, 2); return
        end
        local e = { name = animName, animId = entry.id, delay = 0,
            minDist = 0, maxDist = 25, action = "Custom",
            DodgeDirection = "None", FullHoldBlock = false, MovingAttack = false,
            Repeat = 1, RepeatDelay = 0.35, StartDelay = 0, TriggerDistance = 12,
            SourceFilter = "Any", TargetSide = "Any" }
        table.insert(AP.savedTimings, e)
        if not AP.timings[entry.id] then AP.timings[entry.id] = {} end
        table.insert(AP.timings[entry.id], e)
        local ns = {}; for _, x in ipairs(AP.savedTimings) do table.insert(ns, x.name) end
        ddRefresh(Opt.APSavedTimings, ns); ddSet(Opt.APSavedTimings, animName)
        if Opt.APTimingName then Opt.APTimingName:Set(animName) end
        if Opt.APAnimationID then Opt.APAnimationID:Set(entry.id) end
        AP.saveTimings(); notify("Added: " .. animName, 2)
    end
    local function onBlock()
        AP.logBlacklist[entry.id] = true
        AP.loggedMap[entry.id] = nil
        if AP.selObj == obj then AP.selObj = nil end
        for i, o in ipairs(AP.logLineObjs) do
            if o == obj then table.remove(AP.logLineObjs, i); break end
        end
        pcall(function() card:Destroy() end)
        updCount(); notify("Blocked: " .. animName, 2)
    end

    local zone = AP.inst("TextButton", { Size = UDim2.new(1,-110,1,0), BackgroundTransparency = 1,
        Text = "", ZIndex = 15, Parent = card })
    zone.MouseButton1Click:Connect(onSelect)
    copyBtn.MouseButton1Click:Connect(onSelect)
    addBtn.MouseButton1Click:Connect(onAdd)
    blockBtn.MouseButton1Click:Connect(onBlock)
    card.MouseEnter:Connect(function() if AP.selObj ~= obj then card.BackgroundColor3 = Color3.fromRGB(32,32,32) end end)
    card.MouseLeave:Connect(function() if AP.selObj ~= obj then card.BackgroundColor3 = AP.CARD end end)
end

AP.clearLog = function()
    for _, o in ipairs(AP.logLineObjs) do
        pcall(function() if o.card then o.card:Destroy() end end)
    end
    AP.logLineObjs = {}; AP.selObj = nil; AP.loggedAnims = {}; AP.loggedMap = {}
    AP.logScroll.CanvasSize = UDim2.new(0,0,0,0); updCount()
end

-- ═══ 9. Distance util ═══
AP.distTo = function(root)
    local c = LP.Character; if not c then return nil end
    local r = c:FindFirstChild("HumanoidRootPart"); if not r or not root then return nil end
    return (r.Position - root.Position).Magnitude
end

-- ═══ 10. Log capture ═══
AP.doLogAnim = function(id, src, dist, entityRef, animName, sourceType)
    if not (Tog.APEnableLogger and Tog.APEnableLogger.Value) then return end
    local numId = id:match("%?id=(%d+)") or id:match("rbxassetid://(%d+)") or id:match("^(%d+)$")
    if numId then id = "rbxassetid://" .. numId end
    if id == "" or id == "rbxassetid://0" then return end
    if AP.logBlacklist[id] then return end
    local maxR = Opt.APLogRadius and Opt.APLogRadius.Value or 1000
    if dist and dist > maxR then return end
    if AP.loggedMap[id] then return end
    AP.loggedMap[id] = true
    local entry = { id = id, source = src or "Unknown", dist = dist,
        entity = entityRef, animName = animName, sourceType = sourceType }
    table.insert(AP.loggedAnims, entry)
    if #AP.loggedAnims > 200 then
        local old = table.remove(AP.loggedAnims, 1)
        AP.loggedMap[old.id] = nil
    end
    AP.addLogLine(entry)
end

-- ═══ 11. Animator watcher (self + any entity) ═══
AP.watchAnimator = function(animator)
    if AP.watchedAnims[animator] then return end
    AP.watchedAnims[animator] = true
    table.insert(AP.conns, animator.Destroying:Connect(function()
        AP.watchedAnims[animator] = nil
    end))

    local entity = animator:FindFirstAncestorWhichIsA("Model")
    local src = entity and entity.Name or "Unknown"

    local c = animator.AnimationPlayed:Connect(function(track)
        local isOwn = entity and (entity == LP.Character)
        if isOwn and not AP.logSelf then return end

        local aid = tostring(track.Animation and track.Animation.AnimationId or "")
        local nid = aid:match("%?id=(%d+)") or aid:match("rbxassetid://(%d+)") or aid:match("^(%d+)$")
        if nid then aid = "rbxassetid://" .. nid end
        if aid == "" then return end
        if AP.logBlacklist[aid] then return end

        local root = entity and (entity:FindFirstChild("HumanoidRootPart") or entity.PrimaryPart)
        local dist = root and AP.distTo(root) or nil

        local sourceType = "NPC"
        if isOwn then sourceType = "Self"
        elseif entity and PS:GetPlayerFromCharacter(entity) then sourceType = "Player" end

        local niceName = (track.Name ~= "" and track.Name ~= "Animation"
            and track.Name ~= "animation") and track.Name or nil

        task.defer(AP.doLogAnim, aid, src, dist, entity, niceName, sourceType)
    end)
    table.insert(AP.conns, c)
end

AP.watchPlayer = function(p)
    local function onChar(c)
        task.wait()
        for _, d in next, c:GetDescendants() do
            if d:IsA("Animator") then AP.watchAnimator(d) end
        end
    end
    if p.Character then onChar(p.Character) end
    table.insert(AP.conns, p.CharacterAdded:Connect(onChar))
end

table.insert(AP.conns, workspace.DescendantAdded:Connect(function(d)
    if d:IsA("Animator") then AP.watchAnimator(d)
    elseif d:IsA("AnimationController") then
        local a = d:FindFirstChildOfClass("Animator")
        if a then AP.watchAnimator(a) end
        table.insert(AP.conns, d.ChildAdded:Connect(function(c)
            if c:IsA("Animator") then AP.watchAnimator(c) end
        end))
    end
end))

AP.fullScan = function()
    for _, d in next, workspace:GetDescendants() do
        if d:IsA("Animator") then AP.watchAnimator(d)
        elseif d:IsA("AnimationController") then
            local a = d:FindFirstChildOfClass("Animator")
            if a then AP.watchAnimator(a) end
        end
    end
end
AP.fullScan(); task.delay(3, AP.fullScan)
task.delay(8, AP.fullScan)

for _, p in next, PS:GetPlayers() do AP.watchPlayer(p) end
table.insert(AP.conns, PS.PlayerAdded:Connect(AP.watchPlayer))
if LP.Character then
    task.defer(function()
        for _, d in next, LP.Character:GetDescendants() do
            if d:IsA("Animator") then AP.watchAnimator(d) end
        end
    end)
end
table.insert(AP.conns, LP.CharacterAdded:Connect(function(c)
    task.wait()
    for _, d in next, c:GetDescendants() do
        if d:IsA("Animator") then AP.watchAnimator(d) end
    end
end))

-- ═══ 12. Builder UI ═══
do
    Opt.APSavedTimings = Sec.Table:AddDropdown({
        Name = "Saved Timings", Items = { "--" }, Default = "--", Multi = false, SearchThreshold = 6,
        Callback = function(v)
            local s = type(v) == "table" and next(v) or v
            if not s or s == "--" then return end
            for _, e in ipairs(AP.savedTimings) do
                if e.name == s then
                    pcall(function()
                        Opt.APTimingName:Set(e.name)
                        Opt.APAnimationID:Set(e.animId)
                        Opt.APDelayS:Set(tostring(math.floor(e.delay * 1000)))
                        Opt.APMinDist:Set(e.minDist or 0)
                        Opt.APMaxDist:Set(e.maxDist or 25)
                        ddSet(Opt.APAction, e.action or "Custom")
                        ddSet(Opt.APDodgeDir, e.DodgeDirection or "None")
                        ddSet(Opt.APFullBlock, e.FullHoldBlock and "true" or "false")
                        ddSet(Opt.APMovingAtk, e.MovingAttack and "true" or "false")
                        Opt.APRepeat:Set(e.Repeat or 1)
                        Opt.APRepeatDelay:Set(e.RepeatDelay or 0.35)
                        Opt.APStartDelay:Set(e.StartDelay or 0)
                        Opt.APTriggerDist:Set(e.TriggerDistance or 12)
                        ddSet(Opt.APSourceFilter, e.SourceFilter or "Any")
                        ddSet(Opt.APTargetSide, e.TargetSide or "Any")
                    end)
                    break
                end
            end
        end,
    })
    Opt.APTimingName  = Sec.TimingBuilder:AddTextbox({ Name = "Name",         Placeholder = "e.g. mob swing", Callback = function() end })
    Opt.APAnimationID = Sec.TimingBuilder:AddTextbox({ Name = "Animation ID", Placeholder = "rbxassetid://123456", Callback = function() end })
    Opt.APDelayS      = Sec.TimingBuilder:AddTextbox({ Name = "Delay (ms)",   Placeholder = "350", Numeric = true, Callback = function() end })
    Opt.APMinDist     = Sec.TimingBuilder:AddSlider({ Name = "Min Distance", Min = 0, Max = 500, Default = 0,  Decimals = 1, Callback = function() end })
    Opt.APMaxDist     = Sec.TimingBuilder:AddSlider({ Name = "Max Distance", Min = 0, Max = 500, Default = 25, Decimals = 1, Callback = function() end })
    Opt.APAction      = Sec.TimingBuilder:AddDropdown({ Name = "Action Label",
        Items = { "Custom", "Parry", "Block Start", "Block End", "Dodge", "Dodge Forward",
                  "Counter", "Feint", "M1+Feint", "Attack", "Windup", "Impact" },
        Default = "Custom", Multi = false, Callback = function() end })
    Opt.APDodgeDir    = Sec.TimingBuilder:AddDropdown({ Name = "Dodge Direction",
        Items = { "None", "Forward", "Backward", "Right", "Left", "Counter" },
        Default = "None", Multi = false, Callback = function() end })
    Opt.APFullBlock   = Sec.TimingBuilder:AddDropdown({ Name = "Full Hold",
        Items = { "false", "true" }, Default = "false", Multi = false, Callback = function() end })
    Opt.APMovingAtk   = Sec.TimingBuilder:AddDropdown({ Name = "Moving Attack",
        Items = { "false", "true" }, Default = "false", Multi = false, Callback = function() end })
    Opt.APRepeat      = Sec.TimingBuilder:AddSlider({ Name = "Repeat",           Min = 1, Max = 10,  Default = 1,    Decimals = 1,    Callback = function() end })
    Opt.APRepeatDelay = Sec.TimingBuilder:AddSlider({ Name = "Repeat Delay",     Min = 0, Max = 5,   Default = 0.35, Decimals = 0.01, Callback = function() end })
    Opt.APStartDelay  = Sec.TimingBuilder:AddSlider({ Name = "Start Delay",      Min = 0, Max = 3,   Default = 0,    Decimals = 0.01, Callback = function() end })
    Opt.APTriggerDist = Sec.TimingBuilder:AddSlider({ Name = "Trigger Distance", Min = 1, Max = 200, Default = 12,   Decimals = 1,    Callback = function() end })
    Opt.APSourceFilter = Sec.TimingBuilder:AddDropdown({ Name = "Source Filter",
        Items = { "Any", "Self", "Player", "NPC" }, Default = "Any", Multi = false, Callback = function() end })
    Opt.APTargetSide   = Sec.TimingBuilder:AddDropdown({ Name = "Target Side",
        Items = { "Any", "Enemy", "Ally", "Self" }, Default = "Any", Multi = false, Callback = function() end })

    Sec.TimingBuilder:AddButton({
        Name = "Save Timing",
        Callback = function()
            local n = Opt.APTimingName and Opt.APTimingName.Value or ""
            local a = Opt.APAnimationID and Opt.APAnimationID.Value or ""
            if n == "" or a == "" then notify("Fill Name & Animation ID!", 3); return end
            if not a:find("rbxassetid://") then a = "rbxassetid://" .. a end
            Opt.APAnimationID:Set(a)
            for i = #AP.savedTimings, 1, -1 do
                if AP.savedTimings[i].name == n then
                    local aid = AP.savedTimings[i].animId
                    if AP.timings[aid] then
                        for j, t in ipairs(AP.timings[aid]) do
                            if t.name == n then table.remove(AP.timings[aid], j); break end
                        end
                        if #AP.timings[aid] == 0 then AP.timings[aid] = nil end
                    end
                    table.remove(AP.savedTimings, i)
                end
            end
            local e = {
                name = n, animId = a,
                delay = (tonumber(Opt.APDelayS and Opt.APDelayS.Value) or 0) / 1000,
                minDist = Opt.APMinDist and Opt.APMinDist.Value or 0,
                maxDist = Opt.APMaxDist and Opt.APMaxDist.Value or 25,
                action = Opt.APAction and Opt.APAction.Value or "Custom",
                DodgeDirection = Opt.APDodgeDir and Opt.APDodgeDir.Value or "None",
                FullHoldBlock = (Opt.APFullBlock and Opt.APFullBlock.Value == "true") or false,
                MovingAttack = (Opt.APMovingAtk and Opt.APMovingAtk.Value == "true") or false,
                Repeat = Opt.APRepeat and Opt.APRepeat.Value or 1,
                RepeatDelay = Opt.APRepeatDelay and Opt.APRepeatDelay.Value or 0.35,
                StartDelay = Opt.APStartDelay and Opt.APStartDelay.Value or 0,
                TriggerDistance = Opt.APTriggerDist and Opt.APTriggerDist.Value or 12,
                SourceFilter = Opt.APSourceFilter and Opt.APSourceFilter.Value or "Any",
                TargetSide = Opt.APTargetSide and Opt.APTargetSide.Value or "Any",
            }
            table.insert(AP.savedTimings, e)
            if not AP.timings[a] then AP.timings[a] = {} end
            table.insert(AP.timings[a], e)
            local ns = {}; for _, x in ipairs(AP.savedTimings) do table.insert(ns, x.name) end
            ddRefresh(Opt.APSavedTimings, ns); ddSet(Opt.APSavedTimings, n)
            AP.saveTimings()
            AP.countLbl.Text = #AP.savedTimings .. " in table"
            notify("Saved: " .. n, 2)
        end,
    })
    Sec.TimingBuilder:AddButton({
        Name = "Delete Selected",
        Callback = function()
            local s = Opt.APSavedTimings and Opt.APSavedTimings.Value
            if not s or s == "--" then return end
            for i, e in ipairs(AP.savedTimings) do
                if e.name == s then
                    if AP.timings[e.animId] then
                        for j, t in ipairs(AP.timings[e.animId]) do
                            if t.name == e.name then table.remove(AP.timings[e.animId], j); break end
                        end
                        if #AP.timings[e.animId] == 0 then AP.timings[e.animId] = nil end
                    end
                    table.remove(AP.savedTimings, i); break
                end
            end
            local ns = {}; for _, e in ipairs(AP.savedTimings) do table.insert(ns, e.name) end
            if #ns == 0 then ns = { "--" } end
            ddRefresh(Opt.APSavedTimings, ns); ddSet(Opt.APSavedTimings, ns[1])
            AP.saveTimings()
            AP.countLbl.Text = #AP.savedTimings .. " in table"
        end,
    })
    Sec.TimingBuilder:AddButton({
        Name = "Delete ALL",
        Callback = function()
            AP.savedTimings = {}; AP.timings = {}
            AP.saveTimings()
            task.defer(function()
                ddRefresh(Opt.APSavedTimings, { "--" }); ddSet(Opt.APSavedTimings, "--")
                AP.countLbl.Text = "0 in table"
            end)
            notify("All deleted", 2)
        end,
    })
    Sec.TimingBuilder:AddButton({
        Name = "Export (clipboard)",
        Callback = function()
            local ls = {}
            for _, e in ipairs(AP.savedTimings) do
                table.insert(ls, string.format(
                    '  ["%s"]={name="%s",delay=%.3f,minDist=%d,maxDist=%d,action="%s",DodgeDirection="%s",FullHoldBlock=%s,MovingAttack=%s,Repeat=%d,RepeatDelay=%.2f,StartDelay=%.2f,TriggerDistance=%d,SourceFilter="%s",TargetSide="%s"}',
                    e.animId, e.name, e.delay, e.minDist or 0, e.maxDist or 25,
                    e.action or "Custom", e.DodgeDirection or "None",
                    tostring(e.FullHoldBlock or false), tostring(e.MovingAttack or false),
                    e.Repeat or 1, e.RepeatDelay or 0.35, e.StartDelay or 0,
                    e.TriggerDistance or 12, e.SourceFilter or "Any", e.TargetSide or "Any"))
            end
            if setclipboard then
                setclipboard("local TIMINGS={\n" .. table.concat(ls, ",\n") .. "\n}")
            end
            notify("Copied!", 2)
        end,
    })
    Sec.TimingBuilder:AddButton({
        Name = "Import (from clipboard)",
        Callback = function()
            if not getclipboard then notify("Executor lacks getclipboard", 3); return end
            local raw = getclipboard()
            if not raw or raw == "" then notify("Clipboard empty", 2); return end
            -- accept either a raw JSON array or a "local TIMINGS={...}" lua chunk
            local jsonStart = raw:find("%[")
            local parsed
            if jsonStart then
                local body = raw:sub(jsonStart)
                local ok, data = pcall(function() return HS:JSONDecode(body) end)
                if ok then parsed = data end
            end
            if not parsed then
                -- try lua table literal
                local body = raw:match("local%s+TIMINGS%s*=%s*(.+)$")
                if body then
                    local ok, data = pcall(function() return loadstring("return " .. body)() end)
                    if ok then parsed = data end
                end
            end
            if type(parsed) ~= "table" then notify("Parse failed", 3); return end

            local incoming = AP.parseTimings(HS:JSONEncode(
                (function()
                    local arr = {}
                    for k, v in pairs(parsed) do
                        if type(v) == "table" then
                            local e = { name = v.name or k, animId = v.animId or k,
                                delay = v.delay or 0, minDist = v.minDist or 0,
                                maxDist = v.maxDist or 25, action = v.action or "Custom",
                                DodgeDirection = v.DodgeDirection, FullHoldBlock = v.FullHoldBlock,
                                MovingAttack = v.MovingAttack, Repeat = v.Repeat,
                                RepeatDelay = v.RepeatDelay, StartDelay = v.StartDelay,
                                TriggerDistance = v.TriggerDistance,
                                SourceFilter = v.SourceFilter, TargetSide = v.TargetSide }
                            table.insert(arr, e)
                        end
                    end
                    return arr
                end)()
            ))
            local added = 0
            for _, e in ipairs(incoming) do
                local dup = false
                if AP.timings[e.animId] then
                    for _, t in ipairs(AP.timings[e.animId]) do
                        if t.name == e.name then dup = true; break end
                    end
                end
                if not dup then
                    table.insert(AP.savedTimings, e)
                    if not AP.timings[e.animId] then AP.timings[e.animId] = {} end
                    table.insert(AP.timings[e.animId], e)
                    added = added + 1
                end
            end
            AP.saveTimings()
            local ns = {}; for _, e in ipairs(AP.savedTimings) do table.insert(ns, e.name) end
            ddRefresh(Opt.APSavedTimings, ns)
            AP.countLbl.Text = #AP.savedTimings .. " in table"
            notify("Imported " .. added .. " entries", 3)
        end,
    })
end

-- ═══ 13. Logger UI ═══
do
    Tog.APEnableLogger = Sec.Logger:AddToggle({
        Name = "Log Anims", Default = false,
        Callback = function(p)
            AP.logWin.Visible = p
            if p then AP.clearLog() end
        end,
    })
    Tog.APLogSelf = Sec.Logger:AddToggle({
        Name = "Log Own Anims", Default = true,
        Callback = function(p) AP.logSelf = p end,
    })
    Tog.APShowViz = Sec.Logger:AddToggle({
        Name = "Show Visualizer", Default = false,
        Callback = function(p)
            if AP.visWin then AP.visWin.Visible = p end
            if not p and AP.V and AP.V.hb then AP.V.hb:Disconnect(); AP.V.hb = nil end
        end,
    })
    Opt.APLogRadius = Sec.Logger:AddSlider({
        Name = "Log Radius", Min = 5, Max = 2000, Default = 1000, Decimals = 1,
        Callback = function() end,
    })
    Sec.Logger:AddButton({ Name = "Clear", Callback = function() AP.clearLog(); notify("Cleared", 1.5) end })
    Sec.Logger:AddButton({ Name = "Refresh", Callback = function() notify(#AP.logLineObjs .. " lines", 1.5) end })

    Sec.Blacklist:AddLabel("Blacklist Anim ID (won't log)")
    Opt.APBlacklistAnimID = Sec.Blacklist:AddTextbox({
        Name = "Animation ID", Placeholder = "rbxassetid://0", Callback = function() end,
    })
    Sec.Blacklist:AddButton({
        Name = "Add to Blacklist",
        Callback = function()
            local id = Opt.APBlacklistAnimID and Opt.APBlacklistAnimID.Value or ""
            if id == "" then notify("Enter an Animation ID", 2); return end
            local nid = id:match("%?id=(%d+)") or id:match("rbxassetid://(%d+)") or id:match("^(%d+)$")
            if nid then id = "rbxassetid://" .. nid end
            AP.logBlacklist[id] = true; notify("Blacklisted: " .. id, 2)
        end,
    })
    Sec.Blacklist:AddButton({
        Name = "Clear Blacklist",
        Callback = function() AP.logBlacklist = {}; notify("Blacklist cleared", 2) end,
    })
end

-- ═══ 14. Cleanup ═══
_dzEnv._UCBUnload = function()
    if AP.vClean then AP.vClean() end
    for _, c in ipairs(AP.conns) do pcall(function() c:Disconnect() end) end
    AP.conns = {}
    pcall(function() AP.sg:Destroy() end)
    pcall(function() Library:Unload() end)
end

task.defer(AP.loadTimings)

if type(Window.HideLoading) == "function" then
    pcall(function() Window:HideLoading() end)
end
Library:Notification("Anim Studio", "Logger + Visualizer + Builder loaded.", 5)
