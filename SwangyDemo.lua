-- SwangyDemo.lua - example menu built with Swangy.lua
-- Loads Swangy (and its addons) straight from GitHub with httpget + loadstring.

local BASE = "https://raw.githubusercontent.com/YoungSlaves/matchaUI/main/"

local function fetchScript(name)
    local src
    pcall(function() src = httpget(BASE .. name) end)
    if type(src) ~= "string" or #src < 100 then
        error("Swangy: failed to download " .. name)
    end
    local fn, compileErr = loadstring(src, name)
    if not fn then
        error("Swangy: compile error in " .. name .. ": " .. tostring(compileErr))
    end
    local ok, runErr = pcall(fn)
    if not ok then
        error("Swangy: runtime error in " .. name .. ": " .. tostring(runErr))
    end
end

if _G.Swangy and _G.Swangy.Unload then
    pcall(function() _G.Swangy:Unload() end)
end
if _G.Obsidian and _G.Obsidian ~= _G.Swangy and _G.Obsidian.Unload then
    pcall(function() _G.Obsidian:Unload() end)
end

fetchScript("Swangy.lua")

local Library = _G.Swangy
if not Library then
    error("Swangy library did not expose _G.Swangy")
end

local function getCharacter()
    local Players = game:GetService("Players")
    local lp = Players and Players.LocalPlayer
    if lp and lp.Character then
        return lp.Character
    end
    local cam = workspace.CurrentCamera
    local subject = cam and cam.CameraSubject
    return subject and subject.Parent or nil
end

local function getHumanoid()
    local char = getCharacter()
    return char and char:FindFirstChildOfClass("Humanoid") or nil
end

local Window = Library:CreateWindow({
    Title = "Swangy",
    Footer = "",
    Center = true,
    NotifySide = "Right",
    ToggleKeybind = "RightShift",
})

local Tabs = {
    Main = Window:AddTab("Main", "user"),
    Visuals = Window:AddTab("Visuals", "eye"),
    Movement = Window:AddTab("Movement", "activity"),
    Misc = Window:AddTab("Misc", "wrench"),
    Notifications = Window:AddTab("Notifications", "bell"),
    Settings = Window:AddTab("Settings", "settings"),
}

Library:BuildNotificationSettings(Tabs.Notifications)

-- Main ---------------------------------------------------------------------
local MainGroup = Tabs.Main:AddGroupbox({ Side = "Left", Name = "General", Description = "example controls" })
MainGroup:AddLabel({ Text = "Welcome. This is the Swangy menu rendered entirely with Matcha's Drawing API.", DoesWrap = true })
MainGroup:AddDivider("Demo")
MainGroup:AddToggle("DemoToggle", {
    Text = "Enable Demo Feature",
    Default = false,
    Callback = function(on)
        Library:Notify("Demo feature " .. (on and "enabled" or "disabled"), 3)
    end,
})
MainGroup:AddSlider("DemoSlider", {
    Text = "Strength",
    Default = 50,
    Min = 0,
    Max = 100,
    Rounding = 1,
    Suffix = "%",
    Callback = function(v)
        print("[SwangyDemo] strength", v)
    end,
})
MainGroup:AddDropdown("DemoDropdown", {
    Text = "Mode",
    Values = { "Legit", "Rage", "Silent" },
    Default = "Legit",
})
MainGroup:AddButton({
    Text = "Send Notification",
    Func = function()
        Library:Notify("This is a notification from the button.", 4, "Swangy")
    end,
})

local MainRight = Tabs.Main:AddGroupbox({ Side = "Right", Name = "Keybinds", Description = "bind toggles" })
Library.Options.DemoToggle:AddKeyPicker("DemoKey", { Default = "F", Mode = "Toggle" })
MainGroup:AddColorPicker("DemoColor", { Default = Library.Theme.accent, Title = "Highlight Color" })
MainRight:AddLabel({ Text = "Click a keybind then press a key to rebind. Right-click it to pick Hold, Toggle or Always.", DoesWrap = true })

-- Visuals ------------------------------------------------------------------
local EspGroup = Tabs.Visuals:AddGroupbox({ Side = "Left", Name = "Player ESP" })
EspGroup:AddToggle("EspEnabled", { Text = "Enable ESP", Default = false })
EspGroup:AddToggle("EspHealth", { Text = "Health Bars", Default = true })
EspGroup:AddToggle("EspNames", { Text = "Names", Default = true })
EspGroup:AddSlider("EspMaxDistance", { Text = "Max Distance", Default = 1000, Min = 50, Max = 5000, Rounding = 0 })
EspGroup:AddColorPicker("EspColor", { Text = "ESP Color", Default = Color3.fromRGB(255, 80, 80) })

local WorldGroup = Tabs.Visuals:AddGroupbox({ Side = "Right", Name = "World" })
WorldGroup:AddToggle("NoFog", {
    Text = "No Fog",
    Default = false,
    Callback = function(on)
        local Lighting = game:GetService("Lighting")
        if on then
            if WorldGroup.__fog == nil then
                WorldGroup.__fog = { Lighting.FogStart, Lighting.FogEnd }
            end
            Lighting.FogStart = 100000
            Lighting.FogEnd = 100000
        elseif WorldGroup.__fog then
            Lighting.FogStart = WorldGroup.__fog[1]
            Lighting.FogEnd = WorldGroup.__fog[2]
        end
    end,
})
WorldGroup:AddSlider("FieldOfView", {
    Text = "Field of View",
    Default = 70,
    Min = 50,
    Max = 120,
    Rounding = 1,
    Callback = function(v)
        local cam = workspace.CurrentCamera
        if cam then
            cam.FieldOfView = v
        end
    end,
})

-- Movement -----------------------------------------------------------------
local MoveGroup = Tabs.Movement:AddGroupbox({ Side = "Left", Name = "Movement" })
MoveGroup:AddToggle("SpeedEnabled", { Text = "Speed Modifier", Default = false })
MoveGroup:AddSlider("SpeedValue", {
    Text = "Walk Speed",
    Default = 16,
    Min = 1,
    Max = 250,
    Rounding = 1,
    Callback = function(v)
        if Library.Options.SpeedEnabled and Library.Options.SpeedEnabled.value then
            local hum = getHumanoid()
            if hum then
                hum.WalkSpeed = v
            end
        end
    end,
})
MoveGroup:AddSlider("JumpValue", {
    Text = "Jump Power",
    Default = 50,
    Min = 50,
    Max = 300,
    Rounding = 1,
    Callback = function(v)
        if Library.Options.JumpEnabled and Library.Options.JumpEnabled.value then
            local hum = getHumanoid()
            if hum then
                hum.JumpPower = v
            end
        end
    end,
})
MoveGroup:AddToggle("JumpEnabled", { Text = "Jump Modifier", Default = false })

local InfoGroup = Tabs.Movement:AddGroupbox({ Side = "Right", Name = "Info" })
InfoGroup:AddLabel({ Text = "Movement values apply to the local Humanoid while the matching toggle is enabled.", DoesWrap = true })
InfoGroup:AddButton({
    Text = "Reset Speed",
    Func = function()
        local hum = getHumanoid()
        if hum then
            hum.WalkSpeed = 16
        end
        Library:Notify("Walk speed reset to 16", 2)
    end,
})

-- Misc ---------------------------------------------------------------------
local MiscGroup = Tabs.Misc:AddGroupbox({ Side = "Left", Name = "Utility" })
MiscGroup:AddButton({
    Text = "Copy Game Name",
    Func = function()
        pcall(setclipboard, getgamename())
        Library:Notify("Copied: " .. tostring(getgamename()), 3)
    end,
})
MiscGroup:AddButton({
    Text = "Print Ping",
    Func = function()
        Library:Notify("Ping: " .. tostring(GetPingValue()) .. "ms", 3)
    end,
})
MiscGroup:AddDropdown("NotifySide", {
    Text = "Notification Side",
    Values = { "Right", "Left" },
    Default = "Right",
    Callback = function(v)
        Library.NotifySide = v
    end,
})

local AboutGroup = Tabs.Misc:AddGroupbox({ Side = "Right", Name = "About" })
AboutGroup:AddLabel({ Text = "made by aphalia for matcha", DoesWrap = true })
AboutGroup:AddDivider("Toggle the menu with RightShift")

-- Settings -----------------------------------------------------------------
local ThemeGroup = Tabs.Settings:AddGroupbox({ Side = "Left", Name = "Appearance" })
ThemeGroup:AddColorPicker("AccentPicker", {
    Text = "Accent Color",
    Default = Library.Theme.accent,
    Callback = function(c)
        Library:SetAccent(c)
    end,
})
ThemeGroup:AddToggle("Watermark", {
    Text = "Watermark",
    Default = true,
    Callback = function(on)
        Library:SetWatermark(on)
    end,
})
ThemeGroup:AddKeyPicker("MenuKey", {
    Text = "Menu Key",
    Default = "RightShift",
    CaptureOnly = true,
    ChangedCallback = function(el)
        Library:SetMenuKey(el.vk)
    end,
})

local DangerGroup = Tabs.Settings:AddGroupbox({ Side = "Right", Name = "Danger" })
DangerGroup:AddLabel({ Text = "Unloading removes every Drawing created by this library.", DoesWrap = true })
DangerGroup:AddButton({
    Text = "Unload UI",
    Func = function()
        Library:Unload()
    end,
})

fetchScript("SwangySaveManager.lua")
local SaveManager = _G.SwangySaveManager
if SaveManager then
    SaveManager:SetLibrary(Library)
    SaveManager:BuildConfigSection(Tabs.Settings)
end

fetchScript("SwangyThemeManager.lua")
local ThemeManager = _G.SwangyThemeManager
if ThemeManager then
    ThemeManager:SetLibrary(Library)
    ThemeManager:BuildConfigSection(Tabs.Settings)
end

Library:Notify("Swangy loaded. Press RightShift to toggle.", 5, "Swangy")
