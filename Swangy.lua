-- Swangy: a Drawing UI library for Matcha (Obsidian-compatible look and API).
-- Matcha has no Instance.new/ScreenGui, so this renders with Drawing + polling input.
-- Scheme/metrics are taken from Obsidian's Library.lua defaults.
--
-- Load (top-level returns are dropped in Matcha):
--   local _ = loadstring(readfile("Swangy.lua"))()
--   local Library = _G.Swangy

local Library = {
    Version = "1.1",
    Options = {},
    Toggles = {},
    Sliders = {},
    Buttons = {},
    Dropdowns = {},
    ColorPickers = {},
    KeyPickers = {},
    Labels = {},
    ForceCheckbox = false,
    NotifySide = "Right",
    NotificationOptions = {
        Enabled = true,
        Duration = 4,
        Fade = 0.35,
        Width = 260,
        MaxVisible = 6,
        OffsetY = 16,
        Spacing = 6,
        UseCallDuration = false,
    },
}
_G.Swangy = Library
_G.Obsidian = Library

local function hostGet(name)
    local v
    pcall(function() v = getfenv(1)[name] end)
    if v == nil then pcall(function() v = _G[name] end) end
    return v
end

local D = hostGet("Drawing") or Drawing
local RS = hostGet("RunService") or RunService
local UIS = hostGet("UserInputService") or UserInputService
local floor, abs, min, max, clamp = math.floor, math.abs, math.min, math.max, math.clamp
local clock, fmt = os.clock, string.format
local rgb = Color3.fromRGB

-- Obsidian scheme -----------------------------------------------------------
local Theme = {
    bg = rgb(15, 15, 15),
    main = rgb(25, 25, 25),
    accent = rgb(125, 85, 255),
    outline = rgb(40, 40, 40),
    text = rgb(255, 255, 255),
    subtext = rgb(130, 130, 130),
    dim = rgb(160, 160, 160),
    danger = rgb(255, 50, 50),
    destructive = rgb(220, 38, 38),
    white = rgb(255, 255, 255),
    dark = rgb(0, 0, 0),
    disabled = rgb(95, 95, 95),
}
Theme.panel, Theme.panel2, Theme.stroke, Theme.strokeLit = Theme.bg, Theme.main, Theme.outline, rgb(58, 58, 58)
Theme.track, Theme.sidebar = Theme.main, Theme.bg
Library.Theme = Theme
Library.CornerRadius = 4

local FONT = (D.Fonts and (D.Fonts.Monospace or D.Fonts.SystemBold)) or 5

local function rgbToHsv(c)
    local r, g, b = c.R, c.G, c.B
    local mx = max(r, g, b)
    local mn = min(r, g, b)
    local d = mx - mn
    local h
    if d == 0 then
        h = 0
    elseif mx == r then
        h = ((g - b) / d) % 6
    elseif mx == g then
        h = (b - r) / d + 2
    else
        h = (r - g) / d + 4
    end
    h = h / 6
    local s = (mx == 0) and 0 or (d / mx)
    return h, s, mx
end

local function u16(n)
    return string.char(n % 256, floor(n / 256) % 256)
end
local function u32(n)
    return string.char(n % 256, floor(n / 256) % 256, floor(n / 65536) % 256, floor(n / 16777216) % 256)
end
local GRID_W, GRID_H = 64, 48
local function buildSVBmp(hue)
    local rows = {}
    for y = GRID_H - 1, 0, -1 do
        local v = 1 - y / (GRID_H - 1)
        local row = {}
        for x = 0, GRID_W - 1 do
            local s = x / (GRID_W - 1)
            local c = Color3.fromHSV(hue, s, v)
            row[#row + 1] = string.char(floor(c.B * 255 + 0.5), floor(c.G * 255 + 0.5), floor(c.R * 255 + 0.5))
        end
        local pad = (4 - (GRID_W * 3) % 4) % 4
        rows[#rows + 1] = table.concat(row) .. string.rep("\0", pad)
    end
    local pixels = table.concat(rows)
    local dib = u32(40) .. u32(GRID_W) .. u32(GRID_H) .. u16(1) .. u16(24) .. u32(0)
        .. u32(#pixels) .. u32(2835) .. u32(2835) .. u32(0) .. u32(0)
    return "BM" .. u32(14 + 40 + #pixels) .. u32(0) .. u32(54) .. dib .. pixels
end

local LOGO_D =
    "M161.0 225.0 L129.5 191.0 L0.0 336.2 L62.2 336.0Z " ..
    "M51.0 139.5 L20.5 174.2 L67.8 226.8 L98.5 192.2Z " ..
    "M284.5 121.0 L253.5 155.5 L301.0 208.2 L331.8 173.5Z " ..
    "M0.0 11.2 L67.2 86.8 L98.5 52.8 L61.5 11.0Z " ..
    "M352.0 11.0 L290.8 11.0 L176.0 138.8 L145.0 103.8 L175.8 69.5 L192.5 87.2 " ..
    "L223.2 52.5 L175.8 0.0 L82.8 103.5 L207.2 243.2 L176.8 278.0 L159.8 260.5 " ..
    "L129.0 294.8 L175.8 347.8 L269.2 244.0 L207.5 173.2Z"

local LOGO_SUBS, LOGO_MINX, LOGO_MINY, LOGO_MAXX, LOGO_MAXY = {}, math.huge, math.huge, -math.huge, -math.huge
do
    local function numbers(s)
        local t = {}
        for n in s:gmatch("[-+]?%d*%.?%d+") do t[#t + 1] = tonumber(n) end
        return t
    end
    for cmd, body in LOGO_D:gmatch("([MLZ])([^MLZ]*)") do
        if cmd == "M" then
            local poly, ns = {}, numbers(body)
            for i = 1, #ns - 1, 2 do
                poly[#poly + 1] = { ns[i], ns[i + 1] }
            end
            LOGO_SUBS[#LOGO_SUBS + 1] = poly
        elseif cmd == "L" then
            local poly, ns = LOGO_SUBS[#LOGO_SUBS], numbers(body)
            for i = 1, #ns - 1, 2 do
                poly[#poly + 1] = { ns[i], ns[i + 1] }
            end
        end
    end
    for _, poly in ipairs(LOGO_SUBS) do
        for _, p in ipairs(poly) do
            if p[1] < LOGO_MINX then LOGO_MINX = p[1] end
            if p[2] < LOGO_MINY then LOGO_MINY = p[2] end
            if p[1] > LOGO_MAXX then LOGO_MAXX = p[1] end
            if p[2] > LOGO_MAXY then LOGO_MAXY = p[2] end
        end
    end
end

local function logoInside(sx, sy)
    local c = false
    for _, poly in ipairs(LOGO_SUBS) do
        local n = #poly
        for i = 1, n do
            local a, b = poly[i], poly[i % n + 1]
            if ((a[2] > sy) ~= (b[2] > sy)) then
                local xint = (b[1] - a[1]) * (sy - a[2]) / (b[2] - a[2]) + a[1]
                if sx < xint then c = not c end
            end
        end
    end
    return c
end

local function buildLogoBmp(size, bg, accent)
    local spanx = LOGO_MAXX - LOGO_MINX
    local spany = LOGO_MAXY - LOGO_MINY
    local rows = {}
    for py = 0, size - 1 do
        local row = {}
        local sy = LOGO_MINY + (py + 0.5) / size * spany
        for px = 0, size - 1 do
            local sx = LOGO_MINX + (px + 0.5) / size * spanx
            local r, g, b
            if logoInside(sx, sy) then
                local t = ((px + 0.5) + (py + 0.5)) / (2 * size)
                r = accent.R * t
                g = accent.G * t
                b = accent.B * t
            else
                r, g, b = bg.R, bg.G, bg.B
            end
            row[#row + 1] = string.char(floor(b * 255 + 0.5), floor(g * 255 + 0.5), floor(r * 255 + 0.5))
        end
        rows[size - py] = table.concat(row)
    end
    local pixels = table.concat(rows)
    local pad = (4 - (size * 3) % 4) % 4
    local padded = {}
    for i = 1, #rows do padded[i] = rows[i] .. string.rep("\0", pad) end
    pixels = table.concat(padded)
    local dib = u32(40) .. u32(size) .. u32(size) .. u16(1) .. u16(24) .. u32(0)
        .. u32(#pixels) .. u32(2835) .. u32(2835) .. u32(0) .. u32(0)
    return "BM" .. u32(14 + 40 + #pixels) .. u32(0) .. u32(54) .. dib .. pixels
end

local LogoImage, LogoKey

local function mix(a, b, t)
    return rgb(
        floor(a.R * 255 + (b.R * 255 - a.R * 255) * t + 0.5),
        floor(a.G * 255 + (b.G * 255 - a.G * 255) * t + 0.5),
        floor(a.B * 255 + (b.B * 255 - a.B * 255) * t + 0.5)
    )
end

-- Drawing helpers -----------------------------------------------------------
local ALL = {}
Library.__all = ALL
local function newObj(kind, z)
    local d = D.new(kind)
    if kind == "Text" then
        pcall(function() d.Font = FONT end)
    end
    if z then pcall(function() d.ZIndex = z end) end
    pcall(function() d.Visible = false end)
    local o = { d = d, sc = { Visible = false } }
    ALL[#ALL + 1] = o
    return o
end

local function zset(o, z)
    local d = o and (o.d or o)
    if d then pcall(function() d.ZIndex = z end) end
end

local function ensureLogo()
    if LogoImage then return LogoImage end
    LogoImage = newObj("Image", 9)
    Library.__logo = LogoImage
    return LogoImage
end

local function put(o, k, v)
    if o.sc[k] ~= v then
        o.sc[k] = v
        o.d[k] = v
    end
end
local function putV(o, k, x, y)
    local c = o.sc[k]
    if not c or c[1] ~= x or c[2] ~= y then
        o.sc[k] = { x, y }
        o.d[k] = Vector2.new(x, y)
    end
end
local function putC(o, k, col)
    local c = o.sc[k]
    local r, g, b = col.R, col.G, col.B
    if not c or c[1] ~= r or c[2] ~= g or c[3] ~= b then
        o.sc[k] = { r, g, b }
        o.d[k] = col
    end
end

local function fill(o, x, y, w, h, color, alpha, radius)
    if w <= 0 or h <= 0 then
        put(o, "Visible", false)
        return
    end
    putV(o, "Position", x, y)
    putV(o, "Size", w, h)
    putC(o, "Color", color or Theme.main)
    put(o, "Transparency", alpha or 1)
    put(o, "Filled", true)
    put(o, "Corner", radius or 0)
    put(o, "Visible", true)
end
local function stroke(o, x, y, w, h, color, alpha, radius, thickness)
    if w <= 0 or h <= 0 then
        put(o, "Visible", false)
        return
    end
    putV(o, "Position", x, y)
    putV(o, "Size", w, h)
    putC(o, "Color", color or Theme.outline)
    put(o, "Transparency", alpha or 1)
    put(o, "Filled", false)
    put(o, "Thickness", thickness or 1)
    put(o, "Corner", radius or 0)
    put(o, "Visible", true)
end
local function text(o, x, y, str, size, color, alpha, center, outline)
    put(o, "Text", tostring(str))
    put(o, "Size", size or 14)
    putV(o, "Position", x, y)
    putC(o, "Color", color or Theme.text)
    put(o, "Transparency", alpha or 1)
    put(o, "Center", center == true)
    put(o, "Outline", outline == true)
    put(o, "Visible", true)
end
local function line(o, x1, y1, x2, y2, color, alpha, thickness)
    putV(o, "From", x1, y1)
    putV(o, "To", x2, y2)
    putC(o, "Color", color or Theme.outline)
    put(o, "Transparency", alpha or 1)
    put(o, "Thickness", thickness or 1)
    put(o, "Visible", true)
end

local MEAS = D.new("Text")
MEAS.Visible = false
pcall(function() MEAS.Font = FONT end)
local wcache, wcount = {}, 0
local function textW(str, size)
    str, size = tostring(str), size or 14
    local key = size .. "|" .. str
    local v = wcache[key]
    if v then return v end
    MEAS.Text = str
    MEAS.Size = size
    local w = MEAS.TextBounds.X
    wcount = wcount + 1
    if wcount > 900 then wcache, wcount = {}, 0 end
    wcache[key] = w
    return w
end

local function insideRect(r, x, y)
    return x and y and x >= r[1] and x <= r[1] + r[3] and y >= r[2] and y <= r[2] + r[4]
end

local function vc(y, h, size)
    return y + floor((h - size) / 2 + 0.5)
end

local function clipText(str, size, maxW)
    str = tostring(str)
    if maxW <= 0 then return "" end
    if textW(str, size) <= maxW then return str end
    local ell = "..."
    while #str > 0 and textW(str, size) > maxW - textW(ell, size) do
        str = str:sub(1, #str - 1)
    end
    return str .. ell
end

local function textC(o, cx, y, str, size, color, alpha, outline)
    str = tostring(str)
    text(o, cx - textW(str, size) / 2, y, str, size, color, alpha, false, outline)
end

-- Input ---------------------------------------------------------------------
local Players = _G.__swangy_players
if not Players then pcall(function() Players = game:GetService("Players") end) end
local Mouse = _G.__swangy_mouse

local function mouseAlive(m)
    if not m then return false end
    local ok, x = pcall(function() return m.X end)
    return ok and type(x) == "number"
end

local function getMouse()
    if mouseAlive(Mouse) then return Mouse end
    Mouse = nil
    if not Players then Players = _G.__swangy_players end
    if not Players then
        pcall(function() Players = game:GetService("Players") end)
    end
    if Players then
        _G.__swangy_players = Players
        local lp
        pcall(function() lp = Players.LocalPlayer end)
        if not lp then lp = _G.__swangy_localplayer end
        if lp then
            _G.__swangy_localplayer = lp
            pcall(function() Mouse = lp:GetMouse() end)
        end
    end
    if mouseAlive(Mouse) then
        _G.__swangy_mouse = Mouse
        return Mouse
    end
    Mouse = nil
    return nil
end

local mx, my
local m1 = { down = false, pressed = false, released = false }
local m2 = { down = false, pressed = false }
local m1prev = false
local m2prev = false
local m1latched = false
local m1lastDown = 0
local function poll()
    local m = getMouse()
    if m then
        local okx, xx = pcall(function() return m.X end)
        local oky, yy = pcall(function() return m.Y end)
        if okx and oky then mx, my = xx, yy end
    end
    local down = ismouse1pressed() and true or false
    if down then m1lastDown = clock() end
    if not down and (clock() - m1lastDown) > 0.08 then m1latched = false end
    m1prev = m1.down
    m1.down = down
    m1.pressed = down and not m1latched
    if m1.pressed then m1latched = true end
    m1.released = (not down) and m1prev
    local down2 = ismouse2pressed() and true or false
    m2prev = m2.down
    m2.down = down2
    m2.pressed = down2 and not m2prev
    Library.__mouse = { x = mx, y = my, down = m1.down, pressed = m1.pressed }
end

local kstate = {}
local function keyDown(vk) return iskeypressed(vk) and true or false end
local function keyEdge(vk)
    local down = keyDown(vk)
    local was = kstate[vk]
    kstate[vk] = down
    return down and not was
end

local VK = {
    Backspace = 8, Tab = 9, Enter = 13, Shift = 16, Ctrl = 17, Alt = 18, CapsLock = 20, Escape = 27, Space = 32,
    PageUp = 33, PageDown = 34, End = 35, Home = 36, Left = 37, Up = 38, Right = 39, Down = 40,
    Insert = 45, Delete = 46,
    ["0"] = 48, ["1"] = 49, ["2"] = 50, ["3"] = 51, ["4"] = 52, ["5"] = 53, ["6"] = 54, ["7"] = 55, ["8"] = 56, ["9"] = 57,
    A = 65, B = 66, C = 67, D = 68, E = 69, F = 70, G = 71, H = 72, I = 73, J = 74, K = 75, L = 76, M = 77,
    N = 78, O = 79, P = 80, Q = 81, R = 82, S = 83, T = 84, U = 85, V = 86, W = 87, X = 88, Y = 89, Z = 90,
    F1 = 112, F2 = 113, F3 = 114, F4 = 115, F5 = 116, F6 = 117, F7 = 118, F8 = 119, F9 = 120, F10 = 121, F11 = 122, F12 = 123,
    LeftShift = 160, RightShift = 161, LeftCtrl = 162, RightCtrl = 163, LeftAlt = 164, RightAlt = 165,
    LeftControl = 162, RightControl = 163, Control = 17, Shift = 16, Alt = 18,
    NumLock = 144, ScrollLock = 145, CapsLockKey = 20, Menu = 93,
}
local VK_NAME = {}
for n, c in pairs(VK) do if not VK_NAME[c] then VK_NAME[c] = n end end
local function keyToVk(k)
    if type(k) == "number" then return k end
    if type(k) ~= "string" or k == "" then return nil end
    if VK[k] then return VK[k] end
    local up = k:upper()
    if VK[up] then return VK[up] end
    if #k == 1 then return VK[up] end
    local norm = up:gsub("[%s_%-]", "")
    for name, code in pairs(VK) do
        if name:upper() == norm then return code end
    end
    return nil
end
local function vkName(vk) return VK_NAME[vk] or tostring(vk) end

local capturing
local focusedInput

local function shiftDown()
    return iskeypressed(16) or iskeypressed(160) or iskeypressed(161)
end

local function codeToChar(code)
    local shift = shiftDown()
    if code >= 65 and code <= 90 then
        local ch = string.char(code)
        return shift and ch or ch:lower()
    elseif code >= 97 and code <= 122 then
        local ch = string.char(code)
        return shift and ch:upper() or ch
    elseif code >= 48 and code <= 57 then
        return string.char(code)
    elseif code >= 96 and code <= 105 then
        return tostring(code - 96)
    elseif code == 32 then
        return " "
    elseif code == 189 then
        return shift and "_" or "-"
    elseif code == 190 then
        return "."
    elseif code == 191 then
        return "/"
    end
    return nil
end

-- Key capture is polled with iskeypressed (Windows VK codes), because
-- UIS.InputBegan reports Roblox KeyCodes which don't match iskeypressed.

local INPUT_CODES = { 8, 13, 27, 32, 189, 190, 191 }
for i = 48, 57 do INPUT_CODES[#INPUT_CODES + 1] = i end
for i = 65, 90 do INPUT_CODES[#INPUT_CODES + 1] = i end
for i = 96, 105 do INPUT_CODES[#INPUT_CODES + 1] = i end

local ALL_KEYS = {}
local seenKey = {}
for _, v in pairs(VK) do
    if type(v) == "number" and not seenKey[v] then
        seenKey[v] = true
        ALL_KEYS[#ALL_KEYS + 1] = v
    end
end

local hitList, activeDrag = {}, nil
local popupElements, openPopup = {}, nil

local function clearPopup(except)
    for _, el in ipairs(popupElements) do
        if el ~= except and el.popupOpen then el:ClosePopup() end
    end
end

local function newHit(x, y, w, h, hnd)
    hnd[1], hnd[2], hnd[3], hnd[4] = x, y, w, h
    hitList[#hitList + 1] = hnd
    return hnd
end

local function processInput()
    if not mx then activeDrag = nil return end
    local consumed = false
    if m1.pressed and openPopup then
        local r = openPopup:PopupRect()
        if r and not insideRect(r, mx, my) then
            openPopup:ClosePopup()
            consumed = true
            activeDrag = nil
        end
    end
    if m1.pressed and not consumed then
        local hit
        for i = #hitList, 1, -1 do
            local h = hitList[i]
            if insideRect(h, mx, my) then hit = h break end
        end
        activeDrag = hit
        if hit and hit.press then pcall(hit.press, mx, my) end
    end
    if activeDrag and activeDrag.drag and m1.down then pcall(activeDrag.drag, mx, my) end
    if m1.released then
        if activeDrag and activeDrag.release then pcall(activeDrag.release, mx, my) end
        activeDrag = nil
    end
end

local function hovered(x, y, w, h)
    return insideRect({ x, y, w, h }, mx, my)
end

local Windows = {}
local menuVk = VK.RightShift
local watermarkOn = true
local fps, frameCount, fpsClock = 0, 0, clock()
local notifs = {}

local function hideAll()
    for _, o in ipairs(ALL) do
        pcall(function()
            o.sc.Visible = false
            o.d.Visible = false
        end)
    end
end

-- Library API ---------------------------------------------------------------
function Library:SetMenuKey(k)
    local v = keyToVk(k)
    if v then menuVk = v end
    return self
end
function Library:SetAccent(c)
    Theme.accent = c
    return self
end
function Library:SetTheme(t)
    for k, v in pairs(t or {}) do if Theme[k] ~= nil then Theme[k] = v end end
    return self
end
function Library:SetWatermark(on)
    watermarkOn = on ~= false
    return self
end
function Library:GetWindow() return Windows[1] end

-- Notifications -------------------------------------------------------------
local function removeDrawings(list)
    for _, o in ipairs(list) do pcall(function() o.d:Remove() end) end
end

local function removeNotif(n)
    removeDrawings({ { d = n.bg }, { d = n.bar }, { d = n.tt }, { d = n.mt } })
end

function Library:ClearNotifications()
    for i = #notifs, 1, -1 do
        removeNotif(notifs[i])
        table.remove(notifs, i)
    end
end

function Library:PreviewNotification(msg, title)
    local opts = Library.NotificationOptions
    local was = opts.Enabled
    opts.Enabled = true
    local n = Library:Notify(msg or "Preview notification", nil, title or "Preview")
    opts.Enabled = was
    return n
end

function Library:Notify(msg, duration, title)
    local opts = Library.NotificationOptions
    if not opts.Enabled then
        return nil
    end
    local dur = opts.UseCallDuration and duration or opts.Duration
    local n = {
        msg = tostring(msg), title = tostring(title or "Notification"),
        t = clock(), dur = dur or 4,
        bg = D.new("Square"), bar = D.new("Square"), tt = D.new("Text"), mt = D.new("Text"),
    }
    n.bg.Filled, n.bg.Corner = true, Library.CornerRadius
    n.bar.Filled, n.bar.Corner = true, 2
    n.tt.Size, n.mt.Size = 14, 14
    n.bg.Visible, n.bar.Visible, n.tt.Visible, n.mt.Visible = false, false, false, false
    pcall(function() n.tt.Font = FONT; n.mt.Font = FONT end)
    zset(n.bg, 200); zset(n.bar, 201); zset(n.tt, 202); zset(n.mt, 202)
    table.insert(notifs, 1, n)
    while #notifs > (opts.MaxVisible or 6) do
        removeNotif(table.remove(notifs))
    end
    return n
end

local function renderNotifs()
    local opts = Library.NotificationOptions
    local right = Library.NotifySide ~= "Left"
    local cam = workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
    local w = opts.Width or 260
    local x = right and (vp.X - w - 16) or 16
    local now = clock()
    for i = #notifs, 1, -1 do
        local n = notifs[i]
        local age = now - n.t
        if age > n.dur then
            removeNotif(n)
            table.remove(notifs, i)
        else
            local alpha = 1
            local fade = opts.Fade or 0
            if fade > 0 and (n.dur - age) < fade then
                alpha = (n.dur - age) / fade
            end
            local h = 56
            local yy = (opts.OffsetY or 16) + (i - 1) * (h + (opts.Spacing or 6))
            n.bg.Position, n.bg.Size = Vector2.new(x, yy), Vector2.new(w, h)
            n.bg.Color, n.bg.Transparency = Theme.main, alpha
            n.bg.Visible = true
            n.bar.Position, n.bar.Size = Vector2.new(x + 1, yy + 6), Vector2.new(3, h - 12)
            n.bar.Color, n.bar.Transparency = Theme.accent, alpha
            n.bar.Visible = true
            n.tt.Position, n.tt.Text, n.tt.Color, n.tt.Transparency = Vector2.new(x + 14, yy + 9), clipText(n.title, 14, w - 28), Theme.text, alpha
            n.tt.Visible = true
            n.mt.Position, n.mt.Text, n.mt.Color, n.mt.Transparency = Vector2.new(x + 14, yy + 30), clipText(n.msg, 14, w - 28), Theme.subtext, alpha
            n.mt.Visible = true
        end
    end
end

-- Element base --------------------------------------------------------------
local Element = {}
Element.__index = Element
function Element:OnChanged(fn) table.insert(self.changed, fn) return self end
function Element:Fire(...)
    for _, fn in ipairs(self.changed) do pcall(fn, ...) end
    return self
end
function Element:SetVisible(b) self.visible = b ~= false return self end
function Element:SetDisabled(b) self.disabled = b == true return self end
function Element:Destroy()
    self.destroyed = true
    for _, o in ipairs(self.objects) do pcall(function() o.d:Remove() end) end
end

local function newElement(cls, id, label)
    local el = setmetatable({}, Element)
    for k, v in pairs(cls) do if el[k] == nil then el[k] = v end end
    el.id, el.text = id, label or id
    el.changed, el.objects = {}, {}
    el.visible, el.disabled = true, false
    el.addons = {}
    el.kind = cls.__kind
    return el
end

local function mkText(el, size)
    local o = newObj("Text", 30)
    o.d.Size = size or 14
    o.d.Outline = false
    table.insert(el.objects, o)
    return o
end
local function mkSq(el, z)
    local o = newObj("Square", z or 20)
    table.insert(el.objects, o)
    return o
end
local function mkLine(el, z)
    local o = newObj("Line", z or 20)
    table.insert(el.objects, o)
    return o
end

local function beginCapture(el)
    capturing = el
    for _, code in ipairs(ALL_KEYS) do
        kstate[code] = keyDown(code)
    end
end

-- Inline addons: key picker + color picker --------------------------------
local KeyPicker = {}
KeyPicker.__index = KeyPicker
KeyPicker.__kind = "KeyPicker"
KeyPicker.TypeKey = true
function KeyPicker:GetHeight() return 21 end
function KeyPicker:GetState() return self.state end
function KeyPicker:SetValue(v)
    if type(v) == "table" then
        local vk = keyToVk(v[1]); if vk then self.vk = vk end
        if v[2] then self.mode = v[2] end
    else
        local vk = keyToVk(v); if vk then self.vk = vk end
    end
    self.state = false
    self:Fire(self)
    return self
end
function KeyPicker:Capture(code)
    capturing = nil
    self.vk = code
    self.state = false
    if self.changedCallback then pcall(self.changedCallback, self) end
    self:Fire(self)
end
function KeyPicker:NotifyState(on)
    if self.syncParent and #(self.syncParent.changed or {}) > 0 then
        return
    end
    local label = (self.text and self.text ~= self.id) and self.text or vkName(self.vk)
    if Library and Library.Notify then
        Library:Notify(label .. (on and "  [ ON ]" or "  [ OFF ]"), 1.6, "Keybind")
    end
end
function KeyPicker:Evaluate()
    if capturing == self or not self.vk then return end
    if self.mode == "Always" then
        if not self.state then
            self.state = true
            self:Fire(self)
            self:NotifyState(true)
        end
        return
    end
    local down = keyDown(self.vk)
    if self.mode == "Hold" then
        if down ~= self.state then
            self.state = down
            self:Fire(self)
            self:NotifyState(down)
        end
    elseif keyEdge(self.vk) then
        self.state = not self.state
        self:Fire(self)
        self:NotifyState(self.state)
    end
end
function KeyPicker:AddKeyPicker() return self end
function KeyPicker:CloseModePopup()
    self.modeOpen = false
    if openPopup == self then openPopup = nil end
    if self.modeBg then put(self.modeBg, "Visible", false) end
    if self.modeBorder then put(self.modeBorder, "Visible", false) end
    for _, o in ipairs(self.modeTexts or {}) do put(o, "Visible", false) end
    for _, o in ipairs(self.modeCells or {}) do put(o, "Visible", false) end
end
function KeyPicker:ClosePopup() return self:CloseModePopup() end
function KeyPicker:PopupRect() return { self.mpx, self.mpy, self.mpw, self.mph } end
function KeyPicker:OpenModePopup()
    clearPopup(self)
    self.modeOpen = true
    openPopup = self
end
function KeyPicker:RenderPopup()
    if not self.modeOpen then return end
    local modes = { "Hold", "Toggle", "Always" }
    local rowH = 20
    local pw, ph = 88, rowH * #modes + 6
    local cam = workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
    local px, py = self.boxX or 0, (self.boxY or 0) + (self.boxH or 18) + 2
    if px + pw > vp.X - 8 then px = vp.X - pw - 8 end
    if py + ph > vp.Y - 8 then py = (self.boxY or 0) - ph - 2 end
    self.mpx, self.mpy, self.mpw, self.mph = px, py, pw, ph
    if not self.modeBg then
        self.modeBg, self.modeBorder = newObj("Square", 110), newObj("Square", 111)
        self.modeTexts, self.modeCells = {}, {}
        table.insert(self.objects, self.modeBg)
        table.insert(self.objects, self.modeBorder)
    end
    fill(self.modeBg, px, py, pw, ph, Theme.bg, 1, 4)
    stroke(self.modeBorder, px, py, pw, ph, Theme.outline, 1, 4, 1)
    put(self.modeBg, "Visible", true)
    put(self.modeBorder, "Visible", true)
    newHit(px, py, pw, ph, { press = function() end })
    for i, m in ipairs(modes) do
        local o = self.modeTexts[i]
        if not o then o = newObj("Text", 112) o.d.Size = 14 table.insert(self.objects, o) self.modeTexts[i] = o end
        local cell = self.modeCells[i]
        if not cell then cell = newObj("Square", 111) table.insert(self.objects, cell) self.modeCells[i] = cell end
        local ry = py + 3 + (i - 1) * rowH
        local hv = hovered(px + 3, ry, pw - 6, rowH)
        if hv then fill(cell, px + 3, ry, pw - 6, rowH, Theme.accent, 0.18, 2) else put(cell, "Visible", false) end
        text(o, px + 8, ry + 3, m, 14, self.mode == m and Theme.accent or Theme.text, 1, false, false)
        newHit(px + 3, ry, pw - 6, rowH, {
            press = function()
                self.mode = m
                self.state = false
                self:CloseModePopup()
                self:Fire(self)
            end,
        })
    end
end
function KeyPicker:RenderInline(x, y, h)
    local bw = 68
    local bx = x - bw
    self.boxX, self.boxY, self.boxW, self.boxH = bx, y, bw, h
    fill(self.bg, bx, y + (h - 15) / 2, bw, 15, Theme.main, 1, 2)
    stroke(self.border, bx, y + (h - 15) / 2, bw, 15, (capturing == self or self.modeOpen) and Theme.accent or Theme.outline, 1, 2, 1)
    local shown = capturing == self and "[...]" or vkName(self.vk)
    textC(self.keyText, bx + bw / 2, vc(y + (h - 15) / 2, 15, 14), clipText(shown, 14, bw - 6), 14, Theme.subtext, 1, false)
    if hovered(bx, y, bw, h) and m2.pressed then
        self:OpenModePopup()
    end
    newHit(bx, y, bw, h, {
        press = function()
            beginCapture(self)
            self:CloseModePopup()
        end,
    })
end

local Grid = { cells = {}, hue = {}, alpha = {}, hueKey = nil }
Library.__grid = Grid
local function ensureGrid()
    if Grid.cursor then return end
    Grid.svImage = newObj("Image", 100)
    for i = 1, 32 do Grid.hue[i] = newObj("Square", 101) end
    for i = 1, 16 do Grid.alpha[i] = newObj("Square", 101) end
    Grid.cursor = newObj("Square", 106)
    Grid.cursorH = newObj("Square", 106)
end
local function hideGrid()
    if Grid.svImage then
        Grid.svImage.sc.Visible = false
        Grid.svImage.d.Visible = false
    end
    for _, o in ipairs(Grid.hue) do put(o, "Visible", false) end
    for _, o in ipairs(Grid.alpha) do put(o, "Visible", false) end
    if Grid.cursor then put(Grid.cursor, "Visible", false) end
    if Grid.cursorH then put(Grid.cursorH, "Visible", false) end
end

local ColorPicker = {}
ColorPicker.__index = ColorPicker
ColorPicker.__kind = "ColorPicker"
function ColorPicker:GetHeight() return 21 end
function ColorPicker:Color() return Color3.fromHSV(self.h or 0.72, self.s or 0.6, self.v or 1) end
function ColorPicker:SetValueRGB(c, t)
    self.value = c
    if t then self.alpha = 1 - t end
    self.h, self.s, self.v = rgbToHsv(c)
    self:Fire(self.value, self.alpha)
    return self
end
function ColorPicker:SetValue(hsv, t)
    if hsv then self.h, self.s, self.v = hsv.H or self.h, hsv.S or self.s, hsv.V or self.v end
    if t then self.alpha = 1 - t end
    self.value = self:Color()
    self:Fire(self.value, self.alpha)
    return self
end
function ColorPicker:Key(code)
    if not self.hexEditing then return end
    if code == 13 then
        local t = self.hexBuf or ""
        if #t == 6 then
            local ok, c = pcall(Color3.fromHex, t)
            if ok and c then
                self:SetValueRGB(c, 1 - (self.alpha or 1))
            end
        end
        self.hexEditing = false
        focusedInput = nil
    elseif code == 27 then
        self.hexEditing = false
        focusedInput = nil
    elseif code == 8 then
        self.hexBuf = (self.hexBuf or ""):sub(1, -2)
    else
        local ch
        if code >= 48 and code <= 57 then
            ch = string.char(code)
        elseif code >= 65 and code <= 70 then
            ch = string.char(code)
        elseif code >= 97 and code <= 102 then
            ch = string.char(code):upper()
        end
        if ch and #(self.hexBuf or "") < 6 then
            self.hexBuf = (self.hexBuf or "") .. ch
        end
    end
end
function ColorPicker:ClosePopup()
    self.popupOpen = false
    self.hexEditing = false
    if focusedInput == self then focusedInput = nil end
    if openPopup == self then openPopup = nil end
    put(self.popupBg, "Visible", false)
    put(self.popupBorder, "Visible", false)
    put(self.svBase, "Visible", false)
    hideGrid()
    for _, o in ipairs({ self.hexLabel, self.alphaBG, self.alphaSwatch, self.hexBg, self.hexBorder }) do put(o, "Visible", false) end
end
function ColorPicker:PopupRect() return { self.px, self.py, self.pw, self.ph } end
function ColorPicker:OpenPopup()
    clearPopup(self)
    self.popupOpen = true
    openPopup = self
end
function ColorPicker:RenderInline(x, y, h, anchorRight)
    local s = 18
    local sx = anchorRight and (x - s) or x
    fill(self.swatch, sx, y + (h - s) / 2, s, s, self:Color(), self.alpha or 1, 2)
    stroke(self.swatchBorder, sx, y + (h - s) / 2, s, s, Theme.outline, 1, 2, 1)
    newHit(sx, y, s, h, {
        press = function()
            if self.popupOpen then self:ClosePopup() else self:OpenPopup() end
        end,
    })
    self.hx, self.hy, self.hw = sx, y, s
end
function ColorPicker:RenderPopup()
    if not self.popupOpen then return end
    local pw, ph = 204, 182
    local cam = workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
    local px, py = self.hx - pw + 20, self.hy + 24
    if px < 8 then px = 8 end
    if px + pw > vp.X - 8 then px = vp.X - pw - 8 end
    if py + ph > vp.Y - 8 then py = self.hy - ph - 8 end
    if py < 8 then py = 8 end
    self.px, self.py, self.pw, self.ph = px, py, pw, ph
    fill(self.popupBg, px, py, pw, ph, Theme.bg, 1, 4)
    stroke(self.popupBorder, px, py, pw, ph, Theme.outline, 1, 4, 1)
    newHit(px, py, pw, ph, { press = function() end })

    ensureGrid()
    local gx, gy, gw, gh = px + 8, py + 8, pw - 16, 108
    fill(self.svBase, gx, gy, gw, gh, Color3.fromHSV(self.h, 1, 1), 1, 0)
    local hk = floor(self.h * 100 + 0.5)
    if Grid.hueKey ~= hk then
        Grid.hueKey = hk
        Grid.svImage.d.Data = buildSVBmp(self.h)
    end
    Grid.svImage.d.Position = Vector2.new(gx, gy)
    Grid.svImage.d.Size = Vector2.new(gw, gh)
    put(Grid.svImage, "Visible", true)
    fill(Grid.cursor, gx + self.s * gw - 3, gy + (1 - self.v) * gh - 3, 6, 6, Theme.white, 1, 0)
    local function svSet(xx, yy)
        self.s = clamp((xx - gx) / gw, 0, 1)
        self.v = clamp(1 - (yy - gy) / gh, 0, 1)
        self.value = self:Color()
        self:Fire(self.value, self.alpha)
    end
    newHit(gx, gy, gw, gh, { press = svSet, drag = svSet })

    local hx, hy, hw2, hh2 = px + 8, py + 124, pw - 16, 10
    local segs = 32
    for i = 1, segs do
        local o = Grid.hue[i]
        fill(o, hx + (i - 1) / segs * hw2, hy, hw2 / segs + 0.6, hh2, Color3.fromHSV((i - 0.5) / segs, 1, 1), 1, 0)
        put(o, "Visible", true)
    end
    fill(Grid.cursorH, hx + self.h * hw2 - 1, hy - 1, 2, hh2 + 2, Theme.white, 1, 0)
    local function hueSet(xx)
        self.h = clamp((xx - hx) / hw2, 0, 0.999)
        self.value = self:Color()
        self:Fire(self.value, self.alpha)
    end
    newHit(hx, hy, hw2, hh2, { press = hueSet, drag = function(xx) hueSet(xx) end })

    local ax, ay, aw = px + 8, py + 142, pw - 16
    local acount = 16
    local cc = self:Color()
    for i = 1, acount do
        local o = Grid.alpha[i]
        fill(o, ax + (i - 1) / acount * aw, ay, aw / acount + 0.6, 10, cc, (i - 0.5) / acount, 0)
        put(o, "Visible", true)
    end
    local function alphaSet(xx)
        self.alpha = clamp((xx - ax) / aw, 0, 1)
        self.value = self:Color()
        self:Fire(self.value, self.alpha)
    end
    newHit(ax, ay, aw, 10, { press = alphaSet, drag = function(xx) alphaSet(xx) end })

    local c = self:Color()
    local hex = fmt("#%02X%02X%02X", floor(c.R * 255 + 0.5), floor(c.G * 255 + 0.5), floor(c.B * 255 + 0.5))
    local hx, hy, hw, hh = px + 8, py + 154, 96, 20
    if self.hexEditing and m1.pressed and not hovered(hx, hy, hw, hh) then
        self.hexEditing = false
        if focusedInput == self then focusedInput = nil end
    end
    fill(self.hexBg, hx, hy, hw, hh, Theme.main, 1, 2)
    put(self.hexBg, "Visible", true)
    stroke(self.hexBorder, hx, hy, hw, hh, self.hexEditing and Theme.accent or Theme.outline, 1, 2, 1)
    put(self.hexBorder, "Visible", true)
    local shown = self.hexEditing and ("#" .. (self.hexBuf or "") .. ((clock() % 1) < 0.5 and "|" or "")) or hex
    text(self.hexLabel, hx + 6, vc(hy, hh, 14), shown, 14, self.hexEditing and Theme.text or Theme.subtext, 1, false, false)
    put(self.hexLabel, "Visible", true)
    newHit(hx, hy, hw, hh, {
        press = function()
            self.hexEditing = true
            self.hexBuf = ""
            focusedInput = self
        end,
    })
    fill(self.alphaBG, px + pw - 26, py + 156, 18, 18, Theme.main, 1, 2)
    fill(self.alphaSwatch, px + pw - 26, py + 156, 18, 18, c, self.alpha or 1, 2)
    stroke(self.alphaBG, px + pw - 26, py + 156, 18, 18, Theme.outline, 1, 2, 1)
    put(self.alphaBG, "Visible", true)
    put(self.alphaSwatch, "Visible", true)
end

local Input = {}
Input.__index = Input
Input.__kind = "Input"
function Input:GetHeight() return 39 end
function Input:SetValue(v)
    self.value = tostring(v or "")
    self:Fire(self.value)
    return self
end
function Input:SetText(t) self.text = t return self end
function Input:Focus() focusedInput = self return self end
function Input:SetPlaceholder(t) self.placeholder = t return self end
function Input:Key(code)
    if code == 13 or code == 27 then
        self:Fire(self.value)
        focusedInput = nil
        return
    end
    if code == 8 then
        self.value = self.value:sub(1, -2)
        self:Fire(self.value)
        return
    end
    local ch = codeToChar(code)
    if ch then
        self.value = self.value .. ch
        self:Fire(self.value)
    end
end
function Input:Render(x, y, w)
    text(self.label, x, y, clipText(self.text, 14, w), 14, Theme.text, 0.85, false, false)
    local by = y + 18
    fill(self.bg, x, by, w, 21, Theme.main, 1, 2)
    stroke(self.border, x, by, w, 21, focusedInput == self and Theme.accent or Theme.outline, 1, 2, 1)
    local shown = (self.value ~= "" and self.value) or (self.placeholder or "")
    text(self.valueText, x + 6, vc(by, 21, 14), clipText(shown, 14, w - 14), 14, self.value ~= "" and Theme.text or Theme.subtext, 1, false, false)
    if focusedInput == self and (clock() % 1) < 0.5 then
        local cxp = x + 6 + textW(self.value, 14) + 1
        line(self.caret, cxp, by + 4, cxp, by + 17, Theme.text, 1, 1)
    else
        put(self.caret, "Visible", false)
    end
    if m1.pressed and not hovered(x, by, w, 21) and focusedInput == self then
        focusedInput = nil
    end
    newHit(x, by, w, 21, {
        press = function()
            focusedInput = self
        end,
    })
end

local function attachKeyPicker(parent, id, cfg)
    cfg = cfg or {}
    local el = newElement(KeyPicker, id, cfg.Text or id)
    el.vk = keyToVk(cfg.Default or "F") or VK.F
    el.mode = cfg.Mode or "Toggle"
    el.state = false
    el.changedCallback = cfg.ChangedCallback
    el.captureOnly = cfg.CaptureOnly == true
    if cfg.Callback then table.insert(el.changed, cfg.Callback) end
    el.bg, el.border = mkSq(el, 21), mkSq(el, 22)
    el.keyText = mkText(el, 14)
    el.inline = true
    el.modeOpen = false
    el.parent = parent
    if parent and parent.kind == "Toggle" and cfg.SyncToggleState ~= false then
        el.syncParent = parent
        table.insert(el.changed, function(self)
            if self.state ~= nil then parent:SetValue(self.state) end
        end)
    end
    if not el.captureOnly then table.insert(Library.__keybinds, el) end
    table.insert(popupElements, el)
    Library.Options[id] = el
    Library.KeyPickers[id] = el
    table.insert(parent.addons, el)
    return el
end

local function attachColorPicker(parent, id, cfg)
    cfg = cfg or {}
    local el = newElement(ColorPicker, id, cfg.Title or id)
    local c = cfg.Default or Theme.accent
    el.value = c
    el.alpha = 1 - (cfg.Transparency or 0)
    el.h, el.s, el.v = 0.72, 0.6, 1
    el.h, el.s, el.v = rgbToHsv(c)
    if cfg.Callback then table.insert(el.changed, cfg.Callback) end
    el.swatch = mkSq(el, 21)
    el.swatchBorder = mkSq(el, 22)
    el.popupBg = mkSq(el, 100)
    el.popupBorder = mkSq(el, 101)
    el.svBase = mkSq(el, 99)
    el.hexLabel = mkText(el, 14)
    el.hexBg, el.hexBorder = mkSq(el, 103), mkSq(el, 104)
    el.hexEditing = false
    el.alphaBG = mkSq(el, 103)
    el.alphaSwatch = mkSq(el, 104)
    zset(el.hexLabel, 107)
    el.inline = true
    el.parent = parent
    table.insert(popupElements, el)
    Library.Options[id] = el
    Library.ColorPickers[id] = el
    table.insert(parent.addons, el)
    el:Fire(el.value, el.alpha)
    return el
end

local function renderAddons(parent, x, y, w, h)
    local anchor = x + w
    for _, a in ipairs(parent.addons) do
        if a.TypeKey then
            a:RenderInline(anchor - 2, y, h)
            anchor = anchor - 72
        else
            a:RenderInline(anchor - 2, y, h, true)
            anchor = anchor - 24
        end
    end
    return anchor
end

-- Widgets -------------------------------------------------------------------
local Toggle = {}
Toggle.__index = Toggle
Toggle.__kind = "Toggle"
Toggle.TypeKey = true
function Toggle:GetHeight() return 18 end
function Toggle:SetValue(v)
    v = v == true
    if self.value ~= v then self.value = v self:Fire(v) end
    return self
end
function Toggle:SetText(t) self.text = t return self end
function Toggle:AddKeyPicker(id, cfg) return attachKeyPicker(self, id, cfg) end
function Toggle:AddColorPicker(id, cfg) return attachColorPicker(self, id, cfg) end
function Toggle:Render(x, y, w)
    local h = 18
    if not self.disabled then
        newHit(x, y, w, h, { press = function() self:SetValue(not self.value) end })
    end
    local endX = w
    if #self.addons > 0 then
        endX = (renderAddons(self, x, y, w, h) - x)
    end
    local switchW = 32
    local labelW = endX - switchW - 8
    text(self.label, x, vc(y, h, 14), clipText(self.text, 14, labelW), 14, self.disabled and Theme.disabled or Theme.text, 0.85, false, false)
    local tx = x + endX - switchW
    fill(self.track, tx, y, switchW, h, self.value and Theme.accent or Theme.main, 1, h / 2)
    stroke(self.border, tx, y, switchW, h, Theme.outline, 1, h / 2, 1)
    local ks = 14
    local kx = self.value and (tx + switchW - ks - 2) or (tx + 2)
    fill(self.knob, kx, y + 2, ks, ks, Theme.white, 1, ks / 2)
end

local Slider = {}
Slider.__index = Slider
Slider.__kind = "Slider"
function Slider:GetHeight() return 33 end
function Slider:Format(v)
    local step = self.rounding or 1
    local shown
    if step > 0 and step < 1 then
        shown = string.format("%.2f", v)
    else
        shown = tostring(floor(v + 0.5))
    end
    return (self.prefix or "") .. shown .. (self.suffix or "")
end
function Slider:SetValue(v)
    v = clamp(tonumber(v) or self.min, self.min, self.max)
    local step = self.rounding or 1
    if step > 0 then
        v = floor(v / step + 0.5) * step
        if step >= 1 then
            v = floor(v + 0.5)
        else
            v = floor(v * 100 + 0.5) / 100
        end
    end
    if math.abs((self.value or 0) - v) > 1e-6 then
        self.value = v
        self:Fire(v)
    end
    return self
end
function Slider:SetMin(v) self.min = v return self end
function Slider:SetMax(v) self.max = v return self end
function Slider:SetText(t) self.text = t return self end
function Slider:Render(x, y, w)
    local by, bh = y + 18, 15
    text(self.label, x, y, clipText(self.text, 14, w), 14, self.disabled and Theme.disabled or Theme.text, 0.85, false, false)
    local frac = (self.max > self.min) and ((self.value - self.min) / (self.max - self.min)) or 0
    fill(self.bg, x, by, w, bh, Theme.main, 1, 2)
    fill(self.fill, x, by, w * frac, bh, self.disabled and Theme.disabled or Theme.accent, 1, 2)
    stroke(self.border, x, by, w, bh, Theme.outline, 1, 2, 1)
    local ts = 13
    local tpos = clamp(x + w * frac - ts / 2, x - 1, x + w - ts + 1)
    fill(self.thumb, tpos, by + (bh - ts) / 2, ts, ts, Theme.white, 1, ts / 2)
    textC(self.valueText, x + w / 2, vc(by, bh, 14), self:Format(self.value), 14, Theme.white, 1, true)
    if not self.disabled then
        local function set(xx)
            local f = clamp((xx - x) / max(1, w), 0, 1)
            self:SetValue(self.min + f * (self.max - self.min))
        end
        newHit(x, by, w, bh, { press = set, drag = function(xx) set(xx) end })
    end
end

local Button = {}
Button.__index = Button
Button.__kind = "Button"
function Button:GetHeight() return 21 end
function Button:SetText(t) self.text = t return self end
function Button:Render(x, y, w)
    local hv = hovered(x, y, w, 21)
    fill(self.bg, x, y, w, 21, hv and mix(Theme.main, Theme.accent, 0.18) or Theme.main, 1, 2)
    stroke(self.border, x, y, w, 21, Theme.outline, 1, 2, 1)
    textC(self.label, x + w / 2, vc(y, 21, 14), clipText(self.text, 14, w - 10), 14, Theme.text, 1, false)
    newHit(x, y, w, 21, {
        press = function()
            if self.func then pcall(self.func) end
        end,
    })
end

local Label = {}
Label.__index = Label
Label.__kind = "Label"
Label.TypeKey = true
function Label:Lines(w)
    local size = self.size or 14
    if not self.wrap then return { self.text } end
    local out, cur = {}, ""
    for word in tostring(self.text):gmatch("%S+") do
        local cand = cur == "" and word or (cur .. " " .. word)
        if textW(cand, size) <= w or cur == "" then cur = cand
        else out[#out + 1] = cur cur = word end
    end
    if cur ~= "" then out[#out + 1] = cur end
    if #out == 0 then out[1] = "" end
    return out
end
function Label:GetHeight(w)
    if self.wrap then
        local used = 0
        for _, a in ipairs(self.addons or {}) do
            used = used + (a.kind == "KeyPicker" and 72 or 24)
        end
        return #self:Lines(w - used) * 18
    end
    return 18
end
function Label:SetText(t) self.text = t return self end
function Label:AddKeyPicker(id, cfg) return attachKeyPicker(self, id, cfg) end
function Label:AddColorPicker(id, cfg) return attachColorPicker(self, id, cfg) end
function Label:Render(x, y, w)
    local endX = w
    if #self.addons > 0 then endX = (renderAddons(self, x, y, w, 18) - x) end
    local size = self.size or 14
    local lines = self:Lines(endX)
    for i, ln in ipairs(lines) do
        local o = self.lines[i]
        if not o then o = mkText(self, size) self.lines[i] = o end
        text(o, x, y + (i - 1) * 18, ln, size, self.color or Theme.text, 0.85, false, false)
    end
    for i = #lines + 1, #self.lines do put(self.lines[i], "Visible", false) end
end

local Divider = {}
Divider.__index = Divider
Divider.__kind = "Divider"
function Divider:GetHeight() return self.text and 30 or 6 end
function Divider:Render(x, y, w)
    if self.text and self.text ~= "" then
        textC(self.lbl, x + w / 2, vc(y, 24, 14), clipText(self.text, 14, w), 14, Theme.subtext, 1, false)
        line(self.ln, x, y + 24, x + w, y + 24, Theme.outline, 1, 1)
    else
        line(self.ln, x, y + 3, x + w, y + 3, Theme.outline, 1, 1)
        put(self.lbl, "Visible", false)
    end
end

local Dropdown = {}
Dropdown.__index = Dropdown
Dropdown.__kind = "Dropdown"
function Dropdown:GetHeight() return self.text and 39 or 21 end
function Dropdown:BuildOptions()
    local opts = {}
    local vals = self.values
    local isArray = true
    for k in pairs(vals) do
        if type(k) ~= "number" then isArray = false break end
    end
    if isArray then
        for _, v in ipairs(vals) do opts[#opts + 1] = { key = v, label = tostring(v) } end
    else
        local keys = {}
        for k in pairs(vals) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do opts[#opts + 1] = { key = k, label = tostring(vals[k]) } end
    end
    self.opts = opts
    if self.multi then
        if type(self.value) ~= "table" then self.value = {} end
    elseif self.value == nil and #opts > 0 then
        self.value = opts[1].key
    end
    return opts
end
function Dropdown:LabelFor(key)
    for _, o in ipairs(self.opts or {}) do if o.key == key then return o.label end end
    return tostring(key)
end
function Dropdown:Display()
    if self.multi then
        local parts = {}
        for k in pairs(self.value or {}) do parts[#parts + 1] = self:LabelFor(k) end
        table.sort(parts)
        if #parts == 0 then return self.placeholder or "..." end
        return table.concat(parts, ", ")
    end
    if self.value == nil then return self.placeholder or "..." end
    return self:LabelFor(self.value)
end
function Dropdown:SetValue(v) self.value = v self:Fire(self.value) return self end
function Dropdown:SetValues(t)
    self.values = t or {}
    self.optionArray = nil
    self:BuildOptions()
    if not self.multi and self.value ~= nil then
        local found = false
        for _, o in ipairs(self.opts or {}) do if o.key == self.value then found = true break end end
        if not found then self.value = self.opts and self.opts[1] and self.opts[1].key or nil end
    end
    return self
end
function Dropdown:AddValues(t)
    if type(t) ~= "table" then t = { t } end
    for k, v in pairs(t) do
        if type(k) == "number" then table.insert(self.values, v) else self.values[k] = v end
    end
    self.optionArray = nil
    self:BuildOptions()
    return self
end
function Dropdown:ClosePopup()
    self.popupOpen = false
    if openPopup == self then openPopup = nil end
    put(self.popupBg, "Visible", false)
    put(self.popupBorder, "Visible", false)
    if self.scrollTrack then put(self.scrollTrack, "Visible", false) end
    if self.scrollThumb then put(self.scrollThumb, "Visible", false) end
    for _, o in ipairs(self.optTexts) do put(o, "Visible", false) end
    for _, o in ipairs(self.selCells) do put(o, "Visible", false) end
end
function Dropdown:PopupRect() return { self.px, self.py, self.pw, self.ph } end
function Dropdown:OpenPopup() clearPopup(self) self.popupOpen = true openPopup = self end
function Dropdown:Render(x, y, w)
    local selY = y
    if self.text then
        text(self.label, x, y, clipText(self.text, 14, w - 24), 14, Theme.text, 0.65, false, false)
        selY = y + 18
    else
        put(self.label, "Visible", false)
    end
    local hv = hovered(x, selY, w, 21)
    fill(self.bg, x, selY, w, 21, Theme.main, 1, 2)
    stroke(self.border, x, selY, w, 21, self.popupOpen and Theme.accent or (hv and Theme.strokeLit or Theme.outline), 1, 2, 1)
    text(self.valueText, x + 6, vc(selY, 21, 14), clipText(self:Display(), 14, w - 26), 14, Theme.text, 1, false, false)
    local cx, cy = x + w - 12, selY + 9
    line(self.chev1, cx - 3, cy, cx, cy + 3, Theme.subtext, 1, 1)
    line(self.chev2, cx, cy + 3, cx + 3, cy, Theme.subtext, 1, 1)
    newHit(x, selY, w, 21, {
        press = function()
            if self.popupOpen then self:ClosePopup() else self:OpenPopup() end
        end,
    })
    self.hx, self.hy, self.hw = x, selY, w
end
function Dropdown:RenderPopup()
    if not self.popupOpen then return end
    local opts = self.opts or self:BuildOptions()
    local rowH = 21
    local total = #opts
    local vis = total
    if self.maxVisible and total > self.maxVisible then vis = self.maxVisible end
    local scrollMax = max(0, total - vis)
    self.scroll = clamp(self.scroll or 0, 0, scrollMax)
    local pw, ph = self.hw, rowH * vis + 8
    local cam = workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
    local px, py = self.hx, self.hy + 21 + 3
    if py + ph > vp.Y - 8 then py = self.hy - ph - 3 end
    self.px, self.py, self.pw, self.ph = px, py, pw, ph
    fill(self.popupBg, px, py, pw, ph, Theme.bg, 1, 4)
    stroke(self.popupBorder, px, py, pw, ph, Theme.outline, 1, 4, 1)
    newHit(px, py, pw, ph, { press = function() end })
    local showBar = total > vis
    local listW = pw - (showBar and 12 or 0)
    local first = self.scroll + 1
    for idx = 1, vis do
        local i = first + idx - 1
        local opt = opts[i]
        if not opt then break end
        local o = self.optTexts[idx]
        if not o then o = newObj("Text", 102) o.d.Size = 14 table.insert(self.objects, o) self.optTexts[idx] = o end
        local ry = py + 4 + (idx - 1) * rowH
        local selected = (self.multi and self.value and self.value[opt.key]) or (self.value == opt.key)
        local hv = hovered(px + 4, ry, listW - 8, rowH)
        local cell = self.selCells[idx]
        if hv then
            if not cell then cell = newObj("Square", 101) table.insert(self.objects, cell) self.selCells[idx] = cell end
            fill(cell, px + 4, ry, listW - 8, rowH, Theme.accent, 0.18, 2)
        elseif cell then
            put(cell, "Visible", false)
        end
        text(o, px + 8, ry + 3, clipText(opt.label, 14, listW - 18), 14, selected and Theme.accent or Theme.text, 1, false, false)
        newHit(px + 4, ry, listW - 8, rowH, {
            press = function()
                if self.multi then
                    self.value = self.value or {}
                    if self.value[opt.key] then self.value[opt.key] = nil else self.value[opt.key] = true end
                    self:Fire(self.value)
                else
                    self.value = opt.key
                    self:Fire(opt.key)
                    self:ClosePopup()
                end
            end,
        })
    end
    for i = vis + 1, #self.optTexts do put(self.optTexts[i], "Visible", false) end
    for i = vis + 1, #self.selCells do put(self.selCells[i], "Visible", false) end

    if showBar then
        local tx, ty, tw, th = px + pw - 9, py + 4, 6, ph - 8
        fill(self.scrollTrack, tx, ty, tw, th, Theme.main, 1, 3)
        put(self.scrollTrack, "Visible", true)
        local thumbH = max(18, floor(th * vis / total + 0.5))
        local frac = scrollMax > 0 and (self.scroll / scrollMax) or 0
        local thumbY = ty + (th - thumbH) * frac
        fill(self.scrollThumb, tx, thumbY, tw, thumbH, Theme.accent, 1, 3)
        put(self.scrollThumb, "Visible", true)
        local function scrollTo(yy)
            local f = clamp((yy - ty - thumbH / 2) / max(1, th - thumbH), 0, 1)
            self.scroll = floor(f * scrollMax + 0.5)
        end
        newHit(tx - 2, ty, tw + 4, th, {
            press = function(_, yy) scrollTo(yy) end,
            drag = function(_, yy) scrollTo(yy) end,
        })
    else
        put(self.scrollTrack, "Visible", false)
        put(self.scrollThumb, "Visible", false)
    end
end

-- Groupbox ------------------------------------------------------------------
local Groupbox = {}
Groupbox.__index = Groupbox

local function register(id, el, cat)
    Library.Options[id] = el
    if cat then cat[id] = el end
end

function Groupbox:AddToggle(id, cfg)
    cfg = cfg or {}
    local el = newElement(Toggle, id, cfg.Text or id)
    if cfg.Callback then table.insert(el.changed, cfg.Callback) end
    el.value = cfg.Default == true
    el.bg = mkSq(el, 20) el.label = mkText(el, 14) el.track = mkSq(el, 21) el.border = mkSq(el, 22) el.knob = mkSq(el, 23)
    table.insert(self.elements, el)
    register(id, el, Library.Toggles)
    if el.value then el:Fire(true) end
    return el
end
function Groupbox:AddCheckbox(id, cfg) return self:AddToggle(id, cfg) end
function Groupbox:AddSlider(id, cfg)
    cfg = cfg or {}
    local el = newElement(Slider, id, cfg.Text or id)
    if cfg.Callback then table.insert(el.changed, cfg.Callback) end
    el.min, el.max = cfg.Min or 0, cfg.Max or 100
    el.rounding = cfg.Rounding or 1
    el.prefix, el.suffix = cfg.Prefix, cfg.Suffix
    el.value = clamp(cfg.Default or el.min, el.min, el.max)
    el.bg, el.fill, el.border = mkSq(el, 20), mkSq(el, 21), mkSq(el, 22)
    el.label, el.valueText = mkText(el, 14), mkText(el, 14)
    el.thumb = mkSq(el, 23)
    table.insert(self.elements, el)
    register(id, el, Library.Sliders)
    el:Fire(el.value)
    return el
end
function Groupbox:AddButton(a, b)
    local id, cfg
    if type(a) == "table" and b == nil then cfg = a id = cfg.Id or cfg.Text or "Button"
    else id, cfg = a, b or {} end
    local el = newElement(Button, id, cfg.Text or id)
    el.func = cfg.Func or cfg.Callback
    el.bg, el.border, el.label = mkSq(el, 20), mkSq(el, 22), mkText(el, 14)
    table.insert(self.elements, el)
    register(id, el, Library.Buttons)
    return el
end
function Groupbox:AddLabel(a, b)
    local cfg = type(a) == "table" and a or { Text = a }
    local el = newElement(Label, cfg.Id or ("Label" .. #self.elements + 1), cfg.Text or "")
    el.wrap, el.size, el.color = cfg.DoesWrap == true, cfg.Size or 14, cfg.Color
    el.lines = {}
    table.insert(self.elements, el)
    return el
end
function Groupbox:AddDivider(cfg)
    if type(cfg) == "string" then cfg = { Text = cfg } end
    cfg = cfg or {}
    local el = newElement(Divider, "Divider" .. #self.elements + 1, cfg.Text or "")
    el.ln, el.lbl = mkLine(el), mkText(el, 14)
    table.insert(self.elements, el)
    return el
end
function Groupbox:AddDropdown(id, cfg)
    cfg = cfg or {}
    local el = newElement(Dropdown, id, cfg.Text or id)
    el.values = cfg.Values or cfg.Options or {}
    el.multi = cfg.Multi == true
    el.placeholder = cfg.Placeholder or "..."
    el.value = cfg.Default
    if type(el.value) == "number" and el.values[el.value] ~= nil then
        local opts = el:BuildOptions()
        el.value = opts[el.value] and opts[el.value].key or el.value
    else
        el:BuildOptions()
    end
    if cfg.Callback then table.insert(el.changed, cfg.Callback) end
    el.bg, el.border = mkSq(el, 20), mkSq(el, 22)
    el.label, el.valueText = mkText(el, 14), mkText(el, 14)
    el.chev1, el.chev2 = mkLine(el, 25), mkLine(el, 25)
    el.popupBg, el.popupBorder = mkSq(el, 100), mkSq(el, 101)
    el.scrollTrack, el.scrollThumb = mkSq(el, 101), mkSq(el, 102)
    el.maxVisible = cfg.MaxVisible
    el.scroll = 0
    el.optTexts, el.selCells = {}, {}
    table.insert(self.elements, el)
    table.insert(popupElements, el)
    register(id, el, Library.Dropdowns)
    return el
end
function Groupbox:AddInput(id, cfg)
    cfg = cfg or {}
    local el = newElement(Input, id, cfg.Text or id)
    el.value = tostring(cfg.Default or "")
    el.placeholder = cfg.Placeholder
    if cfg.Callback then table.insert(el.changed, cfg.Callback) end
    el.bg, el.border = mkSq(el, 20), mkSq(el, 22)
    el.label, el.valueText = mkText(el, 14), mkText(el, 14)
    el.caret = mkLine(el, 25)
    table.insert(self.elements, el)
    register(id, el, nil)
    return el
end
function Groupbox:AddKeyPicker(id, cfg)
    cfg = cfg or {}
    local el = newElement(KeyPicker, id, cfg.Text or id)
    el.vk = keyToVk(cfg.Default or "F") or VK.F
    el.mode = cfg.Mode or "Toggle"
    el.state = false
    el.changedCallback = cfg.ChangedCallback
    el.captureOnly = cfg.CaptureOnly == true
    if cfg.Callback then table.insert(el.changed, cfg.Callback) end
    el.bg, el.border, el.keyText = mkSq(el, 21), mkSq(el, 22), mkText(el, 14)
    el.label = mkText(el, 14)
    el.row = true
    el.modeOpen = false
    table.insert(self.elements, el)
    table.insert(popupElements, el)
    if not el.captureOnly then table.insert(Library.__keybinds, el) end
    register(id, el, Library.KeyPickers)
    return el
end
function Groupbox:AddColorPicker(id, cfg)
    cfg = cfg or {}
    local el = newElement(ColorPicker, id, cfg.Title or id)
    local c = cfg.Default or Theme.accent
    el.alpha = 1 - (cfg.Transparency or 0)
    el.swatch, el.swatchBorder = mkSq(el, 23), mkSq(el, 24)
    el.bg, el.border = mkSq(el, 20), mkSq(el, 22)
    el.label, el.hex = mkText(el, 14), mkText(el, 14)
    el.popupBg, el.popupBorder = mkSq(el, 100), mkSq(el, 101)
    el.svBase = mkSq(el, 99)
    el.hexLabel = mkText(el, 14)
    el.hexBg, el.hexBorder = mkSq(el, 103), mkSq(el, 104)
    el.hexEditing = false
    el.alphaBG, el.alphaSwatch = mkSq(el, 103), mkSq(el, 104)
    zset(el.hexLabel, 107)
    el.h, el.s, el.v = rgbToHsv(c)
    el.value = c
    el.row = true
    if cfg.Callback then table.insert(el.changed, cfg.Callback) end
    table.insert(self.elements, el)
    table.insert(popupElements, el)
    register(id, el, Library.ColorPickers)
    return el
end
function Groupbox:GetHeight(w)
    local h = 6 + 15 + (self.desc and self.desc ~= "" and 16 or 0) + 6
    local lw = w - 12
    for _, el in ipairs(self.elements) do
        if el.visible and not el.destroyed then h = h + el:GetHeight(lw) + 6 end
    end
    return h
end
function Groupbox:Render(x, y, w)
    local h = self:GetHeight(w)
    fill(self.bg, x, y, w, h, Theme.bg, 1, Library.CornerRadius)
    stroke(self.border, x, y, w, h, Theme.outline, 1, Library.CornerRadius, 1)
    text(self.title, x + 10, y + 6, clipText(self.name, 15, w - 20), 15, Theme.text, 1, false, false)
    if self.desc and self.desc ~= "" then
        text(self.descText, x + 10, y + 22, clipText(self.desc, 14, w - 20), 14, Theme.subtext, 1, false, false)
    else
        put(self.descText, "Visible", false)
    end
    local ey = y + 6 + 15 + (self.desc and self.desc ~= "" and 16 or 0) + 6
    for _, el in ipairs(self.elements) do
        if el.visible and not el.destroyed then
            local eh = el:GetHeight(w - 12)
            if el.row and el.RenderRow then
                el:RenderRow(x + 6, ey, w - 12, eh)
            else
                el:Render(x + 6, ey, w - 12)
            end
            ey = ey + eh + 6
        end
    end
    return h
end
function Groupbox:RenderPopups()
    for _, el in ipairs(self.elements) do
        if el.RenderPopup then el:RenderPopup() end
        for _, a in ipairs(el.addons or {}) do
            if a.RenderPopup then a:RenderPopup() end
        end
    end
end
function Groupbox:Show() self.visible = true return self end
function Groupbox:Hide() self.visible = false return self end
function Groupbox:SetVisible(b) self.visible = b ~= false return self end

-- row renderers for standalone KeyPicker/ColorPicker
function KeyPicker:RenderRow(x, y, w)
    local bx, bw = x + w - 74, 68
    self.boxX, self.boxY, self.boxW, self.boxH = bx, y + 3, bw, 15
    fill(self.bg, x, y, w, 21, Theme.main, 1, 2)
    stroke(self.border, x, y, w, 21, Theme.outline, 1, 2, 1)
    if self.label then
        text(self.label, x + 6, vc(y, 21, 14), clipText(self.text, 14, w - 90), 14, Theme.text, 0.85, false, false)
    end
    textC(self.keyText, bx + bw / 2, vc(y + 3, 15, 14), clipText(capturing == self and "[...]" or vkName(self.vk), 14, bw - 6), 14, Theme.subtext, 1, false)
    if not self.captureOnly and hovered(bx, y + 3, bw, 15) and m2.pressed then
        self:OpenModePopup()
    end
    newHit(x, y, w, 21, {
        press = function()
            beginCapture(self)
            self:CloseModePopup()
        end,
    })
end
function ColorPicker:RenderRow(x, y, w)
    fill(self.bg, x, y, w, 21, Theme.main, 1, 2)
    stroke(self.border, x, y, w, 21, Theme.outline, 1, 2, 1)
    local c = self:Color()
    local hex = fmt("#%02X%02X%02X", floor(c.R * 255 + 0.5), floor(c.G * 255 + 0.5), floor(c.B * 255 + 0.5))
    text(self.label, x + 6, vc(y, 21, 14), clipText(self.text, 14, w - 96), 14, Theme.text, 0.85, false, false)
    text(self.hex, x + w - 84, vc(y, 21, 14), hex, 14, Theme.subtext, 1, false, false)
    fill(self.swatch, x + w - 24, y + 3, 18, 18, c, self.alpha or 1, 2)
    stroke(self.swatchBorder, x + w - 24, y + 3, 18, 18, Theme.outline, 1, 2, 1)
    newHit(x, y, w, 21, { press = function() if self.popupOpen then self:ClosePopup() else self:OpenPopup() end end })
    self.hx, self.hy, self.hw = x + w - 24, y + 3, 18
end
Toggle.RenderRow = nil
Slider.RenderRow = nil

local Tab = {}
Tab.__index = Tab
function Tab:AddGroupbox(a, b)
    local cfg = type(a) == "table" and a or { Side = a, Name = b }
    local side = cfg.Side
    if side == nil then side = "Left" end
    if type(side) == "string" then side = side:lower() == "right" and "Right" or "Left" end
    if side == 2 then side = "Right" elseif side == 1 then side = "Left" end
    local gb = setmetatable({}, Groupbox)
    gb.name = cfg.Name or "Groupbox"
    gb.desc = cfg.Description
    gb.side = side
    gb.visible = cfg.Visible ~= false
    gb.elements = {}
    gb.bg = newObj("Square", 10)
    gb.border = newObj("Square", 11)
    gb.title = newObj("Text", 12)
    gb.title.d.Size = 15
    gb.descText = newObj("Text", 12)
    gb.descText.d.Size = 14
    table.insert(self.groups, gb)
    return gb
end
function Tab:AddLeftGroupbox(name, cfg)
    cfg = cfg or {} cfg.Name = name cfg.Side = "Left"
    return self:AddGroupbox(cfg)
end
function Tab:AddRightGroupbox(name, cfg)
    cfg = cfg or {} cfg.Name = name cfg.Side = "Right"
    return self:AddGroupbox(cfg)
end
function Tab:Render(x, y, w)
    local colW = w / 2 - 3
    local ly, ry = y, y
    for _, g in ipairs(self.groups) do
        if g.visible then
            if g.side == "Left" then ly = ly + g:Render(x, ly, colW) + 6
            else ry = ry + g:Render(x + colW + 6, ry, colW) + 6 end
        end
    end
end
function Tab:Hide()
    local function hideObj(o)
        o.sc.Visible = false
        o.d.Visible = false
    end
    for _, g in ipairs(self.groups) do
        hideObj(g.bg)
        hideObj(g.border)
        hideObj(g.title)
        hideObj(g.descText)
        for _, el in ipairs(g.elements) do
            for _, o in ipairs(el.objects) do hideObj(o) end
            for _, a in ipairs(el.addons or {}) do
                for _, o in ipairs(a.objects) do hideObj(o) end
            end
        end
    end
end
function Tab:SetVisible(b) self.visible = b ~= false return self end
function Tab:SetName(n) self.name = n return self end

-- Window --------------------------------------------------------------------
local Window = {}
Window.__index = Window
function Window:AddTab(a, icon, desc)
    local cfg = type(a) == "table" and a or { Name = a, Icon = icon, Description = desc }
    local tab = setmetatable({}, Tab)
    tab.window = self
    tab.name = cfg.Name or "Tab"
    tab.icon = cfg.Icon
    tab.description = cfg.Description
    tab.groups = {}
    tab.visible = true
    tab.sel = newObj("Square", 6)
    tab.indicator = newObj("Square", 7)
    tab.label = newObj("Text", 8)
    tab.label.d.Size = 16
    table.insert(self.tabs, tab)
    if not self.activeTab then self.activeTab = tab end
    return tab
end
function Window:SetTitle(t) self.title = tostring(t) return self end
function Window:ChangeTitle(t) return self:SetTitle(t) end
function Window:SetFooter(t) self.footer = tostring(t) return self end
function Window:Toggle(force)
    local v = force
    if v == nil then v = not self.visible end
    self.visible = v and true or false
    if not self.visible then
        hideAll()
        clearPopup()
        focusedInput = nil
        capturing = nil
    end
    pcall(setrobloxinput, true)
    return self
end
function Window:Open() return self:Toggle(true) end
function Window:Close() return self:Toggle(false) end
function Window:SetPos(px, py)
    local cam = workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
    self.x = clamp(px, -self.w + 80, vp.X - 80)
    self.y = clamp(py, 0, vp.Y - 40)
    return self
end
function Window:SetSize(w, h)
    self.w, self.h = w, h
    self.sideW = floor(w * 0.3 + 0.5)
    return self
end
function Window:Center()
    local cam = workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
    self:SetPos((vp.X - self.w) / 2, (vp.Y - self.h) / 2)
    return self
end
function Window:Render()
    local x, y, w, h = self.x, self.y, self.w, self.h
    local titleH = self.titleH
    local sideW = self.sideW
    fill(self.shadow, x - 3, y - 3, w + 6, h + 8, Theme.dark, 0.22, Library.CornerRadius + 4)
    fill(self.bg, x, y, w, h, Theme.bg, 1, Library.CornerRadius)
    stroke(self.border, x, y, w, h, Theme.outline, 1, Library.CornerRadius, 1)
    fill(self.hline, x + sideW, y + titleH, w - sideW, 1, Theme.outline, 1, 0)
    fill(self.vline, x + sideW, y + titleH, 1, h - titleH, Theme.outline, 1, 0)
    local lg = LogoImage or ensureLogo()
    local acc, bgc = Theme.accent, Theme.bg
    local lkey = floor(acc.R * 255) .. "," .. floor(acc.G * 255) .. "," .. floor(acc.B * 255)
        .. "|" .. floor(bgc.R * 255) .. "," .. floor(bgc.G * 255) .. "," .. floor(bgc.B * 255)
    if LogoKey ~= lkey then
        LogoKey = lkey
        lg.d.Data = buildLogoBmp(48, bgc, acc)
    end
    lg.d.Position = Vector2.new(x + 10, y + (titleH - 24) / 2)
    lg.d.Size = Vector2.new(24, 24)
    put(lg, "Visible", true)
    text(self.titleText, x + 40, vc(y, titleH, 15), clipText(self.title, 15, w - 88), 15, Theme.text, 1, false, false)
    put(self.footerText, "Visible", false)
    local cbx, cby = x + w - 20, vc(y, titleH, 8)
    local chv = hovered(cbx - 4, cby - 4, 20, 16)
    line(self.close1, cbx, cby, cbx + 8, cby + 8, chv and Theme.danger or Theme.subtext, 1, 1)
    line(self.close2, cbx + 8, cby, cbx, cby + 8, chv and Theme.danger or Theme.subtext, 1, 1)
    newHit(cbx - 6, cby - 6, 22, 20, { press = function() self:Toggle(false) end })

    local ty = y + titleH
    for _, tab in ipairs(self.tabs) do
        if tab.visible then
            local th = 40
            local active = (self.activeTab == tab)
            local hv = hovered(x, ty, sideW, th)
            if active then
                fill(tab.sel, x, ty, sideW, th, mix(Theme.bg, Theme.accent, 0.10), 1, 0)
                fill(tab.indicator, x, ty, 2, th, Theme.accent, 1, 0)
            elseif hv then
                fill(tab.sel, x, ty, sideW, th, Theme.main, 0.5, 0)
                put(tab.indicator, "Visible", false)
            else
                put(tab.sel, "Visible", false)
                put(tab.indicator, "Visible", false)
            end
            text(tab.label, x + 30, ty + 11, clipText(tab.name, 16, sideW - 38), 16, active and Theme.text or Theme.subtext, active and 1 or 0.55, false, false)
            newHit(x, ty, sideW, th, {
                press = function()
                    if self.activeTab ~= tab then
                        if self.activeTab then self.activeTab:Hide() end
                        self.activeTab = tab
                        clearPopup()
                    end
                end,
            })
            ty = ty + th
        end
    end

    local cx, cy = x + sideW + 4, y + titleH + 4
    local cw, ch = w - sideW - 8, h - titleH - 8
    if self.activeTab then
        self.activeTab:Render(cx, cy, cw)
    end

    newHit(x, y, w - 28, titleH, {
        press = function(px, py) self.dragOff = { px - x, py - y } end,
        drag = function(px, py)
            if self.dragOff then self:SetPos(px - self.dragOff[1], py - self.dragOff[2]) end
        end,
        release = function() self.dragOff = nil end,
    })
    newHit(x + w - 16, y + h - 16, 16, 16, {
        press = function(px, py) self.sizeOff = { w - (px - x), h - (py - y) } end,
        drag = function(px, py)
            if self.sizeOff then
                self:SetSize(max(480, px - x + self.sizeOff[1]), max(360, py - y + self.sizeOff[2]))
            end
        end,
        release = function() self.sizeOff = nil end,
    })
end

Library.__keybinds = {}

function Library:BuildNotificationSettings(Tab)
    local opts = Library.NotificationOptions
    local group = Tab:AddGroupbox({ Side = "Left", Name = "Notifications" })
    group:AddToggle("Notify_Enabled", {
        Text = "Enable notifications",
        Default = opts.Enabled,
        Callback = function(v)
            Library.NotificationOptions.Enabled = v
        end,
    })
    group:AddSlider("Notify_Duration", {
        Text = "Duration",
        Default = opts.Duration,
        Min = 1, Max = 20, Rounding = 0.5, Suffix = "s",
        Callback = function(v)
            Library.NotificationOptions.Duration = v
            for _, n in ipairs(notifs) do n.dur = v end
        end,
    })
    group:AddSlider("Notify_Fade", {
        Text = "Fade time",
        Default = opts.Fade,
        Min = 0, Max = 2, Rounding = 0.05, Suffix = "s",
        Callback = function(v) Library.NotificationOptions.Fade = v end,
    })
    group:AddSlider("Notify_Width", {
        Text = "Width",
        Default = opts.Width,
        Min = 180, Max = 420, Rounding = 1, Suffix = "px",
        Callback = function(v) Library.NotificationOptions.Width = v end,
    })
    group:AddSlider("Notify_Max", {
        Text = "Max visible",
        Default = opts.MaxVisible,
        Min = 1, Max = 10, Rounding = 1,
        Callback = function(v)
            Library.NotificationOptions.MaxVisible = v
            while #notifs > v do removeNotif(table.remove(notifs)) end
        end,
    })
    group:AddSlider("Notify_OffsetY", {
        Text = "Top offset",
        Default = opts.OffsetY,
        Min = 0, Max = 200, Rounding = 1, Suffix = "px",
        Callback = function(v) Library.NotificationOptions.OffsetY = v end,
    })
    group:AddDropdown("Notify_Side", {
        Text = "Side",
        Values = { "Right", "Left" },
        Default = Library.NotifySide,
        Callback = function(v) Library.NotifySide = v end,
    })
    group:AddToggle("Notify_UseCall", {
        Text = "Per-call duration",
        Default = opts.UseCallDuration,
        Callback = function(v) Library.NotificationOptions.UseCallDuration = v end,
    })
    group:AddButton({
        Text = "Test Notification",
        Func = function() Library:Notify("This is a test notification.", nil, "Test") end,
    })
    group:AddButton({
        Text = "Preview (ignores Enabled)",
        Func = function() Library:PreviewNotification() end,
    })
    group:AddButton({
        Text = "Clear Notifications",
        Func = function() Library:ClearNotifications() end,
    })
    group:AddButton({
        Text = "Reset Defaults",
        Func = function()
            local function set(id, v)
                local el = Library.Options[id]
                if el then el:SetValue(v) end
            end
            set("Notify_Enabled", true)
            set("Notify_Duration", 4)
            set("Notify_Fade", 0.35)
            set("Notify_Width", 260)
            set("Notify_Max", 6)
            set("Notify_OffsetY", 16)
            set("Notify_UseCall", false)
            local side = Library.Options.Notify_Side
            if side then side:SetValue("Right") end
            Library.NotifySide = "Right"
        end,
    })
    return group
end

function Library:CreateWindow(cfg)
    cfg = cfg or {}
    if cfg.Accent then Theme.accent = cfg.Accent end
    if cfg.CornerRadius then Library.CornerRadius = cfg.CornerRadius end
    local win = setmetatable({}, Window)
    win.title = cfg.Title or "No Title"
    win.footer = cfg.Footer or ""
    win.w = cfg.Width or 720
    win.h = cfg.Height or 600
    win.titleH = 36
    win.sideW = floor(win.w * 0.3 + 0.5)
    win.x, win.y = 100, 100
    win.tabs, win.activeTab = {}, nil
    win.visible = cfg.AutoShow ~= false
    win.bg = newObj("Square", 2)
    win.border = newObj("Square", 3)
    win.shadow = newObj("Square", 1)
    win.hline = newObj("Square", 4)
    win.vline = newObj("Square", 4)
    win.titleText = newObj("Text", 6)
    win.titleText.d.Size = 15
    win.footerText = newObj("Text", 6)
    win.footerText.d.Size = 14
    win.close1 = newObj("Line", 7)
    win.close2 = newObj("Line", 7)
    table.insert(Windows, win)
    if cfg.Center ~= false then win:Center() end
    if cfg.ToggleKeybind then
        local vk = keyToVk(cfg.ToggleKeybind)
        if vk then menuVk = vk end
    end
    Library.NotifySide = cfg.NotifySide or "Right"
    pcall(setrobloxinput, true)
    return win
end

-- Render loop ---------------------------------------------------------------
local stopped = false
local function resolveRS()
    local rs = hostGet("RunService") or RS
    if not rs then pcall(function() rs = game:GetService("RunService") end) end
    if not rs then pcall(function() rs = game.RunService end) end
    return rs
end
local function trySignal(sig, cb)
    if not sig then return nil end
    local ok, conn = pcall(function() return sig:Connect(cb) end)
    if ok and conn then return conn end
    local ok2, conn2 = pcall(function() return sig.Connect(sig, cb) end)
    if ok2 and conn2 then return conn2 end
    return nil
end
local function connectRender(cb)
    local rs = resolveRS()
    if rs then
        for _, name in ipairs({ "RenderStepped", "Heartbeat", "Stepped" }) do
            local sig
            pcall(function() sig = rs[name] end)
            local conn = trySignal(sig, cb)
            if conn then return conn, name end
        end
    end
    local alive = true
    local conn = { Disconnect = function() alive = false end }
    task.spawn(function()
        while alive and not stopped do cb(0) task.wait(1 / 60) end
    end)
    return conn, "poll"
end

local function win0Text()
    local win = Windows[1]
    return fmt("%s  |  %d fps", win and win.title or "Swangy", fps)
end

local function tickLoop()
    if stopped then return end
    local ok, err = pcall(function()
        poll()
        frameCount = frameCount + 1
        if clock() - fpsClock >= 0.5 then
            fps = floor(frameCount / (clock() - fpsClock) + 0.5)
            frameCount, fpsClock = 0, clock()
        end
        if capturing then
            for _, code in ipairs(ALL_KEYS) do
                if keyEdge(code) then
                    capturing:Capture(code)
                    break
                end
            end
        end
        if focusedInput == nil and not capturing and isrbxactive() and keyEdge(menuVk) then
            local win = Windows[1]
            if win then win:Toggle() end
        end
        for _, kb in ipairs(Library.__keybinds) do
            if not capturing and kb.visible and not kb.destroyed then kb:Evaluate() end
        end
        if focusedInput and not capturing then
            for _, code in ipairs(INPUT_CODES) do
                if keyEdge(code) then focusedInput:Key(code) end
            end
        end
        hitList = {}
        local anyVisible = false
        for _, win in ipairs(Windows) do
            if win.visible then anyVisible = true win:Render() end
        end
        if anyVisible then
            local win = Windows[1]
            if win and win.activeTab then
                for _, g in ipairs(win.activeTab.groups) do g:RenderPopups() end
            end
        end
        Library.__hits = hitList
        processInput()
        if watermarkOn then
            local wm = Library.__wm
            if not wm then
                wm = { bg = D.new("Square"), txt = D.new("Text") }
                wm.bg.Filled, wm.bg.Corner = true, 2
                wm.txt.Size = 14
                pcall(function() wm.txt.Font = FONT wm.bg.ZIndex = 200 wm.txt.ZIndex = 201 end)
                Library.__wm = wm
            end
            local s = win0Text()
            wm.bg.Position, wm.bg.Size = Vector2.new(10, 10), Vector2.new(textW(s, 14) + 16, 22)
            wm.bg.Color, wm.bg.Transparency, wm.bg.Visible = Theme.main, 0.9, true
            wm.txt.Position, wm.txt.Text, wm.txt.Color, wm.txt.Visible = Vector2.new(18, 13), s, Theme.text, true
        elseif Library.__wm then
            Library.__wm.bg.Visible, Library.__wm.txt.Visible = false, false
        end
        renderNotifs()
    end)
    if not ok then
        local msg = tostring(err)
        _G.__swangy_err = msg
        if _G.__swangy_lastwarn ~= msg then
            _G.__swangy_lastwarn = msg
            warn("[Swangy] frame error: " .. msg)
        end
    end
    _G.__swangy_frames = (_G.__swangy_frames or 0) + 1
end

local uiConn, uiSignal
local connOk, connRes, connName = pcall(connectRender, tickLoop)
if connOk then uiConn, uiSignal = connRes, connName
else uiConn = { Disconnect = function() end } end
Library.RenderSignal = uiSignal

function Library:Unload()
    stopped = true
    focusedInput = nil
    capturing = nil
    pcall(function() uiConn:Disconnect() end)
    for _, o in ipairs(ALL) do pcall(function() o.d:Remove() end) end
    for _, n in ipairs(notifs) do
        removeDrawings({ { d = n.bg }, { d = n.bar }, { d = n.tt }, { d = n.mt } })
    end
    notifs = {}
    if Library.__wm then
        pcall(function() Library.__wm.bg:Remove() end)
        pcall(function() Library.__wm.txt:Remove() end)
        Library.__wm = nil
    end
    pcall(function() MEAS:Remove() end)
end

return Library
