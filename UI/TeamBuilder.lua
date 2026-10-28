local TeamBuilder = {}

local PokemonData = require("Core.Data.Pokemon")
local BattleEngine = require("Core.BattleEngine")
local Stats = require("Core.Stats")

local frame
local selectedIndex = 1
local searchText = ""

local function getTeam()
    return ShowdownCloneDB and ShowdownCloneDB.team or {}
end

local function setTeam(team)
    ShowdownCloneDB.team = team
end

local function speciesList()
    local out = {}
    for id = 1, PokemonData.count() do
        local s = PokemonData.get(id)
        if s then out[#out + 1] = s end
    end
    return out
end

local function createPokemonFromSpecies(species, level)
    return BattleEngine.newPokemon(species.id, level or 5)
end

function TeamBuilder:Toggle()
    if frame and frame:IsShown() then
        frame:Hide()
    else
        self:Show()
    end
end

function TeamBuilder:Show()
    if not frame then self:Build() end
    self:Refresh()
    frame:Show()
end

function TeamBuilder:Hide()
    if frame then frame:Hide() end
end

function TeamBuilder:Build()
    frame = CreateFrame("Frame", "ShowdownCloneTeamBuilder", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(720, 480)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame.TitleBg:SetHeight(30)
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOPLEFT", frame.TitleBg, "TOPLEFT", 12, -8)
    frame.title:SetText("Showdown Clone - Team Builder")

    -- Left: team list
    local teamFrame = CreateFrame("Frame", nil, frame, "InsetFrameTemplate3")
    teamFrame:SetSize(300, 400)
    teamFrame:SetPoint("TOPLEFT", 12, -32)

    local teamScroll = CreateFrame("ScrollFrame", "ShowdownCloneTeamScroll", teamFrame, "UIPanelScrollFrameTemplate")
    teamScroll:SetPoint("TOPLEFT", 4, -8)
    teamScroll:SetPoint("BOTTOMRIGHT", -26, 6)
    local teamContent = CreateFrame("Frame")
    teamContent:SetSize(270, 400)
    teamScroll:SetScrollChild(teamContent)
    frame.teamContent = teamContent
    frame.teamButtons = {}

    -- Right: species browser
    local browserFrame = CreateFrame("Frame", nil, frame, "InsetFrameTemplate3")
    browserFrame:SetSize(380, 400)
    browserFrame:SetPoint("TOPRIGHT", -12, -32)

    local searchBox = CreateFrame("EditBox", nil, browserFrame, "InputBoxTemplate")
    searchBox:SetSize(200, 20)
    searchBox:SetPoint("TOPLEFT", 10, -10)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnTextChanged", function(self)
        searchText = self:GetText():lower()
        TeamBuilder:RefreshBrowser()
    end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    local addButton = CreateFrame("Button", nil, browserFrame, "UIPanelButtonTemplate")
    addButton:SetSize(80, 22)
    addButton:SetPoint("LEFT", searchBox, "RIGHT", 8, 0)
    addButton:SetText("Add")
    addButton:SetScript("OnClick", function()
        TeamBuilder:AddSelected()
    end)

    local levelBox = CreateFrame("EditBox", nil, browserFrame, "InputBoxTemplate")
    levelBox:SetSize(50, 20)
    levelBox:SetPoint("LEFT", addButton, "RIGHT", 8, 0)
    levelBox:SetText("5")
    levelBox:SetAutoFocus(false)
    frame.levelBox = levelBox

    local browserScroll = CreateFrame("ScrollFrame", "ShowdownCloneBrowserScroll", browserFrame, "UIPanelScrollFrameTemplate")
    browserScroll:SetPoint("TOPLEFT", 8, -40)
    browserScroll:SetPoint("BOTTOMRIGHT", -26, 6)
    local browserContent = CreateFrame("Frame")
    browserContent:SetSize(350, 600)
    browserScroll:SetScrollChild(browserContent)
    frame.browserContent = browserContent
    frame.browserButtons = {}

    -- Selected species tracking
    frame.selectedSpeciesId = nil

    frame:Hide()
end

function TeamBuilder:Refresh()
    local team = getTeam()
    local content = frame.teamContent
    for _, btn in ipairs(frame.teamButtons) do btn:Hide() end
    frame.teamButtons = {}
    local y = -4
    for i = 1, BattleEngine.MAX_TEAM do
        local slot = team[i]
        local btn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        btn:SetSize(250, 40)
        btn:SetPoint("TOPLEFT", 4, y)
        if slot then
            local p = slot -- serialized pokemon
            local species = PokemonData.get(p.id)
            btn:SetText("#" .. i .. " " .. (p.nickname or (species and species.name or "?")) .. " Lv" .. p.level)
            btn:SetScript("OnClick", function()
                selectedIndex = i
                TeamBuilder:RemoveAt(i)
            end)
            btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText((p.nickname or (species and species.name or "?")))
                GameTooltip:AddLine("Level " .. p.level, 1, 1, 1)
                GameTooltip:AddLine("Click to remove from team", 0.8, 0.8, 0.8)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        else
            btn:SetText("#" .. i .. " (empty)")
            btn:SetScript("OnClick", nil)
        end
        btn:Show()
        frame.teamButtons[#frame.teamButtons + 1] = btn
        y = y - 44
    end
    TeamBuilder:RefreshBrowser()
end

function TeamBuilder:RefreshBrowser()
    local content = frame.browserContent
    for _, btn in ipairs(frame.browserButtons) do btn:Hide() end
    frame.browserButtons = {}
    local y = -4
    local count = 0
    for _, species in ipairs(speciesList()) do
        if searchText == "" or species.name:lower():find(searchText, 1, true) then
            local btn = CreateFrame("Button", nil, content)
            btn:SetSize(330, 22)
            btn:SetPoint("TOPLEFT", 4, y)
            local typeStr = table.concat(species.types, "/")
            btn:SetText(string.format("%03d %s (%s)", species.id, species.name, typeStr))
            btn:SetNormalFontObject("GameFontNormalLeft")
            btn:SetHighlightFontObject("GameFontHighlightLeft")
            btn:SetScript("OnClick", function()
                frame.selectedSpeciesId = species.id
                for _, b in ipairs(frame.browserButtons) do
                    b:UnlockHighlight()
                end
                btn:LockHighlight()
            end)
            btn:Show()
            frame.browserButtons[#frame.browserButtons + 1] = btn
            y = y - 24
            count = count + 1
            if count >= 60 then break end
        end
    end
    content:SetHeight(math.max(400, count * 24 + 8))
end

function TeamBuilder:AddSelected()
    local team = getTeam()
    if #team >= BattleEngine.MAX_TEAM then
        print("|cffff0000Showdown Clone:|r Your team is full (max 6).")
        return
    end
    if not frame.selectedSpeciesId then
        print("|cffff0000Showdown Clone:|r Select a Pokemon first.")
        return
    end
    local level = tonumber(frame.levelBox:GetText()) or 5
    level = math.max(1, math.min(Stats.MAX_LEVEL, level))
    local p = createPokemonFromSpecies(PokemonData.get(frame.selectedSpeciesId), level)
    local Serializer = require("Core.Util.Serializer")
    team[#team + 1] = Serializer.encodePokemon(p)
    setTeam(team)
    self:Refresh()
end

function TeamBuilder:RemoveAt(index)
    local team = getTeam()
    table.remove(team, index)
    setTeam(team)
    self:Refresh()
end

-- Load team from saved variables into live Pokemon instances.
function TeamBuilder:LoadLiveTeam()
    local Serializer = require("Core.Util.Serializer")
    local saved = getTeam()
    local live = {}
    for _, t in ipairs(saved) do
        live[#live + 1] = Serializer.decodePokemon(t, BattleEngine)
    end
    return live
end

function TeamBuilder:GetLiveTeam()
    return self:LoadLiveTeam()
end

_G["ShowdownClone_TeamBuilder"] = TeamBuilder
return TeamBuilder
