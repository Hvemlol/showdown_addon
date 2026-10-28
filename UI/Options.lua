local Options = {}

local MinimapButton = require("UI.MinimapButton")

local panel

local function getSettings()
    ShowdownCloneDB.settings = ShowdownCloneDB.settings or {}
    local s = ShowdownCloneDB.settings
    if s.minimapShown == nil then s.minimapShown = true end
    if s.defaultLevel == nil then s.defaultLevel = 100 end
    if s.loadMessage == nil then s.loadMessage = true end
    return s
end

local function buildPanel()
    panel = CreateFrame("Frame", "ShowdownCloneOptionsPanel", UIParent)
    panel.name = "Showdown Clone"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Showdown Clone")

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetText("A simplified Pokemon Showdown clone (Gen 1, 151 Pokemon).")

    -- Minimap button toggle
    local minimapCheck = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    minimapCheck:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -24)
    minimapCheck.Text:SetText("Show minimap button")
    minimapCheck:SetScript("OnClick", function(self)
        local s = getSettings()
        s.minimapShown = self:GetChecked() and true or false
        if s.minimapShown then
            MinimapButton:Show()
        else
            MinimapButton:Hide()
        end
    end)
    panel.minimapCheck = minimapCheck

    -- Default level
    local levelLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    levelLabel:SetPoint("TOPLEFT", minimapCheck, "BOTTOMLEFT", 0, -24)
    levelLabel:SetText("Default team level (1-100):")

    local levelBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    levelBox:SetSize(60, 20)
    levelBox:SetPoint("LEFT", levelLabel, "RIGHT", 8, 0)
    levelBox:SetAutoFocus(false)
    levelBox:SetScript("OnTextChanged", function(self)
        local v = tonumber(self:GetText())
        if v then
            v = math.max(1, math.min(100, math.floor(v)))
            self:SetText(tostring(v))
            getSettings().defaultLevel = v
        end
    end)
    levelBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    panel.levelBox = levelBox

    -- Load message toggle
    local loadMsgCheck = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    loadMsgCheck:SetPoint("TOPLEFT", levelLabel, "BOTTOMLEFT", 0, -24)
    loadMsgCheck.Text:SetText("Show load message on login")
    loadMsgCheck:SetScript("OnClick", function(self)
        getSettings().loadMessage = self:GetChecked() and true or false
    end)
    panel.loadMsgCheck = loadMsgCheck

    -- Reset record button
    local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetBtn:SetSize(160, 22)
    resetBtn:SetPoint("TOPLEFT", loadMsgCheck, "BOTTOMLEFT", 0, -24)
    resetBtn:SetText("Reset win/loss record")
    resetBtn:SetScript("OnClick", function()
        ShowdownCloneDB.record = { wins = 0, losses = 0 }
        if ShowdownClone and ShowdownClone.Print then
            ShowdownClone.Print("Record reset.")
        end
    end)

    panel.refresh = function()
        local s = getSettings()
        minimapCheck:SetChecked(s.minimapShown)
        levelBox:SetText(tostring(s.defaultLevel))
        loadMsgCheck:SetChecked(s.loadMessage)
    end

    panel.default = function()
        local s = getSettings()
        s.minimapShown = true
        s.defaultLevel = 100
        s.loadMessage = true
    end

    return panel
end

function Options:Register()
    if panel then return end
    buildPanel()
    if InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

Options.getSettings = getSettings

_G["ShowdownClone_Options"] = Options
return Options
