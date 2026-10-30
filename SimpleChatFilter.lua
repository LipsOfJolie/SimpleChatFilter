-- ==============================================
-- SimpleChatFilter for PikaWOW AzerothCore 3.3.5
-- SYSTEM + WORLD + WHISPER
-- ==============================================

if _G.SimpleChatFilter then return end

local SCF = CreateFrame("Frame")
_G.SimpleChatFilter = SCF

-- ==============================================
-- УТИЛИТЫ
-- ==============================================

local CyrillicLower = {
    ["А"]="а",["Б"]="б",["В"]="в",["Г"]="г",["Д"]="д",
    ["Е"]="е",["Ё"]="ё",["Ж"]="ж",["З"]="з",["И"]="и",
    ["Й"]="й",["К"]="к",["Л"]="л",["М"]="м",["Н"]="н",
    ["О"]="о",["П"]="п",["Р"]="р",["С"]="с",["Т"]="т",
    ["У"]="у",["Ф"]="ф",["Х"]="х",["Ц"]="ц",["Ч"]="ч",
    ["Ш"]="ш",["Щ"]="щ",["Ъ"]="ъ",["Ы"]="ы",["Ь"]="ь",
    ["Э"]="э",["Ю"]="ю",["Я"]="я",
}

local Homoglyphs = {
    ["a"]="а", ["e"]="е", ["o"]="о", ["p"]="р",
    ["c"]="с", ["x"]="х", ["y"]="у", ["k"]="к",
    ["m"]="м", ["t"]="т", ["b"]="б", ["h"]="н",
    ["0"]="о", ["3"]="з", ["4"]="ч", ["6"]="б", ["9"]="д",
}

local Separators = "[%.%-%_%*%+%=%/%\\%!%?%@%#%$%^%&%(%)%[%]%{%}%<%>%~%`'\"]"

-- ==============================================
-- OPT #5: StripTags вызывается один раз ДО Normalize.
-- Повторные gsub для тегов убраны из Normalize.
-- ==============================================
local function StripTags(msg)
    if type(msg) ~= "string" then return "" end
    msg = msg:gsub("|c%x%x%x%x%x%x%x%x", "")
    msg = msg:gsub("|r", "")
    msg = msg:gsub("|H.-|h(.-)|h", "%1")
    return msg
end

-- ==============================================
-- NORMALIZE С КЭШЕМ
-- ==============================================
local NormalizeCache     = {}
local NormalizeCacheSize = 0

local function Normalize(msg)
    if type(msg) ~= "string" then return "" end
    if NormalizeCache[msg] then return NormalizeCache[msg] end

    local result = string.lower(msg)
    result = result:gsub("[А-ЯЁ]", CyrillicLower)
    result = result:gsub(Separators, "")
    result = result:gsub("[aeopcxytbhn03469]", Homoglyphs)

    if NormalizeCacheSize >= 200 then
        NormalizeCache     = {}
        NormalizeCacheSize = 0
    end

    NormalizeCache[msg]  = result
    NormalizeCacheSize   = NormalizeCacheSize + 1
    return result
end

-- ==============================================
-- ИНИЦИАЛИЗАЦИЯ ПЕРЕМЕННЫХ
-- ==============================================
SCF.Enabled           = true
SCF.LastBlockedList   = {}
SCF.ShowMinimapButton = true
SCF.TotalBlocked      = 0
SCF.DBLoaded          = false

local JOURNAL_MAX_ENT = 6

SCF.StopWords = {
    { display = "Лучше вводить словосочетания", normalized = Normalize(StripTags("Лучше вводить словосочетания")) }
}

SCF.StopWordsNorm = {}

local function RebuildNormArray()
    local t = {}
    for i = 1, #SCF.StopWords do
        t[i] = SCF.StopWords[i].normalized
    end
    SCF.StopWordsNorm = t
end

RebuildNormArray()

-- ==============================================
-- СОХРАНЕНИЕ / ЗАГРУЗКА
-- DBLoaded: SaveDB не работает пока не выполнен LoadDB.
-- LoadDB всегда выставляет DBLoaded = true в конце —
-- независимо от того нашлась DB или нет.
-- C_Timer убран — в 3.3.5 не существует.
-- SavedVariables гарантированно загружены до PLAYER_LOGIN.
-- ==============================================
local function SaveDB()
    if not SCF.DBLoaded then
        return -- ЗАЩИТА ОТ ПЕРЕТИРАНИЯ WTF
    end

    if not SimpleChatFilterDB then
        SimpleChatFilterDB = {}
    end

    SimpleChatFilterDB.StopWords         = SCF.StopWords
    SimpleChatFilterDB.ShowMinimapButton = SCF.ShowMinimapButton
    SimpleChatFilterDB.TotalBlocked      = SCF.TotalBlocked
end

local function LoadDB()
    local db = SimpleChatFilterDB

    if db and db.StopWords then
        local converted = {}
        for _, v in ipairs(db.StopWords) do
            if type(v) == "string" then
                table.insert(converted, {
                    display    = v,
                    normalized = Normalize(StripTags(v))
                })
            else
                table.insert(converted, {
                    display    = v.display or "",
                    normalized = v.normalized or Normalize(StripTags(v.display or ""))
                })
            end
        end
        SCF.StopWords         = converted
        SCF.ShowMinimapButton = db.ShowMinimapButton ~= false
        SCF.TotalBlocked      = db.TotalBlocked or 0
    end

    -- Всегда разрешаем сохранение после попытки загрузки.
    -- Если DB не было — просто оставляем дефолты и работаем дальше.
    SCF.DBLoaded = true
    RebuildNormArray()
end

local function UpdateTotalBlockedText()
    if SCF.TotalBlockedText then
        SCF.TotalBlockedText:SetText("Заблокировано за всё время: " .. SCF.TotalBlocked)
    end
end

-- ==============================================
-- ЖУРНАЛ ЗАБЛОКИРОВАННЫХ
-- ==============================================
function SCF:AddBlockedMessage(msg)
    SCF.TotalBlocked = SCF.TotalBlocked + 1
    UpdateTotalBlockedText()

    local entry = { text = msg, id = SCF.TotalBlocked }
    table.insert(SCF.LastBlockedList, 1, entry)
    if #SCF.LastBlockedList > JOURNAL_MAX_ENT then
        table.remove(SCF.LastBlockedList, #SCF.LastBlockedList)
    end
    if SCF.UpdateJournal then SCF.UpdateJournal() end
end

-- ==============================================
-- ФИЛЬТР ЧАТА
-- ==============================================
local function MessageFilter(self, event, msg, sender, ...)
    if not SCF.Enabled then return false end

    if #msg < 3 then return false end

    local stripped = StripTags(msg)
    local normMsg  = Normalize(stripped)

    local norms = SCF.StopWordsNorm
    for i = 1, #norms do
        if normMsg:find(norms[i], 1, true) then
            local key = (sender or "") .. "|" .. msg
            local now = GetTime()
            if SCF._lastBlockedKey == key and (now - (SCF._lastBlockedTime or 0)) < 0.1 then
                return true
            end
            SCF._lastBlockedKey  = key
            SCF._lastBlockedTime = now

            local blockedMsg = (sender and sender ~= "") and ("[" .. sender .. "] " .. stripped) or stripped
            SCF:AddBlockedMessage(blockedMsg)
            return true
        end
    end
    return false
end

ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM",  MessageFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", MessageFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", MessageFilter)

-- ==============================================
-- GUI
-- ==============================================

local JOURNAL_LINE_H   = 13
local JOURNAL_LINES    = 3
local JOURNAL_ENTRY_H  = JOURNAL_LINE_H * JOURNAL_LINES


local function CreateGUI()
    if SCF.Frame then return SCF.Frame end

    local f = CreateFrame("Frame", "SimpleChatFilterFrame", UIParent)
    f:SetSize(440, 460)
    f:SetPoint("CENTER")
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 32,
        insets   = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:Hide()

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Simple Chat Filter v1.2")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)

    -- ==============================================
    -- СПИСОК СТОП-СЛОВ (левая колонка)
    -- ==============================================
    local ITEM_HEIGHT = 24
    local LIST_WIDTH  = 180
    local LIST_HEIGHT = 240

    local listContainer = CreateFrame("Frame", nil, f)
    listContainer:SetPoint("TOPLEFT", 20, -50)
    listContainer:SetSize(LIST_WIDTH + 18, LIST_HEIGHT)

    local scrollFrame = CreateFrame("ScrollFrame", "SimpleChatFilterScrollFrame", listContainer, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -18, 0)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(LIST_WIDTH)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    local scrollBar = _G["SimpleChatFilterScrollFrameScrollBar"]
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPLEFT",    scrollFrame, "TOPRIGHT",    4, -16)
        scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 4,  16)
    end

    local buttons = {}

    local function UpdateList()
        for _, b in ipairs(buttons) do b:Hide() end

        local count = #SCF.StopWords
        scrollChild:SetHeight(math.max(count * ITEM_HEIGHT, LIST_HEIGHT))

        for i, entry in ipairs(SCF.StopWords) do
            local btn = buttons[i]
            if not btn then
                btn = CreateFrame("Button", nil, scrollChild)
                btn:SetSize(LIST_WIDTH, ITEM_HEIGHT)

                btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                btn.text:SetPoint("LEFT", 5, 0)
                btn.text:SetWidth(LIST_WIDTH - 10)
                btn.text:SetJustifyH("LEFT")
                btn.text:SetWordWrap(false)

                btn:SetScript("OnClick", function(self)
                    for _, o in ipairs(buttons) do
                        o.text:SetTextColor(1, 1, 1)
                    end
                    self.text:SetTextColor(1, 0.8, 0)
                    SCF.SelectedIndex = self.index
                end)

                buttons[i] = btn
            end

            btn:SetPoint("TOPLEFT", 0, -(i - 1) * ITEM_HEIGHT)
            btn.text:SetText(entry.display)
            btn.text:SetTextColor(1, 1, 1)
            btn.index = i
            btn:Show()
        end

        scrollFrame:SetVerticalScroll(0)
    end

    SCF._UpdateList = UpdateList

    local edit = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    edit:SetSize(150, 25)
    edit:SetPoint("TOPLEFT", listContainer, "BOTTOMLEFT", 0, -10)
    edit:SetAutoFocus(false)

    local function AddStopWord(word)
        word = word:match("^%s*(.-)%s*$")
        if word == "" then return end
        local normalized = Normalize(StripTags(word))
        for _, entry in ipairs(SCF.StopWords) do
            if entry.normalized == normalized then return end
        end
        table.insert(SCF.StopWords, { display = word, normalized = normalized })
        RebuildNormArray()
        SaveDB()
        UpdateList()
    end

    edit:SetScript("OnEnterPressed", function(self)
        AddStopWord(self:GetText())
        self:SetText("")
    end)

    local add = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    add:SetSize(60, 25)
    add:SetPoint("LEFT", edit, "RIGHT", 5, 0)
    add:SetText("Добавить")
    add:SetScript("OnClick", function()
        AddStopWord(edit:GetText())
        edit:SetText("")
    end)

    local del = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    del:SetSize(120, 25)
    del:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", 0, -10)
    del:SetText("Удалить выбранное")
    del:SetScript("OnClick", function()
        local idx = SCF.SelectedIndex
        if not idx then return end
        table.remove(SCF.StopWords, idx)
        RebuildNormArray()
        SCF.SelectedIndex = nil
        SaveDB()
        UpdateList()
    end)

    -- ==============================================
    -- ЖУРНАЛ (правая колонка)
    -- ==============================================
    local JOURNAL_X     = 20
    local JOURNAL_WIDTH = 185
    local LINE_GAP      = 4

    local journalTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    journalTitle:SetPoint("TOPLEFT", listContainer, "TOPRIGHT", JOURNAL_X, 0)
    journalTitle:SetWidth(JOURNAL_WIDTH)
    journalTitle:SetJustifyH("LEFT")
    journalTitle:SetText("Последние заблокированные:")

    local journalTexts   = {}
    local journalClips   = {}

    for i = 1, JOURNAL_MAX_ENT do
        local clip = CreateFrame("ScrollFrame", nil, f)
        clip:SetSize(JOURNAL_WIDTH, JOURNAL_ENTRY_H)

        local inner = CreateFrame("Frame", nil, clip)
        inner:SetSize(JOURNAL_WIDTH, JOURNAL_ENTRY_H * 4)
        clip:SetScrollChild(inner)

        local fs = inner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", inner, "TOPLEFT", 0, 0)
        fs:SetWidth(JOURNAL_WIDTH)
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        fs:SetWordWrap(true)
        fs:SetText("")

        journalClips[i] = clip
        journalTexts[i] = fs
    end

    journalClips[1]:SetPoint("TOPLEFT", journalTitle, "BOTTOMLEFT", 0, -LINE_GAP)
    for i = 2, JOURNAL_MAX_ENT do
        journalClips[i]:SetPoint("TOPLEFT", journalClips[i-1], "BOTTOMLEFT", 0, -LINE_GAP)
    end

    local function UpdateJournal()
        for i = 1, JOURNAL_MAX_ENT do
            local entry = SCF.LastBlockedList[i]
            if entry then
                local text = type(entry) == "table" and (entry.text or "") or tostring(entry)
                journalTexts[i]:SetText(text)
            else
                journalTexts[i]:SetText("")
            end
            journalClips[i]:SetVerticalScroll(0)
            journalClips[i]:SetHeight(JOURNAL_ENTRY_H)
        end

        f:SetScript("OnUpdate", function(self)
            self:SetScript("OnUpdate", nil)
            for i = 1, JOURNAL_MAX_ENT do
                local textH = journalTexts[i]:GetStringHeight()
                local clampedH = math.max(JOURNAL_LINE_H, math.min(textH, JOURNAL_ENTRY_H))
                journalClips[i]:SetHeight(clampedH)
            end
        end)
    end

    SCF.LastBlockedText = {
        SetText = function(self, text)
            UpdateJournal()
        end
    }
    SCF.UpdateJournal = UpdateJournal
    UpdateJournal()

    local clearJournal = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clearJournal:SetSize(120, 25)
    clearJournal:SetPoint("TOPLEFT", del, "TOPRIGHT", 105, 0)
    clearJournal:SetText("Очистить журнал")
    clearJournal:SetScript("OnClick", function()
        SCF.LastBlockedList = {}
        UpdateJournal()
    end)

    -- ==============================================
    -- НИЖНЯЯ ЧАСТЬ
    -- ==============================================

    local showBtnChk = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    showBtnChk:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, 40)
    showBtnChk:SetChecked(SCF.ShowMinimapButton)
    showBtnChk.label = showBtnChk:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    showBtnChk.label:SetPoint("LEFT", showBtnChk, "RIGHT", 2, 0)
    showBtnChk.label:SetText("Кнопка миникарты")
    showBtnChk:SetScript("OnClick", function(self)
        SCF.ShowMinimapButton = self:GetChecked()
        if SCF.MiniBtn then
            if SCF.ShowMinimapButton then SCF.MiniBtn:Show() else SCF.MiniBtn:Hide() end
        end
        SaveDB()
    end)

    local enableChk = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    enableChk:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -100, 40)
    enableChk:SetChecked(SCF.Enabled)
    enableChk.label = enableChk:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    enableChk.label:SetPoint("LEFT", enableChk, "RIGHT", 2, 0)
    enableChk.label:SetText("Фильтр активен")
    enableChk:SetScript("OnClick", function(self)
        SCF.Enabled = self:GetChecked()
        if SCF.UpdateMinimapDimmer then SCF.UpdateMinimapDimmer() end
        local status = SCF.Enabled and "|cff00ff00включён|r" or "|cffff4444выключен|r"
        print("|cffffff00SimpleChatFilter|r: фильтр " .. status)
    end)
    SCF.EnableChk = enableChk

    local footer = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    footer:SetPoint("BOTTOM", f, "BOTTOM", 0, 26)
    footer:SetJustifyH("CENTER")
    footer:SetText("Сделано специально для PikaWoW, автор Бивис-Solo")

    local totalText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totalText:SetPoint("BOTTOM", f, "BOTTOM", 0, 12)
    totalText:SetJustifyH("CENTER")
    SCF.TotalBlockedText = totalText
    UpdateTotalBlockedText()

    UpdateList()
    SCF.Frame = f
    return f
end

-- ==============================================
-- SLASH-КОМАНДА /scf
-- ==============================================
SLASH_SCF1 = "/scf"
SlashCmdList["SCF"] = function()
    local f = SCF.Frame or CreateGUI()
    if f:IsShown() then f:Hide() else f:Show() end
end

-- ==============================================
-- КНОПКА МИНИКАРТЫ
-- ==============================================
local function CreateMinimapButton()
    if SCF.MiniBtn then return end

    local RADIUS = 75
    local angle = (SimpleChatFilterDB and SimpleChatFilterDB.MinimapAngle) or 225

    local function PlaceButton(btn, a)
        local rad = math.rad(a)
        btn:ClearAllPoints()
        btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * RADIUS, math.sin(rad) * RADIUS)
    end

    local btn = CreateFrame("Button", "SimpleChatFilterMinimapButton", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:RegisterForDrag("RightButton")
    btn:RegisterForClicks("LeftButtonUp")

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Background")
    bg:SetAllPoints(btn)

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetTexture("Interface\\AddOns\\SimpleChatFilter\\icon.tga")
    btn.icon:SetPoint("CENTER")
    btn.icon:SetSize(20, 20)

    local function UpdateDimmer()
        if SCF.Enabled then
            btn.icon:SetVertexColor(1, 1, 1)
        else
            btn.icon:SetVertexColor(0.4, 0.4, 0.4)
        end
    end
    SCF.UpdateMinimapDimmer = UpdateDimmer

    local hl = btn:CreateTexture(nil, "OVERLAY")
    hl:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    hl:SetAllPoints(btn)
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0)

    local function UpdateTooltip(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("SimpleChatFilter", 1, 1, 0)
        if SCF.Enabled then
            GameTooltip:AddLine("Фильтр активен.", 0, 1, 0, true)
        else
            GameTooltip:AddLine("Фильтр отключён!", 1, 0, 0, true)
        end
        GameTooltip:AddLine("ЛКМ — открыть настройки", 1, 1, 1, true)
        GameTooltip:AddLine("Ctrl+ЛКМ — включить/выключить фильтр", 1, 1, 1, true)
        GameTooltip:AddLine("ПКМ — переместить кнопку", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end

    btn:SetScript("OnEnter", function(self)
        hl:SetAlpha(1)
        UpdateTooltip(self)
    end)
    btn:SetScript("OnLeave", function(self)
        hl:SetAlpha(0)
        GameTooltip:Hide()
    end)

    function SCF.PulseMinimapButton() end

    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function(self)
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            angle = math.deg(math.atan2(cy - my, cx - mx))
            PlaceButton(self, angle)
        end)
    end)

    btn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        if not SimpleChatFilterDB then SimpleChatFilterDB = {} end
        SimpleChatFilterDB.MinimapAngle = angle
    end)

    btn:SetScript("OnClick", function(self)
        if IsControlKeyDown() then
            SCF.Enabled = not SCF.Enabled
            UpdateDimmer()
            if SCF.EnableChk then SCF.EnableChk:SetChecked(SCF.Enabled) end
            if self:IsMouseOver() then UpdateTooltip(self) end
            local status = SCF.Enabled and "|cff00ff00включён|r" or "|cffff4444выключен|r"
            print("|cffffff00SimpleChatFilter|r: фильтр " .. status)
        else
            local f = SCF.Frame or CreateGUI()
            if not f then return end
            if f:IsShown() then f:Hide() else f:Show() end
        end
    end)

    UpdateDimmer()
    PlaceButton(btn, angle)
    SCF.MiniBtn = btn
    if not SCF.ShowMinimapButton then btn:Hide() end
end

-- ==============================================
-- СОБЫТИЯ
-- ==============================================
SCF:RegisterEvent("PLAYER_LOGIN")
SCF:RegisterEvent("PLAYER_LEAVING_WORLD")
SCF:RegisterEvent("PLAYER_LOGOUT")
SCF:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        LoadDB()
        CreateMinimapButton()
        print("|cff00ff00SimpleChatFilter загружен.|r")
    elseif event == "PLAYER_LEAVING_WORLD" then
        SaveDB()
    elseif event == "PLAYER_LOGOUT" then
        if SCF.MiniBtn then SCF.MiniBtn:SetScript("OnUpdate", nil) end
        SaveDB()
    end
end)