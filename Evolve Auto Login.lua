script_author("Impressive")
script_name('Evolve Auto Login')
local imgui = require ('mimgui')
local encoding = require ('encoding')
local sampev = require('lib.samp.events')
local inicfg = require ('inicfg')
local ffi = require('ffi')
local vkeys = require ('vkeys')
local bit = require('bit')

local PASS_OFFSET = 155   
local GAUTH_OFFSET = 105  

local sha1 = require "sha1"
local basexx = require "basexx"
local band = bit.band

encoding.default = 'CP1251'
u8 = encoding.UTF8

local base_ranges = imgui.new.ImWchar[5](0x0020, 0x00FF, 0x0400, 0x052F, 0)

local configDir = getWorkingDirectory() .. '\\config\\AutoLogin\\'
if not doesDirectoryExist(configDir) then createDirectory(configDir) end

local settings = {}
local currentNick = "None"
local is_loaded = false

local renderWindow = imgui.new.bool()
local show_pass = imgui.new.bool(false)
local show_gkey = imgui.new.bool(false)

local pass_edit = imgui.new.char[128]("")
local gauth_edit = imgui.new.char[128]("")
local auto_pass = imgui.new.bool(false)
local auto_gauth = imgui.new.bool(false)
local auto_login = imgui.new.bool(false)
local spawn_idx = imgui.new.int(0)

local global_suggest = imgui.new.bool(true)

local force_reposition = false

local active_dialog = { id = -1, is_pass = false, is_gauth = false }
local custom_dialog = { is_pass = false, is_gauth = false }
local last_overlay_click = 0

local lastActivePass, wasActivePass = nil, false
local lastActiveGauth, wasActiveGauth = nil, false
local pendingClose = false

local WM_KEYFIRST, WM_KEYLAST = 0x0100, 0x0109
local WM_MOUSEFIRST, WM_MOUSELAST = 0x0200, 0x020E

local spawn_names = {u8'Не выбирать', u8'Точка выхода', u8'Личный дом', u8'Семейный дом', u8'Стандартный спавн', u8'Дом на колёсах', u8'Яхта'}
local spawn_items = imgui.new["const char*"][#spawn_names](spawn_names)
local nameToModel = { [1]=11711, [2]=3634, [3]=3603, [4]=1257, [5]=508, [6]=454 }

local function sendCustomPassword(pass)
    local out_bs = raknetNewBitStream()
    raknetBitStreamWriteInt8(out_bs, 251)
    raknetBitStreamWriteInt32(out_bs, 16)
    raknetBitStreamWriteInt8(out_bs, 0)
    raknetBitStreamWriteInt8(out_bs, #pass)
    raknetBitStreamWriteString(out_bs, pass)
    raknetSendBitStream(out_bs)
    raknetDeleteBitStream(out_bs)
end

local function sendCustomGAuth(code)
    local out_bs = raknetNewBitStream()
    raknetBitStreamWriteInt8(out_bs, 251)
    raknetBitStreamWriteInt32(out_bs, 16)
    raknetBitStreamWriteInt8(out_bs, 5)
    raknetBitStreamWriteInt8(out_bs, #code)
    raknetBitStreamWriteString(out_bs, code)
    raknetSendBitStream(out_bs)
    raknetDeleteBitStream(out_bs)
end

local function DrawIconButton(str_id, icon_type, size, extra_state)
    local is_eye_hidden = (icon_type == "eye" and extra_state)
    
    if is_eye_hidden then
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.20, 0.22, 0.27, 1.00))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.26, 0.29, 0.35, 1.00))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.15, 0.16, 0.20, 1.00))
    end

    local cursor_pos = imgui.GetCursorScreenPos()
    local clicked = imgui.Button(str_id, size)
    
    if is_eye_hidden then
        imgui.PopStyleColor(3)
    end

    local draw_list = imgui.GetWindowDrawList()
    local cx = cursor_pos.x + size.x / 2
    local cy = cursor_pos.y + size.y / 2
    
    local color
    if is_eye_hidden then
        color = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.55, 0.58, 0.63, 1.00))
    else
        color = imgui.GetColorU32(imgui.Col.Text)
    end
    
    if icon_type == "eye" then
        draw_list:AddLine(imgui.ImVec2(cx - 9, cy), imgui.ImVec2(cx, cy - 5), color, 1.5)
        draw_list:AddLine(imgui.ImVec2(cx, cy - 5), imgui.ImVec2(cx + 9, cy), color, 1.5)
        draw_list:AddLine(imgui.ImVec2(cx + 9, cy), imgui.ImVec2(cx, cy + 5), color, 1.5)
        draw_list:AddLine(imgui.ImVec2(cx, cy + 5), imgui.ImVec2(cx - 9, cy), color, 1.5)
        draw_list:AddCircleFilled(imgui.ImVec2(cx, cy), 2.2, color)
        
        if extra_state then
            draw_list:AddLine(imgui.ImVec2(cx - 10, cy - 6), imgui.ImVec2(cx + 10, cy + 6), color, 1.6)
        end
        
    elseif icon_type == "gear" then
        local count = 8
        for i = 0, count - 1 do
            local angle = i * (math.pi * 2 / count)
            local x1 = cx + math.cos(angle) * 3.5
            local y1 = cy + math.sin(angle) * 3.5
            local x2 = cx + math.cos(angle) * 6.5
            local y2 = cy + math.sin(angle) * 6.5
            draw_list:AddLine(imgui.ImVec2(x1, y1), imgui.ImVec2(x2, y2), color, 3.0)
        end
        draw_list:AddCircle(imgui.ImVec2(cx, cy), 4.5, color, 16, 2.0)
    end
    
    return clicked
end

local function DrawSaveButton(str_id, label, size)
    local cursor_pos = imgui.GetCursorScreenPos()
    
    local btn_width = size.x
    if btn_width < 0 then
        btn_width = imgui.GetContentRegionAvail().x
    end
    
    local clicked = imgui.Button(str_id, imgui.ImVec2(btn_width, size.y))
    local draw_list = imgui.GetWindowDrawList()
    local color = imgui.GetColorU32(imgui.Col.Text)
    
    local text_size = imgui.CalcTextSize(label)
    local total_width = 18 + 10 + text_size.x 
    local start_x = cursor_pos.x + (btn_width - total_width) / 2
    local cy = cursor_pos.y + size.y / 2
    
    local cx = start_x + 9
    local r = 7.5
    
    draw_list:PathLineTo(imgui.ImVec2(cx - r, cy - r))
    draw_list:PathLineTo(imgui.ImVec2(cx + r - 3, cy - r)) 
    draw_list:PathLineTo(imgui.ImVec2(cx + r, cy - r + 3)) 
    draw_list:PathLineTo(imgui.ImVec2(cx + r, cy + r))
    draw_list:PathLineTo(imgui.ImVec2(cx - r, cy + r))
    draw_list:PathStroke(color, true, 1.8)
    
    draw_list:AddRectFilled(imgui.ImVec2(cx - 3, cy - r + 1), imgui.ImVec2(cx + 1, cy - r + 4), color)
    draw_list:AddRect(imgui.ImVec2(cx - 4, cy + 1), imgui.ImVec2(cx + 4, cy + r - 1), color, 0.0, 0, 1.2)
    
    draw_list:AddText(imgui.ImVec2(start_x + 28, cy - text_size.y / 2), color, label)
    
    return clicked
end

local function DrawDeleteButton(str_id, label, size)
    local cursor_pos = imgui.GetCursorScreenPos()
    
    local btn_width = size.x
    if btn_width < 0 then
        btn_width = imgui.GetContentRegionAvail().x
    end
    
    imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.20, 0.22, 0.27, 1.00))
    imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.26, 0.29, 0.35, 1.00))
    imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.15, 0.16, 0.20, 1.00))
    
    local clicked = imgui.Button(str_id, imgui.ImVec2(btn_width, size.y))
    
    imgui.PopStyleColor(3)

    local draw_list = imgui.GetWindowDrawList()
    local color = imgui.GetColorU32(imgui.Col.Text)
    
    local text_size = imgui.CalcTextSize(label)
    local total_width = 14 + 10 + text_size.x 
    local start_x = cursor_pos.x + (btn_width - total_width) / 2
    local cy = cursor_pos.y + size.y / 2
    
    local cx = start_x + 7
    
    draw_list:AddLine(imgui.ImVec2(cx - 6, cy - 4), imgui.ImVec2(cx + 6, cy - 4), color, 1.5)
    draw_list:AddRect(imgui.ImVec2(cx - 2, cy - 6), imgui.ImVec2(cx + 2, cy - 4), color, 0.0, 0, 1.5)
    
    draw_list:PathLineTo(imgui.ImVec2(cx - 4, cy - 3))
    draw_list:PathLineTo(imgui.ImVec2(cx - 3, cy + 6))
    draw_list:PathLineTo(imgui.ImVec2(cx + 3, cy + 6))
    draw_list:PathLineTo(imgui.ImVec2(cx + 4, cy - 3))
    draw_list:PathStroke(color, true, 1.5)
    
    draw_list:AddLine(imgui.ImVec2(cx - 1.2, cy - 1), imgui.ImVec2(cx - 1.2, cy + 4), color, 1.2)
    draw_list:AddLine(imgui.ImVec2(cx + 1.2, cy - 1), imgui.ImVec2(cx + 1.2, cy + 4), color, 1.2)
    
    draw_list:AddText(imgui.ImVec2(start_x + 24, cy - text_size.y / 2), color, label)
    
    return clicked
end

function genGoogleCode(secret)
    if not secret or #secret < 8 then return nil end
    local cleanSecret = secret:gsub("%s+", ""):upper()
    local status, key = pcall(basexx.from_base32, cleanSecret)
    if not status then return nil end
    local time = math.floor(os.time() / 30)
    local msg = string.char(0,0,0,0, band(time, 0xFF000000)/0x1000000, band(time, 0xFF0000)/0x10000, band(time, 0xFF00)/0x100, band(time, 0xFF))
    local hash = sha1.hmac_binary(key, msg)
    local offset = band(hash:byte(20), 0x0F)
    local function bytesToInt(a,b,c,d) return a*0x1000000 + b*0x10000 + c*0x100 + d end
    local bin = bytesToInt(hash:byte(offset+1), hash:byte(offset+2), hash:byte(offset+3), hash:byte(offset+4))
    return string.format("%06d", band(bin, 0x7FFFFFFF) % 1000000)
end

function str_to_imgui(str, imgui_var)
    local s = u8(tostring(str))
    ffi.copy(imgui_var, s, #s + 1)
end

function loadGlobalConfig()
    local globalPath = "AutoLogin\\global.ini"
    local g_default = { main = { suggest = true } }
    local g_cfg = inicfg.load(g_default, globalPath)
    global_suggest[0] = g_cfg.main.suggest ~= false
end

function saveGlobalConfig()
    local data = { main = { suggest = global_suggest[0] } }
    inicfg.save(data, "AutoLogin\\global.ini")
end

function loadAccConfig()
    local activeNick = isSampAvailable() and sampGetPlayerNickname(select(2, sampGetPlayerIdByCharHandle(PLAYER_PED))) or "None"
    if activeNick == "" or activeNick == "None" then return end

    activeNick = activeNick:gsub("%(%d+%)", ""):match("^%s*(.-)%s*$")

    currentNick = activeNick
    
    local fullPath = configDir .. currentNick .. ".ini"
    
    if doesFileExist(fullPath) then
        local default = { settings = { password = "", gauth = "", ap = true, ag = true, autologin = false, spawn = 0 } }
        settings = inicfg.load(default, "AutoLogin\\" .. currentNick .. ".ini")
        
        auto_pass[0] = settings.settings.ap ~= false
        auto_gauth[0] = settings.settings.ag ~= false
        auto_login[0] = settings.settings.autologin or false
        spawn_idx[0] = settings.settings.spawn or 0
        
        local saved_pass = settings.settings.password or ""
        str_to_imgui(saved_pass, pass_edit)
        str_to_imgui(settings.settings.gauth or "", gauth_edit)
        is_loaded = true
    else
        auto_pass[0] = true 
        auto_gauth[0] = true
        auto_login[0] = false
        spawn_idx[0] = 0
        str_to_imgui("", pass_edit)
        str_to_imgui("", gauth_edit)
        is_loaded = false
    end
end

function saveAccConfig(silent)
    if currentNick == "None" then return end
    
    local raw_pass = ffi.string(pass_edit)
    local encoded_pass = u8:decode(raw_pass)
    
    local data_to_save = { settings = { password = encoded_pass, gauth = ffi.string(gauth_edit), ap = auto_pass[0], ag = auto_gauth[0], autologin = auto_login[0], spawn = spawn_idx[0] } }
    inicfg.save(data_to_save, "AutoLogin\\" .. currentNick .. ".ini")
    saveGlobalConfig()
    is_loaded = true
    if not silent then 
        sampAddChatMessage("{FF2D55}[AutoLogin]{FFFFFF} Настройки аккаунта {FF2D55}" .. currentNick .. "{FFFFFF} сохранены.", -1) 
    end
end

function deleteAccConfig()
    if currentNick == "None" then return end
    local fullPath = configDir .. currentNick .. ".ini"
    if doesFileExist(fullPath) then
        os.remove(fullPath)
        sampAddChatMessage("{FF2D55}[AutoLogin]{FFFFFF} Настройки аккаунта {FF2D55}" .. currentNick .. "{FFFFFF} успешно удалены.", -1)
    end
    auto_pass[0] = true
    auto_gauth[0] = true
    auto_login[0] = false
    spawn_idx[0] = 0
    str_to_imgui("", pass_edit)
    str_to_imgui("", gauth_edit)
    is_loaded = false
end

function onReceivePacket(id, bs)
    if id == 251 then
        loadAccConfig()
        raknetBitStreamIgnoreBits(bs, 8)
        local sys_type = raknetBitStreamReadInt32(bs)

        if sys_type == 16 then
            local action = raknetBitStreamReadInt8(bs)

            if action == 1 then
                custom_dialog.is_pass = true
                custom_dialog.is_gauth = false

                if auto_login[0] then
                    local p = ffi.string(pass_edit)
                    if #p > 0 then
                        local pass = u8:decode(p)
                        lua_thread.create(function()
                            wait(100)
                            sendCustomPassword(pass)
                            custom_dialog.is_pass = false
                        end)
                    end
                end

            elseif action == 11 then
                custom_dialog.is_pass = false
                custom_dialog.is_gauth = true

                if auto_login[0] then
                    local gkey = ffi.string(gauth_edit)
                    if #gkey > 0 then
                        local code = genGoogleCode(gkey)
                        if code then
                            lua_thread.create(function()
                                wait(100)
                                sendCustomGAuth(code)
                                custom_dialog.is_gauth = false
                            end)
                            return false
                        end
                    end
                end

            elseif action == 12 then
                custom_dialog.is_pass = false
                custom_dialog.is_gauth = false

                if auto_login[0] and spawn_idx[0] > 0 then
                    local spawn_mask = raknetBitStreamReadInt8(bs)
                    local selected_spawn = 1

                    if bit.band(spawn_mask, 8) > 0 and spawn_idx[0] == 5 then
                        selected_spawn = 5
                    elseif bit.band(spawn_mask, 16) > 0 and spawn_idx[0] == 3 then
                        selected_spawn = 4
                    elseif bit.band(spawn_mask, 32) > 0 and spawn_idx[0] == 4 then
                        selected_spawn = 3
                    elseif bit.band(spawn_mask, 64) > 0 and spawn_idx[0] == 2 then
                        selected_spawn = 2
                    elseif bit.band(spawn_mask, 128) > 0 and spawn_idx[0] == 1 then
                        selected_spawn = 0
                    end

                    local out_bs = raknetNewBitStream()
                    raknetBitStreamWriteInt8(out_bs, 251)
                    raknetBitStreamWriteInt32(out_bs, 9)
                    raknetBitStreamWriteInt32(out_bs, selected_spawn)
                    raknetSendBitStream(out_bs)
                    raknetDeleteBitStream(out_bs)
                    return false
                end
            else
                custom_dialog.is_pass = false
                custom_dialog.is_gauth = false
            end
        end
    end
end

imgui.OnInitialize(function()
    local style = imgui.GetStyle()
    style.WindowRounding = 12
    style.FrameRounding = 6
    style.ItemSpacing = imgui.ImVec2(10, 8)
    style.WindowPadding = imgui.ImVec2(15, 15)
    style.WindowTitleAlign = imgui.ImVec2(0.5, 0.5)
    
    local colors = style.Colors
    local pink = imgui.ImVec4(1.00, 0.18, 0.33, 1.00)
    colors[imgui.Col.WindowBg] = imgui.ImVec4(0.11, 0.12, 0.15, 1.00)
    colors[imgui.Col.TitleBgActive] = imgui.ImVec4(0.14, 0.15, 0.19, 1.00)
    colors[imgui.Col.FrameBg] = imgui.ImVec4(0.16, 0.18, 0.23, 1.00)
    colors[imgui.Col.Button] = pink
    colors[imgui.Col.ButtonHovered] = imgui.ImVec4(1.00, 0.25, 0.40, 1.00)
    colors[imgui.Col.ButtonActive] = imgui.ImVec4(0.80, 0.10, 0.25, 1.00)
    colors[imgui.Col.CheckMark] = pink
    colors[imgui.Col.Text] = imgui.ImVec4(0.95, 0.95, 0.95, 1.00)
    colors[imgui.Col.Separator] = imgui.ImVec4(0.20, 0.22, 0.28, 1.00)

    local io = imgui.GetIO()
    local fontConfig = imgui.ImFontConfig()
    fontConfig.GlyphRanges = base_ranges
    
    local baseFont = "C:\\Windows\\Fonts\\trebuc.ttf"
    if not doesFileExist(baseFont) then baseFont = "C:\\Windows\\Fonts\\arial.ttf" end
    if doesFileExist(baseFont) then
        io.Fonts:AddFontFromFileTTF(baseFont, 14.0, fontConfig)
    else
        io.Fonts:AddFontDefault()
    end
end)

imgui.OnFrame(function() return renderWindow[0] end, function()
    local sw, sh = getScreenResolution()
    
    if force_reposition then
        imgui.SetNextWindowPos(imgui.ImVec2(sw / 2 - 410, sh / 2), imgui.Cond.Always, imgui.ImVec2(0.5, 0.5))
        force_reposition = false
    else
        imgui.SetNextWindowPos(imgui.ImVec2(sw / 2 - 410, sh / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    end
    
    imgui.SetNextWindowSize(imgui.ImVec2(390, auto_login[0] and 460 or 410), imgui.Cond.Always)
    
    if imgui.Begin("Evolve AutoLogin | " .. currentNick, renderWindow, imgui.WindowFlags.NoResize + imgui.WindowFlags.NoScrollbar) then
        
        imgui.Text(u8"Пароль")
        local p_flag = not show_pass[0] and imgui.InputTextFlags.Password or 0
        imgui.PushItemWidth(272) 
        imgui.InputText("##pass", pass_edit, 128, p_flag)
        if imgui.IsItemActive() then
            lastActivePass = ffi.string(pass_edit)
            wasActivePass = true
        elseif wasActivePass then
            if lastActivePass then ffi.copy(pass_edit, lastActivePass) end
            wasActivePass = false
        end
        imgui.PopItemWidth()
        imgui.SameLine()
        
        if DrawIconButton("##eye_p", "eye", imgui.ImVec2(35, 24), not show_pass[0]) then 
            show_pass[0] = not show_pass[0] 
        end
        imgui.SameLine()
        
        imgui.Checkbox("##ap", auto_pass)
        if imgui.IsItemHovered() then
            imgui.BeginTooltip()
            imgui.Text(u8"Показывать кнопку Autologin в окне ввода пароля")
            imgui.EndTooltip()
        end

        imgui.Text(u8"G-Auth Key")
        local g_flag = not show_gkey[0] and imgui.InputTextFlags.Password or 0
        imgui.PushItemWidth(272)
        imgui.InputText("##gkey", gauth_edit, 128, g_flag)
        if imgui.IsItemActive() then
            lastActiveGauth = ffi.string(gauth_edit)
            wasActiveGauth = true
        elseif wasActiveGauth then
            if lastActiveGauth then ffi.copy(gauth_edit, lastActiveGauth) end
            wasActiveGauth = false
        end
        imgui.PopItemWidth()
        imgui.SameLine()
        
        if DrawIconButton("##eye_g", "eye", imgui.ImVec2(35, 24), not show_gkey[0]) then 
            show_gkey[0] = not show_gkey[0] 
        end
        imgui.SameLine()
        
        imgui.Checkbox("##ag", auto_gauth)
        if imgui.IsItemHovered() then
            imgui.BeginTooltip()
            imgui.Text(u8"Показывать кнопку Autologin в окне ввода Google Auth")
            imgui.EndTooltip()
        end

        imgui.Separator()

        imgui.Checkbox(u8"Автоматически вводить пароль и G-Auth", auto_login)

        if auto_login[0] then
            imgui.Text(u8"Спавн при заходе в игру")
            imgui.PushItemWidth(-1)
            imgui.Combo("##spawn", spawn_idx, spawn_items, #spawn_names)
            imgui.PopItemWidth()
        end

        imgui.Separator()
        
        imgui.Checkbox(u8"Предлагать добавление новых аккаунтов", global_suggest)

        imgui.Spacing()
        
        if DrawSaveButton("##save_cfg", u8"Сохранить настройки", imgui.ImVec2(-1, 32)) then saveAccConfig(false) end
        
        imgui.Spacing()
        
        if DrawDeleteButton("##delete_cfg", u8"Удалить аккаунт", imgui.ImVec2(-1, 32)) then 
            deleteAccConfig() 
        end
        
        imgui.Spacing()
        
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.20, 0.22, 0.27, 1.00))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.26, 0.29, 0.35, 1.00))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.15, 0.16, 0.20, 1.00))
        if imgui.Button(u8"Открыть папку с аккаунтами", imgui.ImVec2(-1, 32)) then
            os.execute('explorer "' .. configDir .. '"')
        end
        imgui.PopStyleColor(3)

        imgui.End()
    end

    if pendingClose then
        if wasActivePass and lastActivePass then
            ffi.copy(pass_edit, lastActivePass)
            wasActivePass = false
        end
        if wasActiveGauth and lastActiveGauth then
            ffi.copy(gauth_edit, lastActiveGauth)
            wasActiveGauth = false
        end
        renderWindow[0] = false
        pendingClose = false
    end
end)

imgui.OnFrame(
    function() 
        if sampIsDialogActive() then
            local caption = sampGetDialogCaption()
            local text = sampGetDialogText()
            if caption and text then
                local clean_title = caption:gsub("{.-}", "")
                local clean_text = text:gsub("{.-}", "")

                active_dialog.is_pass = (clean_title:find("Ввод пароля", 1, true) ~= nil) 
                                   and (clean_text:find("Введите пароль:", 1, true) ~= nil)

                active_dialog.is_gauth = (clean_title:find("Подтверждение", 1, true) ~= nil) 
                                    and (clean_text:find("Google Authenticator", 1, true) ~= nil)

                if active_dialog.is_pass or active_dialog.is_gauth then
                    local has_pass = ffi.string(pass_edit) ~= ""
                    local has_gauth = ffi.string(gauth_edit) ~= ""
                    if active_dialog.is_pass then
                        return is_loaded and auto_pass[0] and has_pass or global_suggest[0]
                    elseif active_dialog.is_gauth then
                        return is_loaded and auto_gauth[0] and has_gauth or global_suggest[0]
                    end
                end
            end
        end

        if custom_dialog.is_pass or custom_dialog.is_gauth then
            local has_pass = ffi.string(pass_edit) ~= ""
            local has_gauth = ffi.string(gauth_edit) ~= ""
            if custom_dialog.is_pass then
                return (is_loaded and auto_pass[0] and has_pass) or global_suggest[0]
            elseif custom_dialog.is_gauth then
                return (is_loaded and auto_gauth[0] and has_gauth) or global_suggest[0]
            end
        end

        return false
    end,
    function()
        local sw, sh = getScreenResolution()

        if sampIsDialogActive() and (active_dialog.is_pass or active_dialog.is_gauth) then
            local calculated_offset = active_dialog.is_pass and PASS_OFFSET or GAUTH_OFFSET
            imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2 + calculated_offset), imgui.Cond.Always, imgui.ImVec2(0.5, 0.0))
        elseif custom_dialog.is_pass or custom_dialog.is_gauth then
            imgui.SetNextWindowPos(imgui.ImVec2(sw * 0.24, sh * 0.535), imgui.Cond.Always, imgui.ImVec2(0.0, 0.5))
        end

        imgui.SetNextWindowSize(imgui.ImVec2(240, 0), imgui.Cond.Always)

        imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.11, 0.12, 0.15, 0.95))
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 8.0)

        if imgui.Begin("##HelperOverlayWindow", nil, imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize + imgui.WindowFlags.AlwaysAutoResize + imgui.WindowFlags.NoMove) then
            local is_pass = active_dialog.is_pass or custom_dialog.is_pass
            local is_gauth = active_dialog.is_gauth or custom_dialog.is_gauth
            local is_custom = custom_dialog.is_pass or custom_dialog.is_gauth

            if is_pass then
                local has_pass = ffi.string(pass_edit) ~= ""
                if is_loaded and auto_pass[0] and has_pass then
                    if imgui.Button(u8"Enter Password", imgui.ImVec2(-50, 38)) then
                        if os.clock() - last_overlay_click > 0.4 then
                            last_overlay_click = os.clock()
                            active_dialog.is_pass = false
                            custom_dialog.is_pass = false
                            local p = ffi.string(pass_edit)
                            if #p > 0 then
                                local cp_pass = u8:decode(p)
                                if is_custom then
                                    sendCustomPassword(cp_pass)
                                else
                                    sampSetCurrentDialogEditboxText(cp_pass)
                                    sampCloseCurrentDialogWithButton(1)
                                end
                            end
                        end
                    end
                    imgui.SameLine()
                    if DrawIconButton("##cfg_p", "gear", imgui.ImVec2(38, 38)) then
                        loadAccConfig()
                        loadGlobalConfig()
                        renderWindow[0] = not renderWindow[0]
                        if renderWindow[0] then force_reposition = true end
                    end
                else
                    if imgui.Button(u8"Add Account", imgui.ImVec2(-1, 38)) then
                        renderWindow[0] = true
                        force_reposition = true
                    end
                end

            elseif is_gauth then
                local has_gauth = ffi.string(gauth_edit) ~= ""
                if is_loaded and auto_gauth[0] and has_gauth then
                    if imgui.Button(u8"Enter G-Auth", imgui.ImVec2(-50, 38)) then
                        if os.clock() - last_overlay_click > 0.4 then
                            last_overlay_click = os.clock()
                            active_dialog.is_gauth = false
                            custom_dialog.is_gauth = false
                            local code = genGoogleCode(ffi.string(gauth_edit))
                            if code then
                                if is_custom then
                                    sendCustomGAuth(code)
                                else
                                    sampSetCurrentDialogEditboxText(code)
                                    sampCloseCurrentDialogWithButton(1)
                                end
                            end
                        end
                    end
                    imgui.SameLine()
                    if DrawIconButton("##cfg_g", "gear", imgui.ImVec2(38, 38)) then
                        loadAccConfig()
                        loadGlobalConfig()
                        renderWindow[0] = not renderWindow[0]
                        if renderWindow[0] then force_reposition = true end
                    end
                else
                    if imgui.Button(u8"Add Account", imgui.ImVec2(-1, 38)) then
                        renderWindow[0] = true
                        force_reposition = true
                    end
                end
            end
            imgui.End()
        end
        imgui.PopStyleVar()
        imgui.PopStyleColor()
    end
)

function sampev.onShowDialog(id, style, title, b1, b2, text)
    loadAccConfig() 
    active_dialog.id = id
    custom_dialog.is_pass = false
    custom_dialog.is_gauth = false

    local clean_title = title:gsub("{.-}", "")
    local clean_text = text:gsub("{.-}", "")

    local is_pass_dialog = (clean_title:find("Ввод пароля", 1, true) ~= nil) 
                       and (clean_text:find("Введите пароль:", 1, true) ~= nil)
    
    local is_gauth_dialog = (clean_title:find("Подтверждение", 1, true) ~= nil) 
                        and (clean_text:find("Google Authenticator", 1, true) ~= nil)

    if is_pass_dialog then
        active_dialog.is_pass = true
        active_dialog.is_gauth = false
        if auto_login[0] then
            local p = ffi.string(pass_edit)
            if #p > 0 then
                local cp_pass = u8:decode(p)
                lua_thread.create(function()
                    wait(100)
                    sampSetCurrentDialogEditboxText(cp_pass)
                    sampCloseCurrentDialogWithButton(1)
                end)
            end
        end
    elseif is_gauth_dialog then
        active_dialog.is_pass = false
        active_dialog.is_gauth = true
        if auto_login[0] then
            local code = genGoogleCode(ffi.string(gauth_edit))
            if code then
                lua_thread.create(function()
                    wait(100)
                    sampSetCurrentDialogEditboxText(code)
                    sampCloseCurrentDialogWithButton(1)
                end)
            end
        end
    else
        active_dialog.is_pass = false
        active_dialog.is_gauth = false
    end
    
    return true
end

function sampev.onShowTextDraw(id, data)
    if is_loaded and auto_login[0] and spawn_idx[0] > 0 and nameToModel[spawn_idx[0]] and data.modelId == nameToModel[spawn_idx[0]] then
        lua_thread.create(function() wait(100) sampSendClickTextdraw(id + 1) end)
    end
end

function onWindowMessage(msg, wparam, lparam)
    if not renderWindow[0] then return end

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

function main()
    while not isSampAvailable() do wait(0) end
    loadGlobalConfig() 
    loadAccConfig()
    
    sampRegisterChatCommand('autologin', function() loadAccConfig(); loadGlobalConfig(); renderWindow[0] = not renderWindow[0] end)
    wait(-1)
end