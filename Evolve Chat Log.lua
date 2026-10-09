script_author("Impressive")
script_name('Evolve Chat Log')
local imgui = require 'mimgui'
local ffi = require 'ffi'
local encoding = require 'encoding'
local samp = require 'samp.events'
local inicfg = require 'inicfg'
local bit = require 'bit'
local vkeys = require 'vkeys'

encoding.default = 'CP1251'
local u8 = encoding.UTF8
local cp1251 = encoding.CP1251

local _sw, _sh = getScreenResolution()
local scale = math.min(_sw / 1920, _sh / 1080)
if scale < 0.5 then scale = 0.5 end
if scale > 2.0 then scale = 2.0 end
local function S(v)
    return math.floor(v * scale + 0.5)
end

ffi.cdef[[
    typedef struct {
        uint32_t dwFileAttributes;
        uint32_t ftCreationTime[2];
        uint32_t ftLastAccessTime[2];
        uint32_t ftLastWriteTime[2];
        uint32_t nFileSizeHigh;
        uint32_t nFileSizeLow;
        uint32_t dwReserved0;
        uint32_t dwReserved1;
        char     cFileName[260];
        char     cAlternateFileName[14];
    } WIN32_FIND_DATAA;
    void* FindFirstFileA(const char* lpFileName, WIN32_FIND_DATAA* lpFindFileData);
    bool FindNextFileA(void* hFindFile, WIN32_FIND_DATAA* lpFindFileData);
    bool FindClose(void* hFindFile);

    bool OpenClipboard(void* hWndNewOwner);
    bool CloseClipboard();
    bool EmptyClipboard();
    void* SetClipboardData(uint32_t uFormat, void* hMem);
    void* GlobalAlloc(uint32_t uFlags, size_t dwBytes);
    void* GlobalLock(void* hMem);
    bool GlobalUnlock(void* hMem);
    bool GlobalFree(void* hMem);
    int MultiByteToWideChar(uint32_t CodePage, uint32_t dwFlags, const char* lpMultiByteStr, int cbMultiByte, wchar_t* lpWideCharStr, int cchWideChar);

    int SHGetFolderPathA(void* hwnd, int csidl, void* hToken, uint32_t dwFlags, char* pszPath);
]]

local shell32 = ffi.load("shell32")

local pathsToCheck = {}
local nativeLogPath = ""
local lastChatlogSize = 0

local activeTab = 1

local function cp1251_lower(s)
    local res = ""
    for i = 1, #s do
        local b = s:byte(i)
        if b >= 192 and b <= 223 then res = res .. string.char(b + 32)
        elseif b == 168 then res = res .. string.char(184)
        else res = res .. string.char(b):lower() end
    end
    return res
end

local function ensure_cp1251(str)
    if str:find("\xD0") or str:find("\xD1") then
        return u8:encode(str)
    end
    return str
end

local function make_pattern(str)
    local cp = ensure_cp1251(str)
    return cp1251_lower(cp)
end

local STATE_KEYWORDS_BY_FACTION = {
    army = {
        "рядовой", "ефрейтор", "младший сержант", "мл%. сержант", "мл%.сержант",
        "сержант", "старший сержант", "ст%. сержант", "ст%.сержант", "старшина",
        "прапорщик", "младший лейтенант", "мл%. лейтенант", "мл%.лейтенант",
        "лейтенант", "старший лейтенант", "ст%. лейтенант", "ст%.лейтенант",
        "капитан", "майор", "подполковник", "полковник", "генерал"
    },
    hospital = {
        "интерн", "санитар", "медицинский брат", "медбрат", "мед%. брат", "мед%.брат",
        "спасатель", "нарколог", "доктор", "психолог", "псисхолог", "хирург",
        "заместитель главного врача", "зам%. главного врача", "зам%.главного врача",
        "зам%. глав%. врача", "зам%.глав%.врача", "главный врач", "гл%. врач", "гл%.врач"
    },
    police = {
        "кадет", "офицер", "ст%. прапорщик", "ст%.прапорщик", "шериф"
    },
    government = {
        "охранник", "юрист", "координатор", "менеджер", "глава лицензирования",
        "глава аппарата", "заместитель губернатора", "зам%. губернатора", "зам%.губернатора",
        "губернатор"
    },
    fbi = {
        "стажер", "стажёр", "дежурный", "младший агент", "мл%. агент", "мл%.агент",
        "агент dea", "агент cid", "глава dea", "глава cid", "инспектор",
        "заместитель директора", "зам%. директора", "зам%.директора", "директор"
    }
}

local CYAN_KEYWORDS_BY_FACTION = {
    gangs = {
        "блайд", "младший нига", "крэкер", "гун бро", "ап бро", "гангстер", "федерал блок", "фолкс", "райч нига", "биг вилли",
        "новатто", "ординарио", "локал", "верификадо", "бандито", "v%.e%.g", "ассесино", "лидер v%.e%.g", "падрино", "падре",
        "плэйя", "хастла", "килла", "юонг", "гангста", "о%. %г%.", "о%.г%.", "мобста", "де кинг", "легенд", "мэд дог",
        "перро", "тирадор", "геттор", "лас геррас", "мирандо", "сабио", "инвасор", "тесореро", "нестро",
        "новато", "ладрон", "амиго", "мачо", "джуниор", "эрмано", "бандидо", "ауториад", "аджунто"
    },
    bikers = {
        "support", "hang around", "prospect", "member", "road captain", "sergeant%-at%-arms", "treasurer", "vice%-president", "president"
    },
    mafia = {
        "новицио", "шнырь", "вакасю", "ассосиато", "фраер", "сятей", "сомбаттенте", "бык", "кедай", "солдато", "барыга", "фуку%-комбуте",
        "блатной", "вагакасира", "сотто%-капо", "свояк", "со%-хомбуте", "капо", "браток", "камбу", "младший босс", "вор в законе", "вор",
        "сайко%-комон", "консильери", "оядзи", "дон", "авторитет", "кумите"
    },
    news = {
        "звукооператор", "звукорежиссер", "звукорежиссёр", "репортер", "репортёр", "ведущий", "редактор",
        "главный редактор", "гл%. редактор", "гл%.редактор", "технический директор", "тех%. директор", "тех%.директор",
        "программный директор", "прог%. директор", "прог%.директор", "генеральный директор", "ген%. директор", "ген%.директор",
        "зам%. генерального директора", "зам%. ген%. директора", "зам%. ген%.директора", "зам%.ген%.директора"
    }
}

local STATE_KEYWORDS_RAW = {}
for _, group in pairs(STATE_KEYWORDS_BY_FACTION) do
    for _, kw in ipairs(group) do
        table.insert(STATE_KEYWORDS_RAW, kw)
    end
end

local CYAN_KEYWORDS_RAW = {}
for _, group in pairs(CYAN_KEYWORDS_BY_FACTION) do
    for _, kw in ipairs(group) do
        table.insert(CYAN_KEYWORDS_RAW, kw)
    end
end

local STATE_PATTERNS = {}
for _, kw in ipairs(STATE_KEYWORDS_RAW) do
    table.insert(STATE_PATTERNS, make_pattern(kw))
end

local CYAN_PATTERNS = {}
for _, kw in ipairs(CYAN_KEYWORDS_RAW) do
    table.insert(CYAN_PATTERNS, make_pattern(kw))
end

local function isStateMessage(lowLine)
    for _, pattern in ipairs(STATE_PATTERNS) do
        if lowLine:find(pattern) ~= nil then
            return true
        end
    end
    return false
end

local function isCyanMessage(lowLine)
    for _, pattern in ipairs(CYAN_PATTERNS) do
        if lowLine:find(pattern) ~= nil then
            return true
        end
    end
    return false
end

local PATTERNS = {
    ads = {
        make_pattern("объявление:"),
        make_pattern("объявления:"),
        make_pattern("отредактировал сотрудник"),
        make_pattern("news:")
    }
}

local function isPunishment(line)
    if not line or line == "" then return false end
    local clean = line:gsub("^%[%d%d:%d%d:%d%d%]%s*", ""):gsub("{%x%x%x%x%x%x}", ""):gsub("^%s*", "")
    local v_low = cp1251_lower(clean)

    if v_low:find("^offprison%[") or v_low:find("^offmute%[") or v_low:find("^offban%[")
    or v_low:find("^ioffban%[") or v_low:find("^sban%[") or v_low:find("^siban%[") then
        return true
    end

    if v_low:find(make_pattern("в чс фракций:")) or v_low:find(make_pattern("забанил ip:")) then
        return true
    end

    local hasAdmin = v_low:find(make_pattern("администратор")) ~= nil
    if hasAdmin then
        local adminKeywords = {
            make_pattern("деморган"),
            make_pattern("забанил"),
            make_pattern("выдал warn"),
            make_pattern("выдал варн"),
            make_pattern("выдал мут"),
            make_pattern("выдал затычку"),
            make_pattern("снял затычку"),
            make_pattern("заблокировал чат"),
            make_pattern("разблокировал чат"),
            make_pattern("кикнул"),
            make_pattern("поместил в"),
            make_pattern("заблокировал"),
            make_pattern("заглушил"),
            make_pattern("причина:")
        }
        for _, kw in ipairs(adminKeywords) do
            if v_low:find(kw, 1, true) then
                return true
            end
        end
    end

    return false
end

local function isSms(line)
    if not line or line == "" then return false end
    local clean = line:gsub("^%[%d%d:%d%d:%d%d%]%s*", ""):gsub("{%x%x%x%x%x%x}", ""):gsub("^%s*", "")
    if clean:find("^SMS%:") then
        if clean:find("%. Отправитель%:") or clean:find("%. Получатель%:") then
            return true
        end
    end
    return false
end

local function isAd(line)
    if not line or line == "" then return false end
    local clean = line:gsub("^%[%d%d:%d%d:%d%d%]%s*", ""):gsub("{%x%x%x%x%x%x}", ""):gsub("^%s*", "")
    if clean:find("^%-%s*[%a%d_]+%[%d+%]%:") or clean:find("^%-%s") then
        return false
    end
    local cleanLow = cp1251_lower(clean)
    for _, p in ipairs(PATTERNS.ads) do
        if cleanLow:find(p, 1, true) ~= nil then return true end
    end
    return false
end

function isRadio(line)
    if not line or line == "" then return false end
    local clean = line:gsub("^%[%d%d:%d%d:%d%d%]%s*", ""):gsub("{%x%x%x%x%x%x}", ""):gsub("^%s*", ""):gsub("%s*$", "")
    
    if clean:find("^%-%s*[%a%d_]+%[%d+%]%:") or clean:find("^%-%s") then
        return false
    end

    if clean:find("^%[") or clean:find("^%<") then
        return false
    end

    local lowClean = cp1251_lower(clean)
    if lowClean:find(make_pattern("спавн свободных транспортных средств")) or
       lowClean:find(make_pattern("заспавнил свободные транспортные средства")) or
       lowClean:find(make_pattern("отменил спавн свободных транспортных средств")) or
       lowClean:find(make_pattern("открыл доступ к складу с материалами")) or
       lowClean:find(make_pattern("закрыл доступ к складу с материалами")) or
       lowClean:find(make_pattern("разгрузил на склад")) or
       lowClean:find(make_pattern("отобрал рацию")) or
       lowClean:find(make_pattern("вернул рацию")) or
       (lowClean:find(make_pattern("купил")) and lowClean:find(make_pattern("материалов")) and lowClean:find(make_pattern("на общий склад мафии за"))) then
        return true
    end

    if lowClean:find(make_pattern("уволил из организации")) then
        local rankStr = clean:match("^(.-)%s*[%a%d_]+%[%d+%]%s+уволил из организации")
        if rankStr then
            rankStr = rankStr:match("^%s*(.-)%s*$")
            if #rankStr > 0 then
                local rankLow = cp1251_lower(rankStr)
                if isStateMessage(rankLow) or isCyanMessage(rankLow) then
                    return true
                end
            end
        end
        return false
    end

    local oocText = clean:match("^%(%(%s*(.+)$")
    if oocText then
        oocText = oocText:gsub("%s*%)%s*$", "")
        if oocText:find("^%[") or oocText:find("^%<") then
            return false
        end
        local rankStr, nick, id, msg = oocText:match("^(.-)%s*([%a%d_]+)%[(%d+)%]:%s*(.+)$")
        if rankStr and nick and id and msg then
            rankStr = rankStr:match("^%s*(.-)%s*$")
            if #rankStr > 0 then
                local rankLow = cp1251_lower(rankStr)
                if isStateMessage(rankLow) or isCyanMessage(rankLow) then
                    return true
                end
            end
        end
        return false
    end

    local rankStr, nick, id, msg = clean:match("^(.-)%s*([%a%d_]+)%[(%d+)%]:%s*(.+)$")
    if rankStr and nick and id and msg then
        rankStr = rankStr:match("^%s*(.-)%s*$")
        if #rankStr > 0 then
            local rankLow = cp1251_lower(rankStr)
            if isStateMessage(rankLow) or isCyanMessage(rankLow) then
                return true
            end
        end
    end

    return false
end

local function matchesTabFilterParsed(v, tabIdx)
    if tabIdx == 1 then return true
    elseif tabIdx == 2 then return v.isPun
    elseif tabIdx == 3 then return v.isSms
    elseif tabIdx == 4 then return true
    elseif tabIdx == 5 then return v.isAd
    end
    return true
end

local function initChatlogPaths()
    local path = ffi.new("char[260]")
    local docs = ""
    if shell32.SHGetFolderPathA(nil, 5, nil, 0, path) == 0 then
        docs = ffi.string(path)
    else
        docs = os.getenv('USERPROFILE') .. "\\Documents"
    end
    pathsToCheck = {
        docs .. "\\GTA San Andreas User Files\\SAMP\\chatlog.txt",
        docs .. "\\GTA San Andreas User Files\\Evolve\\chatlog.txt"
    }
    nativeLogPath = pathsToCheck[1]
end

local function updateNativeChatlogPath()
    local latestPath = nativeLogPath ~= "" and nativeLogPath or pathsToCheck[1]
    local maxHigh, maxLow = 0, 0
    
    for _, path in ipairs(pathsToCheck) do
        local findData = ffi.new("WIN32_FIND_DATAA")
        local hFind = ffi.C.FindFirstFileA(path, findData)
        if hFind ~= ffi.cast("void*", -1) then
            ffi.C.FindClose(hFind)
            local low = findData.ftLastWriteTime[0]
            local high = findData.ftLastWriteTime[1]
            if high > maxHigh or (high == maxHigh and low > maxLow) then
                maxHigh = high
                maxLow = low
                latestPath = path
            end
        end
    end
    
    if nativeLogPath ~= latestPath then
        nativeLogPath = latestPath
        if doesFileExist(nativeLogPath) then
            local f = io.open(nativeLogPath, "r")
            if f then
                lastChatlogSize = f:seek("end")
                f:close()
            end
        else
            lastChatlogSize = 0
        end
    end
end

initChatlogPaths()
updateNativeChatlogPath()

local function setClipboard(text)
    if text == nil or text == "" then return end
    local wide_str = cp1251:decode(text)
    wide_str = u8:decode(wide_str)
    
    local len = ffi.C.MultiByteToWideChar(1251, 0, text, #text, nil, 0)
    if len > 0 then
        local bufSize = (len + 1) * 2
        local hMem = ffi.C.GlobalAlloc(0x0042, bufSize)
        if hMem ~= nil then
            local pMem = ffi.C.GlobalLock(hMem)
            if pMem ~= nil then
                ffi.C.MultiByteToWideChar(1251, 0, text, #text, ffi.cast("wchar_t*", pMem), len)
                ffi.C.GlobalUnlock(hMem)
                if ffi.C.OpenClipboard(nil) then
                    ffi.C.EmptyClipboard()
                    ffi.C.SetClipboardData(13, hMem)
                    ffi.C.CloseClipboard()
                else
                    ffi.C.GlobalFree(hMem)
                end
            end
        end
    end
end

local eCrimePath = getWorkingDirectory() .. "\\E-CRIME\\"
local eLogsPath = eCrimePath .. "Logs\\"
local logPath = eLogsPath .. "Chatlog\\"
local dateLogPath = logPath .. "Date Chatlog\\"

if not doesDirectoryExist(eCrimePath) then createDirectory(eCrimePath) end
if not doesDirectoryExist(eLogsPath) then createDirectory(eLogsPath) end
if not doesDirectoryExist(logPath) then createDirectory(logPath) end
if not doesDirectoryExist(dateLogPath) then createDirectory(dateLogPath) end

local directIni = "Evolve-ChatLog.ini"
local mainIni = inicfg.load({
    settings = {
        save_all = true,
        save_punishments = true,
        save_sms = true,
        save_radio = true,
        save_ads = true
    }
}, directIni)

inicfg.save(mainIni, directIni)

local WinState = imgui.new.bool(false)
local SearchBuffer = imgui.new.char[256]('')
local SelectedDate = ""
local FileContent = {} 
local FilteredContent = {}
local needRefilter = true
local lastLoadedPos = 0
local LogFiles = {}

local copiedIndex = -1 
local copyType = "" 
local showCopiedUntil = 0 
local NeedScroll = false
local lastUpdate = 0

local closedTime = 0
local lastWinState = false
local userScrolledUp = false
local lastScrollY = 0
local SearchInputActive = false

local pendingClose = false

local WM_KEYFIRST, WM_KEYLAST = 0x0100, 0x0109
local WM_MOUSEFIRST, WM_MOUSELAST = 0x0200, 0x020E

local lastActiveSearchBuffer = ""
local wasActiveSearchBuffer = false

local function safe_u8(text) return (text and text ~= "") and u8(text) or "" end

local function safe_decode_search()
    local str = ffi.string(SearchBuffer)
    if str == "" then return "" end
    local ok, res = pcall(function() return u8:decode(str) end)
    if ok and res then
        return cp1251_lower(res)
    end
    return ""
end

local function refilterContent()
    FilteredContent = {}
    local q = safe_decode_search()
    for i = 1, #FileContent do
        local v = FileContent[i]
        if matchesTabFilterParsed(v, activeTab) then
            if q == "" or v.low:find(q, 1, true) then 
                table.insert(FilteredContent, v.raw) 
            end
        end
    end
    needRefilter = false
end

local function findNicknames(text)
    local nicks = {}
    local seen = {}
    for nick in text:gmatch("[%a%d]+_[%a%d]+") do
        if not seen[nick] then table.insert(nicks, nick); seen[nick] = true end
    end
    return nicks
end

local function getNickWithClistColor(nickname)
    local result, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
    if result then
        if sampGetPlayerNickname(myId) == nickname then
            local clr = sampGetPlayerColor(myId)
            local rgb = bit.band(clr, 0x00FFFFFF)
            return string.format("{%06X}%s", rgb, nickname)
        end
    end

    for i = 0, 1000 do
        if sampIsPlayerConnected(i) then
            if sampGetPlayerNickname(i) == nickname then
                local clr = sampGetPlayerColor(i)
                local rgb = bit.band(clr, 0x00FFFFFF)
                return string.format("{%06X}%s", rgb, nickname)
            end
        end
    end
    return "{00FF00}" .. nickname
end

local function getTargetFileName(tabIdx)
    if tabIdx == 1 then return "chatlog.txt"
    elseif tabIdx == 2 then return "punishments.txt"
    elseif tabIdx == 3 then return "sms.txt"
    elseif tabIdx == 4 then return "radio.txt"
    elseif tabIdx == 5 then return "ads.txt"
    end
    return "chatlog.txt"
end

function updateFileList()
    LogFiles = {}
    local findData = ffi.new("WIN32_FIND_DATAA")
    local hFind = ffi.C.FindFirstFileA(dateLogPath .. "*", findData)
    
    local todayStr = os.date("%d-%m-%Y")
    local nowTime = os.time()
    local sevenDaysAgo = nowTime - (7 * 24 * 60 * 60)

    if hFind ~= ffi.cast("void*", -1) then
        repeat
            local fileName = ffi.string(findData.cFileName)
            if fileName ~= "." and fileName ~= ".." then
                local dateStr = fileName:match("^(%d+%-%d+%-%d+)")
                if dateStr then
                    local d, m, y = dateStr:match("^(%d+)%-(%d+)%-(%d+)$")
                    if d and m and y then
                        local fileTime = os.time({day = tonumber(d), month = tonumber(m), year = tonumber(y), hour = 0, min = 0, sec = 0})
                        if fileTime >= sevenDaysAgo or dateStr == todayStr then
                            table.insert(LogFiles, {
                                name = dateStr,
                                time = fileTime
                            })
                        end
                    end
                end
            end
        until not ffi.C.FindNextFileA(hFind, findData)
        ffi.C.FindClose(hFind)
    end
    
    table.sort(LogFiles, function(a, b) return a.time > b.time end)
    
    local temp = {}
    for i, fileData in ipairs(LogFiles) do
        table.insert(temp, fileData.name)
    end
    LogFiles = temp
end

function loadLogFile(dateStr, isAutoUpdate)
    if not dateStr or dateStr == "" then return end
    SelectedDate = dateStr
    
    local folderPath = dateLogPath .. dateStr .. "\\"
    local targetFile = getTargetFileName(activeTab)
    local fullFilePath = folderPath .. targetFile
    
    if not doesFileExist(fullFilePath) then
        fullFilePath = folderPath .. "chatlog.txt"
    end
    
    if doesFileExist(fullFilePath) then
        local f = io.open(fullFilePath, "r")
        if f then
            if not isAutoUpdate then
                FileContent = {}
                FilteredContent = {}
                lastLoadedPos = 0
            else
                f:seek("set", lastLoadedPos)
            end

            local q = safe_decode_search()
            for line in f:lines() do
                local low = cp1251_lower(line)
                local item = {
                    raw = line,
                    low = low,
                    isPun = isPunishment(line),
                    isSms = isSms(line),
                    isAd = isAd(line),
                    isState = isStateMessage(low),
                    isCyan = isCyanMessage(low)
                }
                table.insert(FileContent, item)
                
                if isAutoUpdate then
                    if matchesTabFilterParsed(item, activeTab) then
                        if q == "" or item.low:find(q, 1, true) then
                            table.insert(FilteredContent, item.raw)
                        end
                    end
                end
            end
            lastLoadedPos = f:seek("end")
            f:close()

            if not isAutoUpdate then 
                NeedScroll = true 
                userScrolledUp = false 
                needRefilter = true
            end
        end
    else
        FileContent = {}
        FilteredContent = {}
        lastLoadedPos = 0
        needRefilter = true
    end
end

local function ensureTodaySelected()
    local today = os.date("%d-%m-%Y")
    local todayFolder = dateLogPath .. today .. "\\"
    if not doesDirectoryExist(todayFolder) then createDirectory(todayFolder) end
    
    if SelectedDate == "" or SelectedDate == nil then
        SelectedDate = today
        loadLogFile(today, false)
    end
end

function onWindowMessage(msg, wparam, lparam)
    if not WinState[0] then return end

    local io = imgui.GetIO()
    local wantKeyboard = io.WantCaptureKeyboard or io.WantTextInput
    local wantMouse = io.WantCaptureMouse

    if wparam == vkeys.VK_ESCAPE then
        if msg == 0x0100 or msg == 0x0104 then
            consumeWindowMessage(true, true)
            return
        elseif msg == 0x0101 or msg == 0x0105 then
            consumeWindowMessage(true, true)
            pendingClose = true
            return
        end
    end

    if wantKeyboard and (msg >= WM_KEYFIRST and msg <= WM_KEYLAST) then
        consumeWindowMessage(true, true)
        return
    end

    if wantMouse and (msg >= WM_MOUSEFIRST and msg <= WM_MOUSELAST) then
        consumeWindowMessage(true, true)
        return
    end
end

imgui.OnInitialize(function()
    local style = imgui.GetStyle()
    style.WindowRounding = 10.0 * scale
    style.ChildRounding = 6.0 * scale
    style.FrameRounding = 5.0 * scale
    style.ItemSpacing = imgui.ImVec2(S(8), S(4))
    style.ScrollbarSize = S(12)
    style.ScrollbarRounding = 4.0 * scale
    
    local colors = style.Colors
    colors[imgui.Col.WindowBg] = imgui.ImVec4(0.07, 0.08, 0.11, 1.00)
    colors[imgui.Col.ChildBg] = imgui.ImVec4(0.09, 0.10, 0.14, 1.00)
    colors[imgui.Col.FrameBg] = imgui.ImVec4(0.12, 0.13, 0.17, 1.00)
    colors[imgui.Col.FrameBgHovered] = imgui.ImVec4(0.15, 0.17, 0.22, 1.00)
    colors[imgui.Col.Button] = imgui.ImVec4(0.18, 0.20, 0.27, 1.00)
    colors[imgui.Col.ButtonHovered] = imgui.ImVec4(0.16, 0.48, 0.43, 1.00)
    colors[imgui.Col.ButtonActive] = imgui.ImVec4(0.12, 0.40, 0.35, 1.00)
    colors[imgui.Col.Text] = imgui.ImVec4(0.90, 0.92, 0.95, 1.00)
    colors[imgui.Col.TitleBg] = imgui.ImVec4(0.07, 0.08, 0.11, 1.00)
    colors[imgui.Col.TitleBgActive] = imgui.ImVec4(0.09, 0.10, 0.14, 1.00)

    imgui.GetIO().FontGlobalScale = scale
end)

imgui.OnFrame(function() return WinState[0] end, function(player)
    player.HideCursor = false
    player.LockPlayer = true

    ensureTodaySelected()
    local sw, sh = getScreenResolution()
    imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    imgui.SetNextWindowSize(imgui.ImVec2(S(1200), S(800)), imgui.Cond.FirstUseEver)
    
    imgui.Begin("##main_window", WinState, imgui.WindowFlags.NoCollapse)
    
    imgui.BeginChild("TopTabsNav", imgui.ImVec2(0, S(32)), false)
        local tabs = { safe_u8"Весь чат", safe_u8"Наказания", safe_u8"SMS", safe_u8"Рация", safe_u8"Объявления" }
        local totalWidth = imgui.GetWindowWidth() - 16
        local tabWidth = totalWidth / #tabs

        for idx, tabName in ipairs(tabs) do
            if idx > 1 then imgui.SameLine(0, S(4)) end
            if activeTab == idx then
                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.16, 0.48, 0.43, 1.00))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.18, 0.52, 0.47, 1.00))
            else
                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.12, 0.13, 0.17, 1.00))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.18, 0.20, 0.27, 1.00))
            end

            if imgui.Button(tabName, imgui.ImVec2(tabWidth - S(4), S(28))) then
                if activeTab ~= idx then
                    activeTab = idx
                    NeedScroll = true
                    if SelectedDate ~= "" then
                        loadLogFile(SelectedDate, false)
                    end
                end
            end
            imgui.PopStyleColor(2)
        end
    imgui.EndChild()

    imgui.Separator()
    imgui.Spacing()

    imgui.BeginChild("Tool", imgui.ImVec2(0, S(44)), true, imgui.WindowFlags.NoScrollbar)
        imgui.SetCursorPosY(S(8))
        
        local currentSaveBool = imgui.new.bool(false)
        if activeTab == 1 then currentSaveBool[0] = mainIni.settings.save_all
        elseif activeTab == 2 then currentSaveBool[0] = mainIni.settings.save_punishments
        elseif activeTab == 3 then currentSaveBool[0] = mainIni.settings.save_sms
        elseif activeTab == 4 then currentSaveBool[0] = mainIni.settings.save_radio
        elseif activeTab == 5 then currentSaveBool[0] = mainIni.settings.save_ads
        end

        local checkboxText = "Записывать весь чат"
        if activeTab == 2 then checkboxText = "Записывать наказания"
        elseif activeTab == 3 then checkboxText = "Записывать SMS"
        elseif activeTab == 4 then checkboxText = "Записывать рацию"
        elseif activeTab == 5 then checkboxText = "Записывать объявления"
        end

        if imgui.Checkbox(safe_u8(checkboxText), currentSaveBool) then
            if activeTab == 1 then mainIni.settings.save_all = currentSaveBool[0]
            elseif activeTab == 2 then mainIni.settings.save_punishments = currentSaveBool[0]
            elseif activeTab == 3 then mainIni.settings.save_sms = currentSaveBool[0]
            elseif activeTab == 4 then mainIni.settings.save_radio = currentSaveBool[0]
            elseif activeTab == 5 then mainIni.settings.save_ads = currentSaveBool[0]
            end
            inicfg.save(mainIni, directIni)
            
            local statusText = currentSaveBool[0] and "{00FF00}включено" or "{FF0000}выключено"
            sampAddChatMessage(string.format("{4A90E2}[ChatLog] {FFFFFF}%s %s", checkboxText, statusText), -1)
            
            if currentSaveBool[0] and doesFileExist(nativeLogPath) then
                local f = io.open(nativeLogPath, "r")
                if f then lastChatlogSize = f:seek("end") f:close() end
            end
        end
        
        imgui.SameLine()

        local folder_w = S(125)
        local date_w = S(150)
        local spacing = imgui.GetStyle().ItemSpacing.x
        local remaining_w = imgui.GetContentRegionAvail().x
        
        local search_w = remaining_w - folder_w - date_w - (spacing * 2)
        if search_w < 120 then search_w = 120 end

        imgui.PushItemWidth(search_w)
        imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, imgui.ImVec2(S(24), S(4)))
        
        if imgui.InputTextWithHint("##sh", safe_u8"Поиск по логам...", SearchBuffer, 256) then
            needRefilter = true
        end

        if imgui.IsItemActive() then
            lastActiveSearchBuffer = ffi.string(SearchBuffer)
            wasActiveSearchBuffer = true
        else
            if wasActiveSearchBuffer then
                if lastActiveSearchBuffer then
                    ffi.copy(SearchBuffer, lastActiveSearchBuffer)
                end
                wasActiveSearchBuffer = false
            end
        end
        
        if imgui.IsItemClicked() then
            imgui.SetKeyboardFocusHere(-1)
        end
        SearchInputActive = imgui.IsItemActive()
        imgui.PopStyleVar()
        imgui.PopItemWidth()

        local imMin = imgui.GetItemRectMin()
        local imMax = imgui.GetItemRectMax()
        local dl = imgui.GetWindowDrawList()
        local cy = (imMin.y + imMax.y) / 2
        local cx = imMin.x + S(13)
        local iconColor = imgui.GetColorU32(imgui.Col.TextDisabled)
        dl:AddCircle(imgui.ImVec2(cx, cy - 1), S(3.5), iconColor, 12, S(1.5))
        dl:AddLine(imgui.ImVec2(cx + S(2.2), cy + S(1.2)), imgui.ImVec2(cx + S(5.5), cy + S(4.5)), iconColor, S(1.5))

        imgui.SameLine()
        if imgui.Button(safe_u8"Открыть папку", imgui.ImVec2(folder_w, S(26))) then 
            local currentFolder = dateLogPath .. (SelectedDate ~= "" and SelectedDate or os.date("%d-%m-%Y"))
            if doesDirectoryExist(currentFolder) then
                os.execute('explorer "' .. currentFolder .. '"')
            else
                os.execute('explorer "' .. logPath .. '"')
            end
        end
        
        imgui.SameLine()
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.16, 0.48, 0.43, 0.85))
        
        local btnLabel = (SelectedDate ~= "" and (SelectedDate .. ".txt") or "Выбрать...")
        if imgui.Button(safe_u8(btnLabel), imgui.ImVec2(date_w, S(26))) then
            updateFileList()
            imgui.OpenPopup("FPop")
        end
        local btnMin = imgui.GetItemRectMin()
        local btnMax = imgui.GetItemRectMax()
        imgui.PopStyleColor()
        
        imgui.SetNextWindowPos(imgui.ImVec2(btnMin.x, btnMax.y + S(2)), imgui.Cond.Always)
        imgui.SetNextWindowSize(imgui.ImVec2(date_w, 0), imgui.Cond.Always)
        if imgui.BeginPopup("FPop") then
            local ru_wday = {[1] = "Вс", [2] = "Пн", [3] = "Вт", [4] = "Ср", [5] = "Чт", [6] = "Пт", [7] = "Сб"}
            local now = os.time()
            
            for i = 0, 6 do
                local target_time = now - (i * 24 * 60 * 60)
                local t = os.date("*t", target_time)
                local dateStr = string.format("%02d-%02d-%04d", t.day, t.month, t.year)
                local displayFileName = dateStr .. ".txt"
                local dayName = ru_wday[t.wday]
                
                local folderExists = doesDirectoryExist(dateLogPath .. dateStr) or doesFileExist(dateLogPath .. displayFileName)
                local isSelected = (SelectedDate == dateStr)
                
                if not folderExists then imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.5, 0.5, 0.5, 1.0))
                elseif isSelected then imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1.0, 0.3, 0.3, 1.0)) end
                
                local selectableFlags = folderExists and 0 or imgui.SelectableFlags.Disabled
                if imgui.Selectable(safe_u8(displayFileName) .. "##" .. i, isSelected, selectableFlags) then
                    if folderExists then
                        FileContent = {}
                        loadLogFile(dateStr, false)
                        imgui.CloseCurrentPopup()
                    end
                end
                
                if not folderExists or isSelected then imgui.PopStyleColor() end
                imgui.SameLine(S(120))
                imgui.TextColored(not folderExists and imgui.ImVec4(0.65, 0.15, 0.15, 1.0) or imgui.ImVec4(0.0, 1.0, 0.2, 1.0), safe_u8(dayName))
            end
            imgui.EndPopup()
        end
    imgui.EndChild()
    
    imgui.BeginChild("Logs", imgui.ImVec2(0, 0), true)
    
    local currentScrollY = imgui.GetScrollY()
    local maxScrollY = imgui.GetScrollMaxY()
    if currentScrollY < lastScrollY and currentScrollY < maxScrollY - 5 then
        userScrolledUp = true 
    elseif currentScrollY >= maxScrollY - 2 then
        userScrolledUp = false 
    end

    if needRefilter then
        refilterContent()
    end
    
    local clip = imgui.ImGuiListClipper(#FilteredContent)
    while clip:Step() do
        for i = clip.DisplayStart + 1, clip.DisplayEnd do
            local line = FilteredContent[i]
            local cur_pos = imgui.GetCursorPos()
            local displayLine = line:gsub("{%x%x%x%x%x%x}", "")
            
            imgui.Selectable("##l" .. i, false, 4096, imgui.ImVec2(0, S(18)))
            
            if imgui.IsItemHovered() then
                if imgui.IsMouseDoubleClicked(0) then
                    setClipboard(displayLine) 
                    copiedIndex = i; copyType = "[Copied + Time]"; showCopiedUntil = os.clock() + 1.2
                    sampAddChatMessage("{4A90E2}[ChatLog] {FFFFFF}Текст со временем скопирован в буфер обмена", -1)
                elseif imgui.IsMouseClicked(0) then
                    local cleanLine = displayLine:sub(12) 
                    setClipboard(cleanLine) 
                    copiedIndex = i; copyType = "[Copied]"; showCopiedUntil = os.clock() + 1.2
                    sampAddChatMessage("{4A90E2}[ChatLog] {FFFFFF}Текст скопирован в буфер обмена", -1)
                end
            end
            
            if imgui.BeginPopupContextItem("Ctx" .. i) then
                local ns = findNicknames(displayLine)
                if #ns > 0 then
                    imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.2, 0.8, 0.7, 1.0))
                    if imgui.Selectable(safe_u8"Скопировать все ники (" .. #ns .. ")") then
                        setClipboard(table.concat(ns, " ")) 
                        copiedIndex = i; copyType = "[Copied Nick]"; showCopiedUntil = os.clock() + 1.2
                        sampAddChatMessage("{4A90E2}[ChatLog] {FFFFFF}Скопированы ники: " .. table.concat(ns, ", "), -1)
                    end
                    imgui.PopStyleColor(); imgui.Separator()
                    for idx, n in ipairs(ns) do
                        if imgui.Selectable(safe_u8(n)) then
                            setClipboard(n) 
                            copiedIndex = i; copyType = "[Copied Nick]"; showCopiedUntil = os.clock() + 1.2
                            sampAddChatMessage("{4A90E2}[ChatLog] {FFFFFF}Скопирован ник: " .. getNickWithClistColor(n), -1)
                        end
                    end
                else imgui.TextDisabled(safe_u8"Ников нет") end
                imgui.EndPopup()
            end
            
            imgui.SetCursorPos(imgui.ImVec2(cur_pos.x + S(8), cur_pos.y + S(1)))
            
            if activeTab == 2 then
                imgui.TextColored(imgui.ImVec4(1.00, 0.39, 0.28, 1.00), safe_u8(displayLine))
            elseif activeTab == 3 then
                imgui.TextColored(imgui.ImVec4(1.00, 1.00, 0.00, 1.00), safe_u8(displayLine))
            elseif activeTab == 4 then
                local lowLine = cp1251_lower(displayLine)
                if lowLine:find(make_pattern("открыл доступ к складу с материалами")) then
                    local s, e = lowLine:find(make_pattern("открыл"), 1, true)
                    if s and e then
                        local part1 = displayLine:sub(1, s - 1)
                        local part2 = displayLine:sub(s, e)
                        local part3 = displayLine:sub(e + 1)
                        imgui.TextColored(imgui.ImVec4(0.00, 0.725, 0.325, 1.00), safe_u8(part1))
                        imgui.SameLine(0, 0)
                        imgui.TextColored(imgui.ImVec4(0.00, 1.00, 0.00, 1.00), safe_u8(part2))
                        imgui.SameLine(0, 0)
                        imgui.TextColored(imgui.ImVec4(0.00, 0.725, 0.325, 1.00), safe_u8(part3))
                    else
                        imgui.TextColored(imgui.ImVec4(0.00, 0.725, 0.325, 1.00), safe_u8(displayLine))
                    end
                elseif lowLine:find(make_pattern("закрыл доступ к складу с материалами")) then
                    local s, e = lowLine:find(make_pattern("закрыл"), 1, true)
                    if s and e then
                        local part1 = displayLine:sub(1, s - 1)
                        local part2 = displayLine:sub(s, e)
                        local part3 = displayLine:sub(e + 1)
                        imgui.TextColored(imgui.ImVec4(0.00, 0.725, 0.325, 1.00), safe_u8(part1))
                        imgui.SameLine(0, 0)
                        imgui.TextColored(imgui.ImVec4(1.00, 0.25, 0.25, 1.00), safe_u8(part2))
                        imgui.SameLine(0, 0)
                        imgui.TextColored(imgui.ImVec4(0.00, 0.725, 0.325, 1.00), safe_u8(part3))
                    else
                        imgui.TextColored(imgui.ImVec4(0.00, 0.725, 0.325, 1.00), safe_u8(displayLine))
                    end
                elseif lowLine:find(make_pattern("спавн свободных транспортных средств")) or
                       lowLine:find(make_pattern("заспавнил свободные транспортные средства")) or
                       lowLine:find(make_pattern("отменил спавн свободных транспортных средств")) or
                       lowLine:find(make_pattern("разгрузил на склад")) then
                    imgui.TextColored(imgui.ImVec4(0.00, 0.725, 0.325, 1.00), safe_u8(displayLine))
                elseif lowLine:find(make_pattern("купил")) and lowLine:find(make_pattern("материалов")) and lowLine:find(make_pattern("на общий склад мафии за")) then
                    imgui.TextColored(imgui.ImVec4(0.184, 0.310, 0.310, 1.00), safe_u8(displayLine))
                else
                    local upperLine = line:upper()
                    if upperLine:find("{00B953}", 1, true) then
                        imgui.TextColored(imgui.ImVec4(0.00, 0.725, 0.325, 1.00), safe_u8(displayLine))
                    elseif upperLine:find("{27604D}", 1, true) then
                        imgui.TextColored(imgui.ImVec4(0.184, 0.310, 0.310, 1.00), safe_u8(displayLine))
                    elseif upperLine:find("{8D8DFF}", 1, true) then
                        imgui.TextColored(imgui.ImVec4(0.553, 0.553, 1.00, 1.00), safe_u8(displayLine))
                    elseif upperLine:find("{01FCFF}", 1, true) then
                        imgui.TextColored(imgui.ImVec4(0.004, 0.988, 1.00, 1.00), safe_u8(displayLine))
                    else
                        if isStateMessage(lowLine) then
                            imgui.TextColored(imgui.ImVec4(0.553, 0.553, 1.00, 1.00), safe_u8(displayLine))
                        elseif isCyanMessage(lowLine) then
                            imgui.TextColored(imgui.ImVec4(0.004, 0.988, 1.00, 1.00), safe_u8(displayLine))
                        else
                            imgui.TextColored(imgui.ImVec4(0.553, 0.553, 1.00, 1.00), safe_u8(displayLine))
                        end
                    end
                end
            elseif activeTab == 5 then
                imgui.TextColored(imgui.ImVec4(0.04, 0.85, 0.00, 1.00), safe_u8(displayLine))
            else
                imgui.TextUnformatted(safe_u8(displayLine))
            end

            if copiedIndex == i and os.clock() < showCopiedUntil then
                imgui.SameLine(); imgui.TextColored(imgui.ImVec4(0.2, 0.8, 0.7, 1.0), copyType)
            end
        end
    end

    if NeedScroll or (not userScrolledUp) then 
        imgui.SetScrollHereY(1.0)
        NeedScroll = false 
    end
    
    lastScrollY = imgui.GetScrollY() 
    imgui.EndChild()
    imgui.End()
end)

function main()
    if not isSampLoaded() or not isSampfuncsLoaded() then return end
    while not isSampAvailable() do wait(100) end

    updateNativeChatlogPath()

    if doesFileExist(nativeLogPath) then
        local f = io.open(nativeLogPath, "r")
        if f then
            lastChatlogSize = f:seek("end")
            f:close()
        end
    end

    updateFileList()
    ensureTodaySelected()
    
    local toggleMenu = function()
        WinState[0] = not WinState[0]
        if WinState[0] then 
            updateFileList()
            ensureTodaySelected()
            if os.clock() - closedTime > 20.0 then
                userScrolledUp = false
                NeedScroll = true
            end
        end
    end

    sampRegisterChatCommand("clog", toggleMenu)
    sampRegisterChatCommand("chatlog", toggleMenu)
	sampRegisterChatCommand("smslog", function()
        if WinState[0] and activeTab == 3 then
            WinState[0] = false
        else
            WinState[0] = true
            activeTab = 3
            updateFileList()
            ensureTodaySelected()
            loadLogFile(SelectedDate, false)
            NeedScroll = true
            userScrolledUp = false
        end
    end)
    
    local pathCheckTimer = 0
    while true do
        wait(0)

        if pendingClose then
            WinState[0] = false
            pendingClose = false
        end
        
        if os.clock() - pathCheckTimer > 2.0 then
            updateNativeChatlogPath()
            pathCheckTimer = os.clock()
        end

        if WinState[0] ~= lastWinState then
            if not WinState[0] then
                closedTime = os.clock()
            end
            lastWinState = WinState[0]
        end

        if doesFileExist(nativeLogPath) then
            local f = io.open(nativeLogPath, "r")
            if f then
                local currentSize = f:seek("end")
                if currentSize > lastChatlogSize then
                    f:seek("set", lastChatlogSize)
                    local newLines = {}
                    for line in f:lines() do
                        if line and line ~= "" then 
                            local cleanLine = line:gsub("\r", "")
                            local textWithoutTime = cleanLine:gsub("^%[%d%d:%d%d:%d%d%]%s*", "")
                            local checkText = textWithoutTime:gsub("{%x%x%x%x%x%x}", ""):gsub("%s+", "")
                            if checkText ~= "" then
                                table.insert(newLines, cleanLine) 
                            end
                        end
                    end
                    lastChatlogSize = currentSize
                    
                    if #newLines > 0 then
                        local todayStr = os.date("%d-%m-%Y")
                        local todayFolder = dateLogPath .. todayStr .. "\\"
                        if not doesDirectoryExist(todayFolder) then createDirectory(todayFolder) end
                        
                        local outAll = mainIni.settings.save_all and io.open(todayFolder .. "chatlog.txt", "a") or nil
                        local outPun = mainIni.settings.save_punishments and io.open(todayFolder .. "punishments.txt", "a") or nil
                        local outSms = mainIni.settings.save_sms and io.open(todayFolder .. "sms.txt", "a") or nil
                        local outRadio = mainIni.settings.save_radio and io.open(todayFolder .. "radio.txt", "a") or nil
                        local outAds = mainIni.settings.save_ads and io.open(todayFolder .. "ads.txt", "a") or nil
                        local outFull = io.open(logPath .. "fullchatlog.txt", "a")
                        
                        if outAll or outPun or outSms or outRadio or outAds or outFull then
                            for _, line in ipairs(newLines) do
                                local textWithoutTime = line:gsub("^%[%d%d:%d%d:%d%d%]%s*", "")
                                local cleanText = textWithoutTime:gsub("{%x%x%x%x%x%x}", "")
                                local logLine = os.date("[%H:%M:%S] ") .. cleanText
                                local lowLine = cp1251_lower(cleanText)
                                
                                if outAll then outAll:write(logLine .. "\n") end
                                if outPun and isPunishment(line) then outPun:write(logLine .. "\n") end
                                if outSms and isSms(line) then outSms:write(logLine .. "\n") end
                                
                                if outRadio and isRadio(line) then
                                    local upperLine = line:upper()
                                    local tag = ""
                                    
                                    if lowLine:find(make_pattern("спавн свободных транспортных средств")) or
                                       lowLine:find(make_pattern("заспавнил свободные транспортные средства")) or
                                       lowLine:find(make_pattern("отменил спавн свободных транспортных средств")) or
                                       lowLine:find(make_pattern("разгрузил на склад")) then
                                        tag = "{00B953}"
                                    elseif lowLine:find(make_pattern("купил")) and lowLine:find(make_pattern("материалов")) and lowLine:find(make_pattern("на общий склад мафии за")) then
                                        tag = "{27604D}"
                                    elseif upperLine:find("{8D8DFF}", 1, true) then
                                        tag = "{8D8DFF}"
                                    elseif upperLine:find("{01FCFF}", 1, true) then
                                        tag = "{01FCFF}"
                                    else
                                        if isStateMessage(lowLine) then
                                            tag = "{8D8DFF}"
                                        elseif isCyanMessage(lowLine) then
                                            tag = "{01FCFF}"
                                        else
                                            tag = "{8D8DFF}"
                                        end
                                    end

                                    if lowLine:find(make_pattern("открыл доступ к складу с материалами")) or
                                       lowLine:find(make_pattern("закрыл доступ к складу с материалами")) then
                                        outRadio:write(os.date("[%H:%M:%S] ") .. textWithoutTime .. "\n")
                                    elseif cleanText:find("^{%x%x%x%x%x%x}") then
                                        outRadio:write(os.date("[%H:%M:%S] ") .. cleanText .. "\n")
                                    else
                                        outRadio:write(os.date("[%H:%M:%S] ") .. tag .. cleanText .. "\n")
                                    end
                                end

                                if outAds and isAd(line) then outAds:write(logLine .. "\n") end

                                if outFull then
                                    local currT = os.date("*t")
                                    local fullLogLine = string.format("[%02d:%02d:%02d / %d.%d.%d] %s", currT.hour, currT.min, currT.sec, currT.day, currT.month, currT.year, textWithoutTime)
                                    outFull:write(fullLogLine .. "\n")
                                end
                            end
                            if outAll then outAll:close() end
                            if outPun then outPun:close() end
                            if outSms then outSms:close() end
                            if outRadio then outRadio:close() end
                            if outAds then outAds:close() end
                            if outFull then outFull:close() end
                        end
                    end
                end
                f:close()
            end
        end

        if WinState[0] and SelectedDate ~= "" and os.clock() - lastUpdate > 0.8 then
            loadLogFile(SelectedDate, true) 
            lastUpdate = os.clock()
        end
    end
end