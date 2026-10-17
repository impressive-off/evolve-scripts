script_author('Impressive')
script_name('GTA Window Title')

local ffi    = require 'ffi'
local inicfg = require 'inicfg'

pcall(ffi.cdef, 'void* FindWindowA(const char* lpClassName, const char* lpWindowName);')
pcall(ffi.cdef, 'void* GetForegroundWindow(void);')
pcall(ffi.cdef, 'int SetWindowTextA(void* hWnd, const char* lpString);')
pcall(ffi.cdef, 'int GetWindowTextA(void* hWnd, char* lpString, int nMaxCount);')
pcall(ffi.cdef, 'int IsWindow(void* hWnd);')
pcall(ffi.cdef, 'uint32_t GetWindowThreadProcessId(void* hWnd, uint32_t* lpdwProcessId);')
pcall(ffi.cdef, 'uint32_t GetCurrentProcessId(void);')

local CONFIG_FILE = 'window_title.ini'
local ini = inicfg.load({
    main = { enabled = true }
}, CONFIG_FILE)

ini.main.enabled = (ini.main.enabled == true or ini.main.enabled == 1 or ini.main.enabled == 'true')
inicfg.save(ini, CONFIG_FILE)

local function saveConfig()
    inicfg.save(ini, CONFIG_FILE)
end

local DEFAULT_TITLE = 'GTA:SA:MP'
local hwnd = nil

local function isMyWindow(h)
    if h == nil then return false end
    local pid = ffi.new('uint32_t[1]')
    ffi.C.GetWindowThreadProcessId(h, pid)
    return tonumber(pid[0]) == tonumber(ffi.C.GetCurrentProcessId())
end

local function findGameWindow()
    if hwnd ~= nil and ffi.C.IsWindow(hwnd) ~= 0 then
        return hwnd
    end
    hwnd = nil

    local h = ffi.C.FindWindowA('Grand theft auto San Andreas', nil)
    if isMyWindow(h) then
        hwnd = h
        return hwnd
    end

    local ok, mem = pcall(readMemory, 0x00C97C1C, 4, false)
    if ok and mem and mem ~= 0 then
        local h2 = ffi.cast('void*', mem)
        if ffi.C.IsWindow(h2) ~= 0 then
            hwnd = h2
            return hwnd
        end
    end

    local fg = ffi.C.GetForegroundWindow()
    if isMyWindow(fg) then
        hwnd = fg
        return hwnd
    end

    return nil
end

local function getTitle(h)
    local buf = ffi.new('char[256]')
    ffi.C.GetWindowTextA(h, buf, 256)
    return ffi.string(buf)
end

local function setTitle(text)
    local h = findGameWindow()
    if h == nil then return false end
    if getTitle(h) ~= text then
        ffi.C.SetWindowTextA(h, text)
    end
    return true
end

local function getMyNick()
    local ok, id = sampGetPlayerIdByCharHandle(PLAYER_PED)
    if not ok then return nil end
    local nick = sampGetPlayerNickname(id)
    if not nick or nick == '' then return nil end
    return nick
end

function main()
    if not isSampLoaded() or not isSampfuncsLoaded() then return end
    while not isSampAvailable() do wait(100) end

    sampRegisterChatCommand('window', function()
        ini.main.enabled = not ini.main.enabled
        saveConfig()
        if ini.main.enabled then
            sampAddChatMessage('[Window]: {00FF00}Смена названия окна включена.', -1)
        else
            pcall(setTitle, DEFAULT_TITLE)
            sampAddChatMessage('[Window]: {FF0000}Смена названия окна выключена.', -1)
        end
    end)

    while true do
        wait(1000)
        if ini.main.enabled then
            pcall(function()
                local nick = getMyNick()
                if nick then setTitle(nick) end
            end)
        end
    end
end

function onScriptTerminate(scr, quitGame)
    if scr == thisScript() and not quitGame then
        pcall(setTitle, DEFAULT_TITLE)
    end
end