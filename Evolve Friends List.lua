script_author("Impressive")
script_name('Evolve Friend List')
require "lib.moonloader"
local sampEvents = require("lib.samp.events")
local requests = require "requests"
local inicfg = require("inicfg")
local imgui = require "mimgui"
local ffi = require "ffi"
local bit = require "bit"
local encoding = require "encoding"
local vkeys = require "vkeys"

encoding.default = 'CP1251'
local u8 = encoding.UTF8

local DEFAULT_URL = "https://pastebin.com/raw/RfCAzybn"

local fontList = { 
    "Arial Black", "Impact", "Tahoma", "Arial", "Verdana", 
    "Century Gothic", "Consolas", "Fixedsys", "Georgia", 
    "Comic Sans MS", "Trebuchet MS", "Times New Roman", 
    "Courier New", "Microsoft Sans Serif", "Lucida Console"
}

local alignList = {
    u8"Левый край",
    u8"По центру",
    u8"Правый край"
}

local eCrimePath = getWorkingDirectory() .. "\\E-CRIME\\"
if not doesDirectoryExist(eCrimePath) then
    createDirectory(eCrimePath)
end

local configFile = "Evolve-FriendList.ini"
local localFriendsFile = eCrimePath .. "friends.txt"
local cfg = inicfg.load(nil, configFile)

local PASTEBIN_URL = DEFAULT_URL
if cfg and cfg.options and cfg.options.friendListURL and #cfg.options.friendListURL:match("^%s*(.-)%s*$") > 0 then
    PASTEBIN_URL = cfg.options.friendListURL
end

local HUD_TITLE_COLOR = 0xFFFF5353
local HUD_FRIEND_COLOR = 0xFFFFFFFF

local friends = {}
local onlineFriends = {}
local FF_TEXT = "~r~~h~FRIENDLY ~w~~h~~h~~h~FIRE"

local fontTitle = nil
local fontListRender = nil
local showMenu = imgui.new.bool(false)
local pendingClose = false
local isMovingHud = false
local clickReleased = false
local renderHidden = false
local bindingKey = false

local hudX, hudY = 6, 270
local menuX, menuY = nil, nil

if not cfg then
    cfg = {
        colors = {
            hudTitleColorR = 1.0,
            hudTitleColorG = 83 / 255,
            hudTitleColorB = 83 / 255,
            hudFriendColorR = 1.0,
            hudFriendColorG = 1.0,
            hudFriendColorB = 1.0
        },
        options = {
            scriptEnabled = 0,
            hudEnabled = 1,
            friendListURL = DEFAULT_URL,
            friendSource = 0,
            hudTitleText = "Friends",
            no_friend_damage = 0,
            inf_ammo_when_friendfire = 0,
            color_by_clist = 1,
            showStreamZone = 1,
            showPlayerId = 1,
            showTitle = 1,
            showCount = 1,
            onlyTab = 0,
            hudX = 6,
            hudY = 270,
            menuX = -1,
            menuY = -1,
            titleFontIndex = 4,
            titleFontSize = 10,
            titleFontFlags = 13,
            listFontIndex = 4,
            listFontSize = 10,
            listFontFlags = 13,
            fontAlign = 0,
            notifyConnect = 1,
            hideKey = 118,
            hideKeyEnabled = 0,
            showSelf = 0
        }
    }
    inicfg.save(cfg, configFile)
else
    cfg.options = cfg.options or {}
    cfg.colors = cfg.colors or {}

    if cfg.options.scriptEnabled == nil then cfg.options.scriptEnabled = 0 end
    if cfg.options.hudEnabled == nil then cfg.options.hudEnabled = 1 end
    if cfg.options.friendSource == nil then cfg.options.friendSource = 0 end
    if cfg.options.no_friend_damage == nil then cfg.options.no_friend_damage = 0 end
    if cfg.options.inf_ammo_when_friendfire == nil then cfg.options.inf_ammo_when_friendfire = 0 end
    if cfg.options.color_by_clist == nil then cfg.options.color_by_clist = 1 end
    if cfg.options.showStreamZone == nil then cfg.options.showStreamZone = 1 end
    if cfg.options.showPlayerId == nil then cfg.options.showPlayerId = 1 end
    if cfg.options.showTitle == nil then cfg.options.showTitle = 1 end
    if cfg.options.showCount == nil then cfg.options.showCount = 1 end
    if cfg.options.onlyTab == nil then cfg.options.onlyTab = 0 end	
    if cfg.options.hudTitleText == nil then cfg.options.hudTitleText = "Friends:" end
    if not cfg.options.friendListURL or #cfg.options.friendListURL:match("^%s*(.-)%s*$") == 0 then
        cfg.options.friendListURL = DEFAULT_URL
    end
    
    if cfg.options.titleFontIndex == nil then cfg.options.titleFontIndex = 4 end
    if cfg.options.titleFontSize == nil then cfg.options.titleFontSize = 10 end
    if cfg.options.titleFontFlags == nil then cfg.options.titleFontFlags = 13 end
    
    if cfg.options.listFontIndex == nil then cfg.options.listFontIndex = 4 end
    if cfg.options.listFontSize == nil then cfg.options.listFontSize = 10 end
    if cfg.options.listFontFlags == nil then cfg.options.listFontFlags = 13 end
    
    if cfg.options.fontAlign == nil then cfg.options.fontAlign = 0 end
    if cfg.options.notifyConnect == nil then cfg.options.notifyConnect = 1 end
    if cfg.options.hideKey == nil then cfg.options.hideKey = 118 end 
    if cfg.options.hideKeyEnabled == nil then cfg.options.hideKeyEnabled = 0 end
    if cfg.options.showSelf == nil then cfg.options.showSelf = 0 end
    
    if cfg.colors.hudTitleColorR == nil then cfg.colors.hudTitleColorR = 1.0 end
    if cfg.colors.hudTitleColorG == nil then cfg.colors.hudTitleColorG = 83 / 255 end
    if cfg.colors.hudTitleColorB == nil then cfg.colors.hudTitleColorB = 83 / 255 end

    if cfg.colors.hudFriendColorR == nil then cfg.colors.hudFriendColorR = 1.0 end
    if cfg.colors.hudFriendColorG == nil then cfg.colors.hudFriendColorG = 1.0 end
    if cfg.colors.hudFriendColorB == nil then cfg.colors.hudFriendColorB = 1.0 end
    
    PASTEBIN_URL = cfg.options.friendListURL
    hudX = cfg.options.hudX or 6
    hudY = cfg.options.hudY or 270
    if cfg.options.menuX and cfg.options.menuY and cfg.options.menuX > 0 and cfg.options.menuY > 0 then
        menuX = cfg.options.menuX
        menuY = cfg.options.menuY
    end
end

local ScriptEnabled = imgui.new.bool(cfg.options.scriptEnabled == 1)
local HudEnabled = imgui.new.bool(cfg.options.hudEnabled == 1)
local friendSourceInt = imgui.new.int(cfg.options.friendSource)
local NoFriendDamage = imgui.new.bool(cfg.options.no_friend_damage == 1)
local InfAmmoWhenFrDmg = imgui.new.bool(cfg.options.inf_ammo_when_friendfire == 1)
local ColorByClist = imgui.new.bool(cfg.options.color_by_clist == 1)
local ShowStreamZone = imgui.new.bool(cfg.options.showStreamZone == 1)
local ShowPlayerId = imgui.new.bool(cfg.options.showPlayerId == 1)
local ShowTitle = imgui.new.bool(cfg.options.showTitle == 1)
local ShowCount = imgui.new.bool(cfg.options.showCount == 1)
local OnlyTab = imgui.new.bool(cfg.options.onlyTab == 1)
local NotifyConnect = imgui.new.bool(cfg.options.notifyConnect == 1)
local HideKeyEnabled = imgui.new.bool(cfg.options.hideKeyEnabled == 1)
local ShowSelf = imgui.new.bool(cfg.options.showSelf == 1)
local hudTitleBuf = imgui.new.char[256](u8(cfg.options.hudTitleText or "Friends:"))
local urlBuf = imgui.new.char[256](u8(cfg.options.friendListURL or DEFAULT_URL))

local addNickBuf = imgui.new.char[64]("")
local addIdBuf = imgui.new.int(0)

local imguiTitleColor = imgui.new.float[3](cfg.colors.hudTitleColorR, cfg.colors.hudTitleColorG, cfg.colors.hudTitleColorB)
local imguiFriendColor = imgui.new.float[3](cfg.colors.hudFriendColorR, cfg.colors.hudFriendColorG, cfg.colors.hudFriendColorB)

local tSize = imgui.new.int(cfg.options.titleFontSize)
local tFlags = imgui.new.int(cfg.options.titleFontFlags)
local lSize = imgui.new.int(cfg.options.listFontSize)
local lFlags = imgui.new.int(cfg.options.listFontFlags)

local WM_KEYFIRST, WM_KEYLAST = 0x0100, 0x0109
local WM_MOUSEFIRST, WM_MOUSELAST = 0x0200, 0x020E

local function imguiFloat3ToARGB(float3)
    local r = math.floor(float3[0] * 255 + 0.5)
    local g = math.floor(float3[1] * 255 + 0.5)
    local b = math.floor(float3[2] * 255 + 0.5)
    r = math.max(0, math.min(255, r))
    g = math.max(0, math.min(255, g))
    b = math.max(0, math.min(255, b))
    return bit.bor(0xFF000000, bit.lshift(r, 16), bit.lshift(g, 8), b)
end

local function getPlayerColorHex(nick)
    for id = 0, 1000 do
        if sampIsPlayerConnected(id) and sampGetPlayerNickname(id) == nick then
            local col = sampGetPlayerColor(id)
            if col and col ~= 0 then
                local r = bit.band(bit.rshift(col, 16), 0xFF)
                local g = bit.band(bit.rshift(col, 8),  0xFF)
                local b = bit.band(col, 0xFF)
                return string.format("{%02X%02X%02X}", r, g, b)
            end
        end
    end
    return "{FFFFFF}"
end

local function getPlayerIdByNick(nick)
    for id = 0, 1000 do
        if sampIsPlayerConnected(id) and sampGetPlayerNickname(id) == nick then
            return id
        end
    end
    return nil
end

local function nickWithId(nick, id)
    local colorHex = getPlayerColorHex(nick)
    id = id or getPlayerIdByNick(nick)
    if id then
        return string.format("%s%s[%d]", colorHex, nick, id)
    end
    return colorHex .. nick
end

local function getKeyName(key)
    if not key or key == 0 then return u8"Нет" end
    local ok, name = pcall(vkeys.id_to_name, key)
    if ok and name then return name end
    return tostring(key)
end

HUD_TITLE_COLOR = imguiFloat3ToARGB(imguiTitleColor)
HUD_FRIEND_COLOR = imguiFloat3ToARGB(imguiFriendColor)

function onWindowMessage(msg, wparam, lparam)
    if not showMenu[0] then return end

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

local function isTabOpen()
    local ok, res = pcall(sampIsScoreboardOpen)
    return ok and res == true
end

local function isFriend(nick)
    for _, f in ipairs(friends) do
        if f == nick then return true end
    end
    return false
end

local function drawTD(font, text, x, y, color)
    if not font then return end
    renderFontDrawText(font, text, x + 1, y + 1, 0x50000000)
    renderFontDrawText(font, text, x, y, color)
end

local function getPlColor(id)
    local col = sampGetPlayerColor(id)
    if col and col ~= 0 then
        local r = bit.band(bit.rshift(col, 16), 0xFF)
        local g = bit.band(bit.rshift(col, 8),  0xFF)
        local b = bit.band(col, 0xFF)
        return bit.bor(0xFF000000, bit.lshift(r, 16), bit.lshift(g, 8), b)
    end
    return HUD_FRIEND_COLOR
end

local function updateFont()
    local tFontName = fontList[cfg.options.titleFontIndex] or "Arial"
    local tSizeVal = math.max(5, math.min(40, cfg.options.titleFontSize or 11))
    local tFlagsVal = math.max(0, cfg.options.titleFontFlags or 0)
    
    local lFontName = fontList[cfg.options.listFontIndex] or "Arial"
    local lSizeVal = math.max(5, math.min(40, cfg.options.listFontSize or 9))
    local lFlagsVal = math.max(0, cfg.options.listFontFlags or 0)

    if fontTitle then renderReleaseFont(fontTitle) end
    if fontListRender then renderReleaseFont(fontListRender) end

    fontTitle = renderCreateFont(tFontName, tSizeVal, tFlagsVal)
    fontListRender = renderCreateFont(lFontName, lSizeVal, lFlagsVal)
end

local function updateOnline()
    local newOnlineFriends = {}
    for id = 0, 1000 do
        if sampIsPlayerConnected(id) and isFriend(sampGetPlayerNickname(id)) then
            table.insert(newOnlineFriends, {id = id, nick = sampGetPlayerNickname(id)})
        end
    end
    onlineFriends = newOnlineFriends
end

local function saveLocalFriends()
    local f = io.open(localFriendsFile, "w")
    if f then
        for _, name in ipairs(friends) do
            f:write(name .. "\n")
        end
        f:close()
    end
    updateOnline()
end

local function addFriend(nick)
    if not isFriend(nick) then
        table.insert(friends, nick)
        saveLocalFriends()
        sampAddChatMessage(string.format("Игрок %s{FFFFFF} добавлен в список друзей", nickWithId(nick)), -1)
    end
end

local function removeFriend(index)
    local nick = friends[index]
    if nick then
        local shownNick = nickWithId(nick)
        table.remove(friends, index)
        saveLocalFriends()
        sampAddChatMessage(string.format("Игрок %s{FFFFFF} удален из списка друзей", shownNick), -1)
    end
end

local function loadFriends()
    if cfg.options.friendSource == 0 then
        friends = {}
        if not doesFileExist(localFriendsFile) then
            local f = io.open(localFriendsFile, "w")
            if f then
                f:write("Nick_Name\nTest_Friend\n")
                f:close()
            end
        end
        local f = io.open(localFriendsFile, "r")
        if f then
            for line in f:lines() do
                local cleanNick = line:match("^%s*(.-)%s*$")
                if cleanNick and #cleanNick > 0 then
                    table.insert(friends, cleanNick)
                end
            end
            f:close()
        end
        updateOnline()
    else
        lua_thread.create(function()
            local targetUrl = PASTEBIN_URL
            if not targetUrl or #targetUrl:match("^%s*(.-)%s*$") == 0 then
                targetUrl = DEFAULT_URL
                PASTEBIN_URL = DEFAULT_URL
                cfg.options.friendListURL = DEFAULT_URL
                inicfg.save(cfg, configFile)
                imgui.StrCopy(urlBuf, u8(DEFAULT_URL))
            end

            local ok, r = pcall(requests.get, targetUrl)
            if ok and r and r.status_code == 200 then
                friends = {}
                for nick in r.text:gmatch("[^\r\n]+") do
                    local cleanNick = nick:match("^%s*(.-)%s*$") or nick
                    if #cleanNick > 0 then
                        table.insert(friends, cleanNick)
                    end
                end
                updateOnline()
            end
        end)
    end
end

imgui.OnInitialize(function()
    local style = imgui.GetStyle()
    local colors = style.Colors

    style.WindowPadding = imgui.ImVec2(10, 10)
    style.WindowRounding = 6.0
    style.ChildRounding = 5.0
    style.FramePadding = imgui.ImVec2(6, 4)
    style.FrameRounding = 4.0
    style.ItemSpacing = imgui.ImVec2(7, 6)
    style.ItemInnerSpacing = imgui.ImVec2(5, 5)
    style.IndentSpacing = 21
    style.ScrollbarSize = 11.0
    style.ScrollbarRounding = 12.0
    style.GrabMinSize = 9.0
    style.GrabRounding = 3.0
    style.TabRounding = 4.0
    style.WindowTitleAlign = imgui.ImVec2(0.5, 0.5)
    style.ButtonTextAlign = imgui.ImVec2(0.5, 0.5)

    colors[imgui.Col.Text] = imgui.ImVec4(0.95, 0.96, 0.98, 1.00)
    colors[imgui.Col.TextDisabled] = imgui.ImVec4(0.50, 0.50, 0.50, 1.00)
    colors[imgui.Col.WindowBg] = imgui.ImVec4(0.10, 0.10, 0.11, 0.97)
    colors[imgui.Col.ChildBg] = imgui.ImVec4(0.09, 0.09, 0.10, 1.00)
    colors[imgui.Col.PopupBg] = imgui.ImVec4(0.08, 0.08, 0.09, 0.98)
    colors[imgui.Col.Border] = imgui.ImVec4(0.20, 0.20, 0.22, 1.00)
    colors[imgui.Col.BorderShadow] = imgui.ImVec4(0.00, 0.00, 0.00, 0.00)
    colors[imgui.Col.FrameBg] = imgui.ImVec4(0.17, 0.17, 0.18, 1.00)
    colors[imgui.Col.FrameBgHovered] = imgui.ImVec4(0.22, 0.16, 0.16, 1.00)
    colors[imgui.Col.FrameBgActive] = imgui.ImVec4(0.28, 0.14, 0.14, 1.00)
    colors[imgui.Col.TitleBg] = imgui.ImVec4(0.08, 0.08, 0.09, 1.00)
    colors[imgui.Col.TitleBgActive] = imgui.ImVec4(0.08, 0.08, 0.09, 1.00)
    colors[imgui.Col.TitleBgCollapsed] = imgui.ImVec4(0.08, 0.08, 0.09, 1.00)
    colors[imgui.Col.MenuBarBg] = imgui.ImVec4(0.13, 0.13, 0.14, 1.00)
    colors[imgui.Col.ScrollbarBg] = imgui.ImVec4(0.05, 0.05, 0.06, 0.60)
    colors[imgui.Col.ScrollbarGrab] = imgui.ImVec4(0.30, 0.30, 0.31, 1.00)
    colors[imgui.Col.ScrollbarGrabHovered] = imgui.ImVec4(0.75, 0.20, 0.20, 1.00)
    colors[imgui.Col.ScrollbarGrabActive] = imgui.ImVec4(0.90, 0.15, 0.15, 1.00)
    colors[imgui.Col.CheckMark] = imgui.ImVec4(1.00, 0.28, 0.28, 1.00)
    colors[imgui.Col.SliderGrab] = imgui.ImVec4(1.00, 0.28, 0.28, 1.00)
    colors[imgui.Col.SliderGrabActive] = imgui.ImVec4(1.00, 0.21, 0.21, 1.00)
    colors[imgui.Col.Button] = imgui.ImVec4(0.85, 0.20, 0.20, 0.90)
    colors[imgui.Col.ButtonHovered] = imgui.ImVec4(1.00, 0.28, 0.28, 1.00)
    colors[imgui.Col.ButtonActive] = imgui.ImVec4(0.75, 0.15, 0.15, 1.00)
    colors[imgui.Col.Header] = imgui.ImVec4(0.85, 0.20, 0.20, 0.75)
    colors[imgui.Col.HeaderHovered] = imgui.ImVec4(1.00, 0.28, 0.28, 0.90)
    colors[imgui.Col.HeaderActive] = imgui.ImVec4(0.75, 0.15, 0.15, 1.00)
    colors[imgui.Col.Separator] = imgui.ImVec4(0.25, 0.20, 0.20, 1.00)
    colors[imgui.Col.SeparatorHovered] = imgui.ImVec4(1.00, 0.28, 0.28, 0.78)
    colors[imgui.Col.SeparatorActive] = imgui.ImVec4(1.00, 0.28, 0.28, 1.00)
    colors[imgui.Col.ResizeGrip] = imgui.ImVec4(1.00, 0.28, 0.28, 0.20)
    colors[imgui.Col.ResizeGripHovered] = imgui.ImVec4(1.00, 0.28, 0.28, 0.67)
    colors[imgui.Col.ResizeGripActive] = imgui.ImVec4(1.00, 0.19, 0.19, 0.95)
    colors[imgui.Col.Tab] = imgui.ImVec4(0.13, 0.13, 0.14, 1.00)
    colors[imgui.Col.TabHovered] = imgui.ImVec4(1.00, 0.28, 0.28, 0.80)
    colors[imgui.Col.TabActive] = imgui.ImVec4(0.75, 0.18, 0.18, 1.00)
    colors[imgui.Col.PlotLines] = imgui.ImVec4(0.61, 0.61, 0.61, 1.00)
    colors[imgui.Col.PlotLinesHovered] = imgui.ImVec4(1.00, 0.43, 0.35, 1.00)
    colors[imgui.Col.PlotHistogram] = imgui.ImVec4(1.00, 0.21, 0.21, 1.00)
    colors[imgui.Col.PlotHistogramHovered] = imgui.ImVec4(1.00, 0.18, 0.18, 1.00)
    colors[imgui.Col.TextSelectedBg] = imgui.ImVec4(1.00, 0.28, 0.28, 0.35)
    colors[imgui.Col.ModalWindowDimBg] = imgui.ImVec4(0.10, 0.10, 0.10, 0.60)
end)

imgui.OnFrame(function() return showMenu[0] end, function(player)
    player.HideCursor = false

    local sx, sy = getScreenResolution()
    local scale = math.max(0.75, sy / 1080)

    local winWidth = 620 * scale
    imgui.SetNextWindowSize(imgui.ImVec2(winWidth, 0), imgui.Cond.Always)

    if not menuX or not menuY then
        menuX = sx / 2 - winWidth / 2
        menuY = sy / 2 - 280 * scale
        imgui.SetNextWindowPos(imgui.ImVec2(menuX, menuY), imgui.Cond.Always)
    end

    local flags = bit.bor(imgui.WindowFlags.AlwaysAutoResize, imgui.WindowFlags.NoCollapse, imgui.WindowFlags.NoResize)

    if imgui.Begin(u8"Evolve Friend List##MainWindow", showMenu, flags) then
        imgui.SetWindowFontScale(scale)

        local curPos = imgui.GetWindowPos()
        if menuX ~= curPos.x or menuY ~= curPos.y then
            menuX, menuY = curPos.x, curPos.y
        end

        if imgui.Checkbox(u8"##ScriptToggle", ScriptEnabled) then
            cfg.options.scriptEnabled = ScriptEnabled[0] and 1 or 0
            inicfg.save(cfg, configFile)
        end
        imgui.SameLine()
        if ScriptEnabled[0] then
            imgui.Text(u8"Friend List включен")
        else
            imgui.Text(u8"Friend List выключен")
        end

        if ScriptEnabled[0] then
            if imgui.Checkbox(u8"##HudToggle", HudEnabled) then
                cfg.options.hudEnabled = HudEnabled[0] and 1 or 0
                inicfg.save(cfg, configFile)
            end
            imgui.SameLine()
            imgui.Text(u8"HUD на экране")
			
            if HudEnabled[0] then
                if imgui.Checkbox(u8"Скрывать рендер по клавише", HideKeyEnabled) then
                    cfg.options.hideKeyEnabled = HideKeyEnabled[0] and 1 or 0
                    bindingKey = false
                    inicfg.save(cfg, configFile)
                end

                if HideKeyEnabled[0] then
                    imgui.AlignTextToFramePadding()
                    imgui.Text(u8"Клавиша:")
                    imgui.SameLine()
                    local keyLabel = bindingKey and u8"Нажмите клавишу..." or getKeyName(cfg.options.hideKey)
                    if imgui.Button(keyLabel .. "##hidekeybtn", imgui.ImVec2(150 * scale, 22 * scale)) then
                        bindingKey = true
                    end
                    if bindingKey then
                        imgui.SameLine()
                        imgui.AlignTextToFramePadding()
                        imgui.Text(u8"Backspace - сбросить")
                    elseif not cfg.options.hideKey or cfg.options.hideKey == 0 then
                        imgui.SameLine()
                        imgui.AlignTextToFramePadding()
                        imgui.TextDisabled(u8"По умолчанию F7")
                    end
                end

                if imgui.Checkbox(u8"Только при открытом TAB", OnlyTab) then
                    cfg.options.onlyTab = OnlyTab[0] and 1 or 0
                    inicfg.save(cfg, configFile)
                end
            end		

            if imgui.Checkbox(u8"Уведомление о подключении / отключении друзей", NotifyConnect) then
                cfg.options.notifyConnect = NotifyConnect[0] and 1 or 0
                inicfg.save(cfg, configFile)
            end

            if imgui.Checkbox(u8"Отображать себя в списке друзей", ShowSelf) then
                cfg.options.showSelf = ShowSelf[0] and 1 or 0
                inicfg.save(cfg, configFile)
            end

            if imgui.Checkbox(u8"Отключить урон по друзьям (No Damage)", NoFriendDamage) then
                cfg.options.no_friend_damage = NoFriendDamage[0] and 1 or 0
                inicfg.save(cfg, configFile)
            end

            if NoFriendDamage[0] then
                if imgui.Checkbox(u8"Бесконечные патроны при стрельбе по друзьям", InfAmmoWhenFrDmg) then
                    cfg.options.inf_ammo_when_friendfire = InfAmmoWhenFrDmg[0] and 1 or 0
                    inicfg.save(cfg, configFile)
                end
            end

            imgui.Separator()

            if imgui.BeginTabBar("MainTabBar") then
                
                if imgui.BeginTabItem(u8"Настройки") then
                    imgui.TextColored(imgui.ImVec4(0.0, 0.85, 1.0, 1.0), u8"Источник списка")
                    if imgui.RadioButtonIntPtr(u8"Файл (friends.txt)", friendSourceInt, 0) then
                        cfg.options.friendSource = 0
                        inicfg.save(cfg, configFile)
                        loadFriends()
                    end
                    imgui.SameLine()
                    if imgui.RadioButtonIntPtr(u8"Ссылка (Pastebin)", friendSourceInt, 1) then
                        cfg.options.friendSource = 1
                        inicfg.save(cfg, configFile)
                        loadFriends()
                    end

                    if friendSourceInt[0] == 1 then
                        imgui.PushItemWidth(380 * scale)
                        if imgui.InputText(u8"##friendurl", urlBuf, 256) then
                            local newUrl = ffi.string(urlBuf):match("^%s*(.-)%s*$")
                            if #newUrl == 0 then
                                newUrl = DEFAULT_URL
                                imgui.StrCopy(urlBuf, u8(DEFAULT_URL))
                            end
                            cfg.options.friendListURL = newUrl
                            PASTEBIN_URL = newUrl
                            inicfg.save(cfg, configFile)
                        end
                        imgui.PopItemWidth()
                        imgui.SameLine()
                        if imgui.Button(u8"Обновить", imgui.ImVec2(-1, 22 * scale)) then
                            loadFriends()
                        end
                    end

                    imgui.Separator()
                    imgui.TextColored(imgui.ImVec4(0.0, 0.85, 1.0, 1.0), u8"Заголовок")

                    imgui.PushItemWidth(200 * scale)
                    if imgui.InputText(u8"##hudtitleinput", hudTitleBuf, 256) then
                        cfg.options.hudTitleText = u8:decode(ffi.string(hudTitleBuf))
                        inicfg.save(cfg, configFile)
                    end
                    imgui.PopItemWidth()
                    imgui.SameLine()
                    if imgui.ColorEdit3(u8"##titlecoloredit", imguiTitleColor, imgui.ColorEditFlags.NoInputs) then
                        cfg.colors.hudTitleColorR = imguiTitleColor[0]
                        cfg.colors.hudTitleColorG = imguiTitleColor[1]
                        cfg.colors.hudTitleColorB = imguiTitleColor[2]
                        HUD_TITLE_COLOR = imguiFloat3ToARGB(imguiTitleColor)
                        inicfg.save(cfg, configFile)
                    end
                    imgui.SameLine()
                    imgui.Text(u8"Цвет заголовка")

                    imgui.PushItemWidth(160 * scale)
                    if imgui.BeginCombo(u8"##TitleFontCombo", fontList[cfg.options.titleFontIndex]) then
                        for i, name in ipairs(fontList) do
                            if imgui.Selectable(name, i == cfg.options.titleFontIndex) then
                                cfg.options.titleFontIndex = i
                                updateFont()
                                inicfg.save(cfg, configFile)
                            end
                        end
                        imgui.EndCombo()
                    end
                    imgui.SameLine()
                    if imgui.BeginCombo(u8"##TitleFontAlign", alignList[(cfg.options.fontAlign or 0) + 1]) then
                        for i, name in ipairs(alignList) do
                            if imgui.Selectable(name, (i - 1) == cfg.options.fontAlign) then
                                cfg.options.fontAlign = i - 1
                                inicfg.save(cfg, configFile)
                            end
                        end
                        imgui.EndCombo()
                    end
                    imgui.PopItemWidth()
                    imgui.SameLine()
                    imgui.Text(u8"Выравнивание")

                    imgui.PushItemWidth(100 * scale)
                    if imgui.InputInt(u8"##titleSizeInput", tSize, 1, 1) then
                        if tSize[0] < 5 then tSize[0] = 5 end
                        if tSize[0] > 40 then tSize[0] = 40 end
                        cfg.options.titleFontSize = tSize[0]
                        updateFont()
                        inicfg.save(cfg, configFile)
                    end
                    imgui.PopItemWidth()
                    imgui.SameLine()
                    imgui.Text(u8"Размер шрифта заголовка")

                    imgui.PushItemWidth(100 * scale)
                    if imgui.InputInt(u8"##titleFlagsInput", tFlags, 1, 1) then
                        if tFlags[0] < 0 then tFlags[0] = 0 end
                        if tFlags[0] > 32 then tFlags[0] = 32 end
                        cfg.options.titleFontFlags = tFlags[0]
                        updateFont()
                        inicfg.save(cfg, configFile)
                    end
                    imgui.PopItemWidth()
                    imgui.SameLine()
                    imgui.Text(u8"Флаг шрифта заголовка")

                    if imgui.Checkbox(u8"Отображать заголовок", ShowTitle) then
                        cfg.options.showTitle = ShowTitle[0] and 1 or 0
                        inicfg.save(cfg, configFile)
                    end
                    imgui.SameLine()
                    if imgui.Checkbox(u8"Отображать кол-во в списке", ShowCount) then
                        cfg.options.showCount = ShowCount[0] and 1 or 0
                        inicfg.save(cfg, configFile)
                    end

                    imgui.Separator()
                    imgui.TextColored(imgui.ImVec4(0.0, 0.85, 1.0, 1.0), u8"Список друзей")

                    imgui.PushItemWidth(160 * scale)
                    if imgui.BeginCombo(u8"##ListFontCombo", fontList[cfg.options.listFontIndex]) then
                        for i, name in ipairs(fontList) do
                            if imgui.Selectable(name, i == cfg.options.listFontIndex) then
                                cfg.options.listFontIndex = i
                                updateFont()
                                inicfg.save(cfg, configFile)
                            end
                        end
                        imgui.EndCombo()
                    end
                    imgui.PopItemWidth()
                    imgui.SameLine()
                    imgui.Text(u8"Шрифт")

                    if not ColorByClist[0] then
                        imgui.SameLine()
                        if imgui.ColorEdit3(u8"##listcoloredit", imguiFriendColor, imgui.ColorEditFlags.NoInputs) then
                            cfg.colors.hudFriendColorR = imguiFriendColor[0]
                            cfg.colors.hudFriendColorG = imguiFriendColor[1]
                            cfg.colors.hudFriendColorB = imguiFriendColor[2]
                            HUD_FRIEND_COLOR = imguiFloat3ToARGB(imguiFriendColor)
                            inicfg.save(cfg, configFile)
                        end
                        imgui.SameLine()
                        imgui.Text(u8"Цвет списка")
                    end

                    imgui.PushItemWidth(100 * scale)
                    if imgui.InputInt(u8"##listSizeInput", lSize, 1, 1) then
                        if lSize[0] < 5 then lSize[0] = 5 end
                        if lSize[0] > 40 then lSize[0] = 40 end
                        cfg.options.listFontSize = lSize[0]
                        updateFont()
                        inicfg.save(cfg, configFile)
                    end
                    imgui.PopItemWidth()
                    imgui.SameLine()
                    imgui.Text(u8"Размер шрифта списка")

                    imgui.PushItemWidth(100 * scale)
                    if imgui.InputInt(u8"##listFlagsInput", lFlags, 1, 1) then
                        if lFlags[0] < 0 then lFlags[0] = 0 end
                        if lFlags[0] > 32 then lFlags[0] = 32 end
                        cfg.options.listFontFlags = lFlags[0]
                        updateFont()
                        inicfg.save(cfg, configFile)
                    end
                    imgui.PopItemWidth()
                    imgui.SameLine()
                    imgui.Text(u8"Флаг шрифта списка")

                    if imgui.Checkbox(u8"ID игрока", ShowPlayerId) then
                        cfg.options.showPlayerId = ShowPlayerId[0] and 1 or 0
                        inicfg.save(cfg, configFile)
                    end
                    imgui.SameLine()
                    if imgui.Checkbox(u8"В зоне стрима", ShowStreamZone) then
                        cfg.options.showStreamZone = ShowStreamZone[0] and 1 or 0
                        inicfg.save(cfg, configFile)
                    end
                    imgui.SameLine()
                    if imgui.Checkbox(u8"Цветной ник", ColorByClist) then
                        cfg.options.color_by_clist = ColorByClist[0] and 1 or 0
                        inicfg.save(cfg, configFile)
                    end

                    imgui.Separator()

                    if imgui.Button(u8"Изменить позицию HUD", imgui.ImVec2(-1, 26 * scale)) then
                        showMenu[0] = false
                        isMovingHud = true
                        clickReleased = false
                        sampAddChatMessage("Нажмите ПКМ, чтобы зафиксировать позицию HUD.", -1)
                    end

                    imgui.EndTabItem()
                end

                if imgui.BeginTabItem(u8"Список друзей") then
                    if cfg.options.friendSource == 1 then
                        imgui.TextDisabled(u8"Включён режим ссылки (Pastebin). Редактирование отключено.")
                    else
                        if imgui.Button(u8"Добавить ник друга", imgui.ImVec2(180 * scale, 26 * scale)) then
                            imgui.OpenPopup(u8"Добавить по нику")
                        end
                        imgui.SameLine()
                        if imgui.Button(u8"Добавить по ID", imgui.ImVec2(180 * scale, 26 * scale)) then
                            imgui.OpenPopup(u8"Добавить по ID")
                        end

                        imgui.SetNextWindowSize(imgui.ImVec2(320 * scale, 0), imgui.Cond.Always)
                        if imgui.BeginPopupModal(u8"Добавить по нику", nil, imgui.WindowFlags.NoResize) then
                            imgui.Text(u8"Введите Nick_Name:")
                            
                            imgui.PushItemWidth(-1)
                            imgui.InputText(u8"##nickinput", addNickBuf, 64)
                            imgui.PopItemWidth()

                            if imgui.Button(u8"Добавить", imgui.ImVec2(135 * scale, 0)) then
                                local nickToAdd = u8:decode(ffi.string(addNickBuf)):match("^%s*(.-)%s*$")
                                if nickToAdd and #nickToAdd > 0 then
                                    addFriend(nickToAdd)
                                    ffi.copy(addNickBuf, "")
                                    imgui.CloseCurrentPopup()
                                end
                            end
                            imgui.SameLine()
                            if imgui.Button(u8"Отмена", imgui.ImVec2(135 * scale, 0)) then
                                imgui.CloseCurrentPopup()
                            end
                            imgui.EndPopup()
                        end

                        imgui.SetNextWindowSize(imgui.ImVec2(320 * scale, 0), imgui.Cond.Always)
                        if imgui.BeginPopupModal(u8"Добавить по ID", nil, imgui.WindowFlags.NoResize) then
                            imgui.Text(u8"Введите ID игрока:")
                            
                            imgui.PushItemWidth(-1)
                            if imgui.InputInt(u8"##idinput", addIdBuf, 1, 10) then
                                if addIdBuf[0] < 0 then addIdBuf[0] = 0 end
                                if addIdBuf[0] > 999 then addIdBuf[0] = 999 end
                            end
                            imgui.PopItemWidth()

                            if imgui.Button(u8"Добавить", imgui.ImVec2(135 * scale, 0)) then
                                local targetId = addIdBuf[0]
                                if targetId >= 0 and targetId <= 999 and sampIsPlayerConnected(targetId) then
                                    local nick = sampGetPlayerNickname(targetId)
                                    if nick and #nick > 0 then
                                        addFriend(nick)
                                        imgui.CloseCurrentPopup()
                                    end
                                else
                                    sampAddChatMessage("{FF0000}Игрок с таким ID не найден!", -1)
                                end
                            end
                            imgui.SameLine()
                            if imgui.Button(u8"Отмена", imgui.ImVec2(135 * scale, 0)) then
                                imgui.CloseCurrentPopup()
                            end
                            imgui.EndPopup()
                        end

                        imgui.Separator()

                        imgui.BeginChild("FriendsListChild", imgui.ImVec2(-1, 320 * scale), true)
                        for i = #friends, 1, -1 do
                            local friendNick = friends[i]
                            imgui.Text(u8(friendNick))
                            imgui.SameLine(imgui.GetWindowWidth() - 85 * scale)
                            
                            if imgui.Button(u8"Удалить##" .. i, imgui.ImVec2(70 * scale, 20 * scale)) then
                                removeFriend(i)
                            end
                        end
                        imgui.EndChild()
                    end

                    imgui.EndTabItem()
                end

                imgui.EndTabBar()
            end
        end
    end
    imgui.End()
end)

local function cmdFriend(arg)
    arg = (arg or ""):match("^%s*(.-)%s*$")
    if #arg == 0 then
        sampAddChatMessage("Использование: /friend [Nick_Name | ID]", -1)
        return
    end

    if cfg.options.friendSource == 1 then
        sampAddChatMessage("{FF0000}Включён режим Pastebin, редактирование списка отключено.", -1)
        return
    end

    local nick = arg
    local id = tonumber(arg)
    if id then
        if id >= 0 and id <= 999 and sampIsPlayerConnected(id) then
            nick = sampGetPlayerNickname(id)
        else
            sampAddChatMessage("{FF0000}Игрок с таким ID не найден!", -1)
            return
        end
    end

    for i, f in ipairs(friends) do
        if f == nick then
            removeFriend(i) 
            return
        end
    end

    addFriend(nick) 
end

function main()
    while not isSampAvailable() do wait(100) end

    sampRegisterChatCommand("friend", cmdFriend)

    updateFont()
    loadFriends()
    wait(500)
    updateOnline()

    while true do
        wait(0)

        if pendingClose then
            showMenu[0] = false
            pendingClose = false
            bindingKey = false
        end

        if cfg.options.hideKeyEnabled ~= 1 then
            bindingKey = false
            renderHidden = false
        end

        if bindingKey then
            for k = 8, 254 do
                if isKeyJustPressed(k) then
                    if k == vkeys.VK_ESCAPE then
                        bindingKey = false
                    else
                        if k == vkeys.VK_BACK then
                            cfg.options.hideKey = 0
                        else
                            cfg.options.hideKey = k
                        end
                        inicfg.save(cfg, configFile)
                        bindingKey = false
                    end
                    break
                end
            end
        elseif cfg.options.hideKeyEnabled == 1 and cfg.options.hideKey and cfg.options.hideKey ~= 0 and isKeyJustPressed(cfg.options.hideKey)
            and not sampIsChatInputActive() and not sampIsDialogActive() then
            renderHidden = not renderHidden
        end

        if isMovingHud then
            showCursor(true)
            local mx, my = getCursorPos()
            local sx, sy = getScreenResolution()
            hudX = math.max(0, math.min(sx - 100, mx))
            hudY = math.max(0, math.min(sy - 30, my))

            if not isKeyDown(vkeys.VK_RBUTTON) then
                clickReleased = true
            end

            if clickReleased and isKeyJustPressed(vkeys.VK_RBUTTON) then
                cfg.options.hudX = hudX
                cfg.options.hudY = hudY
                local saved = inicfg.save(cfg, configFile)
                isMovingHud = false
                clickReleased = false
                showCursor(false)
                if saved then
                    sampAddChatMessage("Позиция HUD сохранена!", -1)
                else
                    sampAddChatMessage("{FF0000}Не удалось сохранить позицию HUD в " .. configFile, -1)
                end
            end
        end

        drawHUD()
    end
end

function drawHUD()
    if renderHidden and not isMovingHud then return end
    if cfg.options.scriptEnabled ~= 1 or cfg.options.hudEnabled ~= 1 or isPauseMenuActive() then return end
	
	if cfg.options.onlyTab == 1 and not isMovingHud and not isTabOpen() then return end

    if not fontTitle or not fontListRender then
        updateFont()
        if not fontTitle or not fontListRender then return end
    end

    local list = {}
    if cfg.options.showSelf == 1 then
        local okSelf, selfId = sampGetPlayerIdByCharHandle(PLAYER_PED)
        if okSelf then
            local alreadyIn = false
            for _, p in ipairs(onlineFriends) do
                if p.id == selfId then alreadyIn = true break end
            end
            if not alreadyIn then
                table.insert(list, {id = selfId, nick = sampGetPlayerNickname(selfId)})
            end
        end
    end
    for _, p in ipairs(onlineFriends) do
        table.insert(list, p)
    end

    local x, y = hudX, hudY
    local align = cfg.options.fontAlign or 0

    if cfg.options.showTitle == 1 then
        local titleText = cfg.options.hudTitleText or "Friends:"
        if cfg.options.showCount == 1 then
            titleText = string.format("%s[%d]", titleText, #list)
        end

        local titleLen = renderGetFontDrawTextLength(fontTitle, titleText) or 0
        local startX = x
        if align == 1 then
            startX = x - (titleLen / 2)
        elseif align == 2 then
            startX = x - titleLen
        end

        drawTD(fontTitle, titleText, startX, y, HUD_TITLE_COLOR)
        y = y + (cfg.options.titleFontSize or 11) + 8
    end

    for _, player in ipairs(list) do
        local inStream, ped = sampGetCharHandleBySampPlayerId(player.id)
        local inStreamZone = (inStream and doesCharExist(ped))
        local name = player.nick or "?"
        
        local textMain = name
        if cfg.options.showPlayerId == 1 then
            textMain = string.format("%s[%d]", name, player.id)
        end

        local mainColor = HUD_FRIEND_COLOR
        if cfg.options.color_by_clist == 1 then
            mainColor = getPlColor(player.id)
        end

        local itemLen = renderGetFontDrawTextLength(fontListRender, textMain) or 0
        local itemX = x
        if align == 1 then
            itemX = x - (itemLen / 2)
        elseif align == 2 then
            itemX = x - itemLen
        end

        drawTD(fontListRender, textMain, itemX, y, mainColor)

        if cfg.options.showStreamZone == 1 and inStreamZone then
            drawTD(fontListRender, " (!!!)", itemX + itemLen, y, 0xFFFFFFFF)
        end

        y = y + (cfg.options.listFontSize or 9) + 6
    end
end

local function stripColors(str)
    return (str:gsub("~%a~", ""))
end

local function isFriend1(nick)
    local cleanNick = stripColors(nick)
    for _, f in ipairs(friends) do
        if f == cleanNick then return true end
    end
    return false
end

function sampEvents.onSendBulletSync(data)
    if cfg.options.scriptEnabled ~= 1 then return end
    if cfg.options.no_friend_damage ~= 1 then return end
    if data.targetType ~= 1 then return end

    local id = data.targetId
    local nick = sampGetPlayerNickname(id)

    if isFriend1(nick) then
        printStyledString(FF_TEXT, 1000, 7)
        return false
    end
end

function sampEvents.onSendGiveDamage(targetId, damage, weapon, bodypart)
    if cfg.options.scriptEnabled ~= 1 then return end
    if cfg.options.no_friend_damage ~= 1 then return true end

    local nick = sampGetPlayerNickname(targetId)

    if isFriend1(nick) then
        printStyledString(FF_TEXT, 1000, 7)

        if cfg.options.inf_ammo_when_friendfire == 1 then
            local ammo = getAmmoInCharWeapon(PLAYER_PED, weapon)
            local weaponId = getCurrentCharWeapon(PLAYER_PED)
            setCharAmmo(PLAYER_PED, weaponId, ammo + 1)
        end

        return false
    end
end

function sampEvents.onPlayerJoin(id, color, isNpc, nickname)
    updateOnline()
    if isFriend(nickname) then
        table.insert(onlineFriends, {id = id, nick = nickname})

        if cfg.options.scriptEnabled == 1 and cfg.options.notifyConnect == 1 then
            lua_thread.create(function()
                wait(300) 
                sampAddChatMessage(string.format("Игрок %s{FFFFFF} подключился к серверу", nickWithId(nickname, id)), -1)
            end)
        end
    end
end

function sampEvents.onPlayerQuit(id)
    for i = #onlineFriends, 1, -1 do
        if onlineFriends[i].id == id then
            local nick = onlineFriends[i].nick

            if cfg.options.scriptEnabled == 1 and cfg.options.notifyConnect == 1 then
                sampAddChatMessage(string.format("Игрок %s{FFFFFF} отключился от сервера", nickWithId(nick, id)), -1)
            end

            table.remove(onlineFriends, i)
        end
    end
end

function sampEvents.onSendCommand(text)
    if text == "/fr" then
        showMenu[0] = not showMenu[0]
        return false
    end
end