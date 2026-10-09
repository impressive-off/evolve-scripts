script_author("Impressive")
script_name('Evolve Fmembers Menu')
require("lib.moonloader")
local imgui = require "imgui"
local vkeys = require "vkeys"
local encoding = require 'encoding'
encoding.default = 'CP1251'
u8 = encoding.UTF8
local sampev = require 'samp.events'
local bit = require 'bit'

local menu_window_state = imgui.ImBool(false)
local sw, sh = getScreenResolution()
local scale = math.min(sw / 1920, sh / 1080)
if scale < 0.5 then scale = 0.5 end
if scale > 2.0 then scale = 2.0 end

local function S(v)
    return math.floor(v * scale + 0.5)
end

local membersList = {}
local filteredList = {}
local need_rebuild_filter = true
local last_search_text = ""
local search_query = imgui.ImBuffer(256)
local filter_type = 1

local show_rank_dialog = imgui.ImBool(false)
local dialog_target_nick = ""
local dialog_target_id = nil
local dialog_target_online = false
local dialog_target_rank = 1

local lastActionClickTime = 0
local ACTION_COOLDOWN_MS = 650

local is_script_updating = false
local pendingClose = false
local theme_applied = false
local last_off_target_nick = nil
local is_menu_action = false

local function actionAllowed()
    local now = os.clock() * 1000
    if now - lastActionClickTime >= ACTION_COOLDOWN_MS then
        lastActionClickTime = now
        return true
    end
    return false
end

local function apply_dark_theme()
    local style = imgui.GetStyle()
    local colors = style.Colors
    local clr = imgui.Col
    local ImVec4 = imgui.ImVec4

    imgui.GetIO().IniSavingRate = -1.0

    style.WindowRounding = S(6)
    style.WindowTitleAlign = imgui.ImVec2(0.5, 0.5)
    style.ChildWindowRounding = S(4)
    style.FrameRounding = S(4)
    style.ItemSpacing = imgui.ImVec2(S(6), S(6))
    style.WindowPadding = imgui.ImVec2(S(10), S(10))
    style.FramePadding = imgui.ImVec2(S(5), S(4))

    colors[clr.Text]                  = ImVec4(0.92, 0.92, 0.93, 1.00)
    colors[clr.TextDisabled]          = ImVec4(0.55, 0.55, 0.58, 1.00)
    colors[clr.WindowBg]              = ImVec4(0.12, 0.12, 0.14, 1.00)
    colors[clr.ChildWindowBg]         = ImVec4(0.16, 0.16, 0.18, 1.00)
    colors[clr.PopupBg]               = ImVec4(0.14, 0.14, 0.16, 1.00)
    colors[clr.Border]                = ImVec4(0.25, 0.25, 0.28, 1.00)
    colors[clr.BorderShadow]          = ImVec4(0.00, 0.00, 0.00, 0.00)
    colors[clr.FrameBg]               = ImVec4(0.22, 0.22, 0.25, 1.00)
    colors[clr.FrameBgHovered]        = ImVec4(0.28, 0.28, 0.32, 1.00)
    colors[clr.FrameBgActive]         = ImVec4(0.34, 0.34, 0.38, 1.00)
    colors[clr.TitleBg]               = ImVec4(0.18, 0.18, 0.20, 1.00)
    colors[clr.TitleBgActive]         = ImVec4(0.22, 0.22, 0.25, 1.00)
    colors[clr.TitleBgCollapsed]      = ImVec4(0.14, 0.14, 0.16, 1.00)
    colors[clr.MenuBarBg]             = ImVec4(0.18, 0.18, 0.20, 1.00)
    colors[clr.ScrollbarBg]           = ImVec4(0.14, 0.14, 0.16, 1.00)
    colors[clr.ScrollbarGrab]         = ImVec4(0.30, 0.30, 0.35, 1.00)
    colors[clr.ScrollbarGrabHovered]  = ImVec4(0.38, 0.38, 0.44, 1.00)
    colors[clr.ScrollbarGrabActive]   = ImVec4(0.46, 0.46, 0.52, 1.00)
    colors[clr.CheckMark]             = ImVec4(0.80, 0.80, 0.83, 1.00)
    colors[clr.SliderGrab]            = ImVec4(0.35, 0.35, 0.40, 1.00)
    colors[clr.SliderGrabActive]      = ImVec4(0.45, 0.45, 0.50, 1.00)
    colors[clr.Button]                = ImVec4(0.22, 0.22, 0.26, 1.00)
    colors[clr.ButtonHovered]         = ImVec4(0.30, 0.30, 0.36, 1.00)
    colors[clr.ButtonActive]          = ImVec4(0.38, 0.38, 0.44, 1.00)
    colors[clr.Header]                = ImVec4(0.24, 0.24, 0.28, 1.00)
    colors[clr.HeaderHovered]         = ImVec4(0.30, 0.30, 0.36, 1.00)
    colors[clr.HeaderActive]          = ImVec4(0.36, 0.36, 0.42, 1.00)

    imgui.GetIO().FontGlobalScale = scale
end

function imgui.OnInitialize()
    apply_dark_theme()
    theme_applied = true
end

function onWindowMessage(msg, wparam, lparam)
    if not menu_window_state.v then return end

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
end

local function getMyId()
    local res, id = sampGetPlayerIdByCharHandle(PLAYER_PED)
    if res then return id end
    return nil
end

local function getPlayerClistHex(id)
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

    local r = bit.band(bit.rshift(color, 16), 0xFF)
    local g = bit.band(bit.rshift(color, 8), 0xFF)
    local b = bit.band(color, 0xFF)

    return string.format("%02X%02X%02X", r, g, b)
end

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

    return imgui.ImVec4(r, g, b, 1.0)
end

local function getFormattedPlayerStr(nick, id)
    if not id then
        for _, m in ipairs(membersList) do
            if m.nick == nick then
                if m.online and m.id then
                    id = m.id
                end
                break
            end
        end
    end

    if id then
        local hex = getPlayerClistHex(id)
        if hex then
            return string.format("{%s}%s[%s]{FFFFFF}", hex, nick, tostring(id))
        else
            return string.format("%s[%s]", nick, tostring(id))
        end
    else
        return nick
    end
end

local function updateOrAddMember(data)
    for i, m in ipairs(membersList) do
        if m.nick == data.nick then
            membersList[i] = data
            need_rebuild_filter = true
            return
        end
    end
    table.insert(membersList, data)
    need_rebuild_filter = true
end

local function removeMember(nick)
    for i, m in ipairs(membersList) do
        if m.nick == nick then
            table.remove(membersList, i)
            need_rebuild_filter = true
            break
        end
    end
end

local function getTimeColor(last_seen_str)
    if not last_seen_str or last_seen_str == "—" then
        return nil
    end
    if last_seen_str == "В сети" then
        return imgui.ImVec4(0.20, 0.85, 0.20, 1.00)
    end
    local h, m, d, mo, y = last_seen_str:match("(%d+):(%d+)%s+(%d+)%.(%d+)%.(%d+)")
    if h and m and d and mo and y then
        y = tonumber(y)
        if y < 100 then y = 2000 + y end
        local t = os.time({year = y, month = tonumber(mo), day = tonumber(d), hour = tonumber(h), min = tonumber(m)})
        local diff = os.difftime(os.time(), t) / 3600
        if diff >= 24 then
            return imgui.ImVec4(0.90, 0.25, 0.25, 1.00)
        elseif diff >= 12 then
            return imgui.ImVec4(0.95, 0.70, 0.10, 1.00)
        end
    end
    return nil
end

local function rebuildFilteredList()
    filteredList = {}
    local q = u8:decode(search_query.v):lower()
    for _, m in ipairs(membersList) do
        local show = true
        if filter_type == 2 and not m.online then show = false end
        if filter_type == 3 and m.online then show = false end

        if show and q ~= "" then
            local n_match = m.nick:lower():find(q, 1, true)
            local id_match = m.id and tostring(m.id):find(q, 1, true)
            local date_match = m.last_seen and m.last_seen:lower():find(q, 1, true)
            if not n_match and not id_match and not date_match then show = false end
        end

        if show then
            table.insert(filteredList, m)
        end
    end

    table.sort(filteredList, function(a, b)
        if a.online and b.online then
            return (a.rank or 0) > (b.rank or 0)
        elseif not a.online and not b.online then
            return (a.rank or 0) > (b.rank or 0)
        elseif a.online and not b.online then
            return true
        else
            return false
        end
    end)
end

function sampev.onShowDialog(dialogId, style, title, button1, button2, text)
    local cleanTitle = title:gsub("{%x+}", "")
    if cleanTitle:find("Состав семьи") or cleanTitle:find("В сети:") then
        local lines = {}
        for line in text:gmatch("[^\r\n]+") do
            table.insert(lines, line)
        end

        if #lines > 0 then
            local has_header = (lines[1]:find("Псевдоним") or lines[1]:find("Степень родства")) and true or false
            local start_idx = has_header and 2 or 1
            local next_page_item_index = nil
            local modified = false

            for i = start_idx, #lines do
                local line = lines[i]
                local item_index = i - start_idx

                if line:find("Следующая страница") then
                    next_page_item_index = item_index
                elseif not line:find("Предыдущая страница") then
                    local clean = line:gsub("{%x+}", "")
                    local nick, pid = clean:match("([%w_]+)%s*%[(%d+)%]")
                    if nick and pid then
                        local rest = clean:match("%[%d+%]%s*(.+)") or clean
                        local rank = rest:match("%[(%d+)%]") or rest:match("(%d+)") or "1"
                        local rating = rest:match("(%d+%.%d+)") or "0.00"
                        updateOrAddMember({
                            nick = nick,
                            id = pid,
                            rank = tonumber(rank) or 1,
                            rating = rating,
                            online = true,
                            last_seen = "В сети"
                        })
                        local hex = getPlayerClistHex(pid)
                        if hex then
                            local pat = "(" .. nick .. "%s*%[" .. pid .. "%])"
                            local rep = "{" .. hex .. "}%1{FFFFFF}"
                            lines[i] = lines[i]:gsub(pat, rep, 1)
                            modified = true
                        end
                    end
                end
            end

            if is_script_updating then
                if next_page_item_index then
                    lua_thread.create(function()
                        wait(100)
                        sampSendDialogResponse(dialogId, 1, next_page_item_index, "")
                    end)
                else
                    lua_thread.create(function()
                        wait(100)
                        sampCloseCurrentDialogWithButton(0)
                        wait(2000)
                        sampSendChat("/offfmembers")
                    end)
                    is_script_updating = false
                end
                return true
            end

            if modified then
                return { dialogId, style, title, button1, button2, table.concat(lines, "\n") }
            end
        end
    end
end

function sampev.onServerMessage(color, text)
    local clean = text:gsub("{%x+}", "")

    local off_check_nick = clean:match("Производится проверка находится ли%s+([%w_]+)%s+в вашей семье")
    if off_check_nick then
        last_off_target_nick = off_check_nick
        return
    end

    local off_set_rank = clean:match("Указанный игрок повышен/понижен до ранга%s+(%d+)")
    if off_set_rank and last_off_target_nick then
        local new_r = tonumber(off_set_rank)
        for i, m in ipairs(membersList) do
            if m.nick == last_off_target_nick then
                local old_r = m.rank or 1
                if is_menu_action then
                    local p_str = getFormattedPlayerStr(last_off_target_nick, nil)
                    if new_r > old_r then
                        sampAddChatMessage(string.format("[FMB Menu] {FFFFFF}Игрок %s был повышен с {808080}%d{FFFFFF} на {808080}%d{FFFFFF} ранг (офлайн)", p_str, old_r, new_r), 0x808080)
                    elseif new_r < old_r then
                        sampAddChatMessage(string.format("[FMB Menu] {FFFFFF}Игрок %s был понижен с {808080}%d{FFFFFF} на {808080}%d{FFFFFF} ранг (офлайн)", p_str, old_r, new_r), 0x808080)
                    else
                        sampAddChatMessage(string.format("[FMB Menu] {FFFFFF}Игроку %s был установлен {808080}%d{FFFFFF} ранг (офлайн)", p_str, old_r, new_r), 0x808080)
                    end
                end
                m.rank = new_r
                need_rebuild_filter = true
                break
            end
        end
        is_menu_action = false
        last_off_target_nick = nil
        return
    end

    local nick, rank, last_seen, rating = clean:match("%[([%w_]+)%]%s*%[(%d+)%]%s*%[(%d%d:%d%d%s+%d%d%.%d%d%.%d%d%d%d)%]%s*%[([%d%.%-]+)%]")
    if nick and rank then
        updateOrAddMember({
            nick = nick,
            id = nil,
            rank = tonumber(rank),
            rating = rating or "0.00",
            online = false,
            last_seen = last_seen
        })
        return
    end

    local uninvited_nick = clean:match("Игрок%s+([%w_]+)%s+уволен из семьи") or clean:match("Вы выгнали%s+([%w_]+)%s+из семьи")
    if uninvited_nick then
        if is_menu_action then
            local p_str = getFormattedPlayerStr(uninvited_nick, nil)
            sampAddChatMessage(string.format("[FMB Menu] {FFFFFF}Игрок %s был уволен из семьи", p_str), 0x808080)
            is_menu_action = false
        end
        removeMember(uninvited_nick)
        return
    end

    local set_nick, set_id, set_rank = clean:match("Вы назначили%s+([%w_]+)%[(%d+)%]%s+.-%[(%d+)%]")
    if not set_nick then
        set_nick, set_rank = clean:match("Вы назначили%s+([%w_]+)%s+.-%[(%d+)%]")
    end
    if set_nick and set_rank then
        local new_r = tonumber(set_rank)
        for i, m in ipairs(membersList) do
            if m.nick == set_nick then
                local old_r = m.rank or 1
                if is_menu_action then
                    local p_str = getFormattedPlayerStr(set_nick, set_id)
                    if new_r > old_r then
                        sampAddChatMessage(string.format("[FMB Menu] {FFFFFF}Игрок %s был повышен с {808080}%d{FFFFFF} на {808080}%d{FFFFFF} ранг", p_str, old_r, new_r), 0x808080)
                    elseif new_r < old_r then
                        sampAddChatMessage(string.format("[FMB Menu] {FFFFFF}Игрок %s был понижен с {808080}%d{FFFFFF} на {808080}%d{FFFFFF} ранг", p_str, old_r, new_r), 0x808080)
                    else
                        sampAddChatMessage(string.format("[FMB Menu] {FFFFFF}Игроку %s был установлен {808080}%d{FFFFFF} ранг", p_str, old_r, new_r), 0x808080)
                    end
                end
                m.rank = new_r
                need_rebuild_filter = true
                break
            end
        end
        is_menu_action = false
        return
    end
end

function main()
    while not isSampAvailable() do wait(100) end

    sampRegisterChatCommand("fmbmenu", function()
        menu_window_state.v = not menu_window_state.v
    end)

    while true do
        wait(0)
        if pendingClose then
            if show_rank_dialog.v then
                show_rank_dialog.v = false
            else
                menu_window_state.v = false
            end
            pendingClose = false
        end
        imgui.Process = menu_window_state.v
    end
end

function imgui.OnDrawFrame()
    if not theme_applied then
        apply_dark_theme()
        theme_applied = true
    end

    if menu_window_state.v then
        if search_query.v ~= last_search_text then
            last_search_text = search_query.v
            need_rebuild_filter = true
        end

        if need_rebuild_filter then
            rebuildFilteredList()
            need_rebuild_filter = false
        end

        imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
        imgui.SetNextWindowSize(imgui.ImVec2(S(850), S(520)), imgui.Cond.Always)

        imgui.Begin(u8"Evolve Состав Семьи", menu_window_state, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize)

        imgui.AlignTextToFramePadding()
        imgui.Text(u8"Поиск:")
        imgui.SameLine()
        imgui.PushItemWidth(S(200))
        imgui.InputText("##search", search_query)
        imgui.PopItemWidth()

        if #membersList > 0 then
            imgui.SameLine()
            if imgui.Button(u8"Все", imgui.ImVec2(S(60), S(24))) then 
                filter_type = 1 
                need_rebuild_filter = true
            end
            imgui.SameLine()
            if imgui.Button(u8"Онлайн", imgui.ImVec2(S(70), S(24))) then 
                filter_type = 2 
                need_rebuild_filter = true
            end
            imgui.SameLine()
            if imgui.Button(u8"Офлайн", imgui.ImVec2(S(70), S(24))) then 
                filter_type = 3 
                need_rebuild_filter = true
            end
        end

        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()

        local total_c = #membersList
        local on_c = 0
        local off_c = 0
        for _, m in ipairs(membersList) do
            if m.online then on_c = on_c + 1 else off_c = off_c + 1 end
        end

        imgui.Text(u8(string.format("Всего игроков: %d | В сети: %d | В офлайне: %d", total_c, on_c, off_c)))
        imgui.Spacing()

        imgui.BeginChild("##members_table", imgui.ImVec2(0, S(360)), true)
        imgui.Columns(6, "members_cols", true)
        imgui.SetColumnWidth(0, S(40))
        imgui.SetColumnWidth(1, S(220))
        imgui.SetColumnWidth(2, S(60))
        imgui.SetColumnWidth(3, S(90))
        imgui.SetColumnWidth(4, S(160))

        imgui.TextDisabled(u8"№")
        imgui.NextColumn()
        imgui.TextDisabled(u8"Игрок [ID]")
        imgui.NextColumn()
        imgui.TextDisabled(u8"Ранг")
        imgui.NextColumn()
        imgui.TextDisabled(u8"Рейтинг")
        imgui.NextColumn()
        imgui.TextDisabled(u8"Заходил")
        imgui.NextColumn()
        imgui.TextDisabled(u8"Действия")
        imgui.NextColumn()
        imgui.Separator()

        local myId = getMyId()
        local myNick = myId and sampGetPlayerNickname(myId) or nil

        for i, member in ipairs(filteredList) do
            imgui.Text(tostring(i))
            imgui.NextColumn()

            local display_name = member.nick
            if member.online and member.id then
                display_name = string.format("%s [%s]", member.nick, member.id)
            end
            if member.online then
                local player_color = getPlayerClistImVec4(member.id)
                if player_color then
                    imgui.TextColored(player_color, u8(display_name))
                else
                    imgui.Text(u8(display_name))
                end
            else
                imgui.Text(u8(display_name))
            end
            imgui.NextColumn()

            imgui.Text(tostring(member.rank or 1))
            imgui.NextColumn()

            imgui.Text(tostring(member.rating or "0.00"))
            imgui.NextColumn()

            local time_color = getTimeColor(member.last_seen)
            if time_color then
                imgui.TextColored(time_color, u8(member.last_seen or "—"))
            else
                imgui.Text(u8(member.last_seen or "—"))
            end
            imgui.NextColumn()

            local isMe = (myId ~= nil and member.id ~= nil and tonumber(member.id) == myId)
                      or (myNick ~= nil and member.nick == myNick)
            local isRank7 = (member.rank == 7)

            if not isMe and not isRank7 then
                local btn_id = u8(string.format("Управлять##%s_%d", member.nick, i))
                if imgui.Button(btn_id, imgui.ImVec2(S(90), S(22))) then
                    if actionAllowed() then
                        dialog_target_nick = member.nick
                        dialog_target_id = member.id
                        dialog_target_online = member.online
                        dialog_target_rank = member.rank or 1
                        show_rank_dialog.v = true
                    end
                end
            end

            imgui.NextColumn()
            imgui.Separator()
        end

        imgui.Columns(1)
        imgui.EndChild()

        imgui.Spacing()
        
        local btn_update_w = S(160)
        imgui.SetCursorPosX((imgui.GetWindowSize().x - btn_update_w) / 2)
        if imgui.Button(u8"Обновить список", imgui.ImVec2(btn_update_w, S(26))) then
            membersList = {}
            filteredList = {}
            need_rebuild_filter = true
            is_script_updating = true
            sampSendChat("/fmembers")
        end

        imgui.End()
    end

    if show_rank_dialog.v then
        imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
        imgui.SetNextWindowSize(imgui.ImVec2(S(280), S(210)), imgui.Cond.Always)
        imgui.Begin(u8"Управление игроком", show_rank_dialog, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize)

        local title_info = string.format("%s (%s)", dialog_target_nick, dialog_target_online and ("ID: " .. tostring(dialog_target_id)) or "OFFLINE")
        imgui.TextColored(imgui.ImVec4(0.35, 0.65, 1.00, 1.00), u8(title_info))
        imgui.Separator()
        imgui.Spacing()

        imgui.Text(u8"Изменить ранг (1-6):")
        for r = 1, 6 do
            if r > 1 then imgui.SameLine() end
            local r_btn = u8(string.format("%d##r_%d", r, r))
            if r == dialog_target_rank then
                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.20, 0.60, 0.20, 1.00))
                imgui.Button(r_btn, imgui.ImVec2(S(38), S(24)))
                imgui.PopStyleColor()
            else
                if imgui.Button(r_btn, imgui.ImVec2(S(38), S(24))) then
                    if actionAllowed() then
                        is_menu_action = true
                        if dialog_target_online and dialog_target_id then
                            sampSendChat(string.format("/fgiverank %s %d", tostring(dialog_target_id), r))
                        else
                            sampSendChat(string.format("/offfgiverank %s %d", dialog_target_nick, r))
                        end
                        show_rank_dialog.v = false
                    end
                end
            end
        end

        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()

        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.85, 0.20, 0.20, 1.00))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.65, 0.15, 0.15, 1.00))

        local uninvite_btn_w = S(140)
        imgui.SetCursorPosX((imgui.GetWindowSize().x - uninvite_btn_w) / 2)
        if imgui.Button(u8"Уволить", imgui.ImVec2(uninvite_btn_w, S(26))) then
            if actionAllowed() then
                is_menu_action = true
                if dialog_target_online and dialog_target_id then
                    sampSendChat(string.format("/funinvite %s Уволен", tostring(dialog_target_id)))
                else
                    sampSendChat(string.format("/offfuninvite %s", dialog_target_nick))
                end
                show_rank_dialog.v = false
            end
        end

        imgui.PopStyleColor(2)

        imgui.Spacing()
        local close_btn_w = S(340)
        imgui.SetCursorPosX((imgui.GetWindowSize().x - close_btn_w) / 2)
        if imgui.Button(u8"Закрыть", imgui.ImVec2(close_btn_w, S(24))) then
            show_rank_dialog.v = false
        end

        imgui.End()
    end
end