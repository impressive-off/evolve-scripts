script_author("Impressive")
script_name('Evolve Chat Helper')
local imgui = require 'mimgui'
local encoding = require 'encoding'
encoding.default = 'CP1251'
local u8 = encoding.UTF8
local inicfg = require 'inicfg'
local vkeys = require 'vkeys'
local sampev = require 'lib.samp.events'
local ffi = require("ffi")
require 'lib.moonloader'
local font_flag = require('moonloader').font_flag

local floor, max, min, sqrt = math.floor, math.max, math.min, math.sqrt

ffi.cdef[[
    short GetKeyState(int nVirtKey);
    bool GetKeyboardLayoutNameA(char* pwszKLID);
    int GetLocaleInfoA(int Locale, int LCType, char* lpLCData, int cchData);
]]
local BuffSize = 32
local KeyboardLayoutName = ffi.new("char[?]", BuffSize)
local LocalInfo = ffi.new("char[?]", BuffSize)

local function deepcopy(t)
    local r = {}
    for k, v in pairs(t) do r[k] = type(v) == 'table' and deepcopy(v) or v end
    return r
end

local directIni = "Evolve-ChatHelper.ini"
local PROFILE_VER = 4

local DEFAULTS = {
    settings = {
        membersEnabled = true,
        chatIdEnabled = true,
        copyNickEnabled = true,
        admCopyId = true,
        smskontr = true,
        uvedkontr = true,
        chatPanelEnabled = true,
        chatCopyEnabled = true,
        fromLauncher = false,
        lockEnabled = true,
        antizz = true,
        colorRadioEnabled = true,
        colorLeadersEnabled = true,
        hideLauncher = true,
        autobar = true,
        autodrugs = true,
        autoSpongebozz = true,
        autoSchool = true
    },
    main = {
        cursorWithChatInput = true,
        profileVer          = 0,
        scrollPos           = 0,
        scrollInv           = 0,
    },
    menu = {
        fontName       = 'Arial',
        fontSize       = 9,
        maxNicks       = 8,
        nicksOnNewLine = false,
        bgColor        = 3992977408,
        btnColor       = 4279834905,
        hoverColor     = 4030479420,
        textColor      = 4294967295,
        padX           = 14,
        padY           = 5,
        gap            = 3,
        outerPadding   = 6,
    },
    copy = {
        stripColorCodes      = true,
        includeSampTimestamp = false,
    },
    ['fs_-3'] = { offsetX = 27, size = 6, offsetY = 0, y = 10, widthRatio = 0.74, lineHeight = 15 },
    ['fs_-2'] = { offsetX = 27, size = 6, offsetY = 0, y = 10, widthRatio = 0.74, lineHeight = 17 },
    ['fs_-1'] = { offsetX = 27, size = 6, offsetY = 0, y = 10, widthRatio = 0.74, lineHeight = 19 },
    ['fs_0']  = { offsetX = 27, size = 6, offsetY = 0, y = 10, widthRatio = 0.74, lineHeight = 20 },
    ['fs_1']  = { offsetX = 27, size = 6, offsetY = 0, y = 10, widthRatio = 0.74, lineHeight = 23 },
    ['fs_2']  = { offsetX = 27, size = 6, offsetY = 0, y = 10, widthRatio = 0.74, lineHeight = 25 },
    ['fs_3']  = { offsetX = 27, size = 6, offsetY = 0, y = 10, widthRatio = 0.74, lineHeight = 27 },
    ['fs_4']  = { offsetX = 27, size = 6, offsetY = 0, y = 10, widthRatio = 0.74, lineHeight = 28 },
    ['fs_5']  = { offsetX = 27, size = 6, offsetY = 0, y = 10, widthRatio = 0.74, lineHeight = 31 },
}

local mainIni = inicfg.load(deepcopy(DEFAULTS), directIni) or deepcopy(DEFAULTS)
local cfg = mainIni

if (tonumber(cfg.main.profileVer) or 0) < PROFILE_VER then
    for key, tbl in pairs(DEFAULTS) do
        if key:sub(1, 3) == 'fs_' then
            cfg[key] = deepcopy(tbl)
        end
    end
    cfg.main.profileVer = PROFILE_VER
end

inicfg.save(mainIni, directIni)

local fromLauncher = mainIni.settings.fromLauncher == true

local showMenu = imgui.new.bool(false)
local isOrgList = false
local totalAFK, inStream, streamAFK = 0, 0, 0
local admids = {}
local infoFont = nil
local pendingCode = nil

local factions = {
    ["Russian mafia"] = "B8B6B6",
    ["Rifa"]          = "2A9171",
    ["Pagans MC"]     = "2C9198",
    ["Government"]    = "139BEC",
    ["Инструктор"]    = "139BEC",
    ["Юрист"]         = "139BEC",
    ["LSPD"]          = "110CE7",
    ["LV News"]       = "E6284E",
    ["Vagos"]         = "FFDE25",
    ["Yakuza"]        = "FF0606",
    ["Mongols MC"]    = "252525",
    ["LS News"]       = "868484",
    ["LCN"]           = "DDA702",
    ["SFPD"]          = "110CE7",
    ["Warlocks MC"]   = "F45001",
    ["ФБР"]           = "252525",
    ["LVPD"]          = "110CE7",
    ["Армия СФ"]      = "51964D",
    ["Армия ЛВ"]      = "51964D",
    ["SF News"]       = "56FB4E",
    ["Медики ЛС"]     = "114D71",
    ["Медики"]        = "114D71",
    ["Grove"]         = "089401",
    ["Aztec"]         = "0CD7E7",
    ["Ballas"]        = "B313E8"
}

local ALLOWED_COLORS = {
    ['8D8DFF'] = true,
    ['01FCFF'] = true,
}

local titleTargets = {
    'игровой лаунчер | evolve-rp'
}

local contentTargets = {
    'игровой лаунчер',
    'на официальном сайте проекта',
    'evolve role play',
    'вас ждут уникальные автомобили',
    'https://evolve-rp.ru'
}

local crime_answers = {
    ["Количество оружия на складе мафии"] = "7 оружий",
    ["Война за бизнес завершается при достижении"] = "200 убийств",
    ["Сколько у мафий мест для стрел"] = "5 мест",
    ["Как часто может быть ограблен магазин оружия"] = "1 раз в 30 минут",
    ["Количество мафий на сервере"] = "3 мафии",
    ["В каком аэропорту берутся заказы на контрабанду"] = "Аэропорт г. Лас-Вентурас",
    ["В каком баре берутся заказные убийства"] = "AlCapone Bar",
    ["Какое оружие не является фракционным"] = "Оружие трость",
    ["Количество криминальных навыков у мафиози"] = "3 навыка",
    ["Какой криминальной деятельности у мафий нет"] = "Количество закрашенных граффити",
    ["Цена грамма зелёной растительности в наркопритоне"] = "30 вирт",
    ["Количество доступных для крафта оружий"] = "7 оружий",
    ["Количество граффити в гетто"] = "20 граффити",
    ["Количество банд на сервере"] = "5 банд",
    ["Количество криминальных навыков у бандита"] = "4 навыка",
    ["зависимости начинается ломка"] = "2.000 единиц",
    ["респавн занимает 3 квадрата"] = "Varios Los Aztecas Gang",
    ["Война за территорию завершается"] = "х3 от онлайна банды",
    ["ограблен магазин одежды"] = "1 раз в 30 минут",
    ["территорий в гетто, доступных для захвата"] = "119 территорий"
}

local driving_school = {
    ["Где разрешена стоянка"] = "Только на обочине",
    ["приближении спецтранспорта"] = "Уступить дорогу",
    ["Где запрещено движение"] = "По тротуарам и газонам",
    ["Что запрещено делать водителю"] = "Пользоваться телефоном",
    ["В каком случае нужно уступить дорогу"] = "При помехе справа",
    ["Какие документы должен иметь"] = "Водительское удостоверение и документы на ТС",
    ["выезде с прилегающей территории"] = "Уступить дорогу движущемуся транспорту",
    ["По какой стороне дороги"] = "По правой стороне",
    ["Когда запрещено управлять"] = "со состоянии алкогольного и наркотического",
    ["отношении организованных колонн"] = "Пересекать колонну или занимать в ней место"
}

local function findIndexInText(dialogText, answerText)
    local cleanAllText = dialogText:gsub("{%x%x%x%x%x%x}", "")
    local line_num = 0
    local ansLower = answerText:lower()
    for line in cleanAllText:gmatch("[^\r\n]+") do
        if line:lower():find(ansLower, 1, true) then
            return line_num
        end
        line_num = line_num + 1
    end
    return nil
end

local function cleanText(text)
    text = text:gsub('{......}', '')
    text = text:gsub('%s+', ' ')
    return text:lower():match('^%s*(.-)%s*$')
end

local function closedialog()
    wait(250)
    sampCloseCurrentDialogWithButton(0)
    wait(250)
    sampCloseCurrentDialogWithButton(0)
end

function getColorById(pid)
    local ok, color = pcall(sampGetPlayerColor, pid)
    if not ok or not color then return nil end
    local r = bit.band(bit.rshift(color, 16), 0xFF)
    local g = bit.band(bit.rshift(color, 8),  0xFF)
    local b = bit.band(color, 0xFF)
    return string.format('%02X%02X%02X', r, g, b)
end

function getIdByName(name)
    if not name or name == '' then return nil end
    local res, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
    if res and sampGetPlayerNickname(myId) == name then
        return myId
    end
    for i = 0, 1000 do
        if sampIsPlayerConnected(i) then
            if sampGetPlayerNickname(i) == name then
                return i
            end
        end
    end
    return nil
end

function getStrByState(keyState)
    return keyState == 0 and "{ff8533}OFF{ffffff}" or "{85cf17}ON{ffffff}"
end

function getStrByPing(ping)
    if ping < 100 then return string.format("{85cf17}%d{ffffff}", ping)
    elseif ping < 150 then return string.format("{ff8533}%d{ffffff}", ping) end
    return string.format("{BF0000}%d{ffffff}", ping)
end

function addIdToNick(text)
    if not text or text == '' then return text, false end
    local resMy, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
    if not resMy then return text, false end

    local changed = false
    for name in text:gmatch('([A-Z%a]%w+_%w+)') do
        if not text:find(name .. '%s*%[%d+%] ') and not text:find(name .. '%[%d+%]') then
            local id = getIdByName(name)
            if id then
                local safeName = name:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
                text = text:gsub(safeName .. '([^%d%[%w_])', name .. '[' .. id .. ']%1')
                text = text:gsub(safeName .. '$', name .. '[' .. id .. ']')
                changed = true
            end
        end
    end
    return text, changed
end

function parseRadioMessage(trimmed)
    local rank, nick, id, msg = trimmed:match('^(.-)([%w_]+)%[(%d+)%]: (.+)$')
    if rank and nick and id and msg then
        rank = rank:match('^(.-)%s*$')
        if #rank == 0 then rank = nil end
        return rank, nick, id, msg
    end
    return nil
end

pcall(ffi.cdef, [[
    int   OpenClipboard(void* hWnd);
    int   CloseClipboard(void);
    int   EmptyClipboard(void);
    void* SetClipboardData(unsigned int uFormat, void* hMem);
    void* GlobalAlloc(unsigned int uFlags, size_t dwBytes);
    void* GlobalLock(void* hMem);
    int   GlobalUnlock(void* hMem);
    void* GlobalFree(void* hMem);
    int   MultiByteToWideChar(unsigned int cp, unsigned long flags, const char* src, int srcLen, wchar_t* dst, int dstLen);
    long  RegOpenKeyExA(void* hKey, const char* sub, unsigned long opt, unsigned long sam, void** out);
    long  RegQueryValueExA(void* hKey, const char* name, unsigned long* res, unsigned long* typ, unsigned char* data, unsigned long* size);
    long  RegCloseKey(void* hKey);
]])

local C = ffi.C
local advapi = select(2, pcall(ffi.load, 'advapi32'))

local function clamp(v, a, b) return v < a and a or (v > b and b or v) end

local function chatCopyActive()
    return mainIni.settings.chatCopyEnabled
end

local function getSampPageSize()
    local ok, res = pcall(function()
        local pChat = sampGetChatInfoPtr()
        if pChat and pChat ~= 0 then
            local ps = ffi.cast('int*', pChat)[0]
            if ps >= 8 and ps <= 40 then return ps end
        end
    end)
    return ok and res or nil
end

local function regDword(name)
    local ok, res = pcall(function()
        local hk   = ffi.new('void*[1]')
        local root = ffi.cast('void*', ffi.cast('uintptr_t', 0x80000001))
        if advapi.RegOpenKeyExA(root, 'Software\\SAMP', 0, 0x20219, hk) ~= 0 then return nil end
        local data = ffi.new('unsigned long[1]')
        local size = ffi.new('unsigned long[1]', 4)
        local rc   = advapi.RegQueryValueExA(hk[0], name, nil, nil, ffi.cast('unsigned char*', data), size)
        advapi.RegCloseKey(hk[0])
        if rc == 0 then
            local v = tonumber(data[0])
            if v and v > 0x7FFFFFFF then v = v - 0x100000000 end
            return v
        end
    end)
    return ok and res or nil
end

local function setClipboard(text)
    if not text then return false end
    local len = #text
    local wlen = C.MultiByteToWideChar(1251, 0, text, len, nil, 0)
    if wlen <= 0 then return false end
    local hMem = C.GlobalAlloc(0x0002, (wlen + 1) * 2)
    if hMem == nil then return false end
    local p = C.GlobalLock(hMem)
    if p == nil then C.GlobalFree(hMem) return false end
    local w = ffi.cast('wchar_t*', p)
    C.MultiByteToWideChar(1251, 0, text, len, w, wlen)
    w[wlen] = 0
    C.GlobalUnlock(hMem)

    local opened = false
    for _ = 1, 5 do
        if C.OpenClipboard(nil) ~= 0 then opened = true break end
    end
    if not opened then C.GlobalFree(hMem) return false end
    C.EmptyClipboard()
    local ok = C.SetClipboardData(13, hMem) ~= nil
    C.CloseClipboard()
    if not ok then C.GlobalFree(hMem) end
    return ok
end

local S = {
    sw = 1920, sh = 1080,
    rows = 10, lh = 20.0, ax = 10, ay = 10, aw = 800,
    markerSize = 6, offsetX = 27, offsetY = 0, widthRatio = 0.74,
    fontReg = 0, pageReg = nil, regStamp = -10,
    hoverRow = nil, hoverText = '', hoverStamp = 0,
    toggled = false, ownsCursor = false,
    regFsSeen = nil, fsPollStamp = -10, lastInput = '',
    live = false, clickL = false, clickR = false, eatLUp = false, eatRUp = false,
    hoverFirst = -1, cal = nil, lastSnap = nil, snapStamp = -10,
    scrollEvent = nil,
}

local function getFsSection(fsVal)
    local key = 'fs_' .. tostring(fsVal or 0)
    if not cfg[key] then
        local ref = cfg['fs_0'] or DEFAULTS['fs_0']
        cfg[key] = {
            y          = ref.y,
            lineHeight = (tonumber(ref.lineHeight) or 20) + 2 * (fsVal or 0),
            widthRatio = ref.widthRatio,
            size       = ref.size,
            offsetX    = ref.offsetX,
            offsetY    = ref.offsetY,
        }
        inicfg.save(cfg, directIni)
    end
    return cfg[key]
end

local function applyProfile(fsVal)
    S.fontReg = fsVal
    local prof = getFsSection(fsVal)
    S.ay         = tonumber(prof.y) or 10
    S.lh         = tonumber(prof.lineHeight) or 20.0
    S.widthRatio = tonumber(prof.widthRatio) or 0.74
    S.markerSize = tonumber(prof.size) or 6
    S.offsetX    = tonumber(prof.offsetX) or 27
    S.offsetY    = tonumber(prof.offsetY) or 0
    S.hoverRow   = nil
end

local function switchProfile(val)
    if val == S.fontReg then return end
    applyProfile(val)
end

local function trackFontSize()
    if wasKeyPressed(0x0D) and S.lastInput ~= '' then
        local fs = S.lastInput:match('^/fontsize%s+(%-?%d+)')
        if fs then
            local val = tonumber(fs)
            if val then switchProfile(val) end
        end
        S.lastInput = ''
    end

    if sampIsChatInputActive() then
        local txt = sampGetChatInputText()
        if txt and txt ~= '' then S.lastInput = txt end
    elseif not wasKeyPressed(0x0D) then
        S.lastInput = ''
    end

    local now = os.clock()
    if now - S.fsPollStamp > 0.3 then
        S.fsPollStamp = now
        local v = regDword('fontsize') or 0
        if v ~= S.regFsSeen then
            S.regFsSeen = v
            switchProfile(v)
        end
    end
end

local function updateGeometry()
    S.sw, S.sh = getScreenResolution()
    local now = os.clock()
    if now - S.regStamp > 0.5 then
        S.regStamp = now
        S.pageReg = getSampPageSize() or regDword('pagesize')
    end
    S.rows = clamp(S.pageReg or 10, 1, 50)
    S.ax   = 10
    S.aw   = floor(S.sw * S.widthRatio)
end

local function rowAt(mx, my)
    if mx < S.ax or mx > S.ax + S.aw then return nil end
    local rel = my - S.ay
    if rel < 0 or rel >= S.rows * S.lh then return nil end
    local r = floor(rel / S.lh)
    if r < 0 or r >= S.rows then return nil end
    return r
end

local function stripColors(s)
    s = s:gsub('{%x%x%x%x%x%x%x%x}', ''):gsub('{%x%x%x%x%x%x}', '')
    return s
end

local function extractCode(text)
    local clean = stripColors(text)
    for w in clean:gmatch('%w+') do
        if #w >= 25 then
            return w
        end
    end
    return nil
end

local function extractLink(text)
    local clean = stripColors(text)
    local link = clean:match('https?://[^%s]+')
    if not link then return nil end
    link = link:gsub('[%.,;:!%?%)%]\'"]+$', '')
    if #link <= 8 then return nil end
    return link
end

local IP_PAT = '(%d+%.%d+%.%d+%.%d+)'

local function extractIps(text)
    local clean = stripColors(text)
    local list, seen = {}, {}

    local function add(label, ip)
        if not seen[label .. ip] then
            seen[label .. ip] = true
            list[#list + 1] = { label = label .. ' ' .. ip, value = ip }
        end
    end

    local rip = clean:match('R%-IP%s*%[?' .. IP_PAT)
    if rip then add('R-IP', rip) end

    local lip = clean:match('L%-IP%s*%[?' .. IP_PAT)
    if lip then add('L-IP', lip) end

    for pos, ip in clean:gmatch('()IP:%s*%[?' .. IP_PAT) do
        local prev = pos > 1 and clean:sub(pos - 1, pos - 1) or ''
        if prev ~= '-' then add('IP', ip) end
    end

    return list
end

local function extractUsers(text)
    local clean = stripColors(text)
    local list, seen = {}, {}
    for token in clean:gmatch('%S+') do
        local name = token:match('^@([%w_]+)')
        if name and #name >= 3 then
            local full = '@' .. name
            if not seen[full] then
                seen[full] = true
                list[#list + 1] = full
            end
        end
    end
    return list
end

local function getFirstIndex()
    local maxFirst = max(0, 100 - S.rows)
    local off = tonumber(cfg.main.scrollPos) or 0
    if off <= 0 then return maxFirst end

    local ok, v = pcall(function()
        local pChat = sampGetChatInfoPtr()
        if not pChat or pChat == 0 then return nil end
        return tonumber(ffi.cast('int*', pChat + off)[0])
    end)
    if not ok or v == nil or v < 0 or v > 100 then return maxFirst end

    local first
    if tonumber(cfg.main.scrollInv) == 1 then first = maxFirst - v else first = v end
    return clamp(first, 0, maxFirst)
end

local SCAN_FROM, SCAN_TO = 0x6390, 0x6440

local function snapshotChat()
    local pChat = sampGetChatInfoPtr()
    if not pChat or pChat == 0 then return nil end
    local base = ffi.cast('uint8_t*', pChat)
    local snap = {}
    for off = SCAN_FROM, SCAN_TO do
        snap[off] = tonumber(ffi.cast('int*', base + off)[0])
    end
    return snap
end

local function calibrateScroll()
    if (tonumber(cfg.main.scrollPos) or 0) > 0 then return end
    local now = os.clock()
    local c = S.cal

    if not c then
        local up, down = wasKeyPressed(0x21), wasKeyPressed(0x22)
        local wheel = S.scrollEvent
        S.scrollEvent = nil

        if (up or down or wheel) and S.lastSnap then
            local dir = 1
            if up then dir = 1
            elseif down then dir = -1
            elseif wheel then dir = wheel end

            S.cal = { dir = dir, s0 = S.lastSnap, t = now, stage = 1 }
            return
        end
        if now - S.snapStamp > 0.1 then
            S.snapStamp = now
            S.lastSnap = snapshotChat()
        end
        return
    end

    if c.stage == 1 then
        if now - c.t > 0.05 then
            c.s1 = snapshotChat()
            c.t = now
            c.stage = 2
        end
        return
    end

    if now - c.t > 0.15 then
        S.cal = nil
        S.lastSnap = nil
        local s2 = snapshotChat()
        if not (c.s1 and s2) then return end

        local best, bestDelta
        for off = SCAN_FROM, SCAN_TO do
            local a, b, d = c.s0[off], c.s1[off], s2[off]
            if a and b and d and a ~= b and b == d
               and a >= 0 and a <= 100 and b >= 0 and b <= 100 and math.abs(b - a) <= 40 then
                if not best or (off % 4 == 2 and best % 4 ~= 2) then
                    best, bestDelta = off, b - a
                end
            end
        end

        if best then
            cfg.main.scrollPos = best
            cfg.main.scrollInv = (bestDelta * c.dir) > 0 and 1 or 0
            inicfg.save(cfg, directIni)
        end
    end
end

local function getRowText(row, first)
    first = first or getFirstIndex()
    local text, prefix = sampGetChatString(first + row)
    if not text or text == '' then return '' end
    if cfg.copy.stripColorCodes then text = stripColors(text) end
    if cfg.copy.includeSampTimestamp and prefix and prefix ~= '' then
        text = prefix .. ' ' .. text
    end
    return text
end

local function extractNicks(text)
    local list, seen = {}, {}
    local clean = stripColors(text):sub(1, 600)
    for w in clean:gmatch('[%w_]+') do
        local len = #w
        if len >= 3 and len <= 24 and not seen[w] and w:find('^%a') and w:find('_', 2, true) and w:sub(-1) ~= '_' then
            seen[w] = true
            list[#list + 1] = w
            if #list >= 30 then break end
        end
    end
    return list
end

local font

local function roundedBox(x, y, w, h, col)
    renderDrawBox(x + 2, y, w - 4, h, col)
    renderDrawBox(x, y + 2, w, h - 4, col)
    renderDrawBox(x + 1, y + 1, w - 2, h - 2, col)
end

local spanCache = {}
local function spansFor(r)
    local s = spanCache[r]
    if not s then
        s = {}
        for dy = -r, r do
            s[#s + 1] = { dy, floor(sqrt((r + 0.5) ^ 2 - dy * dy)) }
        end
        spanCache[r] = s
    end
    return s
end

local function drawCircle(cx, cy, r, col)
    for _, sp in ipairs(spansFor(r)) do
        local hw = sp[2]
        renderDrawBox(cx - hw, cy + sp[1], hw * 2 + 1, 1, col)
    end
end

local function drawMarker(row)
    local r  = max(1, floor(S.markerSize / 2))
    local cx = floor(S.ax + S.offsetX)
    local cy = floor(S.ay + row * S.lh + (S.lh / 2) + S.offsetY)
    drawCircle(cx, cy, r + 1, 0xAA000000)
    drawCircle(cx, cy, r, 0xFFE62020)
end

local menu = { open = false }

local function layoutMenu()
    local m = cfg.menu
    local ih = renderGetFontDrawHeight(font) + m.padY * 2
    local w = 0
    local idW = 0
    for _, it in ipairs(menu.items) do
        w = max(w, renderGetFontDrawTextLength(font, it.label))
        if it.idLabel then
            idW = max(idW, renderGetFontDrawTextLength(font, it.idLabel))
        end
    end
    w = floor(w) + m.padX * 2
    if idW > 0 then idW = floor(idW) + m.padX end
    local off = m.gap
    local fw = w
    if idW > 0 then fw = w + off + idW end
    local h = #menu.items * ih + (#menu.items - 1) * m.gap

    local totalW = fw + m.outerPadding * 2
    local totalH = h + m.outerPadding * 2
    local x, y = menu.mx + 6, menu.my + 6

    if x + totalW > S.sw - 2 then x = max(2, menu.mx - totalW - 6) end
    if y + totalH > S.sh - 2 then y = max(2, S.sh - totalH - 2) end

    menu.x = x + m.outerPadding
    menu.y = floor(y) + m.outerPadding
    menu.w = w
    menu.idw = idW
    menu.fw = fw
    menu.h = h
    menu.ih = ih
end

local function openMenu(row, mx, my, text)
    local m = cfg.menu
    local nicks = extractNicks(text)
    local code = extractCode(text)
    local link = extractLink(text)
    local ips = extractIps(text)
    local users = extractUsers(text)

    local items = {}
    if code then
        items[#items + 1] = { label = 'Активировать код', act = 'code', value = code }
    end
    if link then
        items[#items + 1] = { label = 'Копировать ссылку', act = 'link', value = link }
    end
    items[#items + 1] = { label = 'Копировать сообщение', act = 'msg' }

    if #nicks >= 2 then
        items[#items + 1] = { label = 'Копировать ники', act = 'nicks' }
    end
    for i = 1, min(#nicks, m.maxNicks) do
        local pid = getIdByName(nicks[i])
        items[#items + 1] = {
            label = nicks[i],
            act = 'nick',
            value = nicks[i],
            id = pid,
            idLabel = pid and tostring(pid) or nil
        }
    end

    for _, ipItem in ipairs(ips) do
        items[#items + 1] = { label = ipItem.label, act = 'ip', value = ipItem.value }
    end

    for _, u in ipairs(users) do
        items[#items + 1] = { label = u, act = 'user', value = u }
    end

    menu = { open = true, items = items, row = row, text = text, nicks = nicks, mx = mx, my = my,
             x = 0, y = 0, w = 0, idw = 0, fw = 0, h = 0, ih = 0 }
    layoutMenu()
end

local function closeMenu() menu.open = false end

local function menuItemAt(mx, my)
    if not menu.open then return nil end
    if mx < menu.x or mx > menu.x + menu.fw then return nil end
    local step = menu.ih + cfg.menu.gap
    local rel = my - menu.y
    if rel < 0 then return nil end
    local i = floor(rel / step) + 1
    if i > #menu.items or (rel - (i - 1) * step) > menu.ih then return nil end
    if mx <= menu.x + menu.w then
        return i, 'main'
    end
    local it = menu.items[i]
    if it.idLabel and menu.idw > 0 and mx >= menu.x + menu.w + cfg.menu.gap then
        return i, 'id'
    end
    return nil
end

local function drawMenu(mx, my)
    layoutMenu()
    local m = cfg.menu
    local pad = m.outerPadding
    roundedBox(menu.x - pad, menu.y - pad, menu.w + pad * 2, menu.h + pad * 2, m.bgColor)

    local firstId, lastId
    for i, it in ipairs(menu.items) do
        if it.idLabel then
            firstId = firstId or i
            lastId = i
        end
    end

    local idX = menu.x + menu.w + m.gap
    if firstId and menu.idw > 0 then
        local edge = menu.x + menu.w + pad - 1
        local by = menu.y + (firstId - 1) * (menu.ih + m.gap) - pad
        local bh = (lastId - firstId + 1) * menu.ih + (lastId - firstId) * m.gap + pad * 2
        local bw = (idX + menu.idw + pad) - edge
        roundedBox(edge, by, bw, bh, m.bgColor)
        renderDrawBox(edge, by, 3, bh, m.bgColor)
    end

    local th = renderGetFontDrawHeight(font)
    for i, it in ipairs(menu.items) do
        local iy = menu.y + (i - 1) * (menu.ih + m.gap)
        local inRow = my >= iy and my <= iy + menu.ih
        local hover = mx >= menu.x and mx <= menu.x + menu.w and inRow
        roundedBox(menu.x, iy, menu.w, menu.ih, hover and m.hoverColor or m.btnColor)
        local tw = renderGetFontDrawTextLength(font, it.label)
        renderFontDrawText(font, it.label, menu.x + (menu.w - tw) / 2, iy + (menu.ih - th) / 2, m.textColor)

        if it.idLabel and menu.idw > 0 then
            local hoverId = mx >= idX and mx <= idX + menu.idw and inRow
            roundedBox(idX, iy, menu.idw, menu.ih, hoverId and m.hoverColor or m.btnColor)
            local iw = renderGetFontDrawTextLength(font, it.idLabel)
            renderFontDrawText(font, it.idLabel, idX + (menu.idw - iw) / 2, iy + (menu.ih - th) / 2, m.textColor)
        end
    end
end

local function runAction(it, part)
    if part == 'id' and it.idLabel then
        setClipboard(it.idLabel)
        return
    end
    if it.act == 'msg' then
        setClipboard(menu.text)
    elseif it.act == 'link' then
        setClipboard(it.value)
    elseif it.act == 'ip' then
        setClipboard(it.value)
    elseif it.act == 'user' then
        setClipboard(it.value)
    elseif it.act == 'code' then
        pendingCode = it.value
        setClipboard(it.value)
        sampSendChat('/code')
        lua_thread.create(function()
            wait(5000)
            pendingCode = nil
        end)
    elseif it.act == 'nicks' then
        local sep = cfg.menu.nicksOnNewLine and '\r\n' or ' '
        local strNicks = table.concat(menu.nicks, sep)
        setClipboard(strNicks)
    elseif it.act == 'nick' then
        setClipboard(it.value)
    end
end

local function wantCursor()
    if S.toggled then return true end
    return cfg.main.cursorWithChatInput and sampIsChatInputActive()
end

local function applyCursor(want)
    if want then
        if not sampIsCursorActive() then
            sampToggleCursor(true)
            S.ownsCursor = true
        end
    elseif S.ownsCursor then
        S.ownsCursor = false
        if sampIsCursorActive() then sampToggleCursor(false) end
    end
end

local function resetUi()
    menu.open = false
    S.toggled = false
    S.hoverRow = nil
    S.live = false
    S.clickL = false
    S.clickR = false
    applyCursor(false)
end

local function overClickable(mx, my)
    if menu.open then return true end
    local row = rowAt(mx, my)
    return row ~= nil and S.hoverRow == row and S.hoverText ~= ''
end

local function frame()
    if not chatCopyActive() or showMenu[0] or sampGetChatDisplayMode() == 0 or isPauseMenuActive() then
        if menu.open or S.toggled or S.ownsCursor or S.hoverRow or S.live then resetUi() end
        return
    end

    updateGeometry()

    local want = wantCursor()
    if not want then
        if menu.open or S.ownsCursor or S.hoverRow or S.live then resetUi() end
        return
    end

    S.live = true
    applyCursor(true)
    local mx, my = getCursorPos()

    local first = getFirstIndex()
    local row = rowAt(mx, my)
    if row then
        local now = os.clock()
        if row ~= S.hoverRow or first ~= S.hoverFirst or now - S.hoverStamp > 0.2 then
            S.hoverRow, S.hoverFirst, S.hoverStamp = row, first, now
            S.hoverText = getRowText(row, first)
        end
        if S.hoverText == '' then row = nil end
    else
        S.hoverRow = nil
    end

    local lmb, rmb = S.clickL, S.clickR
    S.clickL, S.clickR = false, false

    local openClick = rmb
    local actClick = fromLauncher and rmb or lmb

    if openClick and row then
        S.hoverText = getRowText(row, first)
        if S.hoverText == '' then row = nil end
    end

    if menu.open then
        if lmb or rmb then
            local idx, part = menuItemAt(mx, my)
            if actClick and idx then
                runAction(menu.items[idx], part)
                closeMenu()
            elseif openClick and row and not idx then
                openMenu(row, mx, my, S.hoverText)
            else
                closeMenu()
            end
        end
    elseif openClick and row then
        openMenu(row, mx, my, S.hoverText)
    end

    local markerRow = menu.open and menu.row or row
    if markerRow then drawMarker(markerRow) end
    if menu.open then drawMenu(mx, my) end
end

function onWindowMessage(msg, wparam, lparam)
    if showMenu[0] and wparam == vkeys.VK_ESCAPE then
        if msg == 0x0100 or msg == 0x0104 then
            consumeWindowMessage(true, false)
            showMenu[0] = false
            imgui.ShowCursor = false
        elseif msg == 0x0101 or msg == 0x0105 then
            consumeWindowMessage(true, false)
        end
        return
    end

    if msg == 0x020A then
        local w = ffi.new('uint32_t[1]', wparam)
        local delta = ffi.cast('short*', w)[1]
        if delta ~= 0 then
            S.scrollEvent = (delta > 0) and 1 or -1
        end
    end

    if msg == 0x0202 then
        if S.eatLUp then
            S.eatLUp = false
            consumeWindowMessage(true, false)
        end
        return
    end

    if msg == 0x0205 then
        if S.eatRUp then
            S.eatRUp = false
            consumeWindowMessage(true, false)
        end
        return
    end

    if not S.live or showMenu[0] then return end

    if msg == 0x0201 or msg == 0x0203 then
        if menu.open then
            S.clickL = true
            S.eatLUp = true
            consumeWindowMessage(true, false)
        end
    elseif msg == 0x0204 or msg == 0x0206 then
        local mx = bit.band(lparam, 0xFFFF)
        local my = bit.band(bit.rshift(lparam, 16), 0xFFFF)
        if overClickable(mx, my) then
            S.clickR = true
            S.eatRUp = true
            consumeWindowMessage(true, false)
        end
    end
end

function main()
    if not isSampLoaded() or not isSampfuncsLoaded() then return end
    while not isSampAvailable() do wait(100) end

    infoFont = renderCreateFont("Segoe UI", 11, 13)
    font = renderCreateFont(cfg.menu.fontName, cfg.menu.fontSize, font_flag.BOLD + font_flag.BORDER + font_flag.SHADOW)

    local initFs = regDword('fontsize') or 0
    S.regFsSeen = initFs
    applyProfile(initFs)

    sampRegisterChatCommand("chathelper", function() showMenu[0] = not showMenu[0] end)

    sampRegisterChatCommand("cn", function(arg)
        if not mainIni.settings.copyNickEnabled then return end
        local id = tonumber(arg)
        local resMy, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)

        if id and (sampIsPlayerConnected(id) or (resMy and id == myId)) then
            local nickname = sampGetPlayerNickname(id)
            local pColor = sampGetPlayerColor(id)
            local hex = string.format("%06X", bit.band(pColor, 0xFFFFFF))
            setClipboard(nickname)
            sampAddChatMessage("{808080}[!] {FFFFFF}Никнейм {" .. hex .. "}" .. nickname .. "[" .. id .. "] {FFFFFF}скопирован", -1)
        else
            sampAddChatMessage("{808080}[!] {FFFFFF}Введите: /cn [id]", -1)
        end
    end)

    lua_thread.create(function()
        while true do
            wait(0)
            if sampIsChatInputActive() and mainIni.settings.chatPanelEnabled then
                local in1 = sampGetInputInfoPtr()
                in1 = getStructElement(in1, 0x8, 4)
                local in2 = getStructElement(in1, 0x8, 4)
                local in3 = getStructElement(in1, 0xC, 4)
                local fib, fib2 = in3 + 40, in2 + 5
                local result, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
                if result then
                    local name = sampGetPlayerNickname(myId)
                    local ping, score, color = sampGetPlayerPing(myId), sampGetPlayerScore(myId), sampGetPlayerColor(myId)
                    local caps, num = ffi.C.GetKeyState(20), ffi.C.GetKeyState(144)
                    ffi.C.GetKeyboardLayoutNameA(KeyboardLayoutName)
                    ffi.C.GetLocaleInfoA(tonumber(ffi.string(KeyboardLayoutName), 16), 0x00000002, LocalInfo, BuffSize)
                    local info = string.format("{bde0ff}%s {ffffff}| {%0.6x}%s {ffffff}| ID: {ff8533}%d {ffffff}| LvL: {ff8533}%d {ffffff}| Ping: %s | Num: %s | Caps: %s | {ffeeaa}%s{ffffff}",
                        os.date("%H:%M:%S"), bit.band(color, 0xFFFFFF), name, myId, score, getStrByPing(ping), getStrByState(num), getStrByState(caps), ffi.string(LocalInfo))
                    renderFontDrawText(infoFont, info, fib2, fib, -1)
                end
            end
        end
    end)

    while true do
        wait(0)
        if showMenu[0] then
            imgui.ShowCursor = true
        end

        if chatCopyActive() then
            trackFontSize()
            calibrateScroll()
        end
        frame()

        if mainIni.settings.lockEnabled and isKeyJustPressed(vkeys.VK_L) and not sampIsChatInputActive() and not sampIsDialogActive() then
            sampSendChat("/lock")
        end
    end
end

function onScriptTerminate(scr, quitGame)
    if scr == thisScript() then
        applyCursor(false)
    end
end

function sampev.onSendClientJoin(version, mod, nickname, challengeResponse, joinAuthKey, clientVer, challengeResponse2)
    local launcher = tostring(clientVer or ''):lower():find('launcher', 1, true) ~= nil
    if launcher ~= fromLauncher or mainIni.settings.fromLauncher ~= launcher then
        fromLauncher = launcher
        mainIni.settings.fromLauncher = launcher
        inicfg.save(mainIni, directIni)
    end
    resetUi()
end

function sampev.onShowDialog(dialogId, dialogStyle, dialogTitle, okButtonText, cancelButtonText, dialogText)
    if pendingCode then
        local codeToActivate = pendingCode
        pendingCode = nil
        lua_thread.create(function()
            wait(50)
            sampSendDialogResponse(dialogId, 1, 0, codeToActivate)
        end)
        return false
    end

    local cleanTitleStr = dialogTitle:gsub("{%x%x%x%x%x%x}", "")
    local cleanTextStr = dialogText:gsub("{%x%x%x%x%x%x}", "")

    if mainIni.settings.autoSpongebozz and (cleanTitleStr:find("Spongebozz", 1, true) or cleanTitleStr:find("CaptTime", 1, true)) then
        if cleanTextStr:find("устройство для подбора кода", 1, true) then
            lua_thread.create(function()
                wait(50)
                sampSendDialogResponse(dialogId, 1, 0, "")
            end)
            return false
        end

        if cleanTextStr:find("проверим твои знания", 1, true) or cleanTextStr:find("устройство твоё", 1, true) or cleanTextStr:find("ошибся на твой счёт", 1, true) then
            lua_thread.create(function()
                wait(50)
                sampSendDialogResponse(dialogId, 1, -1, "")
            end)
            return false
        end

        for q, ans in pairs(crime_answers) do
            if cleanTextStr:find(q, 1, true) then
                local idx = findIndexInText(dialogText, ans)
                if idx then
                    lua_thread.create(function()
                        wait(50)
                        sampSendDialogResponse(dialogId, 1, idx, "")
                    end)
                    return false
                end
            end
        end
    end

    if mainIni.settings.autoSchool and (cleanTitleStr:find("Автошкола", 1, true) or cleanTitleStr:find("Экзамен", 1, true)) then
        for q, ans in pairs(driving_school) do
            if cleanTextStr:find(q, 1, true) then
                local idx = findIndexInText(dialogText, ans)
                if idx then
                    lua_thread.create(function()
                        wait(50)
                        sampSendDialogResponse(dialogId, 1, idx, "")
                    end)
                    return false
                end
            end
        end
    end

    if mainIni.settings.antizz and dialogId == 0 and dialogTitle:find('Информация | {ae433d}Зеленая зона') then
        taskPlayAnimNonInterruptable(PLAYER_PED, 'HIT_WALK', 'PED', 4.0, false, true, true, false, 1)
        sampAddChatMessage('Информация | {ae433d}Зеленая зона', -1)
        sampSendDialogResponse(0, 1, -1, -1)
        return false
    end

    if mainIni.settings.hideLauncher then
        local cTitle = cleanText(dialogTitle)
        local cTx = cleanText(dialogText)

        local titleMatched = false
        for _, t in ipairs(titleTargets) do
            if cTitle == cleanText(t) then
                titleMatched = true
                break
            end
        end

        local contentMatched = false
        for _, c in ipairs(contentTargets) do
            if cTx:find(cleanText(c), 1, true) then
                contentMatched = true
                break
            end
        end

        if titleMatched or contentMatched then
            sampSendDialogResponse(dialogId, 0, 0, "")
            return false
        end
    end

    if dialogId == 32700 and dialogTitle:find("Меню бара") and mainIni.settings.autobar then
        lua_thread.create(function()
            sampSendDialogResponse(dialogId, 1, 0, -1)
            wait(300)
            sampSendDialogResponse(dialogId, 1, 0, -1)
            wait(300)
            sampSendDialogResponse(dialogId, 1, 0, -1)
            wait(300)
            sampSendDialogResponse(dialogId, 1, 0, -1)
            wait(300)
            sampCloseCurrentDialogWithButton(0)
        end)
    end

    if dialogTitle:find('Склад наркотиков') and dialogText:find('Наркотиков на руках') and mainIni.settings.autodrugs then
        local currentDrugs, maxDrugs = dialogText:match('Наркотиков на руках: {......}(%d+) {FFFFFF}/ {......}(%d+)')
        if tonumber(maxDrugs) and tonumber(currentDrugs) and tonumber(maxDrugs) > tonumber(currentDrugs) then
            sampSendDialogResponse(dialogId, 1, 0, maxDrugs - currentDrugs)
            lua_thread.create(closedialog)
        end
    end
end

function sampev.onServerMessage(color, text)
    if mainIni.settings.smskontr and text:find("Отправитель: Контрабандист") then return false end
    if mainIni.settings.uvedkontr and text:find("Сообщает: Контрабандист") then return false end

    if mainIni.settings.admCopyId then
        if text:find("Админы Online:") then admids = {} end
        local aId = text:match("| ID: (%d+)")
        if aId then
            table.insert(admids, aId)
            local admStr = "Admins Online: " .. table.concat(admids, ", ")
            setClipboard(admStr)
        end
    end

    if mainIni.settings.colorLeadersEnabled then
        for name, hex in pairs(factions) do
            local escapedName = name:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
            if text:find("^%s*" .. escapedName .. "%s*:") then
                local cleanText = text:gsub("{%x%x%x%x%x%x}", "")
                local r = tonumber(hex:sub(1, 2), 16)
                local g = tonumber(hex:sub(3, 4), 16)
                local b = tonumber(hex:sub(5, 6), 16)
                local msgColor = bit.bor(bit.lshift(r, 24), bit.lshift(g, 16), bit.lshift(b, 8), 0xFF)

                local formattedText, _ = addIdToNick(cleanText)
                return {msgColor, formattedText}
            end
        end
    end

    if mainIni.settings.colorRadioEnabled then
        local chatColorHex = bit.tohex(color):sub(1, 6):upper()
        if ALLOWED_COLORS[chatColorHex] then
            local prefix = text:match('^(%s+)') or ''
            local trimmed = text:sub(#prefix + 1)

            local isOOC = false
            local oocContent = trimmed:match('^%(%((.+)%)%)$')
            if oocContent then
                isOOC = true
                trimmed = oocContent:match('^%s*(.-)%s*$')
            end

            local rank, nick, id, msg
            if isOOC then
                rank, nick, id, msg = trimmed:match('^(.-)([%w_]+)%[(%d+)%]: (.+)$')
                if not nick then
                    rank, nick, msg = trimmed:match('^(.-)([%w_]+): (.+)$')
                    if nick then
                        id = getIdByName(nick)
                    end
                end
            else
                rank, nick, id, msg = parseRadioMessage(trimmed)
            end

            if nick and msg then
                local pid = tonumber(id)
                local nickColor = (pid and getColorById(pid)) or chatColorHex

                if rank then rank = rank:match('^(.-)%s*$') end
                local rankPart = (rank and #rank > 0) and ('{' .. chatColorHex .. '}' .. rank .. ' ') or ''

                local new_text
                if isOOC then
                    local idStr = pid and ('[' .. pid .. ']') or ''
                    new_text = string.format('%s(( %s{%s}%s%s{%s}: %s ))',
                        prefix, rankPart, nickColor, nick, idStr, chatColorHex, msg)
                else
                    local idStr = id and ('[' .. id .. ']') or ''
                    new_text = string.format('%s%s{%s}%s%s{%s}: %s',
                        prefix, rankPart, nickColor, nick, idStr, chatColorHex, msg)
                end

                if mainIni.settings.chatIdEnabled then
                    new_text, _ = addIdToNick(new_text)
                end

                return {color, new_text}
            end
        end
    end

    if mainIni.settings.membersEnabled then
        if text:find("Члены организации Он%-лайн:") then
            isOrgList = true
            totalAFK, inStream, streamAFK = 0, 0, 0
            return {color, text}
        end

        if isOrgList and text:find("ID: (%d+)") then
            local id = tonumber(text:match("ID: (%d+)"))
            if id then
                local _, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
                local isMe = (id == myId)
                local isPlayerAFK = text:find("%[AFK%]")
                if isPlayerAFK then totalAFK = totalAFK + 1 end

                local isInStream = false
                if isMe then
                    isInStream = true
                else
                    local result, handle = sampGetCharHandleBySampPlayerId(id)
                    isInStream = result and doesCharExist(handle)
                end

                local pColor = sampGetPlayerColor(id)
                local hex = string.format("%06X", bit.band(pColor, 0xFFFFFF))

                local r = bit.band(bit.rshift(pColor, 16), 0xFF)
                local g = bit.band(bit.rshift(pColor, 8),  0xFF)
                local b = bit.band(pColor, 0xFF)
                local msgColor = bit.bor(bit.lshift(r, 24), bit.lshift(g, 16), bit.lshift(b, 8), 0xFF)

                local statusPart = text:match("({%x+}На работе)") or text:match("({%x+}Выходной)")
                local cleanText = text:gsub("{%x+}", ""):gsub("^%s+", "")

                local finalStr, _ = addIdToNick(cleanText)

                if statusPart then
                    local statusClean = statusPart:gsub("{%x+}", "")
                    finalStr = finalStr:gsub(statusClean, statusPart .. "{" .. hex .. "}")
                end

                if isPlayerAFK then
                    finalStr = finalStr:gsub("(%s*|%s*%[AFK%].-)$", "{FFFFFF}%1")
                end

                if not isMe then
                    if isInStream then
                        inStream = inStream + 1
                        finalStr = finalStr .. " {009900}•"
                        if isPlayerAFK then streamAFK = streamAFK + 1 end
                    else
                        finalStr = finalStr .. " {FF0000}•"
                    end
                end

                return {msgColor, finalStr}
            end
        end

        if isOrgList and text:find("Всего: %d+ человек") then
            local totalInOrg = text:match("Всего: (%d+)")
            isOrgList = false
            local finalStats = string.format("[Всего: %s человек / AFK: %d] [В зоне стрима: %d / AFK: %d]",
                totalInOrg, totalAFK, inStream, streamAFK)
            return {color, finalStats}
        end
    end

    if mainIni.settings.chatIdEnabled and not isOrgList then
        local newText, changed = addIdToNick(text)
        if changed then return {color, newText} end
    end
end

imgui.OnFrame(function() return showMenu[0] end, function(player)
    local style = imgui.GetStyle()
    style.WindowRounding = 6.0
    style.Colors[imgui.Col.WindowBg] = imgui.ImVec4(0.12, 0.12, 0.12, 0.94)
    style.Colors[imgui.Col.TitleBg] = imgui.ImVec4(0.20, 0.20, 0.20, 1.00)
    style.Colors[imgui.Col.TitleBgActive] = imgui.ImVec4(0.25, 0.25, 0.25, 1.00)
    style.Colors[imgui.Col.FrameBg] = imgui.ImVec4(0.20, 0.20, 0.20, 1.00)
    style.Colors[imgui.Col.CheckMark] = imgui.ImVec4(0.90, 0.90, 0.90, 1.00)

    imgui.SetNextWindowPos(imgui.ImVec2(getScreenResolution() / 2, select(2, getScreenResolution()) / 2), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))
    imgui.SetNextWindowSize(imgui.ImVec2(380, 610), imgui.Cond.Always)

    if imgui.Begin(u8"Настройки EvolveChatHelper", showMenu, imgui.WindowFlags.NoResize + imgui.WindowFlags.NoCollapse) then
        imgui.Spacing()
        if imgui.Checkbox(u8"Инфо-панель чата", imgui.new.bool(mainIni.settings.chatPanelEnabled)) then
            mainIni.settings.chatPanelEnabled = not mainIni.settings.chatPanelEnabled
            inicfg.save(mainIni, directIni)
        end
        imgui.Spacing()

        if imgui.Checkbox(u8"Копирование строк / ников из чата", imgui.new.bool(mainIni.settings.chatCopyEnabled)) then
            mainIni.settings.chatCopyEnabled = not mainIni.settings.chatCopyEnabled
            inicfg.save(mainIni, directIni)
            if not mainIni.settings.chatCopyEnabled then resetUi() end
        end
        imgui.Spacing()

        if imgui.Checkbox(u8"Улучшенный /members", imgui.new.bool(mainIni.settings.membersEnabled)) then
            mainIni.settings.membersEnabled = not mainIni.settings.membersEnabled
            inicfg.save(mainIni, directIni)
        end
        imgui.TextDisabled(u8"  (Цветной мемберс, AFK-стата, зона стрима)")

        if imgui.Checkbox(u8"Подсветка лидеров", imgui.new.bool(mainIni.settings.colorLeadersEnabled)) then
            mainIni.settings.colorLeadersEnabled = not mainIni.settings.colorLeadersEnabled
            inicfg.save(mainIni, directIni)
        end
        imgui.TextDisabled(u8"  (Полное окрашивание строк лидеров в /dir)")

        if imgui.Checkbox(u8"Показывать ID в чате", imgui.new.bool(mainIni.settings.chatIdEnabled)) then
            mainIni.settings.chatIdEnabled = not mainIni.settings.chatIdEnabled
            inicfg.save(mainIni, directIni)
        end
        imgui.TextDisabled(u8"  (Добавляет [ID] к никам во всем чате)")

        if imgui.Checkbox(u8"Цветные ники в /f и /r чатах", imgui.new.bool(mainIni.settings.colorRadioEnabled)) then
            mainIni.settings.colorRadioEnabled = not mainIni.settings.colorRadioEnabled
            inicfg.save(mainIni, directIni)
        end
        imgui.TextDisabled(u8"  (Цвет ника и ID из TAB в рации фракции)")

        if imgui.Checkbox(u8"Копирование ника по ID (/cn)", imgui.new.bool(mainIni.settings.copyNickEnabled)) then
            mainIni.settings.copyNickEnabled = not mainIni.settings.copyNickEnabled
            inicfg.save(mainIni, directIni)
        end
        imgui.TextDisabled(u8"  (Копирование ника через /cn [id])")

        if imgui.Checkbox(u8"Копировать ID админов из /admins", imgui.new.bool(mainIni.settings.admCopyId)) then
            mainIni.settings.admCopyId = not mainIni.settings.admCopyId
            inicfg.save(mainIni, directIni)
        end
        imgui.TextDisabled(u8"  (Авто-копирование списка ID админов в буфер)")

        if imgui.Checkbox(u8"Быстрый /lock на 'L'", imgui.new.bool(mainIni.settings.lockEnabled)) then
            mainIni.settings.lockEnabled = not mainIni.settings.lockEnabled
            inicfg.save(mainIni, directIni)
        end
        imgui.TextDisabled(u8"  (Нажмите L чтобы открыть/закрыть транспорт)")

        if imgui.Checkbox(u8"Скрыть окно Зеленой Зоны", imgui.new.bool(mainIni.settings.antizz)) then
            mainIni.settings.antizz = not mainIni.settings.antizz
            inicfg.save(mainIni, directIni)
        end

        if imgui.Checkbox(u8"Скрывать предложение установить Evolve-Launcher", imgui.new.bool(mainIni.settings.hideLauncher)) then
            mainIni.settings.hideLauncher = not mainIni.settings.hideLauncher
            inicfg.save(mainIni, directIni)
        end

        if imgui.Checkbox(u8"Автоматически пополнять бар со склада байкеров", imgui.new.bool(mainIni.settings.autobar)) then
            mainIni.settings.autobar = not mainIni.settings.autobar
            inicfg.save(mainIni, directIni)
        end

        if imgui.Checkbox(u8"Автовзятие нарко со склада байкеров", imgui.new.bool(mainIni.settings.autodrugs)) then
            mainIni.settings.autodrugs = not mainIni.settings.autodrugs
            inicfg.save(mainIni, directIni)
        end

        if imgui.Checkbox(u8"Автоответы Spongebozz (Мафия/Гетто)", imgui.new.bool(mainIni.settings.autoSpongebozz)) then
            mainIni.settings.autoSpongebozz = not mainIni.settings.autoSpongebozz
            inicfg.save(mainIni, directIni)
        end

        if imgui.Checkbox(u8"Автоответы в Автошколе", imgui.new.bool(mainIni.settings.autoSchool)) then
            mainIni.settings.autoSchool = not mainIni.settings.autoSchool
            inicfg.save(mainIni, directIni)
        end

        imgui.Spacing()
        if imgui.Checkbox(u8"Скрыть SMS от Контрабандиста", imgui.new.bool(mainIni.settings.smskontr)) then
            mainIni.settings.smskontr = not mainIni.settings.smskontr
            inicfg.save(mainIni, directIni)
        end
        if imgui.Checkbox(u8"Скрыть уведомления о поставках", imgui.new.bool(mainIni.settings.uvedkontr)) then
            mainIni.settings.uvedkontr = not mainIni.settings.uvedkontr
            inicfg.save(mainIni, directIni)
        end
        imgui.End()
    end
end)