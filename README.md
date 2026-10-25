# Swangy UI

A Drawing-based UI library for the Matcha executor, with an Obsidian-compatible API.
No `Instance.new`, no `ScreenGui`; everything is rendered with `Drawing` and polled input.

Made by aphalia for matcha.

---

## Preview

![Swangy UI preview](https://raw.githubusercontent.com/YoungSlaves/matchaUI/refs/heads/main/PreviewUI.gif)

---

## Files

| File | Purpose |
|---|---|
| `Library.lua` | The library. Everything you load. |
| `SwangySaveManager.lua` | JSON config saving/loading + config tab. |
| `SwangyThemeManager.lua` | 18 built-in themes + custom themes. |
| `SwangyDemo.lua` | Example menu showing every element. |
| `README.md` | This documentation. |
| `LLM.md` | Full Matcha + Swangy reference written for AI/LLM code generation. |

Everything is loaded straight from GitHub with `httpget` + `loadstring`. Nothing is
downloaded to disk and `readfile` is not required.

---

## Loading

Top-level returns are dropped by Matcha, so the library exports a global.

```lua
local BASE = "https://raw.githubusercontent.com/YoungSlaves/matchaUI/main/"

local _ = loadstring(httpget(BASE .. "Library.lua"))()
local Library = _G.Swangy
```

Addons:

```lua
loadstring(httpget(BASE .. "SwangySaveManager.lua"))()
loadstring(httpget(BASE .. "SwangyThemeManager.lua"))()
```

`_G.Obsidian` is kept as a legacy alias.

To stop / remove everything:

```lua
_G.Swangy:Unload()
```

Run the demo (it fetches the library and addons itself):

```lua
local BASE = "https://raw.githubusercontent.com/YoungSlaves/matchaUI/main/"
loadstring(httpget(BASE .. "SwangyDemo.lua"))()
```

---

## Quick start

```lua
local BASE = "https://raw.githubusercontent.com/YoungSlaves/matchaUI/main/"
local _ = loadstring(httpget(BASE .. "Library.lua"))()
local Library = _G.Swangy

local Window = Library:CreateWindow({
    Title = "My Script",
    Width = 720,
    Height = 600,
    Center = true,
    ToggleKeybind = "RightShift",
    NotifySide = "Right",
})

local Tab = Window:AddTab("Main", "user")

local Left = Tab:AddGroupbox({ Side = "Left", Name = "General" })
local Right = Tab:AddGroupbox({ Side = "Right", Name = "Info" })

Left:AddToggle("Enabled", {
    Text = "Enable Feature",
    Default = false,
    Callback = function(on)
        print("enabled:", on)
    end,
})

Right:AddLabel({ Text = "made by aphalia for matcha", DoesWrap = true })
```

---

## Window

`Library:CreateWindow(config)`

| Key | Type | Default |
|---|---|---|
| `Title` | string | `"No Title"` |
| `Width` / `Height` | number | `720` / `600` |
| `Center` | boolean | `true` |
| `ToggleKeybind` | string or VK | `"RightShift"` |
| `NotifySide` | `"Right"` / `"Left"` | `"Right"` |
| `Accent` | Color3 | purple |
| `CornerRadius` | number | `4` |

Methods:

```lua
Window:AddTab("Name", "icon", "description")
Window:SelectTab(1)          -- switch to a tab by index or Tab object
Window:Toggle(true/false)    -- open/close
Window:SetTitle("New")
Window:SetPos(100, 100)
Window:SetSize(800, 560)
Window:Center()
```

Menu key uses Windows VK codes internally. `Library:SetMenuKey("RightShift")` also works.

---

## Tabs and groupboxes

```lua
local Tab = Window:AddTab("Visuals", "eye")

local Left = Tab:AddGroupbox({ Side = "Left", Name = "Players", Description = "optional" })
local Right = Tab:AddRightGroupbox("World")
```

Sides accept `"Left"`, `"Right"`, `1`, `2`.

---

## Elements

All elements accept `Callback` and return an object with `OnChanged`, `SetValue`,
`SetText`, `SetVisible`, `SetDisabled`, `Destroy`.

### Toggle

```lua
local t = Group:AddToggle("Id", {
    Text = "Enable",
    Default = false,
    Callback = function(on) end,
})
t:SetValue(true)
print(t.value)
t:OnChanged(function(on) end)
```

Feature switch pattern (what to do with the on/off state):

```lua
local Enabled = Group:AddToggle("Enabled", { Text = "Enable Feature", Default = false })
Enabled:AddKeyPicker("EnabledKey", { Default = "F", Mode = "Toggle" })

task.spawn(function()
    while true do
        if Library.Options.Enabled.value then
            -- feature work while switched on
        end
        task.wait(0.1)
    end
end)
```

Change a switch from anywhere with `Library.Options.Enabled:SetValue(true)`.
The keybind, the toggle, and the read above all share the same `.value`.

### Slider

```lua
Group:AddSlider("Speed", {
    Text = "Walk Speed",
    Default = 16,
    Min = 1,
    Max = 250,
    Rounding = 1,          -- 1 = integers, 0.05 = two decimals
    Prefix = "",
    Suffix = "",
    Callback = function(v) end,
})
```

### Button

```lua
Group:AddButton({ Text = "Run", Func = function() end })
```

### Label / Divider

```lua
Group:AddLabel({ Text = "hello", DoesWrap = true, Size = 14 })
Group:AddDivider("Section")
```

### Dropdown

```lua
Group:AddDropdown("Mode", {
    Text = "Mode",
    Values = { "A", "B", "C" },   -- or a dictionary { id = "Label" }
    Default = "A",                 -- key for dictionaries
    Multi = false,
    MaxVisible = 8,                -- scrollbar with more rows than this
    Callback = function(v) end,
})
```

Dropdowns with more than `MaxVisible` rows get a draggable scrollbar.

### Keybind

```lua
local kb = Group:AddKeyPicker("Key", {
    Text = "Feature Key",
    Default = "F",
    Mode = "Toggle",               -- "Toggle" | "Hold" | "Always"
    Callback = function(kb) end,
})
```

- Click the key box -> it shows `[...]` -> press a key to bind it.
- Right-click the key box -> choose `Hold`, `Toggle`, or `Always`.
- When attached to a toggle (`Toggle:AddKeyPicker`), pressing the key syncs that toggle.
- If that toggle has its own `Callback`, only the toggle's notification is shown
  (prevents double notifications).

Pass `CaptureOnly = true` to make a rebind box that never evaluates as a feature key
(used for the Menu Key).

```lua
Group:AddKeyPicker("MenuKey", {
    Text = "Menu Key",
    Default = "RightShift",
    CaptureOnly = true,
    ChangedCallback = function(el) Library:SetMenuKey(el.vk) end,
})
```

### Colour picker

```lua
local cp = Group:AddColorPicker("Color", {
    Text = "Colour",
    Default = Color3.fromRGB(124, 92, 255),
    Transparency = 0,
    Callback = function(color, alpha) end,
})
```

Features:
- SV gradient image (all hues, including blue/purple), hue bar, alpha bar.
- Draggable cursor.
- Click the hex field, type 6 hex digits, press Enter to apply (Esc cancels).

Can also be attached inline: `Toggle:AddColorPicker` / `Label:AddColorPicker`.

---

## Notifications

```lua
Library:Notify("message", duration?, title?)
Library:PreviewNotification("message", title?)  -- ignores Enabled
Library:ClearNotifications()
```

Options live in `Library.NotificationOptions` and in the Notifications tab
(`Library:BuildNotificationSettings(Tab)`):

| Option | Default |
|---|---|
| `Enabled` | `true` |
| `Duration` | `4` |
| `Fade` | `0.35` |
| `Width` | `260` |
| `MaxVisible` | `6` |
| `OffsetY` | `16` |
| `UseCallDuration` | `false` |

`Library.NotifySide = "Right" / "Left"`.

By default the global `Duration` controls every notification. Set
`UseCallDuration = true` to let `Notify(msg, duration)` override it.

---

## SaveManager

```lua
loadstring(httpget(BASE .. "SwangySaveManager.lua"))()
local SaveManager = _G.SwangySaveManager
SaveManager:SetLibrary(Library)
SaveManager:BuildConfigSection(Tab)
```

Methods:

```lua
SaveManager:SetFolder("Swangy")
SaveManager:SetSubFolder("Configs")
SaveManager:BuildFolderTree()
SaveManager:RefreshConfigList()

SaveManager:Save("name")
SaveManager:Load("name")
SaveManager:Rename("old", "new")
SaveManager:Delete("name")

SaveManager:SaveAutoloadConfig("name")
SaveManager:GetAutoloadConfig()
SaveManager:LoadAutoloadConfig()
SaveManager:DeleteAutoLoadConfig()
```

The config section gives you a dropdown, a name field, `Save / Overwrite`, `Rename`,
`Load`, `Delete`, `Set Autoload`, `Clear Autoload`, `Refresh`, and an
`Autoload: <name>` status line. Configs are stored as JSON in
`C:/matcha/workspace/Swangy/Configs/`.

---

## ThemeManager

```lua
loadstring(httpget(BASE .. "SwangyThemeManager.lua"))()
local ThemeManager = _G.SwangyThemeManager
ThemeManager:SetLibrary(Library)
ThemeManager:BuildConfigSection(Tab)
```

Methods:

```lua
ThemeManager:ApplyTheme("Dracula")
ThemeManager:ApplyThemeData({ BackgroundColor = "0f0f0f", MainColor = "191919",
    AccentColor = "7d55ff", OutlineColor = "282828", FontColor = "ffffff" })
ThemeManager:GetThemes()
ThemeManager:SaveCustomTheme("name")
ThemeManager:GetCustomTheme("name")
ThemeManager:ReloadCustomThemes()
ThemeManager:Delete("name")
ThemeManager:SaveDefault("name")
ThemeManager:LoadDefault()
```

Built-ins: Default, BBot, Fatality, Jester, Mint, Tokyo Night, Ubuntu, Quartz, Nord,
Dracula, Monokai, Gruvbox, Solarized, Catppuccin, One Dark, Cyberpunk, Oceanic Next,
Material.

Selecting a theme in the dropdown applies immediately. Custom themes are stored in
`C:/matcha/workspace/Swangy/CustomThemes/`.

---

## Branding helpers

```lua
Library:SetAccent(Color3)
Library:SetTheme({ accent = Color3 })
Library:SetWatermark(true/false)
Library:SetMenuKey("RightShift")
Library:GetWindow()
```

The logo in the titlebar is generated from an SVG path as a black -> accent diagonal
gradient and rebuilds automatically when the accent/theme changes. The window footer
is intentionally not drawn.

The top-left watermark (title + fps) is draggable. Its position is kept in
`Library.__wmPos`, is clamped to the viewport, and is reset when the library reloads.
Loading Swangy tears down any previous instance and its watermark, so boxes cannot
stack up from repeated reloads.

---

## Matcha notes

- No `Instance.new`; all visuals are `Drawing` objects.
- `Drawing.Transparency` behaves as opacity (`1` = solid).
- `Color3:ToHSV` does not exist; Swangy ships its own RGB->HSV conversion.
- `Players` / `LocalPlayer:GetMouse()` can transiently return nil while Matcha's index
  is cold. Swangy retries and caches them so clicks recover without a reload.
- Input is kept enabled while the menu is open so you can still move.
- Load with `httpget` + `loadstring`; `readfile` is not required.
- Loading the demo unloads any previous Swangy instance first.

---

## Minimal example

```lua
local BASE = "https://raw.githubusercontent.com/YoungSlaves/matchaUI/main/"

local _ = loadstring(httpget(BASE .. "Library.lua"))()
local Library = _G.Swangy

local Window = Library:CreateWindow({ Title = "Swangy", ToggleKeybind = "RightShift" })
local Tab = Window:AddTab("Main", "user")
local Group = Tab:AddGroupbox({ Side = "Left", Name = "Main" })

local Enabled = Group:AddToggle("Enabled", { Text = "Enabled", Default = false })
Enabled:AddKeyPicker("EnabledKey", { Default = "F", Mode = "Toggle" })

Group:AddSlider("Speed", {
    Text = "Speed",
    Default = 16, Min = 1, Max = 100, Rounding = 1,
    Callback = function(v)
        local hum
        local char = workspace.CurrentCamera and workspace.CurrentCamera.CameraSubject
        if char and char.Parent then hum = char.Parent:FindFirstChildOfClass("Humanoid") end
        if hum and Library.Options.Enabled.value then hum.WalkSpeed = v end
    end,
})

Group:AddButton({ Text = "Test", Func = function()
    Library:Notify("It works.", nil, "Swangy")
end })
```
