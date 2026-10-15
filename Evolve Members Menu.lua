script_author("Impressive")
script_name('Evolve Members Menu')
require("lib.moonloader")
local imgui = require "imgui"
local vkeys = require "vkeys"
local encoding = require 'encoding'
encoding.default = 'CP1251'
u8 = encoding.UTF8
local sampev = require 'samp.events'
local bit = require 'bit'

local hide_chat_lines = imgui.ImBool(true)
local menu_window_state = imgui.ImBool(false)
local sw, sh = getScreenResolution()

local scale = math.min(sw / 1920, sh / 1080)
if scale < 0.5 then scale = 0.5 end
if scale > 2.0 then scale = 2.0 end

local function S(v)
    return math.floor(v * scale + 0.5)
end

local my_clist_color = nil

function sampev.onSetPlayerColor(playerId, color)
    local ok, myId = pcall(sampGetPlayerIdByCharHandle, PLAYER_PED)
    if ok and myId and playerId == myId then
        my_clist_color = color
    end
end

local function getMyId()
    local res, id = sampGetPlayerIdByCharHandle(PLAYER_PED)
    if res then return id end
    return nil
end

local MIN_NICK_BRIGHTNESS = 0.35
local NICK_LIGHTEN_AMOUNT = 0.25

local function getPlayerClistImVec4(id)
    if not id then return nil end
    local pid = tonumber(id)
    if not pid then return nil end

    local myId = getMyId()
    local isLocal = (myId ~= nil and pid == myId)

    if not isLocal and not sampIsPlayerConnected(pid) then 
        return nil 
    end

    local ok, color = pcall(sampGetPlayerColor, pid)
    if not ok or not color or color == 0 then 
        return nil 
    end

    local r = bit.band(bit.rshift(color, 16), 0xFF) / 255.0
    local g = bit.band(bit.rshift(color, 8), 0xFF) / 255.0
    local b = bit.band(color, 0xFF) / 255.0

    local brightness = 0.299 * r + 0.587 * g + 0.114 * b
    if brightness < MIN_NICK_BRIGHTNESS then
        r = r + (1.0 - r) * NICK_LIGHTEN_AMOUNT
        g = g + (1.0 - g) * NICK_LIGHTEN_AMOUNT
        b = b + (1.0 - b) * NICK_LIGHTEN_AMOUNT
    end

    return imgui.ImVec4(r, g, b, 1.0)
end

local function getPlayerHexColor(id)
    if not id then return "FFFFFF" end
    local pid = tonumber(id)
    if not pid or not sampIsPlayerConnected(pid) then return "FFFFFF" end
    local ok, color = pcall(sampGetPlayerColor, pid)
    if not ok or not color or color == 0 then return "FFFFFF" end
    local r = bit.band(bit.rshift(color, 16), 0xFF)
    local g = bit.band(bit.rshift(color, 8), 0xFF)
    local b = bit.band(color, 0xFF)
    return string.format("%02X%02X%02X", r, g, b)
end

local membersList = {}
local current_sphere = "unknown"
local current_tab = 1

local search_query = imgui.ImBuffer(256)
local offline_search_query = imgui.ImBuffer(256)

local show_rank_dialog = imgui.ImBool(false)
local dialog_target_nick = ""
local dialog_target_id = nil
local dialog_target_online = false
local dialog_target_rank = 0

local show_eghr_dialog = imgui.ImBool(false)
local show_egha_dialog = imgui.ImBool(false)
local show_eghr_down_dialog = imgui.ImBool(false)
local show_egha_down_dialog = imgui.ImBool(false)
local show_offline_dialog = imgui.ImBool(false)
local show_offline_senior_dialog = imgui.ImBool(false)

local eghr_lvl_val = imgui.ImInt(3)
local eghr_state = { rank = nil }
local egha_state = { rank = nil }
local eghr_down_lvl_val = imgui.ImInt(3)
local eghr_down_state = { rank = nil }
local egha_down_state = { rank = nil }
local offline_senior_state = { rank = nil }

local eghr_down_exceptions = {}
local egha_down_exceptions = {}

local pendingClose = false

local ACTION_COOLDOWN_MS = 650
local lastActionClickTime = 0

local expect_script_rank_notification = 0
local expect_script_uninvite_notification = 0

local function actionAllowed()
    local now = os.clock() * 1000
    if now - lastActionClickTime >= ACTION_COOLDOWN_MS then
        lastActionClickTime = now
        return true
    end
    return false
end

local WM_KEYFIRST, WM_KEYLAST = 0x0100, 0x0109
local WM_MOUSEFIRST, WM_MOUSELAST = 0x0200, 0x020E

local lastActiveSearchQuery = nil
local wasActiveSearchQuery = false

local lastActiveOfflineSearchQuery = nil
local wasActiveOfflineSearchQuery = false

local function closeAllDialogs()
    show_rank_dialog.v = false
    show_eghr_dialog.v = false
    show_egha_dialog.v = false
    show_eghr_down_dialog.v = false
    show_egha_down_dialog.v = false
    show_offline_dialog.v = false
    show_offline_senior_dialog.v = false
end

local function openDialog(dialog)
    closeAllDialogs()
    dialog.v = true
end

local giverank_queue = {}
local process_active = false
local process_type = nil
local queue_ready = false
local processed_count = 0

local total_members_count = 0
local list_synced = false

local syncing_online = false
local syncing_offline = false
local full_sync_running = false

local SLVL, SRANG = nil, nil
local ARANG = nil

local function notify(text)
    sampAddChatMessage(string.format("{AAAAAA}[MBMenu]{FFFFFF} %s", text), -1)
end

local function getUnifiedMaxRank()
    return (current_sphere == "bikers") and 8 or 9
end

local function getSeniorRange()
    if current_sphere == "bikers" then
        return 6, 8
    else
        return 7, 9
    end
end

local function getOfflineSeniorRange()
    if current_sphere == "bikers" then
        return 6, 8
    else
        return 8, 9
    end
end

local function getLastSeenColor(member)
    if not member.last_seen or member.last_seen == "—" then return nil end

    local h, min, d, m, y = member.last_seen:match("(%d%d):(%d%d)%s+(%d%d)%.(%d%d)%.(%d%d%d%d)")
    if h and min and d and m and y then
        local ts = os.time({
            year = tonumber(y),
            month = tonumber(m),
            day = tonumber(d),
            hour = tonumber(h),
            min = tonumber(min),
            sec = 0
        })
        local diffHours = os.difftime(os.time(), ts) / 3600
        if diffHours >= 24 then
            return imgui.ImVec4(0.95, 0.25, 0.25, 1.00) 
        elseif diffHours >= 12 then
            return imgui.ImVec4(0.95, 0.85, 0.25, 1.00) 
        end
    end
    return nil
end

local function setMemberRankByNick(nick, isOnline, newRank)
    for _, m in ipairs(membersList) do
        if m.nick == nick and m.online == isOnline then
            local oldRank = m.rank
            m.rank = newRank
            return m, oldRank
        end
    end
    return nil, nil
end

local function removeMemberByNick(nick)
    for i = #membersList, 1, -1 do
        if membersList[i].nick == nick then
            table.remove(membersList, i)
            return true
        end
    end
    return false
end

local function requestOnlineSync(duration)
    syncing_online = true
    sampSendChat("/members")
    lua_thread.create(function()
        wait(duration or 4000)
        syncing_online = false
    end)
end

local function requestOfflineSync(duration)
    syncing_offline = true
    sampSendChat("/offmembers")
    lua_thread.create(function()
        wait(duration or 9000)
        syncing_offline = false
    end)
end

local skins = {
    bikers = {247, 181, 100, 248, 13945, 13946, 13947, 201, 298, 246, 85, 64, 195, 41, 190, 56, 226},
    mafia  = {111, 112, 125, 126, 117, 120, 123, 186, 113, 124, 127, 223, 214, 216, 169, 263, 12, 91},
    ghetto = {21, 102, 103, 104, 47, 108, 109, 110, 86, 105, 106, 107, 149, 269, 270, 271, 297, 44, 48, 114, 115, 116, 292, 119, 173, 174, 175, 13966, 13967, 13968, 13969, 13970}
}

local limits = {
    bikers = { {r = 8, max = 8}, {r = 7, max = 10}, {r = 6, max = 12} },
    mafia  = { {r = 9, max = 14}, {r = 8, max = 16} },
    ghetto = { {r = 9, max = 25}, {r = 8, max = 30} }
}

function onWindowMessage(msg, wparam, lparam)
    if not menu_window_state.v then return end

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

function detectSphere()
    if not doesCharExist(PLAYER_PED) then return "unknown" end
    local mySkin = getCharModel(PLAYER_PED)
    for sphere, idList in pairs(skins) do
        for _, id in ipairs(idList) do
            if mySkin == id then return sphere end
        end
    end
    return "unknown"
end

function getRankCount(rank, isOnline)
    local count = 0
    for _, item in ipairs(membersList) do
        if item.rank == rank and item.online == isOnline then
            count = count + 1
        end
    end
    return count
end

function stopProcess()
    local count = processed_count
    giverank_queue = {}
    process_active = false
    process_type = nil
    queue_ready = false
    processed_count = 0
    SLVL, SRANG, ARANG = nil, nil, nil
    if count > 0 then
        notify(string.format("Процесс остановлен. Обработано игроков: %d", count))
    else
        notify("Процесс остановлен.")
    end
end

function startEghr(lvl, rank)
    if process_active then
        notify("Процесс уже запущен. Остановите его кнопкой в меню.")
        return
    end
    SLVL, SRANG = lvl, rank
    process_active = true
    process_type = "eghr"
    queue_ready = false
    requestOnlineSync()
    notify("/eghs - остановить процесс")
    notify(string.format("Запущена выдача %d ранга всем игрокам с %d уровнем и выше.", rank, lvl))
    lua_thread.create(function()
        wait(1800)
        if process_active and process_type == "eghr" and not queue_ready then
            buildRankQueue()
        end
    end)
end

function startEgha(rank)
    if process_active then
        notify("Процесс уже запущен. Остановите его кнопкой в меню.")
        return
    end
    ARANG = rank
    process_active = true
    process_type = "egha"
    queue_ready = false
    requestOnlineSync()
    notify("/eghs - остановить процесс")
    notify(string.format("Запущена выдача %d ранга всему составу.", rank))
    lua_thread.create(function()
        wait(1800)
        if process_active and process_type == "egha" and not queue_ready then
            buildRankQueue()
        end
    end)
end

function startEghrDown(lvl, rank)
    if process_active then
        notify("Процесс уже запущен. Остановите его кнопкой в меню.")
        return
    end
    SLVL, SRANG = lvl, rank
    process_active = true
    process_type = "eghr_down"
    queue_ready = false
    requestOnlineSync()
    notify("/eghs - остановить процесс")
    notify(string.format("Запущено понижение до %d ранга всех игроков с %d уровнем и ниже.", rank, lvl))
    lua_thread.create(function()
        wait(1800)
        if process_active and process_type == "eghr_down" and not queue_ready then
            buildRankQueue()
        end
    end)
end

function startEghaDown(rank)
    if process_active then
        notify("Процесс уже запущен. Остановите его кнопкой в меню.")
        return
    end
    ARANG = rank
    process_active = true
    process_type = "egha_down"
    queue_ready = false
    requestOnlineSync()
    notify("/eghs - остановить процесс")
    notify(string.format("Запущено понижение всего состава до %d ранга.", rank))
    lua_thread.create(function()
        wait(1800)
        if process_active and process_type == "egha_down" and not queue_ready then
            buildRankQueue()
        end
    end)
end

function startOfflineClear()
    if process_active then
        notify("Процесс уже запущен. Остановите его кнопкой в меню.")
        return
    end
    process_active = true
    process_type = "offline_clear"
    queue_ready = false
    requestOfflineSync()
    notify("/eghs - остановить процесс")
    notify("Запущено понижение офлайн-состава.")
    lua_thread.create(function()
        wait(1800)
        if process_active and process_type == "offline_clear" and not queue_ready then
            buildOfflineClearQueue()
        end
    end)
end

function startOfflineSeniorDown(rank)
    if process_active then
        notify("Процесс уже запущен. Остановите его кнопкой в меню.")
        return
    end
    ARANG = rank
    process_active = true
    process_type = "offline_senior_down"
    queue_ready = false
    requestOfflineSync()
    notify("/eghs - остановить процесс")
    notify(string.format("Запущено понижение старшего состава (офлайн) до %d ранга.", rank))
    lua_thread.create(function()
        wait(1800)
        if process_active and process_type == "offline_senior_down" and not queue_ready then
            buildOfflineSeniorQueue()
        end
    end)
end

function buildRankQueue()
    giverank_queue = {}
    processed_count = 0
    local unified_max_rank = getUnifiedMaxRank()
    for _, m in ipairs(membersList) do
        if m.online and m.id and m.rank then
            local pid = tonumber(m.id)
            if pid and sampIsPlayerConnected(pid) then
                if process_type == "eghr" and SLVL and SRANG then
                    local lvl = tonumber(sampGetPlayerScore(pid)) or 0
                    if lvl >= SLVL and m.rank < SRANG then
                        table.insert(giverank_queue, { cmd = string.format("/giverank %d %d", pid, SRANG), nick = m.nick, online = true, rank = SRANG })
                    end
                elseif process_type == "egha" and ARANG then
                    if m.rank < ARANG then
                        table.insert(giverank_queue, { cmd = string.format("/giverank %d %d", pid, ARANG), nick = m.nick, online = true, rank = ARANG })
                    end
                elseif process_type == "eghr_down" and SLVL and SRANG then
                    local lvl = tonumber(sampGetPlayerScore(pid)) or 0
                    local excluded = eghr_down_exceptions[m.rank] and eghr_down_exceptions[m.rank].v
                    if lvl < SLVL and m.rank <= unified_max_rank and m.rank > SRANG and not excluded then
                        table.insert(giverank_queue, { cmd = string.format("/giverank %d %d", pid, SRANG), nick = m.nick, online = true, rank = SRANG })
                    end
                elseif process_type == "egha_down" and ARANG then
                    local excluded = egha_down_exceptions[m.rank] and egha_down_exceptions[m.rank].v
                    if m.rank <= unified_max_rank and m.rank > ARANG and not excluded then
                        table.insert(giverank_queue, { cmd = string.format("/giverank %d %d", pid, ARANG), nick = m.nick, online = true, rank = ARANG })
                    end
                end
            end
        end
    end
    queue_ready = true
    if #giverank_queue == 0 then
        notify("Подходящих игроков не найдено.")
        process_active = false
        process_type = nil
        queue_ready = false
    else
        local rank_used = (process_type == "eghr" or process_type == "eghr_down") and SRANG or ARANG
        notify(string.format("В очередь добавлено %d игроков (ранг: %d).", #giverank_queue, rank_used))
    end
end

function buildOfflineClearQueue()
    giverank_queue = {}
    processed_count = 0
    if current_sphere == "bikers" then
        local target = 5
        local leaderRank = 9
        for _, m in ipairs(membersList) do
            if not m.online and m.rank and m.rank > target and m.rank ~= leaderRank then
                table.insert(giverank_queue, { cmd = string.format("/offgiverank %s %d", m.nick, target), nick = m.nick, online = false, rank = target })
            end
        end
    else
        local from_rank, target = 7, 6
        for _, m in ipairs(membersList) do
            if not m.online and m.rank and m.rank == from_rank then
                table.insert(giverank_queue, { cmd = string.format("/offgiverank %s %d", m.nick, target), nick = m.nick, online = false, rank = target })
            end
        end
    end
    queue_ready = true
    if #giverank_queue == 0 then
        notify("Подходящих офлайн-игроков не найдено.")
        process_active = false
        process_type = nil
        queue_ready = false
    else
        local target_used = (current_sphere == "bikers") and 5 or 6
        notify(string.format("В очередь добавлено %d игроков (понижение до %d ранга).", #giverank_queue, target_used))
    end
end

function buildOfflineSeniorQueue()
    giverank_queue = {}
    processed_count = 0
    local senior_min, senior_max = getOfflineSeniorRange()
    local leaderRank = (current_sphere == "bikers") and 9 or 10
    for _, m in ipairs(membersList) do
        if not m.online and m.rank and m.rank >= senior_min and m.rank <= senior_max and m.rank ~= leaderRank and m.rank > ARANG then
            table.insert(giverank_queue, { cmd = string.format("/offgiverank %s %d", m.nick, ARANG), nick = m.nick, online = false, rank = ARANG })
        end
    end
    queue_ready = true
    if #giverank_queue == 0 then
        notify("Подходящих офлайн-игроков не найдено.")
        process_active = false
        process_type = nil
        queue_ready = false
    else
        notify(string.format("В очередь добавлено %d игроков (понижение до %d ранга).", #giverank_queue, ARANG))
    end
end

function main()
    while not isSampAvailable() do wait(100) end

    sampRegisterChatCommand("mbmenu", function()
        current_sphere = detectSphere()
        menu_window_state.v = not menu_window_state.v
    end)

    sampRegisterChatCommand("eghs", function()
        stopProcess()
    end)

    lua_thread.create(function()
        while true do
            wait(0)
            if #giverank_queue > 0 then
                local item = table.remove(giverank_queue, 1)
                expect_script_rank_notification = expect_script_rank_notification + 1
                sampSendChat(item.cmd)
                processed_count = processed_count + 1
                wait(1100)
            elseif process_active and queue_ready then
                local finished_type = process_type
                local count = processed_count
                process_active = false
                process_type = nil
                queue_ready = false
                processed_count = 0

                local action_word = "обработано"
                if finished_type == "eghr" or finished_type == "egha" then
                    action_word = "повышено"
                elseif finished_type == "eghr_down" or finished_type == "egha_down" or finished_type == "offline_clear" or finished_type == "offline_senior_down" then
                    action_word = "понижено"
                end
                notify(string.format("Процесс завершён. Всего %s игроков: %d", action_word, count))
            end
        end
    end)

    while true do
        wait(0)

        if pendingClose then
            menu_window_state.v = false
            pendingClose = false
        end

        imgui.Process = menu_window_state.v
    end
end

function sampev.onServerMessage(color, text)
    local cleanText = text:gsub("{%x+}", "")

    if cleanText:find("Вы назначили") then
        local nick, pId, newRankStr = cleanText:match("Вы назначили%s+([%w_]+)%[(%d+)%].-%[(%d+)%]")
        if not nick then
            nick, newRankStr = cleanText:match("Вы назначили%s+([%w_]+).-%[(%d+)%]")
        end
        if nick and newRankStr then
            local newRank = tonumber(newRankStr)
            local oldRank = "?"
            local found = false
            for _, m in ipairs(membersList) do
                if m.nick == nick then
                    oldRank = tostring(m.rank)
                    m.rank = newRank
                    if pId then m.id = pId end
                    found = true
                    break
                end
            end
            if not found then
                table.insert(membersList, {
                    nick = nick,
                    rank = newRank,
                    online = true,
                    id = pId
                })
            end
            if expect_script_rank_notification > 0 then
                expect_script_rank_notification = expect_script_rank_notification - 1
                local targetId = pId
                if not targetId then
                    for i = 0, 1000 do
                        if sampIsPlayerConnected(i) and sampGetPlayerNickname(i) == nick then
                            targetId = tostring(i)
                            break
                        end
                    end
                end
                local hexCol = getPlayerHexColor(targetId)
                local idStr = targetId and string.format("[%s]", targetId) or ""
                notify(string.format("{%s}%s%s{FFFFFF} отправлен с {AAAAAA}%s{FFFFFF} на {AAAAAA}%d{FFFFFF} ранг.", hexCol, nick, idStr, tostring(oldRank), newRank))
            end
        end
        return
    end

    if cleanText:find("Игрок") and (cleanText:find("ранга") or cleanText:find("ранг")) then
        local nick, newRankStr = cleanText:match("Игрок%s+([%w_]+)%s+.-до%s+(%d+)%s+ранг")
        if not nick then
            nick, newRankStr = cleanText:match("Игрок%s+([%w_]+)%s+.-%[(%d+)%]")
        end
        if nick and newRankStr then
            local newRank = tonumber(newRankStr)
            local oldRank = "?"
            local found = false
            for _, m in ipairs(membersList) do
                if m.nick == nick then
                    oldRank = tostring(m.rank)
                    m.rank = newRank
                    found = true
                    break
                end
            end
            if not found then
                table.insert(membersList, {
                    nick = nick,
                    rank = newRank,
                    online = false,
                    id = nil,
                    last_seen = "—"
                })
            end
            if expect_script_rank_notification > 0 then
                expect_script_rank_notification = expect_script_rank_notification - 1
                notify(string.format("%s (Offline) отправлен с {AAAAAA}%s{FFFFFF} на {AAAAAA}%d{FFFFFF} ранг.", nick, tostring(oldRank), newRank))
            end
        end
        return
    end

    if cleanText:find("Вы выгнали") then
        local nick = cleanText:match("Вы выгнали%s+([%w_]+)%[%d+%]%s+из организации")
        if nick then
            removeMemberByNick(nick)
            if expect_script_uninvite_notification > 0 then
                expect_script_uninvite_notification = expect_script_uninvite_notification - 1
                notify(string.format("Игрок %s уволен из организации.", nick))
            end
        end
        return
    end

    if cleanText:find("уволен из организации") then
        local nick = cleanText:match("Игрок%s+([%w_]+)%s+уволен из организации")
        if nick then
            removeMemberByNick(nick)
            if expect_script_uninvite_notification > 0 then
                expect_script_uninvite_notification = expect_script_uninvite_notification - 1
                notify(string.format("Игрок %s уволен из организации.", nick))
            end
        end
        return
    end

    if syncing_online then
        local nick = cleanText:match("(%w+_%w+)")
        if nick then
            local pId = cleanText:match("ID:%s*(%d+)") or cleanText:match("%[(%d+)%]") or cleanText:match("id:%s*(%d+)")
            local _, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
            local myNick = sampGetPlayerNickname(myId)
            if not pId and nick == myNick then
                pId = tostring(myId)
            end

            local afterNick = cleanText:match(nick .. ".*")
            local rankStr = afterNick and afterNick:match(":%s*[^%[]+%[(%d+)%]")
            if not rankStr then
                rankStr = cleanText:match("(%d+)%s*ранг") or cleanText:match("%[(%d+)%]")
            end
            local rank = tonumber(rankStr)

            if rank then
                current_sphere = detectSphere()
                for i = #membersList, 1, -1 do
                    if membersList[i].nick == nick and membersList[i].online == true then
                        table.remove(membersList, i)
                    end
                end
                table.insert(membersList, {
                    nick = nick,
                    rank = rank,
                    online = true,
                    id = pId
                })
                if hide_chat_lines.v then return false end
            end
        end
    elseif syncing_offline then
        local rStr, nStr, lastSeen = cleanText:match("%[(%d+)%]%s*%[?(%w+_%w+)%]?.*%[(%d%d:%d%d%s+%d%d%.%d%d%.%d%d%d%d)%]")
        if not rStr or not nStr then
            rStr, nStr, lastSeen = cleanText:match("%[?(%w+_%w+)%]?%s*%[(%d+)%].*%[(%d%d:%d%d%s+%d%d%.%d%d%.%d%d%d%d)%]")
        end

        if nStr and rStr then
            local rank = tonumber(rStr)
            if rank and rank >= 1 and rank <= 10 then
                current_sphere = detectSphere()
                for i = #membersList, 1, -1 do
                    if membersList[i].nick == nStr and membersList[i].online == false then
                        table.remove(membersList, i)
                    end
                end
                table.insert(membersList, {
                    nick = nStr,
                    rank = rank,
                    online = false,
                    id = nil,
                    last_seen = lastSeen or "—"
                })
                if hide_chat_lines.v then return false end 
            end
        end
    end

    local totalStr = cleanText:match("Всего%s*:%s*(%d+)%s*человек")
    if totalStr then
        total_members_count = tonumber(totalStr)
        list_synced = true
        if hide_chat_lines.v and (syncing_online or syncing_offline) then
            return false
        end
    end
end

local function drawRankSelector(id_prefix, state, max_rank)
    local btn_width, btn_height, items_per_row = S(70), S(26), 4
    for r = 1, max_rank do
        if (r - 1) % items_per_row ~= 0 then
            imgui.SameLine()
        end
        local label = u8(string.format("%d ранг##%s_%d", r, id_prefix, r))
        local selected = (state.rank == r)
        if selected then
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.20, 0.65, 0.30, 1.00))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.20, 0.65, 0.30, 1.00))
            imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.20, 0.65, 0.30, 1.00))
        end
        if imgui.Button(label, imgui.ImVec2(btn_width, btn_height)) then
            state.rank = r
        end
        if selected then
            imgui.PopStyleColor(3)
        end
    end
end

local function drawRankSelectorFromList(id_prefix, state, ranks)
    local btn_width, btn_height, items_per_row = S(70), S(26), 4
    for i, r in ipairs(ranks) do
        if (i - 1) % items_per_row ~= 0 then
            imgui.SameLine()
        end
        local label = u8(string.format("%d ранг##%s_%d", r, id_prefix, r))
        local selected = (state.rank == r)
        if selected then
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.20, 0.65, 0.30, 1.00))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.20, 0.65, 0.30, 1.00))
            imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.20, 0.65, 0.30, 1.00))
        end
        if imgui.Button(label, imgui.ImVec2(btn_width, btn_height)) then
            state.rank = r
        end
        if selected then
            imgui.PopStyleColor(3)
        end
    end
end

local function drawSeniorExceptions(exceptions_table, id_prefix)
    local senior_min, senior_max = getSeniorRange()
    imgui.Spacing()
    imgui.TextColored(imgui.ImVec4(1.00, 0.80, 0.00, 1.00), u8"Исключить из процесса (не понижать):")
    for r = senior_min, senior_max do
        if exceptions_table[r] == nil then
            exceptions_table[r] = imgui.ImBool(false)
        end
        if r > senior_min then
            imgui.SameLine()
        end
        imgui.Checkbox(u8(string.format("%d ранг##%s_exc_%d", r, id_prefix, r)), exceptions_table[r])
    end
end

local function drawProcessButton(label, my_type, width, on_click)
    if process_active and process_type == my_type then
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.75, 0.15, 0.15, 1.00))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.88, 0.20, 0.20, 1.00))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.88, 0.20, 0.20, 1.00))
        if imgui.Button(u8("Остановить процесс##stop_" .. my_type), imgui.ImVec2(width, S(24))) then
            stopProcess()
        end
        imgui.PopStyleColor(3)
    else
        if imgui.Button(u8(label .. "##btn_" .. my_type), imgui.ImVec2(width, S(24))) then
            if not process_active then
                on_click()
            else
                notify("Другой процесс уже запущен. Остановите его сначала.")
            end
        end
    end
end

function imgui.CenterTextColored(color, text)
    local width = imgui.GetWindowWidth()
    local calc = imgui.CalcTextSize(text)
    imgui.SetCursorPosX((width - calc.x) * 0.5)
    imgui.TextColored(color, text)
end

function imgui.CenterText(text)
    local width = imgui.GetWindowWidth()
    local calc = imgui.CalcTextSize(text)
    imgui.SetCursorPosX((width - calc.x) * 0.5)
    imgui.Text(text)
end

function renderActionButtons(member, idx, id_prefix)
    local isLeaderRank = false
    if current_sphere == "bikers" and member.rank == 9 then
        isLeaderRank = true
    elseif (current_sphere == "mafia" or current_sphere == "ghetto") and member.rank == 10 then
        isLeaderRank = true
    end

    if isLeaderRank then return end

    if current_sphere == "bikers" then
        if member.rank ~= 5 then
            local btn_label = u8(string.format("5##%s_%s_%d", id_prefix, member.nick, idx))
            if imgui.Button(btn_label, imgui.ImVec2(S(32), S(22))) then
                if actionAllowed() then
                    local cmd = member.online and string.format("/giverank %s 5", tostring(member.id)) or string.format("/offgiverank %s 5", member.nick)
                    expect_script_rank_notification = expect_script_rank_notification + 1
                    sampSendChat(cmd)
                end
            end
        else
            imgui.Dummy(imgui.ImVec2(S(32), S(22)))
        end
        imgui.SameLine()
    else
        if member.rank ~= 6 then
            local btn_label6 = u8(string.format("6##%s_6_%s_%d", id_prefix, member.nick, idx))
            if imgui.Button(btn_label6, imgui.ImVec2(S(32), S(22))) then
                if actionAllowed() then
                    local cmd = member.online and string.format("/giverank %s 6", tostring(member.id)) or string.format("/offgiverank %s 6", member.nick)
                    expect_script_rank_notification = expect_script_rank_notification + 1
                    sampSendChat(cmd)
                end
            end
        else
            imgui.Dummy(imgui.ImVec2(S(32), S(22)))
        end
        imgui.SameLine()

        if member.rank ~= 7 then
            local btn_label7 = u8(string.format("7##%s_7_%s_%d", id_prefix, member.nick, idx))
            if imgui.Button(btn_label7, imgui.ImVec2(S(32), S(22))) then
                if actionAllowed() then
                    local cmd = member.online and string.format("/giverank %s 7", tostring(member.id)) or string.format("/offgiverank %s 7", member.nick)
                    expect_script_rank_notification = expect_script_rank_notification + 1
                    sampSendChat(cmd)
                end
            end
        else
            imgui.Dummy(imgui.ImVec2(S(32), S(22)))
        end
        imgui.SameLine()
    end

    local rank_btn_label = u8(string.format("Изменить##%s_edit_%s_%d", id_prefix, member.nick, idx))
    if imgui.Button(rank_btn_label, imgui.ImVec2(S(65), S(22))) then
        if actionAllowed() then
            dialog_target_nick = member.nick
            dialog_target_id = member.id
            dialog_target_online = member.online
            dialog_target_rank = member.rank
            openDialog(show_rank_dialog)
        end
    end
end

function renderMembersSection(isOnlineTarget)
    local idx = 1

    if isOnlineTarget then
        imgui.Columns(4, "senior_online_table", true)
        imgui.SetColumnWidth(0, S(35))
        imgui.SetColumnWidth(1, S(210))
        imgui.SetColumnWidth(2, S(55))

        imgui.TextDisabled(u8"№")
        imgui.NextColumn()
        imgui.TextDisabled(u8"Игрок [ID]")
        imgui.NextColumn()
        imgui.TextDisabled(u8"Ранг")
        imgui.NextColumn()
        imgui.TextDisabled(u8"Действия")
        imgui.NextColumn()
        imgui.Separator()

        for _, member in ipairs(membersList) do
            local isSenior = false
            if current_sphere == "bikers" and (member.rank >= 6 and member.rank <= 8) then
                isSenior = true
            elseif (current_sphere == "mafia" or current_sphere == "ghetto") and (member.rank == 8 or member.rank == 9) then
                isSenior = true
            end

            if member.online and isSenior then
                imgui.AlignTextToFramePadding()
                imgui.Text(string.format("%d", idx))
                imgui.NextColumn()

                imgui.AlignTextToFramePadding()
                local clistColor = getPlayerClistImVec4(member.id)
                if clistColor then
                    imgui.TextColored(clistColor, string.format("%s [%s]", member.nick, member.id or "?"))
                else
                    imgui.Text(string.format("%s [%s]", member.nick, member.id or "?"))
                end
                imgui.NextColumn()

                imgui.AlignTextToFramePadding()
                imgui.Text(tostring(member.rank))
                imgui.NextColumn()

                renderActionButtons(member, idx, "sr_on")

                imgui.NextColumn()
                imgui.Separator()
                idx = idx + 1
            end
        end
        imgui.Columns(1)
    else
        imgui.Columns(5, "senior_offline_table", true)
        imgui.SetColumnWidth(0, S(35))
        imgui.SetColumnWidth(1, S(170))
        imgui.SetColumnWidth(2, S(45))
        imgui.SetColumnWidth(3, S(135))

        imgui.TextDisabled(u8"№")
        imgui.NextColumn()
        imgui.TextDisabled(u8"Игрок")
        imgui.NextColumn()
        imgui.TextDisabled(u8"Ранг")
        imgui.NextColumn()
        imgui.TextDisabled(u8"Заходил")
        imgui.NextColumn()
        imgui.TextDisabled(u8"Действия")
        imgui.NextColumn()
        imgui.Separator()

        for _, member in ipairs(membersList) do
            local isSenior = false
            if current_sphere == "bikers" and (member.rank >= 6 and member.rank <= 8) then
                isSenior = true
            elseif (current_sphere == "mafia" or current_sphere == "ghetto") and (member.rank == 8 or member.rank == 9) then
                isSenior = true
            end

            if not member.online and isSenior then
                imgui.AlignTextToFramePadding()
                imgui.Text(string.format("%d", idx))
                imgui.NextColumn()

                imgui.AlignTextToFramePadding()
                imgui.Text(member.nick)
                imgui.NextColumn()

                imgui.AlignTextToFramePadding()
                imgui.Text(tostring(member.rank))
                imgui.NextColumn()

                imgui.AlignTextToFramePadding()
                local lastSeenColor = getLastSeenColor(member)
                if lastSeenColor then
                    imgui.TextColored(lastSeenColor, member.last_seen or "—")
                else
                    imgui.Text(member.last_seen or "—")
                end
                imgui.NextColumn()

                renderActionButtons(member, idx, "sr_off")

                imgui.NextColumn()
                imgui.Separator()
                idx = idx + 1
            end
        end
        imgui.Columns(1)
    end

    if idx == 1 then
        imgui.TextDisabled(u8" Нет игроков в этой категории.")
    end
end

function imgui.OnDrawFrame()
    if menu_window_state.v then
        imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
        imgui.SetNextWindowSize(imgui.ImVec2(S(1200), S(780)), imgui.Cond.FirstUseEver)

        local sphere_titles = { bikers = "Байкеры", mafia = "Мафии", ghetto = "Гетто", unknown = "Не определена" }
        local title = string.format("Evolve Members Menu || %s", sphere_titles[current_sphere])

        imgui.Begin(u8(title), menu_window_state, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar)

        local tab_w = (imgui.GetWindowContentRegionWidth() - (imgui.GetStyle().ItemSpacing.x * 2)) / 3

        local tab1_active = (current_tab == 1)
        if tab1_active then
            imgui.PushStyleColor(imgui.Col.Button, imgui.GetStyle().Colors[imgui.Col.ButtonActive])
        end
        if imgui.Button(u8"Старший состав", imgui.ImVec2(tab_w, S(30))) then current_tab = 1 end
        if tab1_active then imgui.PopStyleColor() end

        imgui.SameLine()

        local tab2_active = (current_tab == 2)
        if tab2_active then
            imgui.PushStyleColor(imgui.Col.Button, imgui.GetStyle().Colors[imgui.Col.ButtonActive])
        end
        if imgui.Button(u8"ONLINE MEMBERS", imgui.ImVec2(tab_w, S(30))) then current_tab = 2 end
        if tab2_active then imgui.PopStyleColor() end

        imgui.SameLine()

        local tab3_active = (current_tab == 3)
        if tab3_active then
            imgui.PushStyleColor(imgui.Col.Button, imgui.GetStyle().Colors[imgui.Col.ButtonActive])
        end
        if imgui.Button(u8"OFFLINE MEMBERS", imgui.ImVec2(tab_w, S(30))) then current_tab = 3 end
        if tab3_active then imgui.PopStyleColor() end

		imgui.Spacing()
		imgui.Checkbox(u8"Не отображать строки в чате", hide_chat_lines)
        imgui.Spacing()

        if current_tab == 1 then
            local dash_h = (current_sphere == "unknown") and S(160) or S(115)
            imgui.BeginChild("##dashboard_new", imgui.ImVec2(0, dash_h), true)
            if current_sphere ~= "unknown" and limits[current_sphere] then
                local rank_info = limits[current_sphere]
                local num_columns = #rank_info + 1
                imgui.Columns(num_columns, "dashboard_grid", false)

                imgui.SetColumnWidth(0, S(180))
                for col = 1, #rank_info do
                    imgui.SetColumnWidth(col, S(150))
                end

                imgui.TextDisabled(u8"Категория")
                imgui.NextColumn()
                for _, info in ipairs(rank_info) do
                    imgui.TextDisabled(u8(string.format("— %d ранг —", info.r)))
                    imgui.NextColumn()
                end
                imgui.Separator()

                imgui.TextColored(imgui.ImVec4(0.20, 0.85, 0.20, 1.00), u8"В сети (Online):")
                imgui.NextColumn()
                for _, info in ipairs(rank_info) do
                    local on_count = getRankCount(info.r, true)
                    imgui.Text(string.format("%d / %d", on_count, info.max))
                    imgui.NextColumn()
                end

                imgui.TextColored(imgui.ImVec4(0.95, 0.25, 0.25, 1.00), u8"Вне сети (Offline):")
                imgui.NextColumn()
                for _, info in ipairs(rank_info) do
                    local off_count = getRankCount(info.r, false)
                    imgui.Text(string.format("%d / %d", off_count, info.max))
                    imgui.NextColumn()
                end

                imgui.TextColored(imgui.ImVec4(1.00, 0.80, 0.00, 1.00), u8"Свободные слоты:")
                imgui.NextColumn()
                for _, info in ipairs(rank_info) do
                    local on_count = getRankCount(info.r, true)
                    local off_count = getRankCount(info.r, false)
                    local free_slots = info.max - (on_count + off_count)
                    if free_slots < 0 then free_slots = 0 end

                    if free_slots > 0 then
                        imgui.TextColored(imgui.ImVec4(0.20, 0.85, 0.20, 1.00), string.format("%d", free_slots))
                    else
                        imgui.TextColored(imgui.ImVec4(0.95, 0.25, 0.25, 1.00), u8"0 (Лимит)")
                    end
                    imgui.NextColumn()
                end
                imgui.Columns(1)
            else
                imgui.CenterText(u8"Наденьте фракционный скин для автоматического расчёта лимитов.")
                imgui.Spacing()
                if imgui.Button(u8"Гетто##manual_sphere_ghetto", imgui.ImVec2(S(300), S(30))) then
                    current_sphere = "ghetto"
                end
                imgui.SameLine()
                if imgui.Button(u8"Мафии##manual_sphere_mafia", imgui.ImVec2(S(300), S(30))) then
                    current_sphere = "mafia"
                end
                imgui.SameLine()
                if imgui.Button(u8"Байкеры##manual_sphere_bikers", imgui.ImVec2(S(300), S(30))) then
                    current_sphere = "bikers"
                end
            end
            imgui.EndChild()

            imgui.Spacing()

            local bottom_space = S(35) + (imgui.GetStyle().ItemSpacing.y * 3) + S(10)
            local child_h = imgui.GetContentRegionAvail().y - bottom_space
            if child_h < S(100) then child_h = S(505) end

            local child_w = (imgui.GetWindowContentRegionWidth() / 2) - S(6)

            imgui.BeginChild("##online_section", imgui.ImVec2(child_w, child_h), true)
            imgui.CenterTextColored(imgui.ImVec4(0.20, 0.85, 0.20, 1.00), u8"В СЕТИ (ONLINE)")
            imgui.Separator()

            imgui.BeginChild("##online_list_scroll", imgui.ImVec2(0, 0), false)
            renderMembersSection(true)
            imgui.EndChild()
            imgui.EndChild()

            imgui.SameLine()

            imgui.BeginChild("##offline_section", imgui.ImVec2(child_w, child_h), true)
            imgui.CenterTextColored(imgui.ImVec4(0.90, 0.25, 0.25, 1.00), u8"В ОФФЛАЙНЕ (OFFLINE)")
            imgui.Separator()

            imgui.BeginChild("##offline_list_scroll", imgui.ImVec2(0, 0), false)
            renderMembersSection(false)
            imgui.EndChild()
            imgui.EndChild()

        elseif current_tab == 2 then
            local header_text = u8"Полный список игроков в сети (/members)"
            if list_synced then
                header_text = u8(string.format("Всего: %d человек", total_members_count))
            end
            imgui.TextColored(imgui.ImVec4(0.20, 0.85, 0.20, 1.00), header_text)
            imgui.Spacing()

            imgui.AlignTextToFramePadding()
            imgui.Text(u8"Поиск по ID / Нику:")
            imgui.SameLine()
            imgui.PushItemWidth(S(300))
            imgui.InputText("##search_query_input", search_query)
            imgui.PopItemWidth()

            if imgui.IsItemActive() then
                lastActiveSearchQuery = search_query.v
                wasActiveSearchQuery = true
            else
                if wasActiveSearchQuery then
                    if lastActiveSearchQuery then
                        search_query.v = lastActiveSearchQuery
                    end
                    wasActiveSearchQuery = false
                end
            end

            imgui.Spacing()

            drawProcessButton("Повысить по LVL", "eghr", S(170), function()
                eghr_lvl_val.v = 3
                eghr_state.rank = nil
                openDialog(show_eghr_dialog)
            end)
            imgui.SameLine()
            drawProcessButton("Повысить всех", "egha", S(170), function()
                egha_state.rank = nil
                openDialog(show_egha_dialog)
            end)
            imgui.SameLine()
            drawProcessButton("Понизить по LVL", "eghr_down", S(170), function()
                eghr_down_lvl_val.v = 3
                local ranks = (current_sphere == "bikers") and {5} or {6, 7}
                eghr_down_state.rank = ranks[1]
                eghr_down_exceptions = {}
                openDialog(show_eghr_down_dialog)
            end)
            imgui.SameLine()
            drawProcessButton("Понизить всех", "egha_down", S(170), function()
                local ranks = (current_sphere == "bikers") and {5} or {6, 7}
                egha_down_state.rank = ranks[1]
                egha_down_exceptions = {}
                openDialog(show_egha_down_dialog)
            end)

            imgui.Spacing()

            local bottom_space = S(35) + (imgui.GetStyle().ItemSpacing.y * 3) + S(10)
            local child_h = imgui.GetContentRegionAvail().y - bottom_space
            if child_h < S(100) then child_h = S(540) end

            imgui.BeginChild("##full_online_list", imgui.ImVec2(0, child_h), true)

            imgui.Columns(5, "full_online_table", true)
            imgui.SetColumnWidth(0, S(45))
            imgui.SetColumnWidth(1, S(280))
            imgui.SetColumnWidth(2, S(75))
            imgui.SetColumnWidth(3, S(65))

            imgui.TextDisabled(u8"№")
            imgui.NextColumn()
            imgui.TextDisabled(u8"Игрок [ID]")
            imgui.NextColumn()
            imgui.TextDisabled(u8"Ранг")
            imgui.NextColumn()
            imgui.TextDisabled(u8"LVL")
            imgui.NextColumn()
            imgui.TextDisabled(u8"Действия")
            imgui.NextColumn()
            imgui.Separator()

            local q = u8:decode(search_query.v):lower()
            local full_idx = 1

            local sortedMembers = {}
            for _, m in ipairs(membersList) do
                if m.online then table.insert(sortedMembers, m) end
            end
            table.sort(sortedMembers, function(a, b) return (a.rank or 0) > (b.rank or 0) end)

            local _, myId = sampGetPlayerIdByCharHandle(PLAYER_PED)
            local myNick = sampGetPlayerNickname(myId)

            for _, member in ipairs(sortedMembers) do
                local match = true
                if q ~= "" then
                    local name_match = member.nick:lower():find(q, 1, true)
                    local id_match = member.id and member.id:find(q, 1, true)
                    if not name_match and not id_match then match = false end
                end

                if match then
                    local lvl_text = "?"
                    if member.nick == myNick then
                        if not member.id then member.id = tostring(myId) end
                        local score = sampGetPlayerScore(myId)
                        if not score or score <= 0 then score = getCharScore(PLAYER_PED) end
                        if score and score >= 0 then lvl_text = tostring(score) end
                    else
                        local pid_num = member.id and tonumber(member.id)
                        if pid_num and sampIsPlayerConnected(pid_num) then
                            local score = sampGetPlayerScore(pid_num)
                            if score and score >= 0 then lvl_text = tostring(score) end
                        end
                    end

                    imgui.AlignTextToFramePadding()
                    imgui.Text(string.format("%d", full_idx))
                    imgui.NextColumn()

                    imgui.AlignTextToFramePadding()
                    local clistColor = getPlayerClistImVec4(member.id)
                    if clistColor then
                        imgui.TextColored(clistColor, string.format("%s [%s]", member.nick, member.id or "?"))
                    else
                        imgui.Text(string.format("%s [%s]", member.nick, member.id or "?"))
                    end
                    imgui.NextColumn()

                    imgui.AlignTextToFramePadding()
                    imgui.Text(tostring(member.rank or 0))
                    imgui.NextColumn()

                    imgui.AlignTextToFramePadding()
                    imgui.Text(lvl_text)
                    imgui.NextColumn()

                    renderActionButtons(member, full_idx, "full_on")

                    imgui.NextColumn()
                    imgui.Separator()
                    full_idx = full_idx + 1
                end
            end

            imgui.Columns(1)

            if full_idx == 1 then
                imgui.TextDisabled(u8" Нет подходящих игроков онлайн или список пуст. Нажмите кнопку синхронизации ниже.")
            end

            imgui.EndChild()

        elseif current_tab == 3 then
            local total_offline_count = 0
            for _, m in ipairs(membersList) do
                if not m.online then total_offline_count = total_offline_count + 1 end
            end
            local header_text_off = u8"Полный список офлайн-игроков (/offmembers)"
            if total_offline_count > 0 then
                header_text_off = u8(string.format("Всего: %d человек", total_offline_count))
            end
            imgui.TextColored(imgui.ImVec4(0.90, 0.25, 0.25, 1.00), header_text_off)
            imgui.Spacing()

            imgui.AlignTextToFramePadding()
            imgui.Text(u8"Поиск по Нику:")
            imgui.SameLine()
            imgui.PushItemWidth(S(300))
            imgui.InputText("##offline_search_query_input", offline_search_query)
            imgui.PopItemWidth()

            if imgui.IsItemActive() then
                lastActiveOfflineSearchQuery = offline_search_query.v
                wasActiveOfflineSearchQuery = true
            else
                if wasActiveOfflineSearchQuery then
                    if lastActiveOfflineSearchQuery then
                        offline_search_query.v = lastActiveOfflineSearchQuery
                    end
                    wasActiveOfflineSearchQuery = false
                end
            end

            imgui.Spacing()

            local offline_clear_label = (current_sphere == "bikers") and "OFFLINE понизить все 6-8 ранги" or "OFFLINE понизить все 7 ранги"
            drawProcessButton(offline_clear_label, "offline_clear", S(240), function()
                openDialog(show_offline_dialog)
            end)
            if current_sphere ~= "bikers" then
                imgui.SameLine()
                drawProcessButton("OFFLINE понизить все 8-9 ранги", "offline_senior_down", S(240), function()
                    local ranks = (current_sphere == "bikers") and {5} or {6, 7}
                    offline_senior_state.rank = ranks[1]
                    openDialog(show_offline_senior_dialog)
                end)
            end

            imgui.Spacing()

            local bottom_space3 = S(35) + (imgui.GetStyle().ItemSpacing.y * 3) + S(10)
            local child_h3 = imgui.GetContentRegionAvail().y - bottom_space3
            if child_h3 < S(100) then child_h3 = S(540) end

            imgui.BeginChild("##full_offline_list", imgui.ImVec2(0, child_h3), true)

            imgui.Columns(5, "full_offline_table", true)
            imgui.SetColumnWidth(0, S(45))
            imgui.SetColumnWidth(1, S(260))
            imgui.SetColumnWidth(2, S(75))
            imgui.SetColumnWidth(3, S(180))

            imgui.TextDisabled(u8"№")
            imgui.NextColumn()
            imgui.TextDisabled(u8"Ник")
            imgui.NextColumn()
            imgui.TextDisabled(u8"Ранг")
            imgui.NextColumn()
            imgui.TextDisabled(u8"Последний вход")
            imgui.NextColumn()
            imgui.TextDisabled(u8"Действия")
            imgui.NextColumn()
            imgui.Separator()

            local qo = u8:decode(offline_search_query.v):lower()
            local off_idx = 1

            local sortedOffline = {}
            for _, m in ipairs(membersList) do
                if not m.online then table.insert(sortedOffline, m) end
            end
            table.sort(sortedOffline, function(a, b) return (a.rank or 0) > (b.rank or 0) end)

            for _, member in ipairs(sortedOffline) do
                local match = true
                if qo ~= "" then
                    if not member.nick:lower():find(qo, 1, true) then match = false end
                end

                if match then
                    imgui.AlignTextToFramePadding()
                    imgui.Text(string.format("%d", off_idx))
                    imgui.NextColumn()

                    imgui.AlignTextToFramePadding()
                    imgui.Text(member.nick)
                    imgui.NextColumn()

                    imgui.AlignTextToFramePadding()
                    imgui.Text(tostring(member.rank or 0))
                    imgui.NextColumn()

                    imgui.AlignTextToFramePadding()
                    local lastSeenColor = getLastSeenColor(member)
                    if lastSeenColor then
                        imgui.TextColored(lastSeenColor, member.last_seen or "—")
                    else
                        imgui.Text(member.last_seen or "—")
                    end
                    imgui.NextColumn()

                    renderActionButtons(member, off_idx, "full_off")

                    imgui.NextColumn()
                    imgui.Separator()
                    off_idx = off_idx + 1
                end
            end

            imgui.Columns(1)

            if off_idx == 1 then
                imgui.TextDisabled(u8" Нет офлайн-игроков или список пуст. Нажмите кнопку синхронизации ниже.")
            end

            imgui.EndChild()
        end

        imgui.Separator()
        imgui.Spacing()
        imgui.SetCursorPosX((imgui.GetWindowWidth() - S(320)) * 0.5)

        local sync_btn_text
        if current_tab == 1 then
            sync_btn_text = "Синхронизировать (Online + Offline)"
        elseif current_tab == 2 then
            sync_btn_text = "Синхронизировать (Только Online)"
        else
            sync_btn_text = "Синхронизировать (Только Offline)"
        end

        if imgui.Button(u8(sync_btn_text), imgui.ImVec2(S(320), S(32))) then
            if current_sphere ~= "unknown" then
                if current_tab == 1 then
                    if not full_sync_running then
                        full_sync_running = true
                        membersList = {}
                        list_synced = false
                        requestOnlineSync()
                        lua_thread.create(function()
                            wait(1500)
                            notify("Запущена полная синхронизация (Online + Offline)...")
                            local waited = 1500
                            while syncing_online and waited < 8000 do
                                wait(100)
                                waited = waited + 100
                            end
                            wait(500)
                            requestOfflineSync()
                            local waited2 = 0
                            while syncing_offline and waited2 < 15000 do
                                wait(100)
                                waited2 = waited2 + 100
                            end
                            full_sync_running = false
                        end)
                    else
                        notify("Синхронизация уже выполняется, подождите.")
                    end
                elseif current_tab == 2 then
                    for i = #membersList, 1, -1 do
                        if membersList[i].online then
                            table.remove(membersList, i)
                        end
                    end
                    list_synced = false
                    requestOnlineSync()
                    notify("Синхронизация только онлайн-состава...")
                else
                    for i = #membersList, 1, -1 do
                        if not membersList[i].online then
                            table.remove(membersList, i)
                        end
                    end
                    list_synced = false
                    requestOfflineSync()
                    notify("Синхронизация только офлайн-состава...")
                end
            else
                current_sphere = detectSphere()
            end
        end

        imgui.End()
    end

    if show_rank_dialog.v then
        imgui.SetNextWindowFocus()
        imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))
        imgui.SetNextWindowSize(imgui.ImVec2(S(380), S(285)), imgui.Cond.Always)

        imgui.Begin(u8"Изменение ранга", show_rank_dialog, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoScrollbar)

        local info_target = string.format("Игрок: %s", dialog_target_nick)
        if dialog_target_online and dialog_target_id then
            info_target = info_target .. string.format(" [ID: %s]", dialog_target_id)
        else
            info_target = info_target .. " [OFFLINE]"
        end
        info_target = info_target .. string.format(" | Ранг: %d", dialog_target_rank or 0)
        imgui.CenterTextColored(imgui.ImVec4(1.00, 0.80, 0.00, 1.00), u8(info_target))
        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()

        local max_allowed_rank = (current_sphere == "bikers") and 8 or 9
        imgui.Text(u8(string.format("Выберите новый ранг (1-%d):", max_allowed_rank)))
        imgui.Spacing()

        local btn_width, btn_height = S(85), S(26)
        local items_per_row = 4

        for r = 1, max_allowed_rank do
            if (r - 1) % items_per_row ~= 0 then
                imgui.SameLine()
            end

            local btn_label = u8(string.format("%d##select_%d", r, r))

            if r == dialog_target_rank then
                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.20, 0.65, 0.30, 1.00))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.20, 0.65, 0.30, 1.00))
                imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.20, 0.65, 0.30, 1.00))

                imgui.Button(btn_label, imgui.ImVec2(btn_width, btn_height))

                imgui.PopStyleColor(3)
            else
                if imgui.Button(btn_label, imgui.ImVec2(btn_width, btn_height)) then
                    if actionAllowed() then
                        expect_script_rank_notification = expect_script_rank_notification + 1
                        if dialog_target_online then
                            sampSendChat(string.format("/giverank %s %d", tostring(dialog_target_id), r))
                        else
                            sampSendChat(string.format("/offgiverank %s %d", dialog_target_nick, r))
                        end
                        show_rank_dialog.v = false
                    end
                end
            end
        end

        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()

        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.75, 0.15, 0.15, 1.00))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.88, 0.20, 0.20, 1.00))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.88, 0.20, 0.20, 1.00))

        if imgui.Button(u8"Уволить", imgui.ImVec2(S(380), S(26))) then
            if actionAllowed() then
                expect_script_uninvite_notification = expect_script_uninvite_notification + 1
                if dialog_target_online and dialog_target_id then
                    sampSendChat(string.format("/uninvite %s уволен", tostring(dialog_target_id)))
                else
                    sampSendChat(string.format("/offuninvite %s уволен", dialog_target_nick))
                end
                show_rank_dialog.v = false
            end
        end

        imgui.PopStyleColor(3)

        imgui.Spacing()

        if imgui.Button(u8"Отмена", imgui.ImVec2(S(380), S(26))) then
            show_rank_dialog.v = false
        end

        imgui.End()
    end

    if show_eghr_dialog.v then
        imgui.SetNextWindowFocus()
        imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))
        imgui.SetNextWindowSize(imgui.ImVec2(S(380), S(175)), imgui.Cond.Always)
        imgui.Begin(u8"Повысить по LVL", show_eghr_dialog, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoScrollbar)

        imgui.Text(u8(string.format("Минимальный уровень игрока: %d", eghr_lvl_val.v)))
        imgui.PushItemWidth(-1)
        imgui.SliderInt("##eghr_lvl", eghr_lvl_val, 3, 20)
        imgui.PopItemWidth()
        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()

        local eghr_from, eghr_to
        if current_sphere == "bikers" then
            eghr_from, eghr_to = 4, 5
        else
            eghr_from, eghr_to = 6, 7
        end
        imgui.TextWrapped(u8(string.format("Все игроки 1-%d ранга будут повышены на %d ранг", eghr_from, eghr_to)))

        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()

        if imgui.Button(u8"Запустить", imgui.ImVec2(S(175), S(28))) then
            local lvl = eghr_lvl_val.v
            if lvl then
                startEghr(lvl, eghr_to)
                show_eghr_dialog.v = false
            else
                notify("Укажите уровень.")
            end
        end
        imgui.SameLine()
        if imgui.Button(u8"Отмена", imgui.ImVec2(S(175), S(28))) then
            show_eghr_dialog.v = false
        end

        imgui.End()
    end

    if show_egha_dialog.v then
        imgui.SetNextWindowFocus()
        imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))
        imgui.SetNextWindowSize(imgui.ImVec2(S(380), S(110)), imgui.Cond.Always)
        imgui.Begin(u8"Повысить всех", show_egha_dialog, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoScrollbar)

        local egha_from, egha_to
        if current_sphere == "bikers" then
            egha_from, egha_to = 4, 5
        else
            egha_from, egha_to = 6, 7
        end
        imgui.TextWrapped(u8(string.format("Все игроки 1-%d ранга будут повышены на %d ранг", egha_from, egha_to)))

        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()

        if imgui.Button(u8"Запустить", imgui.ImVec2(S(175), S(28))) then
            startEgha(egha_to)
            show_egha_dialog.v = false
        end
        imgui.SameLine()
        if imgui.Button(u8"Отмена", imgui.ImVec2(S(175), S(28))) then
            show_egha_dialog.v = false
        end

        imgui.End()
    end

    if show_eghr_down_dialog.v then
        imgui.SetNextWindowFocus()
        imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))
        imgui.SetNextWindowSize(imgui.ImVec2(S(360), S(255)), imgui.Cond.Always)
        imgui.Begin(u8"Понизить по LVL", show_eghr_down_dialog, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoScrollbar)

        imgui.Text(u8(string.format("Минимальный уровень игрока: %d", eghr_down_lvl_val.v)))
        imgui.PushItemWidth(-1)
        imgui.SliderInt("##eghr_down_lvl", eghr_down_lvl_val, 3, 20)
        imgui.PopItemWidth()
        imgui.Spacing()

        local eghr_down_ranks = (current_sphere == "bikers") and {5} or {6, 7}
        if eghr_down_state.rank == nil then
            eghr_down_state.rank = eghr_down_ranks[1]
        end
        imgui.Text(u8"Ранг для понижения:")
        imgui.Spacing()
        drawRankSelectorFromList("eghr_down", eghr_down_state, eghr_down_ranks)

        drawSeniorExceptions(eghr_down_exceptions, "eghr_down")

        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()

        if imgui.Button(u8"Запустить", imgui.ImVec2(S(165), S(28))) then
            local lvl = eghr_down_lvl_val.v
            if lvl and eghr_down_state.rank then
                startEghrDown(lvl, eghr_down_state.rank)
                show_eghr_down_dialog.v = false
            else
                notify("Укажите уровень и выберите ранг.")
            end
        end
        imgui.SameLine()
        if imgui.Button(u8"Отмена", imgui.ImVec2(S(165), S(28))) then
            show_eghr_down_dialog.v = false
        end

        imgui.End()
    end

    if show_egha_down_dialog.v then
        imgui.SetNextWindowFocus()
        imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))
        imgui.SetNextWindowSize(imgui.ImVec2(S(360), S(200)), imgui.Cond.Always)
        imgui.Begin(u8"Понизить всех", show_egha_down_dialog, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoScrollbar)

        local egha_down_ranks = (current_sphere == "bikers") and {5} or {6, 7}
        if egha_down_state.rank == nil then
            egha_down_state.rank = egha_down_ranks[1]
        end
        imgui.Text(u8"Ранг для понижения всего состава:")
        imgui.Spacing()
        drawRankSelectorFromList("egha_down", egha_down_state, egha_down_ranks)

        drawSeniorExceptions(egha_down_exceptions, "egha_down")

        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()

        if imgui.Button(u8"Запустить", imgui.ImVec2(S(165), S(28))) then
            if egha_down_state.rank then
                startEghaDown(egha_down_state.rank)
                show_egha_down_dialog.v = false
            else
                notify("Выберите ранг.")
            end
        end
        imgui.SameLine()
        if imgui.Button(u8"Отмена", imgui.ImVec2(S(165), S(28))) then
            show_egha_down_dialog.v = false
        end

        imgui.End()
    end

    if show_offline_dialog.v then
        imgui.SetNextWindowFocus()
        imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))
        imgui.SetNextWindowSize(imgui.ImVec2(S(400), S(120)), imgui.Cond.Always)
        local offline_clear_title = (current_sphere == "bikers") and "OFFLINE понизить все 6-8 ранги" or "OFFLINE понизить все 7 ранги"
        imgui.Begin(u8(offline_clear_title), show_offline_dialog, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoScrollbar)

        local offline_dialog_text
        if current_sphere == "bikers" then
            offline_dialog_text = string.format("Все офлайн-игроки с рангом выше %d будут понижены до %d ранга.", 5, 5)
        else
            offline_dialog_text = "Все оффлайн-игроки с рангом 7 будут понижены до 6 ранга."
        end
        imgui.TextWrapped(u8(offline_dialog_text))
        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()

        if imgui.Button(u8"Запустить", imgui.ImVec2(S(185), S(28))) then
            startOfflineClear()
            show_offline_dialog.v = false
        end
        imgui.SameLine()
        if imgui.Button(u8"Отмена", imgui.ImVec2(S(185), S(28))) then
            show_offline_dialog.v = false
        end

        imgui.End()
    end

    if show_offline_senior_dialog.v then
        imgui.SetNextWindowFocus()
        imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))
        imgui.SetNextWindowSize(imgui.ImVec2(S(360), S(190)), imgui.Cond.Always)
        imgui.Begin(u8"OFFLINE понизить все 8-9 ранги", show_offline_senior_dialog, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoScrollbar)

        local senior_min, senior_max = getOfflineSeniorRange()
        local offline_senior_ranks = (current_sphere == "bikers") and {5} or {6, 7}
        if offline_senior_state.rank == nil then
            offline_senior_state.rank = offline_senior_ranks[1]
        end
        imgui.TextWrapped(u8(string.format("Будут понижены офлайн-игроки старшего состава с рангом %d-%d.", senior_min, senior_max)))
        imgui.Spacing()
        imgui.Text(u8"Ранг для понижения:")
        imgui.Spacing()
        drawRankSelectorFromList("offline_senior", offline_senior_state, offline_senior_ranks)

        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()

        if imgui.Button(u8"Запустить", imgui.ImVec2(S(165), S(28))) then
            if offline_senior_state.rank then
                startOfflineSeniorDown(offline_senior_state.rank)
                show_offline_senior_dialog.v = false
            else
                notify("Выберите ранг.")
            end
        end
        imgui.SameLine()
        if imgui.Button(u8"Отмена", imgui.ImVec2(S(165), S(28))) then
            show_offline_senior_dialog.v = false
        end

        imgui.End()
    end
end

function apply_custom_style()
    local style = imgui.GetStyle()
    local colors = style.Colors
    local clr = imgui.Col
    local ImVec4 = imgui.ImVec4

    style.WindowRounding = 8.0 * scale
    style.WindowTitleAlign = imgui.ImVec2(0.5, 0.5)
    style.ChildWindowRounding = 6.0 * scale
    style.FrameRounding = 4.0 * scale
    style.ItemSpacing = imgui.ImVec2(S(6), S(6))
    style.WindowPadding = imgui.ImVec2(S(10), S(10))
    style.FramePadding = imgui.ImVec2(S(5), S(4))

    colors[clr.Text]                 = ImVec4(0.95, 0.95, 0.95, 1.00)
    colors[clr.WindowBg]             = ImVec4(0.08, 0.08, 0.09, 1.00)
    colors[clr.ChildWindowBg]        = ImVec4(0.12, 0.12, 0.13, 1.00)
    colors[clr.Border]               = ImVec4(0.22, 0.22, 0.24, 1.00)
    colors[clr.FrameBg]              = ImVec4(0.16, 0.16, 0.18, 1.00)
    colors[clr.FrameBgHovered]       = ImVec4(0.25, 0.25, 0.28, 0.50)
    colors[clr.FrameBgActive]        = ImVec4(0.30, 0.30, 0.35, 0.70)
    colors[clr.TitleBg]              = ImVec4(0.13, 0.13, 0.15, 1.00)
    colors[clr.TitleBgActive]        = ImVec4(0.18, 0.18, 0.20, 1.00)
    colors[clr.Button]               = ImVec4(0.18, 0.18, 0.20, 1.00)
    colors[clr.ButtonHovered]        = ImVec4(0.26, 0.26, 0.30, 1.00)
    colors[clr.ButtonActive]         = ImVec4(0.34, 0.34, 0.38, 1.00)
    colors[clr.Header]               = ImVec4(0.00, 0.00, 0.00, 0.00)
    colors[clr.HeaderHovered]        = ImVec4(0.00, 0.00, 0.00, 0.00)
    colors[clr.HeaderActive]         = ImVec4(0.00, 0.00, 0.00, 0.00)

    imgui.GetIO().FontGlobalScale = scale
end

apply_custom_style()