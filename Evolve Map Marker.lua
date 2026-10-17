script_author("Impressive")
script_name('Evolve Map Marker')
local se = require 'samp.events'
local vkeys = require 'vkeys'
local inicfg = require 'inicfg'
local ffi = require 'ffi'
local imgui = require 'mimgui'
local encoding = require 'encoding'
local dlstatus = require('moonloader').download_status

encoding.default = 'CP1251'
local u8 = encoding.UTF8

ffi.cdef[[
    int MultiByteToWideChar(unsigned int CodePage, unsigned long dwFlags, const char* lpMultiByteStr, int cbMultiByte, unsigned short* lpWideCharStr, int cchWideChar);
    void* GlobalAlloc(unsigned int uFlags, size_t dwBytes);
    void* GlobalLock(void* hMem);
    int GlobalUnlock(void* hMem);
    int OpenClipboard(void* hWndNewOwner);
    int CloseClipboard(void);
    int EmptyClipboard(void);
    void* SetClipboardData(unsigned int uFormat, void* hMem);
]]

local directIni = "Evolve-MapMarker.ini"
local iniData = inicfg.load({
    main = {
        enabled = true,
        clickmark = true,
        markmode = 1,
        waypointcopy = false,
        waypointmsg = true,
        screenmarker = true,
        markersize = 100,
        acceptown = false,
        listmode = 1,
        whitelist = "",
        blacklist = ""
    },
    commands = {
        markmenu = "mapmarker",
        fkv = "fkv",
        mkv = "mkv",
        mykv = "mykv",
        mark = "mark",
        markdell = "markdell"
    }
}, directIni)

iniData.commands = iniData.commands or {}
iniData.commands.mapmarker = nil
if iniData.commands.markmenu == nil or iniData.commands.markmenu == "markmenu" then
    iniData.commands.markmenu = "mapmarker"
end

if iniData.main.screenmarker == nil then
    iniData.main.screenmarker = true
end

iniData.main.markersize = math.floor(math.max(50, math.min(200, tonumber(iniData.main.markersize) or 100)))

inicfg.save(iniData, directIni)

local function splitList(s)
    local t = {}
    for n in tostring(s or ""):gmatch("[^,]+") do
        t[#t + 1] = n
    end
    return t
end

if iniData.main.listmode ~= 1 and iniData.main.listmode ~= 2 then
    iniData.main.listmode = 1
end

local whitelist = splitList(iniData.main.whitelist)
local blacklist = splitList(iniData.main.blacklist)

local function saveCfg()
    iniData.main.whitelist = table.concat(whitelist, ",")
    iniData.main.blacklist = table.concat(blacklist, ",")
    inicfg.save(iniData, directIni)
end

local MAP_SIZE = 6000
local GRID_STAGES = 24
local SQUARE_SIZE = MAP_SIZE / GRID_STAGES

local letters = {
    "\xC0", "\xC1", "\xC2", "\xC3", "\xC4", "\xC5", "\xC6", "\xC7", "\xC8", "\xCA",
    "\xCB", "\xCC", "\xCD", "\xCE", "\xCF", "\xD0", "\xD1", "\xD2", "\xD3", "\xD4",
    "\xD5", "\xD6", "\xD7", "\xD8"
}

local letterToRow = {
    ["\xC0"] = 1, ["\xE0"] = 1, ["\xC1"] = 2, ["\xE1"] = 2, ["\xC2"] = 3, ["\xE2"] = 3,
    ["\xC3"] = 4, ["\xE3"] = 4, ["\xC4"] = 5, ["\xE4"] = 5, ["\xC5"] = 6, ["\xE5"] = 6,
    ["\xC6"] = 7, ["\xE6"] = 7, ["\xC7"] = 8, ["\xE7"] = 8, ["\xC8"] = 9, ["\xE8"] = 9,
    ["\xCA"] = 10, ["\xEA"] = 10, ["\xCB"] = 11, ["\xEB"] = 11, ["\xCC"] = 12, ["\xEC"] = 12,
    ["\xCD"] = 13, ["\xED"] = 13, ["\xCE"] = 14, ["\xEE"] = 14, ["\xCF"] = 15, ["\xEF"] = 15,
    ["\xD0"] = 16, ["\xF0"] = 16, ["\xD1"] = 17, ["\xF1"] = 17, ["\xD2"] = 18, ["\xF2"] = 18,
    ["\xD3"] = 19, ["\xF3"] = 19, ["\xD4"] = 20, ["\xF4"] = 20, ["\xD5"] = 21, ["\xF5"] = 21,
    ["\xD6"] = 22, ["\xF6"] = 22, ["\xD7"] = 23, ["\xF7"] = 23, ["\xD8"] = 24, ["\xF8"] = 24
}

local currentBlip = nil
local currentCheckpoint = nil
local pointMarker = nil

local lastWaypoint = nil
local waypointInit = false

local pendingCoords = nil
local activeTarget = nil
local cursorEnabled = false

local SEKTOR_CP1251 = "\xD1\xE5\xEA\xF2\xEE\xF0"

local WAYPOINT_ICON_SIZE = 256
local waypointFont = nil
local WAYPOINT_TEXT_OFFSET = 0.2

local WAYPOINT_FOLDER = "E-CRIME\\Resource\\marker"
local WAYPOINT_FRAME_PREFIX = "marker_"
local WAYPOINT_FRAMES = 6
local WAYPOINT_FPS = 8
local WAYPOINT_URL = "https://raw.githubusercontent.com/impressive-off/evolve-scripts/main/E-CRIME/Resource/marker/"
local WAYPOINT_DOWNLOAD_TIMEOUT = 30
local waypointTextures = {}
local waypointLoaded = false

local BLIP_COLOR = 0xFFFF00FF

local ARROW_SIZE = 16
local ARROW_COLOR = 0xDDFFFFFF
local ARROW_RING_X = 0.42
local ARROW_RING_Y = 0.42
local SCREEN_MARGIN = 20

local cmdDefs = {
    {key = "markmenu",  default = "mapmarker", usage = "",          desc = "Открыть это меню",                                     fn = function(a) cmd_markmenu(a) end},
    {key = "fkv",       default = "fkv",       usage = "[Квадрат]", desc = "Поставить метку на указанный квадрат (пример: А-12)", fn = function(a) cmd_fkv(a) end},
    {key = "mkv",       default = "mkv",       usage = "",          desc = "Показать квадрат вашей метки с карты (ПКМ в ESC)",     fn = function(a) cmd_mkv(a) end},
    {key = "mykv",      default = "mykv",      usage = "",          desc = "Узнать квадрат, в котором вы сейчас находитесь",       fn = function(a) cmd_mykv(a) end},
    {key = "mark",      default = "mark",      usage = "",          desc = "Отправить квадрат, в котором вы сейчас находитесь",    fn = function(a) cmd_mark(a) end},
    {key = "markdell",  default = "markdell",  usage = "",          desc = "Удалить текущую метку/чекпоинт",                       fn = function(a) cmd_markdell(a) end},
}

function cmdName(def)
    local n = tostring(iniData.commands[def.key] or def.default)
    if not n:match("^[%w_]+$") then n = def.default end
    return n
end

function registerAllCommands()
    for _, d in ipairs(cmdDefs) do
        sampRegisterChatCommand(cmdName(d), d.fn)
    end
end

function unregisterAllCommands()
    for _, d in ipairs(cmdDefs) do
        sampUnregisterChatCommand(cmdName(d))
    end
end

local function applyCommandName(def, name)
    if not name:match("^[%w_]+$") then
        sampAddChatMessage("{8A8383}[Map Marker]{FFFFFF} Команда может содержать только латинские буквы, цифры и {8A8383}_{FFFFFF}.", -1)
        return false
    end
    for _, other in ipairs(cmdDefs) do
        if other.key ~= def.key and cmdName(other):lower() == name:lower() then
            sampAddChatMessage("{8A8383}[Map Marker]{FFFFFF} Команда {8A8383}/" .. name .. "{FFFFFF} уже занята другой функцией скрипта.", -1)
            return false
        end
    end
    local old = cmdName(def)
    if old == name then return true end

    sampUnregisterChatCommand(old)
    sampRegisterChatCommand(name, def.fn)
    iniData.commands[def.key] = name
    inicfg.save(iniData, directIni)
    sampAddChatMessage(string.format("{8A8383}[Map Marker]{FFFFFF} Команда изменена: {8A8383}/%s{FFFFFF} -> {8A8383}/%s", old, name), -1)
    return true
end

local ACCENT      = imgui.ImVec4(1.00, 0.78, 0.16, 1.00)
local ACCENT_2    = imgui.ImVec4(1.00, 0.42, 0.18, 1.00)
local ACCENT_HOV  = imgui.ImVec4(1.00, 0.85, 0.35, 1.00)
local ACCENT_ACT  = imgui.ImVec4(0.90, 0.68, 0.10, 1.00)
local TEXT_DARK   = imgui.ImVec4(0.10, 0.10, 0.12, 1.00)
local TEXT_LIGHT  = imgui.ImVec4(0.92, 0.92, 0.95, 1.00)
local TEXT_DIM    = imgui.ImVec4(0.58, 0.58, 0.64, 1.00)
local LINE_COLOR  = imgui.ImVec4(0.16, 0.16, 0.21, 1.00)
local CARD_BG     = imgui.ImVec4(0.085, 0.085, 0.115, 1.00)
local CARD_BORDER = imgui.ImVec4(0.15, 0.15, 0.20, 1.00)
local PILL_BG     = imgui.ImVec4(0.055, 0.055, 0.075, 1.00)
local GREEN       = imgui.ImVec4(0.30, 0.85, 0.50, 1.00)
local RED         = imgui.ImVec4(0.95, 0.32, 0.36, 1.00)

local S  = 1.0
local S0 = 1.0

local function calcScale()
    local sw, sh = getScreenResolution()
    local s = math.min(sh / 1080, sw / 1440)
    return math.max(0.6, math.min(3.0, s))
end

local function sc(v) return v * S end

local ui = {
    window = imgui.new.bool(false),
    enabled = imgui.new.bool(iniData.main.enabled),
    clickmark = imgui.new.bool(iniData.main.clickmark),
    waypointmsg = imgui.new.bool(iniData.main.waypointmsg),
    screenmarker = imgui.new.bool(iniData.main.screenmarker),
    markersize = imgui.new.int(iniData.main.markersize),
    acceptown = imgui.new.bool(iniData.main.acceptown == true),
    waypointcopy = imgui.new.bool(iniData.main.waypointcopy),
    inputWhite = imgui.new.char[32](),
    inputBlack = imgui.new.char[32](),
    cmdBuf = {},
}

for _, d in ipairs(cmdDefs) do
    ui.cmdBuf[d.key] = imgui.new.char[32](cmdName(d))
end

local anim = {}

local function animTo(id, target)
    local cur = anim[id]
    if cur == nil then cur = target end
    local dt = imgui.GetIO().DeltaTime
    cur = cur + (target - cur) * math.min(1, dt * 14)
    if math.abs(target - cur) < 0.002 then cur = target end
    anim[id] = cur
    return cur
end

local function mix(a, b, t)
    return imgui.ImVec4(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t, a.w + (b.w - a.w) * t)
end

local function withAlpha(c, a)
    return imgui.ImVec4(c.x, c.y, c.z, a)
end

local function u32(c)
    return imgui.ColorConvertFloat4ToU32(c)
end

local function lineH()
    return imgui.GetTextLineHeight()
end

local function advanceTo(x0, y)
    imgui.SetCursorPos(imgui.ImVec2(x0, y - imgui.GetStyle().ItemSpacing.y - 1))
    imgui.Dummy(imgui.ImVec2(1, 1))
end

local function padX() return sc(18) end
local function padY() return sc(14) end
local function titleH() return lineH() + sc(16) end
local function rowH() return lineH() * 2 + sc(20) end
local function sliderBlockH() return lineH() + sc(6) + imgui.GetFrameHeight() + sc(18) end
local function cmdRowH() return lineH() + imgui.GetFrameHeight() + sc(24) end
local SEG_H = 42
local function blockH() return lineH() + sc(6) + sc(SEG_H) + sc(16) end

local function addToList(list, raw)
    local name = u8:decode(raw):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return false end

    local id = tonumber(name)
    if id and sampIsPlayerConnected(id) then
        name = sampGetPlayerNickname(id)
    end

    name = name:gsub(",", "")
    for _, v in ipairs(list) do
        if v:lower() == name:lower() then return false end
    end
    list[#list + 1] = name
    return true
end

local function beginCard(id, h, title)
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(padX(), padY()))
    imgui.PushStyleColor(imgui.Col.ChildBg, CARD_BG)
    imgui.PushStyleColor(imgui.Col.Border, CARD_BORDER)
    imgui.BeginChild("##card" .. id, imgui.ImVec2(0, h), true,
        imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)

    local dl = imgui.GetWindowDrawList()
    local x0 = imgui.GetCursorPosX()
    local y0 = imgui.GetCursorPosY()
    local p = imgui.GetCursorScreenPos()
    local w = imgui.GetContentRegionAvail().x
    local lh = lineH()

    dl:AddRectFilled(imgui.ImVec2(p.x, p.y + sc(1)), imgui.ImVec2(p.x + sc(4), p.y + lh - sc(1)), u32(ACCENT), sc(2))
    imgui.SetCursorPos(imgui.ImVec2(x0 + sc(12), y0))
    imgui.TextColored(TEXT_LIGHT, u8(title))
    dl:AddLine(imgui.ImVec2(p.x, p.y + lh + sc(8)), imgui.ImVec2(p.x + w, p.y + lh + sc(8)), u32(LINE_COLOR), 1)
    advanceTo(x0, y0 + titleH())
end

local function endCard()
    imgui.EndChild()
    imgui.PopStyleColor(2)
    imgui.PopStyleVar()
end

local function cardHeight(contentH)
    return padY() * 2 + titleH() + contentH
end

local function drawSwitch(dl, x, y, w, h, t, hov)
    local bg = mix(imgui.ImVec4(0.22, 0.22, 0.28, 1.00), ACCENT, t)
    if hov then bg = mix(bg, imgui.ImVec4(1, 1, 1, 1), 0.10) end

    if t > 0.01 then
        dl:AddRectFilled(imgui.ImVec2(x - sc(2), y - sc(2)), imgui.ImVec2(x + w + sc(2), y + h + sc(2)),
            u32(withAlpha(ACCENT, 0.18 * t)), (h + sc(4)) / 2)
    end
    dl:AddRectFilled(imgui.ImVec2(x, y), imgui.ImVec2(x + w, y + h), u32(bg), h / 2)

    local cx = x + h / 2 + (w - h) * t
    local knob = mix(imgui.ImVec4(0.85, 0.85, 0.90, 1.00), TEXT_DARK, t)
    dl:AddCircleFilled(imgui.ImVec2(cx, y + h / 2), h / 2 - sc(3), u32(knob))
end

local function settingRow(id, title, desc, v, last)
    local dl = imgui.GetWindowDrawList()
    local x0 = imgui.GetCursorPosX()
    local y0 = imgui.GetCursorPosY()
    local availW = imgui.GetContentRegionAvail().x
    local rh = rowH()
    local lh = lineH()
    local sw_, sh_ = sc(44), sc(24)
    local p = imgui.GetCursorScreenPos()

    imgui.InvisibleButton("##row" .. id, imgui.ImVec2(availW, rh))
    local hov = imgui.IsItemHovered()
    local clicked = imgui.IsItemClicked()
    if clicked then v[0] = not v[0] end

    if hov then
        dl:AddRectFilled(imgui.ImVec2(p.x - sc(8), p.y + sc(2)), imgui.ImVec2(p.x + availW + sc(8), p.y + rh - sc(2)),
            u32(imgui.ImVec4(1, 1, 1, 0.04)), sc(8))
    end

    imgui.SetCursorPos(imgui.ImVec2(x0, y0 + sc(9)))
    imgui.Text(u8(title))
    imgui.SetCursorPos(imgui.ImVec2(x0, y0 + sc(9) + lh + sc(2)))
    imgui.PushStyleColor(imgui.Col.Text, TEXT_DIM)
    imgui.Text(u8(desc))
    imgui.PopStyleColor()

    local t = animTo("sw" .. id, v[0] and 1 or 0)
    drawSwitch(dl, p.x + availW - sw_, p.y + (rh - sh_) / 2, sw_, sh_, t, hov)

    if not last then
        dl:AddLine(imgui.ImVec2(p.x, p.y + rh - 1), imgui.ImVec2(p.x + availW, p.y + rh - 1), u32(LINE_COLOR), 1)
    end

    advanceTo(x0, y0 + rh)
    return clicked
end

local function segmented(id, options, tbl, key, onChange)
    local n = #options
    local dl = imgui.GetWindowDrawList()
    local p = imgui.GetCursorScreenPos()
    local totalW = imgui.GetContentRegionAvail().x
    local h = sc(SEG_H)
    local inset = sc(4)
    local gap = sc(4)
    local bw = (totalW - inset * 2 - gap * (n - 1)) / n
    local bh = h - inset * 2

    local pos = animTo("seg" .. id, tbl[key] - 1)

    dl:AddRectFilled(p, imgui.ImVec2(p.x + totalW, p.y + h), u32(PILL_BG), sc(11))

    local px = p.x + inset + pos * (bw + gap)
    dl:AddRectFilled(imgui.ImVec2(px - sc(1), p.y + inset - sc(1)), imgui.ImVec2(px + bw + sc(1), p.y + inset + bh + sc(1)),
        u32(withAlpha(ACCENT, 0.20)), sc(9))
    dl:AddRectFilled(imgui.ImVec2(px, p.y + inset), imgui.ImVec2(px + bw, p.y + inset + bh), u32(ACCENT), sc(8))

    imgui.SetCursorScreenPos(imgui.ImVec2(p.x + inset, p.y + inset))
    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0, 0, 0, 0))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(1, 1, 1, 0.05))
    imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(1, 1, 1, 0.09))

    for i, label in ipairs(options) do
        if i > 1 then imgui.SameLine(0, gap) end
        local near = 1 - math.min(1, math.abs((i - 1) - pos))
        imgui.PushStyleColor(imgui.Col.Text, mix(imgui.ImVec4(0.78, 0.78, 0.84, 1.00), TEXT_DARK, near))
        if imgui.Button(u8(label) .. "##" .. id .. i, imgui.ImVec2(bw, bh)) then
            tbl[key] = i
            if onChange then onChange() end
        end
        imgui.PopStyleColor()
    end
    imgui.PopStyleColor(3)
end

local function segBlock(label, id, options, tbl, key, onChange)
    local x0 = imgui.GetCursorPosX()
    local y0 = imgui.GetCursorPosY()

    imgui.SetCursorPos(imgui.ImVec2(x0, y0))
    imgui.PushStyleColor(imgui.Col.Text, TEXT_DIM)
    imgui.Text(u8(label))
    imgui.PopStyleColor()

    imgui.SetCursorPos(imgui.ImVec2(x0, y0 + lineH() + sc(6)))
    segmented(id, options, tbl, key, onChange)
    advanceTo(x0, y0 + blockH())
end

local function drawList(title, list, buf, id)
    imgui.Text(u8(title))

    local avail = imgui.GetContentRegionAvail().x
    local btnW = sc(86)
    imgui.PushItemWidth(avail - btnW - imgui.GetStyle().ItemSpacing.x)
    local inputPos = imgui.GetCursorScreenPos()
    local enter = imgui.InputText("##in" .. id, buf, ffi.sizeof(buf), imgui.InputTextFlags.EnterReturnsTrue)
    if ffi.string(buf) == "" and not imgui.IsItemActive() then
        local fp = imgui.GetStyle().FramePadding
        imgui.GetWindowDrawList():AddText(imgui.ImVec2(inputPos.x + fp.x, inputPos.y + fp.y), u32(withAlpha(TEXT_DIM, 0.6)), u8"Nick_Name или ID")
    end
    imgui.PopItemWidth()
    imgui.SameLine()
    imgui.PushStyleColor(imgui.Col.Button, ACCENT)
    imgui.PushStyleColor(imgui.Col.ButtonHovered, ACCENT_HOV)
    imgui.PushStyleColor(imgui.Col.ButtonActive, ACCENT_ACT)
    imgui.PushStyleColor(imgui.Col.Text, TEXT_DARK)
    local click = imgui.Button(u8"Добавить##" .. id, imgui.ImVec2(btnW, 0))
    imgui.PopStyleColor(4)
	
    if enter or click then
        if addToList(list, ffi.string(buf)) then
            ffi.fill(buf, ffi.sizeof(buf))
            saveCfg()
        end
    end

    local h = math.max(sc(90), imgui.GetContentRegionAvail().y - sc(2))
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(sc(10), sc(8)))
    imgui.PushStyleColor(imgui.Col.ChildBg, PILL_BG)
    imgui.BeginChild("##child" .. id, imgui.ImVec2(0, h), true)
    local remove = nil
    if #list == 0 then
        imgui.PushStyleColor(imgui.Col.Text, TEXT_DIM)
        imgui.Text(u8"Список пуст")
        imgui.PopStyleColor()
    end
    for i, name in ipairs(list) do
        imgui.AlignTextToFramePadding()
        imgui.Text(u8(name))
        imgui.SameLine(imgui.GetWindowWidth() - sc(46))
        if imgui.SmallButton("X##" .. id .. i) then remove = i end
    end
    if remove then
        table.remove(list, remove)
        saveCfg()
    end
    imgui.EndChild()
    imgui.PopStyleColor()
    imgui.PopStyleVar()
end

local function drawCommandRow(def, last)
    local buf = ui.cmdBuf[def.key]
    local x0 = imgui.GetCursorPosX()
    local y0 = imgui.GetCursorPosY()
    local availW = imgui.GetContentRegionAvail().x
    local rh = cmdRowH()

    imgui.SetCursorPos(imgui.ImVec2(x0, y0 + sc(9)))
    imgui.Text(u8(def.desc))
    if def.usage ~= "" then
        imgui.SameLine(0, sc(8))
        imgui.PushStyleColor(imgui.Col.Text, TEXT_DIM)
        imgui.Text(u8(def.usage))
        imgui.PopStyleColor()
    end

    imgui.SetCursorPos(imgui.ImVec2(x0, y0 + sc(9) + lineH() + sc(6)))
    imgui.AlignTextToFramePadding()
    imgui.TextColored(ACCENT, "/")
    imgui.SameLine(0, sc(4))
    imgui.PushItemWidth(sc(190))
    local enter = imgui.InputText("##cmd" .. def.key, buf, ffi.sizeof(buf), imgui.InputTextFlags.EnterReturnsTrue)
    imgui.PopItemWidth()
    imgui.SameLine()
    local apply = imgui.Button(u8"Применить##" .. def.key, imgui.ImVec2(sc(110), 0))
    imgui.SameLine()
    local reset = imgui.Button(u8"Сброс##" .. def.key, imgui.ImVec2(sc(80), 0))

    if enter or apply then
        local name = u8:decode(ffi.string(buf)):gsub("^/", ""):gsub("%s+", "")
        if not applyCommandName(def, name) then
            ffi.fill(buf, ffi.sizeof(buf))
            ffi.copy(buf, cmdName(def))
        end
    elseif reset then
        applyCommandName(def, def.default)
        ffi.fill(buf, ffi.sizeof(buf))
        ffi.copy(buf, cmdName(def))
    end

    if not last then
        local dl = imgui.GetWindowDrawList()
        imgui.SetCursorPos(imgui.ImVec2(x0, y0 + rh - 1))
        local p = imgui.GetCursorScreenPos()
        dl:AddLine(imgui.ImVec2(p.x, p.y), imgui.ImVec2(p.x + availW, p.y), u32(LINE_COLOR), 1)
    end

    advanceTo(x0, y0 + rh)
end

local sizeDirty = false

local function drawSizeSlider()
    local dl = imgui.GetWindowDrawList()
    local x0 = imgui.GetCursorPosX()
    local y0 = imgui.GetCursorPosY()
    local availW = imgui.GetContentRegionAvail().x
    local bh = sliderBlockH()
    local p = imgui.GetCursorScreenPos()

    imgui.SetCursorPos(imgui.ImVec2(x0, y0 + sc(2)))
    imgui.PushStyleColor(imgui.Col.Text, TEXT_DIM)
    imgui.Text(u8"Размер метки")
    imgui.PopStyleColor()

    imgui.SetCursorPos(imgui.ImVec2(x0, y0 + sc(2) + lineH() + sc(6)))
    imgui.PushItemWidth(availW)
    imgui.PushStyleColor(imgui.Col.SliderGrab, ACCENT)
    imgui.PushStyleColor(imgui.Col.SliderGrabActive, ACCENT_HOV)
    imgui.PushStyleColor(imgui.Col.FrameBg, PILL_BG)
    imgui.PushStyleColor(imgui.Col.FrameBgHovered, imgui.ImVec4(0.09, 0.09, 0.12, 1.00))
    imgui.PushStyleColor(imgui.Col.FrameBgActive, imgui.ImVec4(0.11, 0.11, 0.15, 1.00))
    if imgui.SliderInt("##markersize", ui.markersize, 50, 200, "%d%%") then
        iniData.main.markersize = ui.markersize[0]
        sizeDirty = true
    end
    imgui.PopStyleColor(5)
    imgui.PopItemWidth()

    if sizeDirty and not imgui.IsItemActive() then
        sizeDirty = false
        saveCfg()
    end

    dl:AddLine(imgui.ImVec2(p.x, p.y + bh - 1), imgui.ImVec2(p.x + availW, p.y + bh - 1), u32(LINE_COLOR), 1)
    advanceTo(x0, y0 + bh)
end

local function applyTheme(scale)
    scale = scale or 1.0
    local style = imgui.GetStyle()
    local c, col = style.Colors, imgui.Col
    local V = imgui.ImVec4

    style.WindowRounding = 16 * scale
    style.ChildRounding = 12 * scale
    style.FrameRounding = 9 * scale
    style.PopupRounding = 10 * scale
    style.GrabRounding = 9 * scale
    style.ScrollbarRounding = 8 * scale
    style.WindowPadding = imgui.ImVec2(18 * scale, 18 * scale)
    style.FramePadding = imgui.ImVec2(12 * scale, 7 * scale)
    style.ItemSpacing = imgui.ImVec2(10 * scale, 12 * scale)
    style.ScrollbarSize = 7 * scale
    style.WindowBorderSize = 1
    style.ChildBorderSize = 1
    style.FrameBorderSize = 0

    c[col.Text]                 = V(0.92, 0.92, 0.95, 1.00)
    c[col.TextDisabled]         = V(0.50, 0.50, 0.56, 1.00)
    c[col.WindowBg]             = V(0.045, 0.045, 0.062, 0.98)
    c[col.ChildBg]              = V(0.085, 0.085, 0.115, 1.00)
    c[col.PopupBg]              = V(0.09, 0.09, 0.12, 0.98)
    c[col.Border]               = V(0.17, 0.17, 0.23, 1.00)
    c[col.FrameBg]              = V(0.055, 0.055, 0.075, 1.00)
    c[col.FrameBgHovered]       = V(0.09, 0.09, 0.12, 1.00)
    c[col.FrameBgActive]        = V(0.11, 0.11, 0.15, 1.00)
    c[col.ScrollbarBg]          = V(0.00, 0.00, 0.00, 0.00)
    c[col.ScrollbarGrab]        = V(0.25, 0.25, 0.31, 1.00)
    c[col.ScrollbarGrabHovered] = V(0.35, 0.35, 0.42, 1.00)
    c[col.ScrollbarGrabActive]  = V(1.00, 0.78, 0.16, 1.00)
    c[col.CheckMark]            = V(1.00, 0.78, 0.16, 1.00)
    c[col.Button]               = V(0.15, 0.15, 0.20, 1.00)
    c[col.ButtonHovered]        = V(0.21, 0.21, 0.28, 1.00)
    c[col.ButtonActive]         = V(0.27, 0.27, 0.35, 1.00)
    c[col.Header]               = V(0.17, 0.17, 0.22, 1.00)
    c[col.HeaderHovered]        = V(0.24, 0.24, 0.30, 1.00)
    c[col.HeaderActive]         = V(0.30, 0.30, 0.37, 1.00)
    c[col.Separator]            = V(0.22, 0.22, 0.28, 1.00)
    c[col.TextSelectedBg]       = V(1.00, 0.78, 0.16, 0.30)
end

imgui.OnInitialize(function()
    S0 = calcScale()
    S = S0
    local io = imgui.GetIO()
    io.IniFilename = nil
    io.Fonts:AddFontFromFileTTF(getFolderPath(0x14) .. '\\arial.ttf', 15 * S0, nil, io.Fonts:GetGlyphRangesCyrillic())
    applyTheme(S)
end)

imgui.OnFrame(function() return ui.window[0] end, function()
    local sw, sh = getScreenResolution()

    local ns = calcScale()
    if math.abs(ns - S) > 0.001 then
        S = ns
        applyTheme(S)
    end
    imgui.GetIO().FontGlobalScale = S / S0

    local winW = math.min(sc(620), sw - sc(40))
    local winH = math.min(sc(780), sh - sc(80))

    imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    imgui.SetNextWindowSize(imgui.ImVec2(winW, winH), imgui.Cond.Always)

    local flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoCollapse
                + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar
                + imgui.WindowFlags.NoScrollWithMouse

    if imgui.Begin("Map Marker##main", ui.window, flags) then
        local dl = imgui.GetWindowDrawList()
        local wp = imgui.GetWindowPos()
        local ww = imgui.GetWindowWidth()
        local pad = imgui.GetStyle().WindowPadding
        local hdrH = sc(52)
        local lh = lineH()

        local p1 = imgui.ImVec2(wp.x + pad.x, wp.y + pad.y)
        local p2 = imgui.ImVec2(wp.x + ww - pad.x, wp.y + pad.y + hdrH)

        imgui.SetWindowFontScale(1.6)
        imgui.SetCursorScreenPos(imgui.ImVec2(p1.x, p1.y + (hdrH - lh * 1.6) / 2))
        imgui.TextColored(TEXT_LIGHT, "MAP")
        imgui.SameLine(0, sc(9))
        imgui.TextColored(ACCENT, "MARKER")
        imgui.SetWindowFontScale(1.0)

        local btn = sc(30)
        local bx = p2.x - btn
        local by = p1.y + (hdrH - btn) / 2
        imgui.SetCursorScreenPos(imgui.ImVec2(bx, by))
        imgui.InvisibleButton("##close", imgui.ImVec2(btn, btn))
        local closeHov = imgui.IsItemHovered()
        if imgui.IsItemClicked() then ui.window[0] = false end
        local cc = imgui.ImVec2(bx + btn / 2, by + btn / 2)
        dl:AddCircleFilled(cc, btn / 2, u32(closeHov and imgui.ImVec4(0.85, 0.22, 0.27, 1.00) or imgui.ImVec4(0.14, 0.14, 0.19, 1.00)))
        local r = btn * 0.19
        local xc = u32(closeHov and imgui.ImVec4(1, 1, 1, 1) or imgui.ImVec4(0.75, 0.75, 0.82, 1.00))
        dl:AddLine(imgui.ImVec2(cc.x - r, cc.y - r), imgui.ImVec2(cc.x + r, cc.y + r), xc, sc(2))
        dl:AddLine(imgui.ImVec2(cc.x - r, cc.y + r), imgui.ImVec2(cc.x + r, cc.y - r), xc, sc(2))

        local on = iniData.main.enabled
        local stText = u8(on and "Активен" or "Отключён")
        local stW = imgui.CalcTextSize(stText).x + sc(38)
        local stH = sc(30)
        local sx = bx - sc(10) - stW
        local sy = by
        imgui.SetCursorScreenPos(imgui.ImVec2(sx, sy))
        imgui.InvisibleButton("##status", imgui.ImVec2(stW, stH))
        local stHov = imgui.IsItemHovered()
        if imgui.IsItemClicked() then setEnabled(not iniData.main.enabled) end
        local stCol = on and GREEN or RED
        dl:AddRectFilled(imgui.ImVec2(sx, sy), imgui.ImVec2(sx + stW, sy + stH), u32(withAlpha(stCol, stHov and 0.22 or 0.14)), stH / 2)
        dl:AddCircleFilled(imgui.ImVec2(sx + sc(16), sy + stH / 2), sc(4), u32(stCol))
        dl:AddText(imgui.ImVec2(sx + sc(28), sy + (stH - lh) / 2), u32(stCol), stText)

        local ly = p2.y + sc(8)
        local steps = 56
        local lw = p2.x - p1.x
        for i = 0, steps - 1 do
            local t0 = i / steps
            local c = mix(ACCENT, ACCENT_2, t0)
            c.w = 1 - 0.85 * t0
            dl:AddRectFilled(imgui.ImVec2(p1.x + lw * t0, ly), imgui.ImVec2(p1.x + lw * (i + 1) / steps + 1, ly + sc(3)), u32(c))
        end

        imgui.SetCursorScreenPos(imgui.ImVec2(p1.x, ly + sc(16)))
        imgui.BeginChild("##content", imgui.ImVec2(0, 0), false)

        local rows = 5
        if ui.waypointmsg[0] then rows = 6 end
        local extra = 0
        if ui.screenmarker[0] then extra = sliderBlockH() end
        beginCard("main", cardHeight(rows * rowH() + extra), "Основное")
        if settingRow("enabled", "Работа скрипта", "Полное включение или отключение работы скрипта", ui.enabled, false) then
            setEnabled(ui.enabled[0])
        end
        if settingRow("screenmarker", "Экранная метка", "Иконка над меткой и стрелка-указатель на экране", ui.screenmarker, false) then
            iniData.main.screenmarker = ui.screenmarker[0]
            saveCfg()
        end
        if ui.screenmarker[0] then
            drawSizeSlider()
        end
        if settingRow("acceptown", "Принимать координаты от себя", "Предлагать поставить метку и по вашим сообщениям", ui.acceptown, false) then
            iniData.main.acceptown = ui.acceptown[0]
            saveCfg()
        end
        if settingRow("clickmark", "Клик на колесико мыши", "Вызывает курсор для установки метки", ui.clickmark, false) then
            iniData.main.clickmark = ui.clickmark[0]
            saveCfg()
            if not ui.clickmark[0] then disableCursorMode() end
        end
        if settingRow("wpmsg", "Сообщение о метке с карты", "Писать в чат квадрат метки, поставленной через ESC", ui.waypointmsg, not ui.waypointmsg[0]) then
            iniData.main.waypointmsg = ui.waypointmsg[0]
            saveCfg()
        end
        if ui.waypointmsg[0] then
            if settingRow("wpcopy", "Копировать в буфер обмена", "Копировать координаты метки с карты в буфер", ui.waypointcopy, true) then
                iniData.main.waypointcopy = ui.waypointcopy[0]
                saveCfg()
            end
        end
        endCard()

        beginCard("coords", cardHeight(blockH() * 2 - sc(10)), "Координаты")
        segBlock("Куда отправлять координаты", "send", {"Буфер", "Фракция", "Семья"}, iniData.main, "markmode", saveCfg)
        segBlock("От кого принимать координаты", "recv", {"От всех", "Мой список"}, iniData.main, "listmode", saveCfg)
        endCard()

        beginCard("lists", sc(290), "Списки игроков")
        imgui.Columns(2, "##lists", false)
        drawList("Мой список", whitelist, ui.inputWhite, "w")
        imgui.NextColumn()
        drawList("Игнор-лист", blacklist, ui.inputBlack, "b")
        imgui.Columns(1)
        endCard()

        beginCard("cmds", cardHeight(#cmdDefs * cmdRowH()), "Команды")
        for i, def in ipairs(cmdDefs) do
            drawCommandRow(def, i == #cmdDefs)
        end
        endCard()

        imgui.EndChild()
    end
    imgui.End()
end)

function setClipboardTextUnicode(text)
    local len = ffi.C.MultiByteToWideChar(1251, 0, text, -1, nil, 0)
    if len > 0 then
        local hMem = ffi.C.GlobalAlloc(0x0042, len * 2)
        if hMem ~= nil then
            local pMem = ffi.C.GlobalLock(hMem)
            if pMem ~= nil then
                ffi.C.MultiByteToWideChar(1251, 0, text, -1, ffi.cast("unsigned short*", pMem), len)
                ffi.C.GlobalUnlock(hMem)
                if ffi.C.OpenClipboard(nil) ~= 0 then
                    ffi.C.EmptyClipboard()
                    ffi.C.SetClipboardData(13, hMem)
                    ffi.C.CloseClipboard()
                    return true
                end
            end
        end
    end
    return false
end

local function isValidPng(path)
    local f = io.open(path, "rb")
    if not f then return false end
    local head = f:read(8)
    f:close()
    return head == "\137PNG\r\n\26\n"
end

local function ensureWaypointDirectory()
    local path = getWorkingDirectory()
    for part in WAYPOINT_FOLDER:gmatch("[^\\]+") do
        path = path .. "\\" .. part
        if not doesDirectoryExist(path) then
            createDirectory(path)
        end
    end
    return path
end

function loadWaypointTextures()
    local dir = ensureWaypointDirectory()
    local pending = 0

    local function framePath(i)
        return string.format("%s\\%s%02d.png", dir, WAYPOINT_FRAME_PREFIX, i)
    end

    for i = 1, WAYPOINT_FRAMES do
        local path = framePath(i)
        if doesFileExist(path) and not isValidPng(path) then
            os.remove(path)
        end
        if not doesFileExist(path) then
            pending = pending + 1
            local url = string.format("%s%s%02d.png", WAYPOINT_URL, WAYPOINT_FRAME_PREFIX, i)
            downloadUrlToFile(url, path, function(id, status)
                if status == dlstatus.STATUSEX_ENDDOWNLOAD then
                    pending = pending - 1
                end
            end)
        end
    end

    local started = os.clock()
    while pending > 0 and os.clock() - started < WAYPOINT_DOWNLOAD_TIMEOUT do
        wait(100)
    end

    local missing = false
    for i = 1, WAYPOINT_FRAMES do
        local path = framePath(i)
        if isValidPng(path) then
            waypointTextures[i] = renderLoadTextureFromFile(path)
        else
            if doesFileExist(path) then os.remove(path) end
            missing = true
        end
    end

    if missing then
        sampAddChatMessage("{8A8383}[Map Marker]{FFFFFF} Не удалось получить кадры метки с GitHub, экранная метка не будет отображаться.", -1)
    else
        waypointLoaded = true
    end
end

function releaseWaypointTextures()
    for i = 1, WAYPOINT_FRAMES do
        if waypointTextures[i] then
            renderReleaseTexture(waypointTextures[i])
            waypointTextures[i] = nil
        end
    end
    waypointLoaded = false
end

function main()
    while not isSampAvailable() do wait(100) end

    local font = renderCreateFont("Tahoma", 10, 5)

    waypointFont = renderCreateFont("PricedownBl-Regular", 14)

    registerAllCommands()

    lua_thread.create(loadWaypointTextures)

    while true do
        wait(0)

        if iniData.main.enabled then
            removePointMarker()

            if iniData.main.clickmark and not ui.window[0] then
                if not sampIsChatInputActive() and not sampIsDialogActive() and not isPauseMenuActive() then
                    if wasKeyPressed(vkeys.VK_MBUTTON) then
                        cursorEnabled = not cursorEnabled
                        toggleGameCursor(cursorEnabled)
                        if not cursorEnabled then
                            removePointMarker()
                        end
                    end
                end
            end

            if cursorEnabled then
                if isPauseMenuActive() then
                    disableCursorMode()
                else
                    local mode = sampGetCursorMode()
                    if mode == 0 then
                        toggleGameCursor(true)
                    end

                    local sx, sy = getCursorPos()
                    local sw, sh = getScreenResolution()

                    if sx >= 0 and sy >= 0 and sx < sw and sy < sh then
                        local posX, posY, posZ = convertScreenCoordsToWorld3D(sx, sy, 700.0)
                        local camX, camY, camZ = getActiveCameraCoordinates()
                        local result, colpoint = processLineOfSight(camX, camY, camZ, posX, posY, posZ, true, true, false, true, false, false, false)

                        if result and colpoint.pos then
                            local hX, hY, hZ = colpoint.pos[1], colpoint.pos[2], colpoint.pos[3]
                            local nX, nY, nZ = colpoint.normal[1], colpoint.normal[2], colpoint.normal[3]

                            local pX = hX - nX * 0.1
                            local pY = hY - nY * 0.1
                            local pZ = hZ - nZ * 0.1

                            local zOffset = 300
                            if nZ >= 0.5 then zOffset = 1 end

                            local result2, colpoint2 = processLineOfSight(pX, pY, pZ + zOffset, pX, pY, pZ - 0.3, true, true, false, true, false, false, false)
                            if result2 and colpoint2.pos then
                                local targetX = colpoint2.pos[1]
                                local targetY = colpoint2.pos[2]
                                local targetZ = colpoint2.pos[3] + 1.0

                                createPointMarker(targetX, targetY, targetZ)

                                local curX, curY, curZ = getCharCoordinates(PLAYER_PED)
                                local dist = getDistanceBetweenCoords3d(curX, curY, curZ, targetX, targetY, targetZ)
                                local hoffs = renderGetFontDrawHeight(font)

                                sy = sy - 2
                                sx = sx - 2
                                renderFontDrawText(font, string.format("%.2fm", dist), sx, sy - hoffs, 0xEEEEEEEE)

                                if wasKeyPressed(vkeys.VK_LBUTTON) then
                                    local sector = getSectorFromCoords(targetX, targetY)
                                    disableCursorMode()
                                    handleMarkOutput(sector, targetX, targetY, targetZ)
                                end
                            end
                        end
                    end
                end
            end

            if pendingCoords then
                if os.clock() - pendingCoords.timestamp > 15.0 then
                    sampAddChatMessage("{8A8383}[Map Marker]{FFFFFF} Время действия предложения (15 секунд) истекло.", -1)
                    pendingCoords = nil
                else
                    if not sampIsChatInputActive() and not sampIsDialogActive() and not isPauseMenuActive() then
                        if wasKeyPressed(vkeys.VK_Y) then
                            setMarkers(pendingCoords.x, pendingCoords.y, pendingCoords.z, pendingCoords.sector)
                            sampAddChatMessage(string.format("{8A8383}[Map Marker]{FFFFFF} Метка установлена на сектор: {8A8383}%s{FFFFFF}. {FFFFFF}GPS: {8A8383}%.1f, %.1f, %.1f", pendingCoords.sector, pendingCoords.x, pendingCoords.y, pendingCoords.z), -1)
                            pendingCoords = nil
                        elseif wasKeyPressed(vkeys.VK_N) then
                            sampAddChatMessage("{8A8383}[Map Marker]{FFFFFF} Предложение отменено.", -1)
                            pendingCoords = nil
                        end
                    end
                end
            end

            if activeTarget then
                local px, py, pz = getCharCoordinates(PLAYER_PED)
                local dist = getDistanceBetweenCoords2d(px, py, activeTarget.x, activeTarget.y)

                if dist < 3.0 then
                    sampAddChatMessage(string.format("{8A8383}[Map Marker]{FFFFFF} Вы прибыли на метку. Сектор {8A8383}%s{FFFFFF}. {FFFFFF}GPS: {8A8383}%.1f, %.1f, %.1f{FFFFFF}.", activeTarget.sector, activeTarget.x, activeTarget.y, activeTarget.z), -1)
                    clearMarkers()
                end
            end

            if not isPauseMenuActive() then
                if activeTarget and iniData.main.screenmarker then
                    local px, py = getCharCoordinates(PLAYER_PED)
                    local dist = getDistanceBetweenCoords2d(px, py, activeTarget.x, activeTarget.y)
                    drawScreenWaypoint(activeTarget.x, activeTarget.y, activeTarget.z, dist)
                end

                local hasBlip, Wx, Wy, Wz = getTargetBlipCoordinates()
                if hasBlip then
                    local Px, Py, Pz = getCharCoordinates(PLAYER_PED)
                    local dist = math.sqrt((Px - Wx) ^ 2 + (Py - Wy) ^ 2 + (Pz - Wz) ^ 2)
                    if dist < 5 then
                        removeWaypoint()
                    elseif iniData.main.screenmarker then
                        drawScreenWaypoint(Wx, Wy, Wz, dist)
                    end
                end
            end

            local hasW, wx, wy, wz = getTargetBlipCoordinates()
            if hasW then
                if not lastWaypoint or lastWaypoint.x ~= wx or lastWaypoint.y ~= wy then
                    lastWaypoint = {x = wx, y = wy, z = wz}
                    if waypointInit and iniData.main.waypointmsg then
                        local wsector = getSectorFromCoords(wx, wy)
                        sampAddChatMessage(string.format("{8A8383}[Map Marker]{FFFFFF} Метка установлена на карте. Квадрат: {8A8383}%s{FFFFFF}. {FFFFFF}GPS: {8A8383}%.1f, %.1f, %.1f", wsector, wx, wy, wz), -1)
                        if iniData.main.waypointcopy then
                            setClipboardTextUnicode(string.format(SEKTOR_CP1251 .. " %s. GPS: %.1f, %.1f, %.1f", wsector, wx, wy, wz))
                            sampAddChatMessage("{8A8383}[Map Marker]{FFFFFF} Координаты скопированы в буфер обмена.", -1)
                        end
                    end
                end
            else
                lastWaypoint = nil
            end
            waypointInit = true
        else
            removePointMarker()
            wait(100)
        end
    end
end

function drawArrow(cx, cy, ux, uy, size, color)
    local px, py = -uy, ux

    local tipX, tipY = cx + ux * size, cy + uy * size
    local baseX, baseY = cx - ux * size * 0.6, cy - uy * size * 0.6
    local halfW = size * 0.75

    local steps = 12
    for i = 0, steps do
        local t = (i / steps) * 2 - 1
        local bx = baseX + px * halfW * t
        local by = baseY + py * halfW * t
        renderDrawLine(tipX, tipY, bx, by, 3, color)
    end
end

function drawScreenWaypoint(x, y, z, dist)
    local k = (iniData.main.markersize or 100) / 100
    local iconSize = WAYPOINT_ICON_SIZE * k
    local arrowSize = ARROW_SIZE * k
    local sw, sh = getScreenResolution()
    local ok, sx, sy, sz = convert3DCoordsToScreenEx(x, y, z)

    local onScreen = ok and sz and sz > 0
        and sx >= SCREEN_MARGIN and sx <= sw - SCREEN_MARGIN
        and sy >= SCREEN_MARGIN and sy <= sh - SCREEN_MARGIN

    if onScreen then
        if not waypointLoaded then return end

        local frame = math.floor(os.clock() * WAYPOINT_FPS) % WAYPOINT_FRAMES + 1

        renderDrawTexture(waypointTextures[frame], sx - iconSize / 2, sy - iconSize / 2, iconSize, iconSize, 0, 0xFFFFFFFF)

        local text = string.format("%.f", dist)
        local tw = renderGetFontDrawTextLength(waypointFont, text)
        renderFontDrawText(waypointFont, text, sx - tw / 2, sy + iconSize * WAYPOINT_TEXT_OFFSET, 0xB4FFFFFF)
        return
    end

    local camX, camY = getActiveCameraCoordinates()
    local atX, atY = getActiveCameraPointAt()

    local fx, fy = atX - camX, atY - camY
    local fl = math.sqrt(fx * fx + fy * fy)
    if fl < 0.0001 then return end
    fx, fy = fx / fl, fy / fl

    local rx, ry = fy, -fx

    local dx, dy = x - camX, y - camY
    local side = dx * rx + dy * ry
    local fwd = dx * fx + dy * fy

    local ux, uy = side, -fwd
    local ul = math.sqrt(ux * ux + uy * uy)
    if ul < 0.0001 then
        ux, uy = 0, 1
    else
        ux, uy = ux / ul, uy / ul
    end

    if math.abs(ux) < 0.05 and uy > 0 then
        ux = (side >= 0) and 0.05 or -0.05
        local l = math.sqrt(ux * ux + uy * uy)
        ux, uy = ux / l, uy / l
    end

    local cx, cy = sw / 2, sh / 2
    local ax = cx + ux * sw * ARROW_RING_X
    local ay = cy + uy * sh * ARROW_RING_Y

    drawArrow(ax, ay, ux, uy, arrowSize, ARROW_COLOR)

    local text = string.format("%.f", dist)
    local tw = renderGetFontDrawTextLength(waypointFont, text)
    local th = renderGetFontDrawHeight(waypointFont)
    local tx = ax - ux * (arrowSize + 22) - tw / 2
    local ty = ay - uy * (arrowSize + 22) - th / 2
    renderFontDrawText(waypointFont, text, tx, ty, 0xB4FFFFFF)
end

function handleMarkOutput(sector, x, y, z)
    local chatMsg = string.format(SEKTOR_CP1251 .. " %s. GPS: %.1f, %.1f, %.1f", sector, x, y, z)

    if iniData.main.markmode == 1 then
        setClipboardTextUnicode(chatMsg)
        sampAddChatMessage("{8A8383}[Map Marker]{FFFFFF} Координаты скопированы в буфер обмена.", -1)
    elseif iniData.main.markmode == 2 then
        sampSendChat("/f " .. chatMsg)
    elseif iniData.main.markmode == 3 then
        sampSendChat("/fc " .. chatMsg)
    end
end

function toggleGameCursor(toggle)
    if toggle then
        sampSetCursorMode(3)
    else
        sampToggleCursor(false)
    end
    cursorEnabled = toggle
end

function disableCursorMode()
    cursorEnabled = false
    toggleGameCursor(false)
    removePointMarker()
end

function createPointMarker(x, y, z)
    pointMarker = createUser3dMarker(x, y, z + 0.3, 4)
end

function removePointMarker()
    if pointMarker then
        removeUser3dMarker(pointMarker)
        pointMarker = nil
    end
end

function clearMarkers()
    if currentBlip and doesBlipExist(currentBlip) then
        removeBlip(currentBlip)
        currentBlip = nil
    end
    if currentCheckpoint then
        deleteCheckpoint(currentCheckpoint)
        currentCheckpoint = nil
    end
    activeTarget = nil
end

function setMarkers(x, y, z, sector)
    clearMarkers()
    activeTarget = {x = x, y = y, z = z, sector = sector or "Неизвестно"}

    currentBlip = addBlipForCoord(x, y, z)
    changeBlipColour(currentBlip, BLIP_COLOR)
    currentCheckpoint = createCheckpoint(2, x, y, z + 1.5, x, y, z + 1.5, 2.0)
end

function triggerConfirmation(sector, x, y, z)
    pendingCoords = {
        x = x,
        y = y,
        z = z,
        sector = sector,
        timestamp = os.clock()
    }
    sampAddChatMessage("{8A8383}[Map Marker]{FFFFFF} Вывести метку на карте {00FF00}Y{FFFFFF}. Отменить предложение {FF0000}N{FFFFFF}", -1)
end

function getSectorFromCoords(x, y)
    local col = math.floor((x + 3000) / SQUARE_SIZE) + 1
    local row = math.floor((3000 - y) / SQUARE_SIZE) + 1

    col = math.max(1, math.min(GRID_STAGES, col))
    row = math.max(1, math.min(#letters, row))

    return letters[row] .. "-" .. col
end

function getCoordsFromSector(sectorStr)
    local inputLetter, inputCol = sectorStr:match("^([^%-]+)%-(%d+)$")
    if not inputLetter or not inputCol then return nil end

    inputCol = tonumber(inputCol)
    if inputCol < 1 or inputCol > GRID_STAGES then return nil end

    local rowIndex = letterToRow[inputLetter]
    if not rowIndex then return nil end

    local x = -3000 + (inputCol - 1) * SQUARE_SIZE + (SQUARE_SIZE / 2)
    local y = 3000 - (rowIndex - 1) * SQUARE_SIZE - (SQUARE_SIZE / 2)
    return x, y
end

function setEnabled(state)
    iniData.main.enabled = state
    ui.enabled[0] = state
    saveCfg()
    if not state then
        disableCursorMode()
        clearMarkers()
        pendingCoords = nil
    end
end

function cmd_markmenu()
    if not ui.window[0] then
        disableCursorMode()
    end
    ui.window[0] = not ui.window[0]
end

function cmd_fkv(arg)
    if not iniData.main.enabled then return end
    if arg == "" then
        sampAddChatMessage("{8A8383}[Map Marker]{FFFFFF} Используйте: /fkv [Квадрат]", -1)
        return
    end

    local x, y = getCoordsFromSector(arg)
    if x and y then
        setMarkers(x, y, 15.0, arg)
        sampAddChatMessage(string.format("{8A8383}[Map Marker]{FFFFFF} Метка установлена на сектор: {8A8383}%s", arg), -1)
    else
        sampAddChatMessage("{8A8383}[Map Marker]{FFFFFF} Неверный формат квадрата.", -1)
    end
end

function cmd_mkv()
    if not iniData.main.enabled then return end
    local bool, x, y, z = getTargetBlipCoordinates()
    if bool then
        local sector = getSectorFromCoords(x, y)
        sampAddChatMessage(string.format("{8A8383}[Map Marker]{FFFFFF} Ваша метка находится в квадрате: {8A8383}%s{FFFFFF}. {FFFFFF}GPS: {8A8383}%.1f, %.1f, %.1f", sector, x, y, z), -1)
    else
        sampAddChatMessage("{8A8383}[Map Marker]{FFFFFF} Вы не поставили метку ПКМ на карте.", -1)
    end
end

function cmd_mykv()
    if not iniData.main.enabled then return end
    local x, y, z = getCharCoordinates(PLAYER_PED)
    local sector = getSectorFromCoords(x, y)
    sampAddChatMessage(string.format("{8A8383}[Map Marker]{FFFFFF} Вы находитесь в квадрате: {8A8383}%s{FFFFFF}. {FFFFFF}GPS: {8A8383}%.1f, %.1f, %.1f", sector, x, y, z), -1)
end

function cmd_mark()
    if not iniData.main.enabled then return end
    local x, y, z = getCharCoordinates(PLAYER_PED)
    local sector = getSectorFromCoords(x, y)
    handleMarkOutput(sector, x, y, z)
end

function cmd_markdell()
    if not iniData.main.enabled then return end
    clearMarkers()
    sampAddChatMessage("{8A8383}[Map Marker]{FFFFFF} Метка успешно удалена с карты.", -1)
end

local function nameInList(list, haystack)
    for _, n in ipairs(list) do
        if haystack:find(n:lower(), 1, true) then
            return true
        end
    end
    return false
end

function se.onServerMessage(color, text)
    if not iniData.main.enabled then return end
    local cleanText = text:gsub("{%x%x%x%x%x%x}", "")

    local sectorPos = cleanText:find("\xD1\xE5\xEA\xF2\xEE\xF0") or cleanText:find("[Ss]ector")
    if not sectorPos then return end

    local sender = cleanText:match("\xCE\xF2\xEF\xF0\xE0\xE2\xE8\xF2\xE5\xEB\xFC:%s*([%w_%.%-]+)")
    local before = (sender or cleanText:sub(1, sectorPos - 1)):lower()

    local res, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
    if res and not iniData.main.acceptown then
        local myName = sampGetPlayerNickname(myId)
        if myName and myName ~= "" and before:find(myName:lower(), 1, true) then
            return
        end
    end

    if nameInList(blacklist, before) then return end
    if iniData.main.listmode == 2 and not nameInList(whitelist, before) then return end

    local pattern1 = "\xD1\xE5\xEA\xF2\xEE\xF0%s+(.-)%.%s*GPS:%s*(%-?%d+%.?%d*),%s*(%-?%d+%.?%d*),%s*(%-?%d+%.?%d*)"
    local pattern2 = "[Ss]ector%s+(.-)%.%s*GPS:%s*(%-?%d+%.?%d*),%s*(%-?%d+%.?%d*),%s*(%-?%d+%.?%d*)"

    local sector, sX, sY, sZ = cleanText:match(pattern1)
    if not sector then
        sector, sX, sY, sZ = cleanText:match(pattern2)
    end

    if sector and sX and sY and sZ then
        local x, y, z = tonumber(sX), tonumber(sY), tonumber(sZ)
        if x and y and z then
            if pendingCoords and pendingCoords.x == x and pendingCoords.y == y and pendingCoords.z == z then
                return
            end
            if activeTarget and activeTarget.x == x and activeTarget.y == y and activeTarget.z == z then
                return
            end

            lua_thread.create(function()
                wait(0)
                triggerConfirmation(sector, x, y, z)
            end)
        end
    end
end

addEventHandler("onScriptTerminate", function(scr, quit)
    if scr == thisScript() then
        clearMarkers()
        disableCursorMode()
        releaseWaypointTextures()
        unregisterAllCommands()
    end
end)

addEventHandler("onWindowMessage", function(msg, wparam, lparam)
    if (msg == 0x100 or msg == 0x101) and wparam == vkeys.VK_ESCAPE and ui.window[0] then
        consumeWindowMessage(true, false)
        if msg == 0x101 then
            ui.window[0] = false
        end
    end
end)
