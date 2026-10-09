script_author("Impressive")
script_name('Evolve Pay Helper')
require("moonloader")
local SE = require("samp.events")
local inicfg = require("inicfg")
local imgui = require("imgui")
local mimgui = require("mimgui")
local encoding = require("encoding")
local bit = require("bit")

encoding.default = "CP1251"
local u8 = encoding.UTF8

local directIni = "Evolve-PayHelper.ini"

local moneyColors = {
    skyblue = {0.53, 0.81, 0.98, 1.00},
    gold = {1.00, 0.84, 0.00, 1.00},
    green = {50/255, 205/255, 50/255, 1.00}, 
    silver = {0.75, 0.75, 0.75, 1.00},
    bronze = {0.80, 0.50, 0.20, 1.00}
}

local iniData = {
    main = {
        enabled = true,
        recolor_chat = true,
        recolor_dialog = true,
        enable_counter = true
    },
    vip_status = {}
}

local function toBool(val, default)
    if val == nil then return default end
    if type(val) == "boolean" then return val end
    if type(val) == "string" then 
        local s = val:lower()
        if s == "true" or s == "1" then return true end
        if s == "false" or s == "0" then return false end
    end
    if type(val) == "number" then return val ~= 0 end
    return default
end

local ini = inicfg.load(iniData, directIni)
if not ini then 
    inicfg.save(iniData, directIni) 
    ini = iniData 
else
    if not ini.main then ini.main = {} end
    ini.main.enabled = toBool(ini.main.enabled, iniData.main.enabled)
    ini.main.recolor_chat = toBool(ini.main.recolor_chat, iniData.main.recolor_chat)
    ini.main.recolor_dialog = toBool(ini.main.recolor_dialog, iniData.main.recolor_dialog)
    ini.main.enable_counter = toBool(ini.main.enable_counter, iniData.main.enable_counter)

    if not ini.vip_status then ini.vip_status = {} end
    inicfg.save(ini, directIni)
end

local main_window_state = imgui.ImBool(false)
local imgui_enabled = imgui.ImBool(ini.main.enabled)
local imgui_recolor_chat = imgui.ImBool(ini.main.recolor_chat)
local imgui_recolor_dialog = imgui.ImBool(ini.main.recolor_dialog)
local imgui_enable_counter = imgui.ImBool(ini.main.enable_counter)
local vip_checked = imgui.ImBool(false)
local last_nick = "None"

local withdraw = { summ = 0, process = false }
local deposit = { summ = 0, process = false }
local transfer = { summ = 0, nick = '', process = false, isBank = false }

local fpay_state = { running = false, id = -1, total = 0, sent = 0 }
local fpay_confirm = { id = -1, amount = 0, timestamp = 0 }
local player_limits = {}

local show_overlay = false
local is_auto_paying = false 
local current_dialog_type = 0
local last_clicked_type = 0    
local max_amount = 0          
local step_limit = 5000
local OFFSET_Y = 135

local stats = {
    received_pay = {},
    sent_pay     = {},
    received_bank = {}
}

local allowedChatPatterns = {
    "%[Выписка%]: Новый баланс: ",
    "%[Выписка%]: Зачислено: ",
    "Ваш домашний счет: ",
    "Снято со счёта: ",
    "Новый баланс: ",
    "Положили на счёт: ",
    "Переведено на счёт .-: ",
    "Остаток на руках: ",
    "Вы получили %$",
    "Вы передали .- %$",
    "перевёл Вам %$",
    "Положили на домашний счёт: ",
    "Новый баланс на домашнем счёте: ",
    "Новый баланс на счёте: ",
    "Новый баланс на руках: "
}

local function getLocalPlayerName()
    if not isSampAvailable() then return "None" end
    local result, id = sampGetPlayerIdByCharHandle(PLAYER_PED)
    if result and id and id ~= -1 then
        local name = sampGetPlayerNickname(id)
        if name and name ~= "" then return name end
    end
    return "None"
end

local function parseMoney(str)
    if not str or str == "" then return 0 end
    local cleaned = str:gsub("[%D]", "")
    return tonumber(cleaned) or 0
end

local function formatMoney(amount)
    if not amount then return "0" end
    local formatted = tostring(math.floor(amount))
    while true do  
        local newFormatted, k = string.gsub(formatted, "(%d+)(%d%d%d)", "%1.%2")
        if k == 0 then break end
        formatted = newFormatted
    end
    return formatted
end

local function getAmountColor(amount)
    local c
    amount = tonumber(amount) or 0
    if amount >= 10000000 then c = moneyColors.skyblue
    elseif amount >= 1000000 then c = moneyColors.gold
    elseif amount >= 100000 then c = moneyColors.green
    elseif amount >= 50000 then c = moneyColors.silver
    else c = moneyColors.bronze
    end
    
    local r = tonumber(c[1] or c['1']) or 1.0
    local g = tonumber(c[2] or c['2']) or 1.0
    local b = tonumber(c[3] or c['3']) or 1.0
    
    return string.format("{%02X%02X%02X}", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
end

local function getTargetId(input)
    if not input or input == "" then return nil end
    local id = tonumber(input)
    if id and id >= 0 and id <= 1000 and sampIsPlayerConnected(id) then return id end
    local name = input:lower()
    for i = 0, 1000 do
        if sampIsPlayerConnected(i) then
            local pName = sampGetPlayerNickname(i):lower()
            if pName:find(name, 1, true) then return i end
        end
    end
    return nil
end

function onWindowMessage(msg, wparam, lparam)
    if main_window_state.v and msg == 0x0100 and wparam == 0x1B then
        main_window_state.v = false
        consumeWindowMessage()
    end
end

local function ApplyCustomStyle()
    local style = imgui.GetStyle()
    style.WindowRounding = 6.0
    style.FrameRounding = 4.0
    style.ItemSpacing = imgui.ImVec2(8, 7)
    style.WindowPadding = imgui.ImVec2(12, 12)
    style.ChildWindowRounding = 5.0
    style.ScrollbarSize = 10.0
    
    style.Colors[imgui.Col.WindowBg] = imgui.ImVec4(0.07, 0.08, 0.08, 0.96)
    style.Colors[imgui.Col.TitleBg] = imgui.ImVec4(0.10, 0.12, 0.12, 1.00)
    style.Colors[imgui.Col.TitleBgActive] = imgui.ImVec4(0.12, 0.38, 0.19, 1.00)
    style.Colors[imgui.Col.CheckMark] = imgui.ImVec4(0.22, 0.82, 0.38, 1.00)
    style.Colors[imgui.Col.FrameBg] = imgui.ImVec4(0.12, 0.15, 0.14, 1.00)
    style.Colors[imgui.Col.FrameBgHovered] = imgui.ImVec4(0.16, 0.22, 0.19, 1.00)
    style.Colors[imgui.Col.FrameBgActive] = imgui.ImVec4(0.20, 0.29, 0.24, 1.00)
    style.Colors[imgui.Col.Button] = imgui.ImVec4(0.11, 0.14, 0.13, 1.00)
    style.Colors[imgui.Col.ButtonHovered] = imgui.ImVec4(0.16, 0.35, 0.22, 1.00)
    style.Colors[imgui.Col.ButtonActive] = imgui.ImVec4(0.14, 0.49, 0.25, 1.00)
    style.Colors[imgui.Col.ChildWindowBg] = imgui.ImVec4(0.09, 0.11, 0.10, 0.60)
    style.Colors[imgui.Col.Border] = imgui.ImVec4(0.16, 0.22, 0.19, 0.50)
end

mimgui.OnFrame(
    function()
        if not ini.main.enabled or not sampIsDialogActive() then 
            show_overlay = false
            return false 
        end
        return show_overlay
    end,
    function()
        local sw, sh = getScreenResolution()
        
        mimgui.SetNextWindowPos(mimgui.ImVec2(sw / 2, sh / 2 + OFFSET_Y), mimgui.Cond.Always, mimgui.ImVec2(0.5, 0.0))
        mimgui.SetNextWindowSize(mimgui.ImVec2(250, 0), mimgui.Cond.Always)
        
        mimgui.PushStyleColor(mimgui.Col.WindowBg, mimgui.ImVec4(0.11, 0.12, 0.15, 0.95))
        mimgui.PushStyleVarFloat(mimgui.StyleVar.WindowRounding, 6.0)
        mimgui.PushStyleVarFloat(mimgui.StyleVar.FrameRounding, 4.0)
        
        if mimgui.Begin("##AutoPayHelperHouse", nil, mimgui.WindowFlags.NoTitleBar + mimgui.WindowFlags.NoResize + mimgui.WindowFlags.AlwaysAutoResize + mimgui.WindowFlags.NoMove) then
            
            if is_auto_paying then
                mimgui.PushStyleColor(mimgui.Col.Button, mimgui.ImVec4(0.75, 0.15, 0.15, 1.00))
                mimgui.PushStyleColor(mimgui.Col.ButtonHovered, mimgui.ImVec4(0.85, 0.25, 0.25, 1.00))
                mimgui.PushStyleColor(mimgui.Col.ButtonActive, mimgui.ImVec4(0.60, 0.10, 0.10, 1.00))
                
                if mimgui.Button(u8"Остановить авто-оплату", mimgui.ImVec2(-1, 35)) then
                    is_auto_paying = false
                    sampAddChatMessage("{FFC800}[PayHelper] {ffffff}Авто-оплата принудительно остановлена.", -1)
                end
                mimgui.PopStyleColor(3)
            else
                mimgui.PushStyleColor(mimgui.Col.Button, mimgui.ImVec4(0.20, 0.65, 0.20, 1.00)) 
                mimgui.PushStyleColor(mimgui.Col.ButtonHovered, mimgui.ImVec4(0.25, 0.75, 0.25, 1.00))
                mimgui.PushStyleColor(mimgui.Col.ButtonActive, mimgui.ImVec4(0.15, 0.55, 0.15, 1.00))
                
                if mimgui.Button(u8"Оплатить Дом", mimgui.ImVec2(-1, 35)) then
                    if max_amount > 0 then
                        is_auto_paying = true
                        last_clicked_type = current_dialog_type
                        
                        local pay_sum = math.min(step_limit, max_amount)
                        sampSetCurrentDialogEditboxText(tostring(pay_sum))
                        sampCloseCurrentDialogWithButton(1)
                        show_overlay = false
                    else
                        sampAddChatMessage("{FFC800}[PayHelper] {ffffff}Дом уже оплачен до максимума!", -1)
                    end
                end
                mimgui.PopStyleColor(3)
            end
            
            mimgui.End()
        end
        
        mimgui.PopStyleVar(2)
        mimgui.PopStyleColor()
    end
)

function main()
    while not isSampAvailable() or not isSampLoaded() or not isSampfuncsLoaded() do wait(100) end

    sampRegisterChatCommand('payhelper', function()
        main_window_state.v = not main_window_state.v
    end)

    sampRegisterChatCommand('pay', function(param)
        if not ini.main.enabled then return end
        local target, summRaw = param:match("^(%S+)%s+(.+)$")
        local id = getTargetId(target)
        if id and summRaw then
            local cleanSumm = parseMoney(summRaw)
            sampSendChat(string.format("/pay %d %d", id, cleanSumm))
        else
            sampAddChatMessage("{FFC800}[PayHelper] {ffffff}Используйте: /pay [ID/Ник] [Сумма]", -1)
        end
    end)

    sampRegisterChatCommand('bwd', withdraw_process)
    sampRegisterChatCommand('снять', withdraw_process)
    sampRegisterChatCommand('bpt', deposit_process)
    sampRegisterChatCommand('положить', deposit_process)
    
    sampRegisterChatCommand('per', function(arg) transfer_logic(arg, false) end)
    sampRegisterChatCommand('перевести', function(arg) transfer_logic(arg, false) end)
    sampRegisterChatCommand('bper', function(arg) transfer_logic(arg, true) end)
    sampRegisterChatCommand('перевестибанк', function(arg) transfer_logic(arg, true) end)
    
    sampRegisterChatCommand('fpay', fastPayFunc)
    
    sampRegisterChatCommand("mcclear", function()
        for k, _ in pairs(stats) do stats[k] = {} end
        player_limits = {}
        sampAddChatMessage("{1ca9c9}[MoneyCounter] {ffffff}Счетчики сброшены.", -1)
    end)

    local lastTimerCheck = 0
    local last_state = false
    while true do
        wait(0)
        if main_window_state.v ~= last_state then
            last_state = main_window_state.v
            sampToggleCursor(main_window_state.v)
        end
        imgui.Process = main_window_state.v
        
        local currentTime = os.time()
        if currentTime >= lastTimerCheck + 1 then
            lastTimerCheck = currentTime
            if ini.main.enabled then
                for category, players in pairs(stats) do
                    for pNick, data in pairs(players) do
                        if data.timer > 0 and currentTime >= data.timer then
                            players[pNick] = nil
                        end
                    end
                end
            end
        end
    end
end

function imgui.OnTotalDraw() end

function imgui.OnDrawFrame()
    if not main_window_state.v then return end
    ApplyCustomStyle()
    
    local current_nick = getLocalPlayerName()
    if current_nick ~= "None" and current_nick ~= last_nick then
        last_nick = current_nick
        if ini.vip_status[current_nick] == nil then
            ini.vip_status[current_nick] = false
            inicfg.save(ini, directIni)
        end
        vip_checked.v = ini.vip_status[current_nick]
    end
    
    local showMoneyTooltip = function()
        if imgui.IsItemHovered() then
            imgui.BeginTooltip()
            imgui.TextColored(imgui.ImVec4(0.22, 0.82, 0.38, 1.00), u8"Color Money (Градация подсветки):")
            imgui.Separator()
            imgui.TextColored(imgui.ImVec4(0.53, 0.81, 0.98, 1.00), u8"Sky Blue  — от 10.000.000$")
            imgui.TextColored(imgui.ImVec4(1.00, 0.84, 0.00, 1.00), u8"Золотой   — от 1.000.000$")
            imgui.TextColored(imgui.ImVec4(50/255, 205/255, 50/255, 1.00), u8"Зеленый   — от 100.000$")
            imgui.TextColored(imgui.ImVec4(0.75, 0.75, 0.75, 1.00), u8"Серебряный— от 50.000$")
            imgui.TextColored(imgui.ImVec4(0.80, 0.50, 0.20, 1.00), u8"Бронзовый — до 49.999$")
            imgui.EndTooltip()
        end
    end

    local sw, sh = getScreenResolution()
    imgui.SetNextWindowPos(imgui.ImVec2(sw / 2, sh / 2), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
    
    imgui.SetNextWindowSize(imgui.ImVec2(980, 265), imgui.Cond.Always)
    imgui.Begin(u8"Evolve Pay Helper — Панель управления", main_window_state, imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoSavedSettings)
    
    imgui.BeginChild("LeftSettingsPanel", imgui.ImVec2(520, 215), true)
        imgui.TextColored(imgui.ImVec4(0.22, 0.82, 0.38, 1.00), u8"ГЛОБАЛЬНЫЕ ПАРАМЕТРЫ:")
        imgui.Spacing()
        
        if imgui.Checkbox(u8" Включить работу скрипта", imgui_enabled) then
            ini.main.enabled = imgui_enabled.v
            inicfg.save(ini, directIni)
        end
        
        imgui.SameLine(300)
        if imgui.Checkbox(u8"VIP PLATINUM", vip_checked) then
            if current_nick ~= "None" then
                ini.vip_status[current_nick] = vip_checked.v
                inicfg.save(ini, directIni)
                if vip_checked.v then
                    sampAddChatMessage(string.format("{FFC800}[PayHelper] {ffffff}Режим {22D14C}VIP PLATINUM {ffffff}активирован для игрока {0099FF}%s{ffffff}.", current_nick), -1)
                else
                    sampAddChatMessage(string.format("{FFC800}[PayHelper] {ffffff}Режим {E64646}VIP PLATINUM {ffffff}деактивирован для игрока {0099FF}%s{ffffff}.", current_nick), -1)
                end
            end
        end
        if imgui.IsItemHovered() then
            imgui.BeginTooltip()
            imgui.TextColored(imgui.ImVec4(1.00, 0.84, 0.00, 1.00), u8"Скрипт автоматически бьет крупные суммы для игроков с VIP PLATINUM")
            imgui.Text(u8"Лимит на передачу до 100.000")
            imgui.Text(u8"Банкомат до 250.000 (Оплата дома до 15.000 за раз)")
            imgui.EndTooltip()
        end
        
        imgui.Spacing()
        imgui.Separator()
        imgui.Spacing()
        
        imgui.TextColored(imgui.ImVec4(0.22, 0.82, 0.38, 1.00), u8"КАСТОМИЗАЦИЯ И МОНИТОРИНГ:")
        imgui.Spacing()
        
        if imgui.Checkbox(u8" Перекрашивать суммы в чате", imgui_recolor_chat) then
            ini.main.recolor_chat = imgui_recolor_chat.v
            inicfg.save(ini, directIni)
        end
        showMoneyTooltip()
        
        if imgui.Checkbox(u8" Перекрашивать суммы в диалогах", imgui_recolor_dialog) then
            ini.main.recolor_dialog = imgui_recolor_dialog.v
            inicfg.save(ini, directIni)
        end
        showMoneyTooltip()
        
        if imgui.Checkbox(u8" Счетчик, сколько всего было передано/получено за последние 25 секунд", imgui_enable_counter) then
            ini.main.enable_counter = imgui_enable_counter.v
            inicfg.save(ini, directIni)
        end
    imgui.EndChild()
    
    imgui.SameLine(0, 10)
    
    imgui.BeginChild("RightCommandsPanel", imgui.ImVec2(430, 215), true)
        imgui.TextColored(imgui.ImVec4(0.22, 0.82, 0.38, 1.00), u8"СПИСОК ФУНКЦИОНАЛЬНЫХ КОМАНД:")
        imgui.Spacing()
        
        local function drawCommandLine(cmd, desc)
            imgui.TextColored(imgui.ImVec4(1.00, 0.84, 0.00, 1.00), u8(cmd))
            imgui.SameLine(170)
            imgui.Text(u8(desc))
        end
        
        drawCommandLine("/снять , /bwd", "— Снятие наличных в Банкомате")
        drawCommandLine("/положить , /bpt", "— Положить деньги на счет")
        drawCommandLine("/per , /перевести", "— Быстрый перевод из рук")
        drawCommandLine("/bper , /перевестибанк", "— Безналичный перевод в Банкомате")
        drawCommandLine("/fpay [ID] [Сумма]", "— Быстрая передача больших сумм")
        drawCommandLine("/mcclear", "— Очистить счетчик за 25 сек.")
    imgui.EndChild()
    
    imgui.End()
end

function fastPayFunc(param)
    if not ini.main.enabled then return end

    if fpay_state.running then
        fpay_state.running = false
        sampAddChatMessage("{FFC800}[PayHelper] {ffffff}Передача средств остановлена.", -1)
        return
    end

    local target, rawAmount = param:match("^(%S+)%s+(.+)$")
    local id = getTargetId(target)
    local amount = parseMoney(rawAmount)
    
    if not id or amount <= 0 then
        sampAddChatMessage("{FFC800}[PayHelper] {ffffff}Используйте: /fpay [ID] [Сумма]", -1)
        return
    end

    local targetLevel = 4
    if sampIsPlayerConnected(id) then targetLevel = sampGetPlayerScore(id) end

    local maxPortion = 5000

    if targetLevel > 0 and targetLevel < 4 then
        maxPortion = 5000
    else
        local current_nick = getLocalPlayerName()
        if current_nick ~= "None" and ini.vip_status[current_nick] then
            maxPortion = 100000
        else
            maxPortion = 50000
        end
    end

    if player_limits[id] then maxPortion = player_limits[id] end
    
    local currentTime = os.clock()
    if fpay_confirm.id ~= id or fpay_confirm.amount ~= amount or (currentTime - fpay_confirm.timestamp) > 15 then
        fpay_confirm.id = id
        fpay_confirm.amount = amount
        fpay_confirm.timestamp = currentTime
        
        local targetNick = sampGetPlayerNickname(id)
        local pColor = sampGetPlayerColor(id)
        local hexColor = string.format("%06X", bit.band(pColor, 0xFFFFFF))
        
        sampAddChatMessage(string.format("{FFC800}[PayHelper] {ffffff}Вы хотите передать %s$%s {ffffff}игроку {%s}%s[%d]{ffffff} по %s$", getAmountColor(amount), formatMoney(amount), hexColor, targetNick, id, formatMoney(maxPortion)), -1)
        sampAddChatMessage("{FFC800}[PayHelper] {ffffff}Для подтверждения {22D14C}введите команду {ffffff}повторно", -1)
        return
    else
        fpay_confirm.id = -1
        fpay_confirm.amount = 0
        fpay_confirm.timestamp = 0
    end

    fpay_state.running = true
    fpay_state.id = id
    fpay_state.total = amount
    fpay_state.sent = 0

    local targetNick = sampGetPlayerNickname(id)
    local pColor = sampGetPlayerColor(id)
    local hexColor = string.format("%06X", bit.band(pColor, 0xFFFFFF))
    
    sampAddChatMessage(string.format("{FFC800}[PayHelper] {ffffff}Запущена отправка %s$%s{ffffff} игроку {%s}%s[%d]{ffffff} по %s$", getAmountColor(amount), formatMoney(amount), hexColor, targetNick, id, formatMoney(maxPortion)), -1)

    lua_thread.create(function()
        while fpay_state.running and fpay_state.sent < fpay_state.total do
            if not ini.main.enabled then break end
            
            local portion = math.min(fpay_state.total - fpay_state.sent, maxPortion)
            sampSendChat(string.format("/pay %d %d", fpay_state.id, portion))
            
            wait(850)
        end
        
        if fpay_state.running and fpay_state.sent >= fpay_state.total then
            sampAddChatMessage("{FFC800}[PayHelper] {ffffff}Все средства успешно переданы!", -1)
        else
            if fpay_state.sent > 0 then
                sampAddChatMessage(string.format("{FFC800}[PayHelper] {ffffff}Передача прервана. Успешно переведено: %s$%s {ffffff}из %s$%s", 
                    getAmountColor(fpay_state.sent), formatMoney(fpay_state.sent), 
                    getAmountColor(fpay_state.total), formatMoney(fpay_state.total)), -1)
            else
                sampAddChatMessage("{FFC800}[PayHelper] {ffffff}Передача прервана. Вирты не были отправлены.", -1)
            end
        end
        fpay_state.running = false
    end)
end

function transfer_logic(arg, isBank)
    if not ini.main.enabled then return end
    local targetInput, amountInput = arg:match("^(%S+)%s+(.+)$")
    local cmd = isBank and "/bper" or "/per"
    
    if not targetInput or not amountInput then
        sampAddChatMessage("{FFC800}[PayHelper] {ffffff}Используйте: " .. cmd .. " [ID/Ник] [Сумма]", -1)
        return
    end

    local id = getTargetId(targetInput)
    if not id then
        sampAddChatMessage("{FFC800}[PayHelper] {ffffff}Игрок с ID {0099FF}" .. targetInput .. " {ffffff}не найден.", -1)
        return
    end

    local summ = parseMoney(amountInput)
    if summ <= 0 then
        sampAddChatMessage("{FFC800}[PayHelper] {ffffff}Укажите корректную сумму.", -1)
        return
    end

    local targetNick = sampGetPlayerNickname(id)
    transfer.summ, transfer.nick, transfer.process, transfer.isBank = summ, targetNick, true, isBank
    local typeStr = isBank and "{32CD32}со счета" or "{FFD700}с наличных"
    
    sampAddChatMessage("Будет переведено " .. typeStr .. ": " .. getAmountColor(summ) .. "$" .. formatMoney(summ) .. " {ffffff}На ник: {0099FF}" .. targetNick, -1)
    sampAddChatMessage("{ffffff}Теперь подойдите к банкомату и нажмите {32CD32}Enter", -1)
end

function withdraw_process(arg)
    if not ini.main.enabled then return end
    local val = parseMoney(arg)
    if not arg or arg == "" or val <= 0 then
        sampAddChatMessage("{FFC800}[PayHelper] {ffffff}Введите сумму. Пример: /снять 500.000", -1)
        return 
    end
    withdraw.summ, withdraw.process = val, true
    sampAddChatMessage("Будет снято: "..getAmountColor(val).."$"..formatMoney(val), -1)
    sampAddChatMessage("{ffffff}Теперь подойдите к банкомату и нажмите {32CD32}Enter", -1)
end

function deposit_process(arg)
    if not ini.main.enabled then return end
    local val = parseMoney(arg)
    if not arg or arg == "" or val <= 0 then
        sampAddChatMessage("{FFC800}[PayHelper] {ffffff}Введите сумму. Пример: /положить 500.000", -1)
        return 
    end
    deposit.summ, deposit.process = val, true
    sampAddChatMessage("Положим на счет: "..getAmountColor(val).."$"..formatMoney(val), -1)
    sampAddChatMessage("{ffffff}Теперь подойдите к банкомату и нажмите {32CD32}Enter", -1)
end

function SE.onServerMessage(color, text)
    if not ini.main.enabled then return {color, text} end

    local cleanText = text:gsub("{%x%x%x%x%x%x}", ""):gsub("{[A-Fa-f0-9][A-Fa-f0-9][A-Fa-f0-9][A-Fa-f0-9][A-Fa-f0-9][A-Fa-f0-9]}", "")
    
    if cleanText:lower():find("у вас нет столько денег") then
        if fpay_state.running then
            fpay_state.running = false
            sampAddChatMessage("{FFC800}[PayHelper] {ffffff}Передача остановлена! Недостаточно денег.", -1)
        end
    end

    if cleanText:find("Вы слишком далеко") then
        if fpay_state.running then
            fpay_state.running = false
            sampAddChatMessage("{FFC800}[PayHelper] {ffffff}Передача остановлена! Вы слишком далеко от игрока.", -1)
        end
    end

    if cleanText:find("Недостаточно средств на руках") or cleanText:find("Недостаточно средств на банковском счету") then
        if is_auto_paying then
            is_auto_paying = false
            last_clicked_type = 0
            show_overlay = false
            sampAddChatMessage("{FFC800}[PayHelper] {ffffff}Авто-оплата остановлена! Недостаточно средств.", -1)
        end
    end

    if cleanText:find("Нельзя передать меньше %$1 и больше %$5%.000") then
        if fpay_state.running then
            fpay_state.running = false
            if fpay_state.id ~= -1 then player_limits[fpay_state.id] = 5000 end
            sampAddChatMessage("{FFC800}[PayHelper] {ffffff}Обнаружен лимит 1-3 LVL. Процесс скорректирован, запустите команду еще раз.", -1)
        end
    end

    if cleanText:find("Нельзя передать меньше %$1 и больше %$50%.000") then
        if fpay_state.running then
            fpay_state.running = false
            sampAddChatMessage("{FFC800}[PayHelper] {ffffff}Передача остановлена! Обнаружен лимит сервера ($50.000).", -1)
        end
    end

    if ini.main.recolor_chat and text:find("%$") then
        local isAllowedLine = false
        for _, pattern in ipairs(allowedChatPatterns) do
            if cleanText:find(pattern) then
                isAllowedLine = true
                break
            end
        end

        if isAllowedLine then
            text = text:gsub("%$(%d+[%d%.,]*)", function(raw)
                local val = parseMoney(raw)
                if val > 0 then
                    return getAmountColor(val) .. "$" .. formatMoney(val) .. "{ffffff}"
                end
                return nil
            end)
        end
    end

    if fpay_state.running and cleanText:find("Вы передали") then
        local rawVal = cleanText:match("%$(%d+[%d%.,]*)")
        if rawVal then
            fpay_state.sent = fpay_state.sent + parseMoney(rawVal)
        end
    end

    local statsKeys = {
        ["перевёл Вам %$"] = "received_bank",
        ["Вы передали"] = "sent_pay",
        ["Вы получили"] = "received_pay"
    }
    
    if ini.main.enable_counter then
        for trigger, key in pairs(statsKeys) do
            if cleanText:find(trigger) then
                local foundNick = nil
                for i = 0, 1000 do
                    if sampIsPlayerConnected(i) then
                        local pName = sampGetPlayerNickname(i)
                        if pName and #pName > 0 and cleanText:find(pName, 1, true) then
                            foundNick = pName
                            break
                        end
                    end
                end

                if foundNick then
                    local rawVal = cleanText:match("%$(%d+[%d%.,]*)")
                    if rawVal then
                        if not stats[key][foundNick] then
                            stats[key][foundNick] = { money = 0, timer = 0 }
                        end
                        
                        stats[key][foundNick].money = stats[key][foundNick].money + parseMoney(rawVal)
                        stats[key][foundNick].timer = os.time() + 25
                        
                        if key == "received_bank" then
                            local formattedTotal = string.format(" {ffffff}Всего переведено на ваш счёт %s$%s", getAmountColor(stats[key][foundNick].money), formatMoney(stats[key][foundNick].money))
                            lua_thread.create(function()
                                wait(50) 
                                sampAddChatMessage(formattedTotal, -1)
                            end)
                        else
                            local formattedTotal = string.format(" {ffffff}| Всего %s$%s", getAmountColor(stats[key][foundNick].money), formatMoney(stats[key][foundNick].money))
                            text = text .. formattedTotal
                        end
                        break 
                    end
                end
            end
        end
    end
    return {color, text}
end

function SE.onSendDialogResponse(id, button, list, input)
    if not ini.main.enabled then return end
    if button == 1 and input and #input > 0 then
        if input:match("^[%d%.,%s]+$") then
            local clean = input:gsub("[%s%.,]", "")
            return {id, button, list, clean}
        end
        local sum, nick = input:match("^([%d%.,%s]+)%s+(.+)$")
        if sum and nick then
            local cleanSum = sum:gsub("[%s%.,]", "")
            return {id, button, list, cleanSum .. " " .. nick}
        end
    end
end

function SE.onShowDialog(id, style, caption, b1, b2, text)
    if not ini.main.enabled then return end

    local clean_title = caption:gsub("{%x+}", "")
    local clean_text = text:gsub("{%x+}", "")
    
    local is_atm = clean_title:find("| Банкомат", 1, true) ~= nil
    local is_bank = clean_title:find("| Банк", 1, true) ~= nil
    
    if is_atm then
        local current_nick = getLocalPlayerName()
        if current_nick ~= "None" and ini.vip_status[current_nick] then
            step_limit = 15000
        else
            step_limit = 5000
        end
    elseif is_bank then
        step_limit = 50000
    end
    
    if clean_title:find("Меню | Банкомат", 1, true) or clean_title:find("Меню | Банк", 1, true) then
        if is_auto_paying and last_clicked_type > 0 then
            local menu_slot = (last_clicked_type == 1) and 3 or 4
            lua_thread.create(function()
                wait(100) 
                sampSendDialogResponse(id, 1, menu_slot, "")
            end)
        end
    end
    
    local is_cash = clean_title:find("Оплатить квартплату наличными", 1, true) ~= nil and (is_atm or is_bank)
    local is_account = (clean_title:find("Оплатить квартплату со счёта", 1, true) ~= nil or clean_title:find("Оплатить квартплату со счета", 1, true) ~= nil) and (is_atm or is_bank)
    
    if is_cash or is_account then
        current_dialog_type = is_cash and 1 or 2
        
        local match = clean_text:match("Можно пополнить на сумму: %$([%d%.%,]+)")
        if match then
            local clean_match = match:gsub("[%.%,]", "")
            max_amount = tonumber(clean_match) or 0
        else
            max_amount = 0
        end
        
        if is_auto_paying then
            if max_amount <= 0 then
                is_auto_paying = false
                last_clicked_type = 0
                show_overlay = false
                sampAddChatMessage("{FFC800}[PayHelper] {ffffff}Авто-оплата завершена! Дом полностью оплачен.", -1)
            else
                local pay_sum = math.min(step_limit, max_amount)
                lua_thread.create(function()
                    wait(100) 
                    sampSetCurrentDialogEditboxText(tostring(pay_sum))
                    sampCloseCurrentDialogWithButton(1)
                end)
            end
        else
            show_overlay = true
        end
    else
        if is_auto_paying and not (clean_title:find("Меню | Банкомат", 1, true) or clean_title:find("Меню | Банк", 1, true)) then
            is_auto_paying = false
            last_clicked_type = 0
        end
        show_overlay = false
    end

    if caption:find("Статистика") and caption:find("Персонаж") then
        local lines = {}
        for line in text:gmatch("[^\r\n]+") do
            if ini.main.recolor_dialog and (line:find("Наличные") or line:find("Банковский счет")) then
                local p, vR = line:match("^(.-)\t(.-)$")
                if p and vR then
                    local v = parseMoney(vR)
                    line = string.format("%s\t%s$%s", p, getAmountColor(v), formatMoney(v))
                end
            end
            table.insert(lines, line)
        end
        text = table.concat(lines, "\n")
    end

    if ini.main.recolor_dialog and text:find("Баланс:") then
        text = text:gsub("Баланс: %$(%d+[%d%.,]*)", function(bal)
            local v = parseMoney(bal)
            return "Баланс: " .. getAmountColor(v) .. "$" .. formatMoney(v) .. "{ffffff}"
        end)
    end

    local active = (withdraw.process or deposit.process or transfer.process)
    if active and (caption:find('Банкомат') or caption:find('Банк')) then
        local action = withdraw.process and "Снять со счета" or (deposit.process and "Положить на счет" or (transfer.isBank and "Перевести игроку со счета" or "Перевести игроку с наличных"))
        if text:find(action) then
            lua_thread.create(function() 
                wait(75)
                local n = 0
                for line in text:gmatch("[^\r\n]+") do
                    if line:find(action) then sampSendDialogResponse(id, 1, n, "") break end
                    n = n + 1
                end
            end)
        elseif caption:find('Снять') or caption:find('Положить') or caption:find('Перевести') then
            lua_thread.create(function() 
                wait(75)
                local obj = withdraw.process and withdraw or (deposit.process and deposit or transfer)
                
                local current_nick = getLocalPlayerName()
                local max_atm_limit = 100000
                if current_nick ~= "None" and ini.vip_status[current_nick] then
                    max_atm_limit = 250000
                end
                
                local send_val = obj.summ > max_atm_limit and max_atm_limit or obj.summ
                local data = tostring(math.floor(send_val))
                if transfer.process then data = data .. " " .. transfer.nick end
                sampSendDialogResponse(id, 1, -1, data)
                obj.summ = obj.summ - send_val
                if obj.summ <= 0 then 
                    obj.process = false 
                    sampAddChatMessage('{FFC800}[PayHelper] {ffffff}Операция успешно завершена!', -1) 
                end
            end)
        end
    end
    return {id, style, caption, b1, b2, text}
end