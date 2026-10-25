# Swangy UI - LLM Integration Guide

This file is written for an AI/LLM that has to write scripts using Swangy UI inside the
**Matcha** executor. Read all of it before generating code. It contains the exact API,
the Matcha environment rules, and the mistakes to avoid.

---

## 0. TL;DR rules

1. Load the library, then read it from `_G.Swangy`. `loadstring` drops top-level returns.
2. Never use `Instance.new` - Matcha has no `Instance` global at all.
3. All UI comes from Swangy (`Library:CreateWindow` ...). Never build `ScreenGui`/`Frame`.
4. Use `Library.Options.<id>` to read widget state.
5. Wrap long-running work in `task.spawn` with `task.wait`; the top level is killed at 5s.
6. Don't create `Drawing` objects inside a loop. Pool them.
7. `Color3:ToHSV` does not exist in Matcha. `Drawing.Transparency` is opacity (1 = solid).

---

## 1. Matcha environment

Matcha is an external Lua VM for Roblox. It is NOT a normal executor. It reads the game
from outside, so many standard APIs are missing or behave differently.

### 1.1 Globals that exist (approx. 120)

UI / interaction:
`Drawing`, `UI` (native Matcha menu: `AddTab`, `RemoveTab`, `GetValue`, `SetValue`),
`WorldToScreen`, `RegisterModel`, `RunService`, `UserInputService`, `workspace`, `game`,
`Enum`, `Vector2`, `Vector3`, `CFrame`, `Color3`, `UDim`, `UDim2`, `Ray`, `RaycastParams`,
`NumberRange`.

Input:
`iskeypressed(vk)`, `keypress(vk)`, `keyrelease(vk)`,
`ismouse1pressed()`, `ismouse2pressed()`, `mouse1press/mouse1release/mouse1click`,
`mouse2press/mouse2release/mouse2click`, `mousemoveabs(x, y)`, `mousemoverel(x, y)`,
`mousescroll(n)`, `isrbxactive()`, `setrobloxinput(state)`.

Screen / misc:
`notify(msg, title, secs)`, `tick()`, `identifyexecutor()`, `getgamename()`,
`getrbxversion()`, `gethwid()`, `GetPingValue()`, `setclipboard(text)`,
`base64encode/base64decode`, `getfflag/setfflag`, `getbase()`.

Scripts / files / net:
`getscripts()`, `decompile(inst)`, `getscriptbytecode(inst)`, `getscripthash(inst)`,
`readfile/writefile/appendfile/listfiles/isfile/isfolder/makefolder/delfile/delfolder`
(sandboxed to `C:/matcha/workspace`), `httpget(url, headers)`,
`httppost(url, body, contentType, headers)`.

GC / memory (advanced):
`getgc`, `findgc`, `setgc`, `applygc`, `getgctbl`, `readtbl`, `refreshgc`,
`memory_read(type, addr)`, `memory_write(type, addr, value)` (needs "Allow Unsafe LuaU").

Scheduler / lua:
`task.spawn/defer/delay/wait`, `spawn`, `wait`, `loadstring`, `load`, `pcall`, `xpcall`,
`setmetatable`, `getmetatable`, `if` standard library (`os`, `math`, `string`, `table`,
`utf8`, `bit32`, `buffer`, `coroutine`, `debug`).

You can always dump the real list at runtime with:

```lua
for k, v in pairs(getfenv(1)) do print(k, typeof(v)) end
```

### 1.2 What does NOT exist / is broken

- `Instance` global does not exist. No `Instance.new`, `Clone`, `Destroy`,
  `ClearAllChildren`, `GetPropertyChangedSignal`, `ChildAdded`, `ChildRemoved`,
  `AncestryChanged`.
- No instance signals: `Touched`, `Died`, `HumanoidStateChanged`, `CharacterAdded`,
  `CharacterRemoving`, and any `:Connect` on a property. Only these signals exist:
  `RunService.Stepped/.Heartbeat/.RenderStepped`, `UserInputService.InputBegan/.InputEnded`.
- `Players.PlayerAdded` and `Players.PlayerRemoving` return `nil`. Poll
  `Players:GetPlayers()` and diff the list instead.
- `IsA(class)` is broken (always returns true). Compare `instance.ClassName == "Part"`.
- `Paint`-style methods on instances: only these are bound -
  `FindFirstChild`, `FindFirstChildOfClass`, `FindFirstChildWhichIsA`, `WaitForChild`,
  `GetChildren`, `GetDescendants`, `GetFullName`, `IsDescendantOf`, `GetService`,
  `GetAttribute`, `GetAttributes`, `SetAttribute`, `GetPlayers`, `Raycast`, `FireServer`,
  `InvokeServer`, `GetMouse` (LocalPlayer), `IsLoaded`, `JSONEncode`, `JSONDecode`,
  `GenerateGUID`, `Camera.lookAt`.
- `workspace.CurrentCamera:WorldToViewportPoint` does not exist. Use `WorldToScreen`.
- `game:HttpGet` / `game:HttpPost` do not exist. Use `httpget` / `httppost`.
- Reading a property that is not supported returns `nil` (it does not error).
  Writing an unsupported property throws `Unknown property`.
- `Color3` reads are uppercase only: `.R .G .B` (lowercase returns nil).
- `Color3:ToHSV()` does not exist. Convert RGB -> HSV manually if needed.
- `Drawing.Text` uses `.Size` (a number = font size). There is no `.FontSize`.
- `Drawing` colors are write-only (reading `.Color` returns nil).
- `UserInputService` is a plain table with only `IsKeyDown`, `InputBegan`, `InputEnded`.
  `InputBegan` gives a table with a single integer `.KeyCode`, which is a **Roblox**
  KeyCode (letters are 97..122, e.g. `G` = 103), not a Windows VK code.

### 1.3 Readable instance properties (matcha API)

Any: `Name`, `ClassName`, `Parent`, `Address`.
BasePart: `Position`, `Size`, `CFrame`, `Velocity`, `AssemblyLinearVelocity`,
`Transparency`, `Color`, `CanCollide`.
Humanoid: `Health`, `MaxHealth`, `WalkToPoint`, `WalkToPart`.
Player: `Character`, `Team`, `UserId`. Players: `LocalPlayer`.
Camera: `CFrame`, `Position`, `FieldOfView`, `ViewportSize`, `CameraSubject`.
Model: `PrimaryPart`. DataModel: `PlaceId`, `GameId`, `JobId`.
GuiObject: `AbsolutePosition`, `AbsoluteSize`. TextLabel: `Text`.
MeshPart: `MeshId`, `TextureID`. ValueObjects: `Value`.

### 1.4 Writable instance properties

`Name`, `Parent`, `Position`, `Size`, `CFrame`, `Velocity`, `AssemblyLinearVelocity`,
`CanCollide`, `FieldOfView`, `AbsolutePosition`, `AbsoluteSize`, `Value`,
`WalkToPoint`, `WalkToPart`. Anything else throws.

### 1.5 Execution rules

- `matcha_exec`-style runs return only what `print()` produced.
- `wait()` / `task.wait()` only work inside `task.spawn` / `spawn` (top level throws).
- Scripts are killed after ~5s unless they yield.
- A script that spawns a background loop returns immediately.
- `FireServer` / `InvokeServer` only work when Hybrid Mode is enabled.
- `defer` / `delay` are effectively no-ops in some builds - use `task.spawn` +
  `task.wait`.
- `WorldToScreen` only works inside a render callback (Heartbeat/RenderStepped).
  Anywhere else it returns `(0,0), false`.

### 1.6 Matcha performance rules

- Writing `Position`, `CFrame`, `Velocity`, `AssemblyLinearVelocity` is very expensive
  (thousands of internal writes). Never do it per-frame; do it on a keypress/state
  change or a few times a second.
- `GetDescendants` is expensive - use it in setup only, or on a multi-second timer.
- `getgc` / `findgc` is a full heap scan - call once, reuse the result with `applygc` /
  `refreshgc`.
- Never create `Drawing` objects inside a loop. Create them once and reuse; call
  `:Remove()` when finished.
- Every loop must yield (`task.wait`).

### 1.7 Mouse / Players caveat

`game:GetService("Players")` and `Players.LocalPlayer:GetMouse()` can return nil for a
while if Matcha's index is cold. Swangy works around this by retrying and caching the
`Players` service, the `LocalPlayer`, and the `Mouse` object in `_G`. Your own scripts
should also guard against nil here.

### 1.8 Screen overlay - Drawing

```lua
local d = Drawing.new("Square")   -- Line, Text, Image, Circle, Square, Triangle, Quad
```

- Shared: `Visible`, `Color` (Color3, write-only), `Transparency`, `Thickness`,
  `ZIndex`, `Outline`, `Filled`, `Rounding`, `Corner`, `Remove()`.
- `Line`: `From`, `To`. `Square`: `Position`, `Size`. `Circle`: `Position`, `Radius`,
  `NumSides`. `Triangle`: `PointA..C`. `Quad`: `PointA..D`.
- `Text`: `Text`, `Position`, `Size` (number), `Center`, `Font`, `TextBounds`.
- `Image`: `Position`, `Size`, `Data` (raw bytes of an image file such as BMP/PNG,
  NOT a URL), `IsLoaded`, `ImageSize`.
- Fonts (`Drawing.Fonts`): `UI`=0, `System`=1, `SystemBold`=2, `Minecraft`=4,
  `Monospace`=5, `Pixel`=7, `Fortnite`=8, `ProximaSoftBold`=11.
- **`Transparency` is opacity in this build** (`1` = fully visible, `0` = invisible).
  This contradicts some written docs. Passing `1` gives a solid object.

---

## 2. Swangy UI - full API

### 2.1 Loading and globals

```lua
local BASE = "https://raw.githubusercontent.com/YoungSlaves/matchaUI/main/"
local _ = loadstring(httpget(BASE .. "Swangy.lua"))()   -- return is dropped
local Library = _G.Swangy                                -- use this
```

Loading is done with Matcha's global `httpget` + `loadstring`. No files are written to
disk and `readfile` is not required. Never use `game:HttpGet` (does not exist here).

Addons:

```lua
loadstring(httpget(BASE .. "SwangySaveManager.lua"))()
loadstring(httpget(BASE .. "SwangyThemeManager.lua"))()
```

Demo (it fetches the library and addons itself):

```lua
loadstring(httpget(BASE .. "SwangyDemo.lua"))()
```

Globals: `_G.Swangy`, `_G.SwangySaveManager`, `_G.SwangyThemeManager`.
Legacy aliases exist: `_G.Obsidian`, `_G.ObsidianSaveManager`, `_G.ObsidianThemeManager`.

Stop:

```lua
_G.Swangy:Unload()
```

### 2.2 Window

```lua
local Window = Library:CreateWindow({
    Title = "My Script",     -- top bar title
    Width = 720,             -- default 720
    Height = 600,            -- default 600
    Center = true,           -- center on screen
    ToggleKeybind = "RightShift",
    NotifySide = "Right",    -- "Right" | "Left"
    Accent = Color3.fromRGB(125, 85, 255),
    CornerRadius = 4,
})
```

Methods: `AddTab(name, icon?, desc?)`, `SelectTab(indexOrTab)`, `Toggle(bool?)`,
`Open()`, `Close()`, `SetTitle(str)`, `SetPos(x, y)`, `SetSize(w, h)`, `Center()`.

`Library:GetWindow()` returns the first window. `Library:SetMenuKey("RightShift")`
or `Library:SetMenuKey(0x3D)` changes the open/close key.

### 2.3 Tab

```lua
local Tab = Window:AddTab("Main", "user", "description")
```

Methods: `AddGroupbox(opts)`, `AddLeftGroupbox(name)`, `AddRightGroupbox(name)`,
`SetVisible(bool)`, `SetName(str)`, `Hide()`.

Groupbox:

```lua
local g = Tab:AddGroupbox({ Side = "Left", Name = "Group", Description = "optional" })
```

`Side` accepts `"Left"`, `"Right"`, `1`, `2`. Returned groupbox also has
`Show()` / `Hide()` / `SetVisible()`.

### 2.4 Elements

Every element takes an id string as the first argument and a config table second,
returns an element with `OnChanged`, `SetValue`, `SetText`, `SetVisible`, `SetDisabled`,
`Destroy`. State lives in `Library.Options[id]` (and in `Library.Toggles`,
`Sliders`, `Buttons`, `Dropdowns`, `ColorPickers`, `KeyPickers`).

Toggle:

```lua
local t = g:AddToggle("id", { Text = "Enable", Default = false,
    Callback = function(on) end })
t:SetValue(true)
if t.value then end
```

Slider:

```lua
g:AddSlider("id", { Text = "Speed", Default = 16, Min = 1, Max = 250,
    Rounding = 1, Prefix = "", Suffix = "", Callback = function(v) end })
```

`Rounding` >= 1 rounds to integers; a fraction (<1) rounds to that step and shows two
decimals.

Button:

```lua
g:AddButton({ Text = "Run", Func = function() end })
-- or g:AddButton("Id", { Text = "Run", Func = function() end })
```

Label / Divider:

```lua
g:AddLabel({ Text = "text", DoesWrap = true, Size = 14, Color = Color3.new(1,1,1) })
g:AddDivider("Section")   -- or g:AddDivider({ Text = "Section" })
```

Dropdown:

```lua
local dd = g:AddDropdown("id", {
    Text = "Mode",
    Values = { "A", "B", "C" },          -- or { key = "Label" }
    Default = "A",                        -- key for dictionaries, value for arrays
    Multi = false,
    MaxVisible = 8,                       -- adds a draggable scrollbar above this
    Placeholder = "...",
    Callback = function(v) end,
})
dd:SetValue("B")
dd:SetValues({ "X", "Y" })
dd:AddValues("Z")
print(dd.value)   -- selected key (or a map when Multi = true)
```

For `Multi = true`, `dd.value` is a map `{ [key] = true }`.

Input (text field):

```lua
local i = g:AddInput("id", { Text = "Name", Default = "", Placeholder = "type..." })
i.value   -- current string
```

Text input only accepts letters, digits, space, `- _ . /`. Enter commits, Esc cancels.

Keybind:

```lua
local kb = g:AddKeyPicker("id", {
    Text = "Feature Key",
    Default = "F",
    Mode = "Toggle",              -- "Toggle" | "Hold" | "Always"
    SyncToggleState = true,       -- when attached to a Toggle
    Callback = function(kb) end,
    ChangedCallback = function(kb) end,
})
kb:GetState()      -- true/false
kb:SetValue({ "G", "Hold" })
```

- Attach to a toggle: `Toggle:AddKeyPicker("id", cfg)`.
- Click the key box -> shows `[...]` -> next key becomes the bind.
- Right-click the key box -> Hold / Toggle / Always.
- If the toggle has its own `Callback`, the keybind's own notification is suppressed
  (only the toggle's notification shows).
- `CaptureOnly = true` makes a pure rebind box (not polled as a feature key), used by
  the Menu Key widget.

Colour picker:

```lua
local cp = g:AddColorPicker("id", {
    Text = "Colour",
    Default = Color3.fromRGB(124, 92, 255),
    Transparency = 0,             -- 0..1
    Callback = function(color, alpha) end,
})
cp:SetValueRGB(color, transparency)   -- transparency = 1 - alpha
cp:SetValue({ H = 0.7, S = 1, V = 1 }, transparency)
```

- SV gradient image, hue bar, alpha bar, draggable cursor.
- Click the hex field, type 6 hex digits, Enter to apply, Esc to cancel.
- Inline: `Toggle:AddColorPicker` / `Label:AddColorPicker`.

### 2.5 Notifications

```lua
Library:Notify("message", duration?, title?)
Library:PreviewNotification("message", title?)  -- shows even when disabled
Library:ClearNotifications()
```

Options (`Library.NotificationOptions`), also editable from the Notifications tab via
`Library:BuildNotificationSettings(Tab)`:

| Field | Default |
|---|---|
| `Enabled` | `true` |
| `Duration` | `4` |
| `Fade` | `0.35` |
| `Width` | `260` |
| `MaxVisible` | `6` |
| `OffsetY` | `16` |
| `Spacing` | `6` |
| `UseCallDuration` | `false` |

`Library.NotifySide = "Right" / "Left"`. With `UseCallDuration = false` the global
`Duration` overrides per-call durations.

### 2.6 SaveManager

```lua
loadstring(httpget(BASE .. "SwangySaveManager.lua"))()
local SaveManager = _G.SwangySaveManager
SaveManager:SetLibrary(Library)
SaveManager:BuildConfigSection(Tab)   -- builds the whole config groupbox
```

Core methods: `SetFolder`, `SetSubFolder`, `BuildFolderTree`, `RefreshConfigList`,
`Save(name)`, `Load(name)`, `Rename(old, new)`, `Delete(name)`, `SaveAutoloadConfig`,
`GetAutoloadConfig`, `LoadAutoloadConfig`, `DeleteAutoLoadConfig`.

Storage: `C:/matcha/workspace/Swangy/Configs/*.json` (folder is configurable).

`BuildConfigSection` gives: config dropdown, name field, `Save / Overwrite`, `Rename`,
`Load`, `Delete`, `Set Autoload`, `Clear Autoload`, `Refresh`, and an
`Autoload: <name>` line. It also loads the autoload config on build.

### 2.7 ThemeManager

```lua
loadstring(httpget(BASE .. "SwangyThemeManager.lua"))()
local ThemeManager = _G.SwangyThemeManager
ThemeManager:SetLibrary(Library)
ThemeManager:BuildConfigSection(Tab)
```

Methods: `ApplyTheme(name)`, `ApplyThemeData({ BackgroundColor, MainColor,
AccentColor, OutlineColor, FontColor })` (hex strings or Color3),
`GetThemes()`, `SaveCustomTheme(name)`, `GetCustomTheme(name)`,
`ReloadCustomThemes()`, `Delete(name)`, `SaveDefault(name)`, `LoadDefault()`,
`ApplyToGroupbox(group)`.

Built-ins: Default, BBot, Fatality, Jester, Mint, Tokyo Night, Ubuntu, Quartz, Nord,
Dracula, Monokai, Gruvbox, Solarized, Catppuccin, One Dark, Cyberpunk, Oceanic Next,
Material. Storage: `C:/matcha/workspace/Swangy/CustomThemes/*.json`.

Selecting a theme in the dropdown applies immediately. Themes change the live
`Library.Theme` table, so all elements update on the next frame.

### 2.8 Branding

```lua
Library:SetAccent(Color3)
Library:SetTheme({ accent = Color3.fromRGB(...) })
Library:SetWatermark(true/false)
Library:SetMenuKey("RightShift")
```

- The titlebar logo is generated from an SVG path as a black -> accent diagonal
  gradient and rebuilds when accent/background changes.
- The top-left watermark box (window title + fps) is draggable; position is kept in
  `Library.__wmPos`.
- The window footer is intentionally not drawn.

---

## 3. Correct patterns for LLM-generated scripts

### 3.1 Standard skeleton

```lua
-- load
local BASE = "https://raw.githubusercontent.com/YoungSlaves/matchaUI/main/"
local _ = loadstring(httpget(BASE .. "Swangy.lua"))()
local Library = _G.Swangy

-- window + tab
local Window = Library:CreateWindow({ Title = "Script", ToggleKeybind = "RightShift" })
local Tab = Window:AddTab("Main", "user")

-- groupboxes
local Main = Tab:AddGroupbox({ Side = "Left", Name = "Main" })
local Misc = Tab:AddGroupbox({ Side = "Right", Name = "Misc" })

-- elements
local Enabled = Main:AddToggle("Enabled", {
    Text = "Enable",
    Default = false,
    Callback = function(on) end,
})
Enabled:AddKeyPicker("EnabledKey", { Default = "F", Mode = "Toggle" })

Main:AddSlider("Value", {
    Text = "Value",
    Default = 16, Min = 1, Max = 100, Rounding = 1,
    Callback = function(v) end,
})

-- background feature loop (yields!)
local running = true
task.spawn(function()
    while running do
        if Library.Options.Enabled.value then
            -- feature work
        end
        task.wait(0.1)
    end
end)
```

### 3.2 UI switches (toggles)

A switch is an `AddToggle`. Its state is `Library.Options.<id>.value`.

```lua
local Enabled = Group:AddToggle("Enabled", {
    Text = "Enable Feature",
    Default = false,
    Callback = function(on)
        Library:Notify("Feature " .. (on and "enabled" or "disabled"), nil, "Script")
    end,
})

-- optional keybind that flips the same switch
Enabled:AddKeyPicker("EnabledKey", { Default = "F", Mode = "Toggle" })

-- reading the switch (poll, never cache across characters)
task.spawn(function()
    while true do
        if Library.Options.Enabled.value then
            -- feature work
        end
        task.wait(0.1)
    end
end)

-- changing it from code
Library.Options.Enabled:SetValue(true)
```

- `Callback` runs immediately with the default value at creation, then on every change.
- Use `:OnChanged(fn)` to add another listener.
- The keybind and the toggle share the same value, so there is only one source of truth.
- If the toggle has a `Callback`, the keybind suppresses its own duplicate notification.

Switching tabs from code:

```lua
Window:SelectTab(1)              -- by index
Window:SelectTab(Window.tabs[2]) -- by Tab object
```

### 3.3 Reading local character without Players.LocalPlayer

`Players.LocalPlayer` may be nil; the camera subject survives longer:

```lua
local function getHumanoid()
    local cam = workspace.CurrentCamera
    local subj = cam and cam.CameraSubject
    local char = subj and subj.Parent
    return char and char:FindFirstChildOfClass("Humanoid") or nil
end
```

### 3.4 ESP (read-only, pooled)

Use the two-loop pattern: a slow collector and a `RenderStepped` renderer that only
reads cached instances. Never create `Drawing` objects per frame. Remember
`WorldToScreen` only works inside the render callback and returns a visibility bool.

Prefer `RegisterModel{...}` (Matcha's native C++ ESP) for Model targets - it gets
boxes/names/health for free and is far cheaper.

### 3.5 Notifications for state changes

```lua
Library:Notify("Feature " .. (on and "enabled" or "disabled"), nil, "Script")
```

---

## 4. Do / Don't

Do:
- Use `_G.Swangy` after loading with `loadstring`.
- Keep widget ids unique and stable (they are the config keys).
- Use `Library.Options.id.value` / `.mode` / `.state` to read state.
- Put feature loops in `task.spawn` with `task.wait`.
- Use `FindFirstChildOfClass("Humanoid")` and nil-check characters every iteration.
- Clip/limit anything drawn on screen; Drawing has no clipping.

Don't:
- `Instance.new`, `Clone`, `Destroy`, `ScreenGui`, `Frame`, `TextLabel`.
- `game:HttpGet` / `game:HttpPost` (use `httpget` / `httppost`).
- `WorldToViewportPoint` (use `WorldToScreen`, render callback only).
- `Instance:IsA(...)` (compare `.ClassName`).
- `Players.PlayerAdded` / `CharacterAdded` (poll instead; they return nil).
- `Color3:ToHSV` (does not exist).
- `Drawing.new(...)` inside a loop (leaks until the VM restarts).
- Setting `Position` / `CFrame` / `Velocity` every frame.
- Assume `Drawing.Transparency` is standard; here `1` is fully solid.
- Assume `readfile` can access arbitrary paths; only `C:/matcha/workspace`.
- Rely on top-level `return` from `loadstring`.

---

## 5. Files and storage

No files need to be installed. Everything is fetched at runtime from:

```
https://raw.githubusercontent.com/YoungSlaves/matchaUI/main/
```

Swangy still uses Matcha's file API for saved data only:

```
C:/matcha/workspace/Swangy/Configs/*.json
C:/matcha/workspace/Swangy/CustomThemes/*.json
```

Only `.txt .lua .luau .json .cfg .dat .ini` file extensions are allowed by Matcha's file
API. Creating those config/theme files is done by Swangy, not by the loader.