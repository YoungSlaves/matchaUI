-- SwangySaveManager for Swangy
-- Port of Obsidian's addons/SaveManager.lua core (JSON configs + config tab),
-- built on Matcha file APIs and the Drawing UI.
--
--   local _ = loadstring(readfile("SwangySaveManager.lua"))()
--   local SaveManager = _G.SwangySaveManager
--   SaveManager:SetLibrary(_G.Swangy)
--   SaveManager:BuildConfigSection(_G.Swangy:GetWindow().tabs[1], "settings")

local SaveManager = {}
_G.SwangySaveManager = SaveManager
_G.ObsidianSaveManager = SaveManager -- legacy alias

local Library
local Folder = "Swangy"
local SubFolder = "Configs"
local IgnoreIndexes = {}
local LoadingOrder = nil

local function jsonEncode(t)
    local hs
    pcall(function() hs = game:GetService("HttpService") end)
    if hs then
        local ok, res = pcall(function() return hs:JSONEncode(t) end)
        if ok then return res end
    end
    return nil, "JSONEncode unavailable"
end

local function jsonDecode(s)
    local hs
    pcall(function() hs = game:GetService("HttpService") end)
    if hs then
        local ok, res = pcall(function() return hs:JSONDecode(s) end)
        if ok then return res end
    end
    return nil, "JSONDecode unavailable"
end

local function base()
    return Folder .. "/" .. SubFolder
end

local function ensureTree()
    if not isfolder(Folder) then pcall(makefolder, Folder) end
    local p = base()
    if not isfolder(p) then pcall(makefolder, p) end
    return p
end

local function safeName(name)
    name = tostring(name or "default")
    name = name:gsub("[^%w%-_ ]", "")
    if name == "" then name = "default" end
    return name
end

function SaveManager:SetLibrary(lib)
    Library = lib
    return self
end
function SaveManager:SetFolder(f)
    Folder = tostring(f)
    return self
end
function SaveManager:SetSubFolder(f)
    SubFolder = tostring(f)
    return self
end
function SaveManager:GetPaths()
    return { ensureTree() }
end
function SaveManager:BuildFolderTree()
    ensureTree()
    return self
end
function SaveManager:CheckFolderTree()
    ensureTree()
    return self
end
function SaveManager:CheckSubFolder()
    ensureTree()
    return self
end
function SaveManager:SetIgnoreIndexes(list)
    IgnoreIndexes = {}
    for _, v in ipairs(list or {}) do IgnoreIndexes[v] = true end
    return self
end
function SaveManager:SetLoadingOrder(enabled, order)
    LoadingOrder = order
    return self
end
function SaveManager:IgnoreThemeSettings()
    return self
end

local function ignored(id)
    return IgnoreIndexes[id] == true
end

local function gather()
    local out = {}
    if not Library then return out end
    for id, el in pairs(Library.Options) do
        if not ignored(id) and el and not el.destroyed then
            local kind = el.kind
            if kind == "Toggle" then
                out[id] = { t = "Toggle", v = el.value == true }
            elseif kind == "Slider" then
                out[id] = { t = "Slider", v = el.value }
            elseif kind == "Dropdown" then
                out[id] = { t = "Dropdown", v = el.value }
            elseif kind == "KeyPicker" then
                out[id] = { t = "KeyPicker", v = el.vk, m = el.mode }
            elseif kind == "ColorPicker" then
                local c = el:Color()
                out[id] = { t = "Color", r = c.R, g = c.G, b = c.B, a = el.alpha or 1 }
            end
        end
    end
    return out
end

local function applyData(data)
    if not Library then return false end
    for id, d in pairs(data or {}) do
        local el = Library.Options[id]
        if el and not ignored(id) then
            local kind = d.t or el.kind
            if kind == "Toggle" then
                el:SetValue(d.v == true)
            elseif kind == "Slider" then
                el:SetValue(d.v)
            elseif kind == "Dropdown" then
                el:SetValue(d.v)
            elseif kind == "KeyPicker" then
                el.vk = d.v
                if d.m then el.mode = d.m end
                el.state = false
            elseif kind == "Color" then
                local c = Color3.new(d.r or 1, d.g or 1, d.b or 1)
                el:SetValueRGB(c, 1 - (d.a or 1))
            end
        end
    end
    return true
end

function SaveManager:RefreshConfigList()
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

function SaveManager:Save(ConfigName)
    if not Library then return false, "library not set" end
    local name = safeName(ConfigName)
    local encoded, err = jsonEncode({ Options = gather() })
    if not encoded then return false, err end
    ensureTree()
    local ok, werr = pcall(writefile, base() .. "/" .. name .. ".json", encoded)
    if not ok then return false, tostring(werr) end
    return true
end

function SaveManager:Load(ConfigName)
    local name = safeName(ConfigName)
    local path = base() .. "/" .. name .. ".json"
    if not isfile(path) then return false, "config not found" end
    local ok, content = pcall(readfile, path)
    if not ok then return false, tostring(content) end
    local data, derr = jsonDecode(content)
    if not data then return false, derr end
    applyData(data.Options or data)
    return true
end

function SaveManager:Delete(ConfigName)
    local name = safeName(ConfigName)
    local path = base() .. "/" .. name .. ".json"
    if not isfile(path) then return false, "config not found" end
    local ok, err = pcall(delfile, path)
    if not ok then return false, tostring(err) end
    return true
end

function SaveManager:Rename(OldName, NewName)
    local old = base() .. "/" .. safeName(OldName) .. ".json"
    if not isfile(old) then return false, "config not found" end
    local newp = base() .. "/" .. safeName(NewName) .. ".json"
    if isfile(newp) then return false, "a config with that name exists" end
    local ok, content = pcall(readfile, old)
    if not ok then return false, tostring(content) end
    local wok, werr = pcall(writefile, newp, content)
    if not wok then return false, tostring(werr) end
    pcall(delfile, old)
    if self:GetAutoloadConfig() == safeName(OldName) then
        self:SaveAutoloadConfig(NewName)
    end
    return true
end

function SaveManager:GetAutoloadConfig()
    local path = base() .. "/autoload.txt"
    if not isfile(path) then return nil end
    local ok, content = pcall(readfile, path)
    if not ok then return nil end
    return (tostring(content):gsub("%s+$", ""))
end

function SaveManager:SaveAutoloadConfig(ConfigName)
    ensureTree()
    local ok, err = pcall(writefile, base() .. "/autoload.txt", safeName(ConfigName))
    if not ok then return false, tostring(err) end
    return true
end

function SaveManager:LoadAutoloadConfig()
    local name = self:GetAutoloadConfig()
    if not name or name == "" then return false, "no autoload config" end
    return self:Load(name)
end

function SaveManager:DeleteAutoLoadConfig()
    local path = base() .. "/autoload.txt"
    if not isfile(path) then return false, "no autoload config" end
    pcall(delfile, path)
    return true
end

function SaveManager:BuildConfigSection(Tab, IconName)
    local group = Tab:AddGroupbox({ Side = "Right", Name = "Configs" })
    local list = self:RefreshConfigList()
    local nameInput
    local dd = group:AddDropdown("SaveManager_ConfigList", {
        Text = "Config",
        Values = list,
        Default = list[1],
        MaxVisible = 6,
        Callback = function(v)
            if nameInput then nameInput:SetValue(v or "") end
        end,
    })
    nameInput = group:AddInput("SaveManager_ConfigName", {
        Text = "Config name",
        Default = list[1] or "",
        Placeholder = "type a name",
    })
    local autoloadLabel = group:AddLabel({ Text = "Autoload: none", DoesWrap = true })

    local function currentName()
        local n = nameInput.value
        if not n or n == "" then n = dd.value end
        return n
    end
    local function updateAutoload()
        local a = self:GetAutoloadConfig()
        autoloadLabel:SetText("Autoload: " .. ((a and a ~= "") and a or "none"))
    end
    local function refresh()
        local l = self:RefreshConfigList()
        dd:SetValues(l)
        if not dd.value and l[1] then dd.value = l[1] end
        updateAutoload()
        return l
    end
    local function notify(msg, ok)
        if Library then Library:Notify(msg, 3, ok and "Config" or "Config error") end
    end

    group:AddButton({
        Text = "Save / Overwrite",
        Func = function()
            local name = currentName()
            if not name or name == "" then return notify("Pick a config or type a name", false) end
            local ok, err = self:Save(name)
            refresh()
            if ok then dd:SetValue(name) end
            notify(ok and ("Saved " .. name) or ("Save failed: " .. tostring(err)), ok)
        end,
    })
    group:AddButton({
        Text = "Rename",
        Func = function()
            local old, new = dd.value, nameInput.value
            if not old then return notify("No config selected", false) end
            if not new or new == "" then return notify("Type the new name", false) end
            local ok, err = self:Rename(old, new)
            refresh()
            if ok then dd:SetValue(new) end
            notify(ok and ("Renamed to " .. new) or ("Rename failed: " .. tostring(err)), ok)
        end,
    })
    group:AddButton({
        Text = "Load",
        Func = function()
            if not dd.value then return notify("No config selected", false) end
            local ok, err = self:Load(dd.value)
            notify(ok and ("Loaded " .. dd.value) or ("Load failed: " .. tostring(err)), ok)
        end,
    })
    group:AddButton({
        Text = "Delete",
        Func = function()
            if not dd.value then return notify("No config selected", false) end
            local name = dd.value
            local ok, err = self:Delete(name)
            refresh()
            if ok and self:GetAutoloadConfig() == name then
                self:DeleteAutoLoadConfig()
                updateAutoload()
            end
            notify(ok and ("Deleted " .. name) or ("Delete failed: " .. tostring(err)), ok)
        end,
    })
    group:AddButton({
        Text = "Set Autoload",
        Func = function()
            local name = currentName() or dd.value
            if not name or name == "" then return notify("Select a config first", false) end
            if not isfile(base() .. "/" .. safeName(name) .. ".json") then
                return notify("Save the config before setting autoload", false)
            end
            self:SaveAutoloadConfig(name)
            updateAutoload()
            notify("Autoload set to " .. name, true)
        end,
    })
    group:AddButton({
        Text = "Clear Autoload",
        Func = function()
            self:DeleteAutoLoadConfig()
            updateAutoload()
            notify("Autoload cleared", true)
        end,
    })
    group:AddButton({ Text = "Refresh", Func = refresh })
    group:AddLabel({ Text = "Configs are stored as JSON in " .. base() .. ".", DoesWrap = true })

    updateAutoload()
    pcall(function() self:LoadAutoloadConfig() end)
    return group
end

return SaveManager
