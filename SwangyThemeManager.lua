-- SwangyThemeManager for Swangy
-- Port of Obsidian's addons/ThemeManager.lua built-in themes + custom theme
-- storage, applied to the Drawing library's live Theme table.
--
--   local _ = loadstring(readfile("SwangyThemeManager.lua"))()
--   local ThemeManager = _G.SwangyThemeManager
--   ThemeManager:SetLibrary(_G.Swangy)
--   ThemeManager:BuildConfigSection(_G.Swangy:GetWindow().tabs[5])

local ThemeManager = {}
_G.SwangyThemeManager = ThemeManager
_G.ObsidianThemeManager = ThemeManager -- legacy alias

local Library
local Folder = "Swangy"
local SubFolder = "CustomThemes"

ThemeManager.BuiltInThemes = {
    ["Default"] = { 1, { FontColor = "ffffff", MainColor = "191919", AccentColor = "7d55ff", BackgroundColor = "0f0f0f", OutlineColor = "282828" } },
    ["BBot"] = { 2, { FontColor = "ffffff", MainColor = "1e1e1e", AccentColor = "7e48a3", BackgroundColor = "232323", OutlineColor = "141414" } },
    ["Fatality"] = { 3, { FontColor = "ffffff", MainColor = "1e1842", AccentColor = "c50754", BackgroundColor = "191335", OutlineColor = "3c355d" } },
    ["Jester"] = { 4, { FontColor = "ffffff", MainColor = "242424", AccentColor = "db4467", BackgroundColor = "1c1c1c", OutlineColor = "373737" } },
    ["Mint"] = { 5, { FontColor = "ffffff", MainColor = "242424", AccentColor = "3db488", BackgroundColor = "1c1c1c", OutlineColor = "373737" } },
    ["Tokyo Night"] = { 6, { FontColor = "ffffff", MainColor = "191925", AccentColor = "6759b3", BackgroundColor = "16161f", OutlineColor = "323232" } },
    ["Ubuntu"] = { 7, { FontColor = "ffffff", MainColor = "3e3e3e", AccentColor = "e2581e", BackgroundColor = "323232", OutlineColor = "191919" } },
    ["Quartz"] = { 8, { FontColor = "ffffff", MainColor = "232330", AccentColor = "426e87", BackgroundColor = "1d1b26", OutlineColor = "27232f" } },
    ["Nord"] = { 9, { FontColor = "eceff4", MainColor = "3b4252", AccentColor = "88c0d0", BackgroundColor = "2e3440", OutlineColor = "4c566a" } },
    ["Dracula"] = { 10, { FontColor = "f8f8f2", MainColor = "44475a", AccentColor = "ff79c6", BackgroundColor = "282a36", OutlineColor = "6272a4" } },
    ["Monokai"] = { 11, { FontColor = "f8f8f2", MainColor = "272822", AccentColor = "f92672", BackgroundColor = "1e1f1c", OutlineColor = "49483e" } },
    ["Gruvbox"] = { 12, { FontColor = "ebdbb2", MainColor = "3c3836", AccentColor = "fb4934", BackgroundColor = "282828", OutlineColor = "504945" } },
    ["Solarized"] = { 13, { FontColor = "839496", MainColor = "073642", AccentColor = "cb4b16", BackgroundColor = "002b36", OutlineColor = "586e75" } },
    ["Catppuccin"] = { 14, { FontColor = "d9e0ee", MainColor = "302d41", AccentColor = "f5c2e7", BackgroundColor = "1e1e2e", OutlineColor = "575268" } },
    ["One Dark"] = { 15, { FontColor = "abb2bf", MainColor = "282c34", AccentColor = "c678dd", BackgroundColor = "21252b", OutlineColor = "5c6370" } },
    ["Cyberpunk"] = { 16, { FontColor = "f9f9f9", MainColor = "262335", AccentColor = "00ff9f", BackgroundColor = "1a1a2e", OutlineColor = "413c5e" } },
    ["Oceanic Next"] = { 17, { FontColor = "d8dee9", MainColor = "1b2b34", AccentColor = "6699cc", BackgroundColor = "16232a", OutlineColor = "343d46" } },
    ["Material"] = { 18, { FontColor = "eeffff", MainColor = "212121", AccentColor = "82aaff", BackgroundColor = "151515", OutlineColor = "424242" } },
}

local function jsonEncode(t)
    local hs
    pcall(function() hs = game:GetService("HttpService") end)
    if hs then
        local ok, res = pcall(function() return hs:JSONEncode(t) end)
        if ok then return res end
    end
end
local function jsonDecode(s)
    local hs
    pcall(function() hs = game:GetService("HttpService") end)
    if hs then
        local ok, res = pcall(function() return hs:JSONDecode(s) end)
        if ok then return res end
    end
end

local function toColor(v)
    if typeof and typeof(v) == "Color3" then return v end
    if type(v) == "table" and v.R then return Color3.new(v.R, v.G, v.B) end
    if type(v) == "string" then
        local ok, c = pcall(function() return Color3.fromHex(v) end)
        if ok and c then return c end
    end
    return nil
end
local function toHex(c)
    local function p(x) return string.format("%02x", math.floor(x * 255 + 0.5)) end
    return p(c.R) .. p(c.G) .. p(c.B)
end
local function mix(a, b, t)
    return Color3.fromRGB(
        math.floor(a.R * 255 + (b.R * 255 - a.R * 255) * t + 0.5),
        math.floor(a.G * 255 + (b.G * 255 - a.G * 255) * t + 0.5),
        math.floor(a.B * 255 + (b.B * 255 - a.B * 255) * t + 0.5)
    )
end

local function base() return Folder .. "/" .. SubFolder end
local function ensureTree()
    if not isfolder(Folder) then pcall(makefolder, Folder) end
    if not isfolder(base()) then pcall(makefolder, base()) end
    return base()
end
local function safeName(n)
    n = tostring(n or "theme"):gsub("[^%w%-_ ]", "")
    if n == "" then n = "theme" end
    return n
end

function ThemeManager:SetLibrary(lib)
    Library = lib
    return self
end
function ThemeManager:SetFolder(f) Folder = tostring(f) return self end
function ThemeManager:SetSubFolder(f) SubFolder = tostring(f) return self end
function ThemeManager:GetPaths() return { ensureTree() } end
function ThemeManager:BuildFolderTree() ensureTree() return self end
function ThemeManager:CheckFolderTree() ensureTree() return self end
function ThemeManager:ThemeUpdate() return self end

function ThemeManager:ApplyThemeData(data)
    if not Library then return false, "library not set" end
    if type(data) == "table" and data[2] and type(data[2]) == "table" then data = data[2] end
    if type(data) ~= "table" then return false, "invalid theme data" end
    local T = Library.Theme
    local bg = toColor(data.BackgroundColor) or T.bg
    local main = toColor(data.MainColor) or T.main
    local accent = toColor(data.AccentColor) or T.accent
    local outline = toColor(data.OutlineColor) or T.outline
    local font = toColor(data.FontColor) or T.text
    T.bg, T.main, T.accent, T.outline, T.text = bg, main, accent, outline, font
    T.panel, T.panel2, T.stroke, T.track, T.sidebar = bg, main, outline, main, bg
    T.strokeLit = mix(outline, font, 0.15)
    T.subtext = mix(font, bg, 0.5)
    T.dim = mix(font, bg, 0.35)
    T.disabled = mix(font, bg, 0.6)
    T.white = font
    if data.CornerRadius then Library.CornerRadius = data.CornerRadius end
    return true
end

function ThemeManager:ApplyTheme(name)
    local data = self:GetCustomTheme(name) or self.BuiltInThemes[name]
    if not data then return false, "theme not found" end
    return self:ApplyThemeData(data)
end

function ThemeManager:CurrentThemeData()
    local T = Library and Library.Theme
    if not T then return nil end
    return {
        FontColor = toHex(T.text),
        MainColor = toHex(T.main),
        AccentColor = toHex(T.accent),
        BackgroundColor = toHex(T.bg),
        OutlineColor = toHex(T.outline),
    }
end

function ThemeManager:ReloadCustomThemes()
    ensureTree()
    local out = {}
    local ok, files = pcall(listfiles, base())
    if ok then
        for _, path in ipairs(files or {}) do
            local name = tostring(path):match("([^/\\]+)%.json$")
            if name then out[#out + 1] = name end
        end
    end
    table.sort(out)
    return out
end

function ThemeManager:GetCustomTheme(name)
    local path = base() .. "/" .. safeName(name) .. ".json"
    if not isfile(path) then return nil end
    local ok, content = pcall(readfile, path)
    if not ok then return nil end
    return jsonDecode(content)
end

function ThemeManager:SaveCustomTheme(name)
    ensureTree()
    local data = self:CurrentThemeData()
    local encoded = jsonEncode(data)
    if not encoded then return false, "JSONEncode unavailable" end
    local ok, err = pcall(writefile, base() .. "/" .. safeName(name) .. ".json", encoded)
    if not ok then return false, tostring(err) end
    return true
end

function ThemeManager:Delete(name)
    local path = base() .. "/" .. safeName(name) .. ".json"
    if not isfile(path) then return false, "theme not found" end
    pcall(delfile, path)
    return true
end

function ThemeManager:GetDefaultTheme()
    local path = Folder .. "/defaulttheme.txt"
    if not isfile(path) then return nil end
    local ok, content = pcall(readfile, path)
    if not ok then return nil end
    return (tostring(content):gsub("%s+$", ""))
end
function ThemeManager:SaveDefault(ThemeName)
    ensureTree()
    local ok, err = pcall(writefile, Folder .. "/defaulttheme.txt", safeName(ThemeName))
    if not ok then return false, tostring(err) end
    return true
end
function ThemeManager:LoadDefault()
    local name = self:GetDefaultTheme()
    if not name or name == "" then return false, "no default theme" end
    return self:ApplyTheme(name)
end
function ThemeManager:DeleteDefaultTheme()
    local path = Folder .. "/defaulttheme.txt"
    if not isfile(path) then return false, "no default theme" end
    pcall(delfile, path)
    return true
end

local function themeNames()
    local names = {}
    for name in pairs(ThemeManager.BuiltInThemes) do names[#names + 1] = name end
    for _, name in ipairs(ThemeManager:ReloadCustomThemes()) do
        if not ThemeManager.BuiltInThemes[name] then names[#names + 1] = name end
    end
    table.sort(names)
    for i, name in ipairs(names) do
        if name == "Default" then
            table.remove(names, i)
            table.insert(names, 1, "Default")
            break
        end
    end
    return names
end

function ThemeManager:GetThemes()
    return themeNames()
end

local function build(group)
    local savedDefault = ThemeManager:GetDefaultTheme()
    local dd = group:AddDropdown("ThemeManager_ThemeList", {
        Text = "Theme",
        Values = themeNames(),
        Default = savedDefault or "Default",
        MaxVisible = 8,
        Callback = function(name)
            if name then
                ThemeManager:ApplyTheme(name)
                if Library then Library:Notify("Theme: " .. tostring(name), 2, "Theme") end
            end
        end,
    })
    local function refresh()
        dd:SetValues(themeNames())
    end
    group:AddButton({
        Text = "Apply Theme",
        Func = function()
            if not dd.value then return end
            local ok, err = ThemeManager:ApplyTheme(dd.value)
            if Library then Library:Notify(ok and ("Theme: " .. dd.value) or ("Theme failed: " .. tostring(err)), 3, "Theme") end
        end,
    })
    group:AddButton({
        Text = "Save Current As New",
        Func = function()
            local name = "theme-" .. tostring(os.date and os.date("%Y%m%d-%H%M%S") or math.floor(tick()))
            local ok = ThemeManager:SaveCustomTheme(name)
            refresh()
            if ok then dd.value = name end
            if Library then Library:Notify(ok and ("Saved theme " .. name) or "Theme save failed", 3, "Theme") end
        end,
    })
    group:AddButton({
        Text = "Save As Default",
        Func = function()
            if not dd.value then return end
            ThemeManager:SaveDefault(dd.value)
            if Library then Library:Notify("Default theme: " .. dd.value, 3, "Theme") end
        end,
    })
    group:AddButton({
        Text = "Load Default",
        Func = function()
            local ok, err = ThemeManager:LoadDefault()
            if Library then Library:Notify(ok and "Loaded default theme" or tostring(err), 3, "Theme") end
        end,
    })
    group:AddButton({
        Text = "Delete Theme",
        Func = function()
            if not dd.value then return end
            local ok, err = ThemeManager:Delete(dd.value)
            refresh()
            if Library then Library:Notify(ok and ("Deleted " .. dd.value) or tostring(err), 3, "Theme") end
        end,
    })
    group:AddButton({ Text = "Refresh Themes", Func = refresh })
    return group
end

function ThemeManager:BuildConfigSection(Tab)
    local group = Tab:AddGroupbox({ Side = "Left", Name = "Themes" })
    build(group)
    local saved = self:GetDefaultTheme()
    if saved then
        pcall(function() self:ApplyTheme(saved) end)
    end
    return group
end

function ThemeManager:ApplyToTab(Tab)
    return self:BuildConfigSection(Tab)
end

function ThemeManager:ApplyToGroupbox(group)
    return build(group)
end

return ThemeManager
