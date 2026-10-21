script_name("AI-Sens")
script_author("Impressive")
require("lib.moonloader")
local ffi = require("ffi")
local imgui = require("mimgui")
local encoding = require("encoding")
local inicfg = require("inicfg")
local wm = require("windows.message")

encoding.default = "CP1251"
local u8 = encoding.UTF8
local new = imgui.new

local samem = require("SAMemory")
samem.require("CCamera")
samem.require("CCam")
samem.require("eCamMode")
samem.require("CPed")
samem.require("CEntity")

local sensH = ffi.cast("float*", 0xB6EC1C)
local sensV = ffi.cast("float*", 0xB6EC20)
local activeCam = ffi.cast("uint8_t*", 0xB6F028 + 0x59)
local menuData = 0xBA6748
local menuOpened = ffi.cast("uint8_t*", menuData + 0x15C)
local menuSelect = ffi.cast("uint8_t*", menuData + 0x15D)

local SENS_MIN, SENS_MAX = 0.005, 5.0

local CFG_FILE = "AI-Sens.ini"
local firstRun = not doesFileExist(getWorkingDirectory() .. "\\config\\" .. CFG_FILE)

local cfg = inicfg.load({
    main = {
        enable = false,
        vertical = true,
        sightObjectsFix = true,
        camera = 1.0,
        aiming = 1.0,
        sniper = 1.0,
    },
}, CFG_FILE)

local function round3(v) return math.floor(v * 1000 + 0.5) / 1000 end
local function clamp(v) return math.max(SENS_MIN, math.min(SENS_MAX, v)) end
local function saveCfg() inicfg.save(cfg, CFG_FILE) end

local C = ffi.C
local active = false
local origH, origV = 0, 0

local function getMode()
    local mode = samem.camera.aCams[activeCam[0]].nMode
    if mode == C.MODE_SNIPER or mode == C.MODE_ROCKETLAUNCHER
       or mode == C.MODE_ROCKETLAUNCHER_HS or mode == C.MODE_CAMERA then
        return "sniper"
    elseif mode == C.MODE_AIMING or mode == C.MODE_AIMWEAPON
       or mode == C.MODE_AIMWEAPON_ATTACHED then
        return "aiming"
    end
    return "camera"
end

local function restore()
    if active then
        sensH[0] = origH
        sensV[0] = origV
        active = false
    end
end

local hideAcs = false
local function processAccessories()
    if not cfg.main.sightObjectsFix or not isSampAvailable() then
        if hideAcs then
            local ped = ffi.cast("CPed*", getCharPointer(PLAYER_PED))
            if ped and ped.HasAccessory and ped:HasAccessory() then
                local t = ped.m_accessories
                for i = 0, 9 do
                    if t.m_bNotEmpty[i] == 1 then
                        local ent = ffi.cast("SCEntity*", t.m_pObject[i]).m_pGameEntity
                        if ent ~= nil then ent.bIsVisible = true end
                    end
                end
            end
            hideAcs = false
        end
        return
    end

    local mode = samem.camera.aCams[activeCam[0]].nMode
    if mode == C.MODE_CAMERA or mode == C.MODE_SNIPER or mode == C.MODE_ROCKETLAUNCHER or mode == C.MODE_ROCKETLAUNCHER_HS then
        if not hideAcs then
            local ped = ffi.cast("CPed*", getCharPointer(PLAYER_PED))
            if ped and ped.HasAccessory and ped:HasAccessory() then
                local t = ped.m_accessories
                for i = 0, 9 do
                    if t.m_bNotEmpty[i] == 1 then
                        local ent = ffi.cast("SCEntity*", t.m_pObject[i]).m_pGameEntity
                        if ent ~= nil then ent.bIsVisible = false end
                    end
                end
            end
            hideAcs = true
        end
    elseif hideAcs then
        local ped = ffi.cast("CPed*", getCharPointer(PLAYER_PED))
        if ped and ped.HasAccessory and ped:HasAccessory() then
            local t = ped.m_accessories
            for i = 0, 9 do
                if t.m_bNotEmpty[i] == 1 then
                    local ent = ffi.cast("SCEntity*", t.m_pObject[i]).m_pGameEntity
                    if ent ~= nil then ent.bIsVisible = true end
                end
            end
        end
        hideAcs = false
    end
end

local enableBuf = new.bool(cfg.main.enable)
local vertBuf = new.bool(cfg.main.vertical)
local sightBuf = new.bool(cfg.main.sightObjectsFix)
local bufs = {
    camera = new.float(cfg.main.camera),
    aiming = new.float(cfg.main.aiming),
    sniper = new.float(cfg.main.sniper),
}

local function process()
    processAccessories()

    if not cfg.main.enable then
        restore()
        return
    end

    if menuOpened[0] == 1 and menuSelect[0] == 39 then
        active = false
        cfg.main.enable = false
        enableBuf[0] = false
        saveCfg()
        sampAddChatMessage("[AI-Sens] {FFFFFF}Функция {dc4747}отключена{FFFFFF}: вы изменили чувствительность через меню игры.", 0x88aa62)
        return
    end

    if not active then
        origH, origV = sensH[0], sensV[0]
        active = true
    end

    local v = cfg.main[getMode()] / 1000
    sensH[0] = v
    if cfg.main.vertical then sensV[0] = v end
end

local window = new.bool(false)
local V4, V2 = imgui.ImVec4, imgui.ImVec2

local COL = {
    accent = V4(0.53, 0.67, 0.38, 1.00),
    red = V4(0.86, 0.28, 0.28, 1.00),
    text = V4(0.92, 0.92, 0.94, 1.00),
    dim = V4(0.58, 0.60, 0.65, 1.00),
    bg = V4(0.08, 0.09, 0.11, 0.98),
    card = V4(0.12, 0.13, 0.16, 1.00),
    frame = V4(0.17, 0.18, 0.22, 1.00),
    off = V4(0.30, 0.32, 0.38, 1.00),
}

local function u32(v) return imgui.ColorConvertFloat4ToU32(v) end

local function switch(id, buf)
    local p = imgui.GetCursorScreenPos()
    local h = 22
    local w = 42
    imgui.InvisibleButton(id, V2(w, h))
    local clicked = imgui.IsItemClicked()
    if clicked then buf[0] = not buf[0] end
    local dl = imgui.GetWindowDrawList()
    dl:AddRectFilled(p, V2(p.x + w, p.y + h), u32(buf[0] and COL.accent or COL.off), h / 2)
    local cx = buf[0] and (p.x + w - h / 2) or (p.x + h / 2)
    dl:AddCircleFilled(V2(cx, p.y + h / 2), h / 2 - 3, u32(V4(1, 1, 1, 1)), 24)
    return clicked
end

local CARDS = {
    { field = "camera", title = "Вращение камерой", hint = "обычный режим, от третьего лица" },
    { field = "aiming", title = "Прицеливание", hint = "ПКМ с оружием" },
    { field = "sniper", title = "Снайпер", hint = "снайперка, РПГ, фотокамера" },
}

local function drawCard(card)
    local buf = bufs[card.field]
    local io = imgui.GetIO()

    imgui.PushStyleColor(imgui.Col.Border, V4(0, 0, 0, 0))
    imgui.PushStyleColor(imgui.Col.ChildBg, COL.card)
    imgui.BeginChild("##card_" .. card.field, V2(0, 75), true)

    imgui.TextColored(COL.text, u8(card.title))
    imgui.SameLine()
    imgui.TextColored(COL.dim, u8("— " .. card.hint))

    local availWidth = imgui.GetContentRegionAvail().x
    local inputWidth = 70
    local spacing = imgui.GetStyle().ItemSpacing.x
    local sliderWidth = availWidth - inputWidth - spacing

    imgui.PushItemWidth(sliderWidth)
    imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, V2(8, 3))
    imgui.PushStyleColor(imgui.Col.Text, V4(0, 0, 0, 0))

    local ctrl = io.KeyCtrl
    io.KeyCtrl = false
    local changed = imgui.SliderFloat("##s_" .. card.field, buf, SENS_MIN, SENS_MAX, "%.3f")
    io.KeyCtrl = ctrl

    imgui.PopStyleColor()
    imgui.PopStyleVar()
    imgui.PopItemWidth()

    if changed then
        buf[0] = clamp(buf[0])
        cfg.main[card.field] = round3(buf[0])
    end

    if imgui.IsItemDeactivatedAfterEdit() then saveCfg() end

    imgui.SameLine()
    imgui.PushItemWidth(inputWidth)
    imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, V2(8, 3))
    if imgui.InputFloat("##inp_" .. card.field, buf, 0.0, 0.0, "%.3f") then
        cfg.main[card.field] = round3(clamp(buf[0])) 
    end
    if imgui.IsItemDeactivatedAfterEdit() then
        buf[0] = clamp(buf[0])
        cfg.main[card.field] = round3(buf[0])
        saveCfg()
    end
    imgui.PopStyleVar()
    imgui.PopItemWidth()

    imgui.EndChild()
    imgui.PopStyleColor(2)
end

imgui.OnInitialize(function()
    imgui.GetIO().IniFilename = nil
end)

local mainWindowFrame = imgui.OnFrame(function() return window[0] end, function(player)
    player.HideCursor = not window[0]
    if isKeyDown(32) and player.HideCursor == false then
        player.HideCursor = true
    elseif not isKeyDown(32) and player.HideCursor == true and window[0] then
        player.HideCursor = false
    end

    local sx, sy = getScreenResolution()
    imgui.SetNextWindowPos(V2(sx / 2, sy / 2), imgui.Cond.FirstUseEver, V2(0.5, 0.5))
    imgui.SetNextWindowSize(V2(500, 0), imgui.Cond.Always)

    local colors = {
        { imgui.Col.WindowBg, COL.bg },
        { imgui.Col.Text, COL.text },
        { imgui.Col.TitleBg, COL.bg },
        { imgui.Col.TitleBgActive, COL.bg },
        { imgui.Col.FrameBg, COL.frame },
        { imgui.Col.FrameBgHovered, V4(0.22, 0.24, 0.29, 1) },
        { imgui.Col.FrameBgActive, V4(0.25, 0.27, 0.33, 1) },
        { imgui.Col.SliderGrab, COL.accent },
        { imgui.Col.SliderGrabActive, V4(0.65, 0.80, 0.47, 1) },
        { imgui.Col.Separator, V4(1, 1, 1, 0.08) },
        { imgui.Col.Button, COL.card },
        { imgui.Col.ButtonHovered, V4(0.18, 0.20, 0.25, 1) },
        { imgui.Col.ButtonActive, V4(0.22, 0.25, 0.32, 1) },
    }
    for _, c in ipairs(colors) do imgui.PushStyleColor(c[1], c[2]) end
    imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 12)
    imgui.PushStyleVarFloat(imgui.StyleVar.ChildRounding, 8)
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 6)
    imgui.PushStyleVarFloat(imgui.StyleVar.GrabRounding, 6)
    imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V2(14, 12))
    imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing, V2(8, 9))
    imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, V2(8, 6))

    imgui.Begin(u8"##aisens", window,
        imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoTitleBar
        + imgui.WindowFlags.AlwaysAutoResize)

    imgui.TextColored(COL.accent, "AI-Sens")
    imgui.SameLine(imgui.GetWindowWidth() - 40)
    if imgui.Button("X##close", V2(26, 22)) then window[0] = false end

    imgui.Separator()

    if switch("##enable", enableBuf) then
        cfg.main.enable = enableBuf[0]; saveCfg()
    end
    imgui.SameLine()
    imgui.AlignTextToFramePadding()
    imgui.Text(u8"AI-Sens")

    if switch("##vert", vertBuf) then
        cfg.main.vertical = vertBuf[0]; saveCfg()
    end
    imgui.SameLine()
    imgui.AlignTextToFramePadding()
    imgui.Text(u8"Применять и к вертикальной оси")

    if switch("##sight", sightBuf) then
        cfg.main.sightObjectsFix = sightBuf[0]; saveCfg()
    end
    imgui.SameLine()
    imgui.AlignTextToFramePadding()
    imgui.Text(u8"Отключить аксессуары при прицеливании (Sniper, RPG, Camera)")

    imgui.Spacing()

    for _, card in ipairs(CARDS) do drawCard(card) end

    imgui.Spacing()

    if imgui.Button(u8"Сбросить настройки чувствительности", V2(imgui.GetContentRegionAvail().x, 26)) then
        local base = active and origH or sensH[0]
        local defVal = round3(clamp(base * 1000))
        for _, f in ipairs({ "camera", "aiming", "sniper" }) do
            cfg.main[f] = defVal
            bufs[f][0] = defVal
        end
        saveCfg()
    end

    imgui.End()

    imgui.PopStyleVar(7)
    imgui.PopStyleColor(#colors)
end)
mainWindowFrame.HideCursor = true

addEventHandler("onWindowMessage", function(msg, wparam, lparam)
    if wparam == 27 then
        if window[0] then
            if msg == wm.WM_KEYDOWN then
                consumeWindowMessage(true, false)
            elseif msg == wm.WM_KEYUP then
                window[0] = false
            end
        end
    end
end)

function main()
    while not isSampAvailable() do wait(100) end

    if firstRun then
        local cur = round3(clamp(sensH[0] * 1000))
        for _, f in ipairs({ "camera", "aiming", "sniper" }) do
            cfg.main[f] = cur
            bufs[f][0] = cur
        end
        saveCfg()
    end

    sampRegisterChatCommand("aisens", function() window[0] = not window[0] end)

    while true do
        wait(0)
        process()
    end
end

function onScriptTerminate(scr, quit)
    if scr == thisScript() then restore() end
end