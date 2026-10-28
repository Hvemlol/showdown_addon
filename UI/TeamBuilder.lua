local TeamBuilder = {}

local PokemonData = require("Core.Data.Pokemon")
local BattleEngine = require("Core.BattleEngine")
local Moves = require("Core.Data.Moves")
local Types = require("Core.Data.Types")
local Stats = require("Core.Stats")
local Serializer = require("Core.Util.Serializer")

local frame
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

function TeamBuilder:IsOpen()
    return frame and frame:IsShown()
end

function TeamBuilder:Build()
    frame = CreateFrame("Frame", "ShowdownCloneTeamBuilder", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(760, 500)
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

    -- Close button + Esc-to-close (standard WoW window behavior)
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", frame.TitleBg, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() TeamBuilder:Hide() end)
    frame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            TeamBuilder:Hide()
            self:SetPropagateKeyboardInput(false)
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    frame:SetPropagateKeyboardInput(true)
    tinsert(UISpecialFrames, frame:GetName())

    -- Left: current team (6 slots)
    local teamFrame = CreateFrame("Frame", nil, frame, "InsetFrameTemplate3")
    teamFrame:SetSize(300, 420)
    teamFrame:SetPoint("TOPLEFT", 12, -32)

    frame.teamTitle = teamFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.teamTitle:SetPoint("TOP", 0, -8)
    frame.teamTitle:SetText("Your Team (max 6)")

    frame.teamSlots = {}
    frame.removeButtons = {}
    local y = -30
    for i = 1, BattleEngine.MAX_TEAM do
        local slot = CreateFrame("Button", nil, teamFrame, "UIPanelButtonTemplate")
        slot:SetSize(240, 56)
        slot:SetPoint("TOPLEFT", 8, y)
        slot.slotIndex = i
        slot:SetScript("OnClick", function(self)
            TeamBuilder:EditSlot(self.slotIndex)
        end)
        frame.teamSlots[i] = slot

        -- Per-slot Remove button (only meaningful when the slot is filled)
        local rm = CreateFrame("Button", nil, teamFrame, "UIPanelButtonTemplate")
        rm:SetSize(24, 24)
        rm:SetPoint("LEFT", slot, "RIGHT", 4, 0)
        rm:SetText("X")
        rm.slotIndex = i
        rm:SetScript("OnClick", function(self)
            TeamBuilder:RemoveSlot(self.slotIndex)
        end)
        rm:Hide()
        frame.removeButtons[i] = rm

        y = y - 60
    end

    -- "Use starter team" button: shown when the team is empty so a new
    -- player can get a default team explicitly (no silent SavedVariables write)
    local starterBtn = CreateFrame("Button", nil, teamFrame, "UIPanelButtonTemplate")
    starterBtn:SetSize(270, 24)
    starterBtn:SetPoint("BOTTOMLEFT", 8, 8)
    starterBtn:SetText("Use starter team (Bulba/Char/Squirt)")
    starterBtn:SetScript("OnClick", function()
        TeamBuilder:UseStarterTeam()
    end)
    frame.starterBtn = starterBtn

    -- Right: species browser
    local browserFrame = CreateFrame("Frame", nil, frame, "InsetFrameTemplate3")
    browserFrame:SetSize(420, 420)
    browserFrame:SetPoint("TOPRIGHT", -12, -32)

    local searchBox = CreateFrame("EditBox", nil, browserFrame, "InputBoxTemplate")
    searchBox:SetSize(260, 20)
    searchBox:SetPoint("TOPLEFT", 10, -10)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnTextChanged", function(self)
        searchText = self:GetText():lower()
        TeamBuilder:RefreshBrowser()
    end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    frame.levelBox = CreateFrame("EditBox", nil, browserFrame, "InputBoxTemplate")
    frame.levelBox:SetSize(50, 20)
    frame.levelBox:SetPoint("LEFT", searchBox, "RIGHT", 8, 0)
    -- Default level comes from settings (options panel), falling back to 100
    local defaultLevel = (ShowdownCloneDB and ShowdownCloneDB.settings and ShowdownCloneDB.settings.defaultLevel) or 100
    frame.levelBox:SetText(tostring(defaultLevel))
    frame.levelBox:SetAutoFocus(false)
    frame.levelBox:SetScript("OnTextChanged", function(self)
        local v = tonumber(self:GetText())
        if v then
            v = math.max(1, math.min(Stats.MAX_LEVEL, math.floor(v)))
            ShowdownCloneDB.settings = ShowdownCloneDB.settings or {}
            ShowdownCloneDB.settings.defaultLevel = v
            if frame.selectedSpeciesId then
                TeamBuilder:RefreshMovePicker(frame.selectedSpeciesId)
            end
        end
    end)

    local levelLabel = browserFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    levelLabel:SetPoint("LEFT", frame.levelBox, "RIGHT", 4, 0)
    levelLabel:SetText("level")

    local browserScroll = CreateFrame("ScrollFrame", "ShowdownCloneBrowserScroll", browserFrame, "UIPanelScrollFrameTemplate")
    browserScroll:SetPoint("TOPLEFT", 8, -40)
    browserScroll:SetPoint("BOTTOMRIGHT", -26, 40)
    local browserContent = CreateFrame("Frame")
    browserContent:SetSize(390, 600)
    browserScroll:SetScrollChild(browserContent)
    frame.browserContent = browserContent
    frame.browserButtons = {}

    -- Move picker row (bottom of browser)
    frame.movePicker = CreateFrame("Frame", nil, browserFrame, "InsetFrameTemplate3")
    frame.movePicker:SetSize(400, 32)
    frame.movePicker:SetPoint("BOTTOMLEFT", 8, 6)
    frame.moveButtons = {}
    for i = 1, 4 do
        local btn = CreateFrame("Button", nil, frame.movePicker, "UIPanelButtonTemplate")
        btn:SetSize(92, 22)
        btn:SetPoint("LEFT", 8 + (i - 1) * 98, 5)
        btn:Hide()
        frame.moveButtons[i] = btn
    end

    frame.selectedSpeciesId = nil
    frame.editingSlot = nil

    frame:Hide()
end

function TeamBuilder:Refresh()
    local team = getTeam()
    for i = 1, BattleEngine.MAX_TEAM do
        local slot = frame.teamSlots[i]
        local rm = frame.removeButtons[i]
        local entry = team[i]
        if entry then
            local species = PokemonData.get(entry.id)
            local name = entry.nickname or (species and species.name or "?")
            local moveNames = {}
            for _, mid in ipairs(entry.moves or {}) do
                moveNames[#moveNames + 1] = Moves.displayName(mid)
            end
            slot:SetText(string.format("#%d %s Lv%d\n    %s", i, name, entry.level, table.concat(moveNames, ", ")))
            slot:SetNormalFontObject("GameFontNormalLeft")
            rm:Show()
        else
            slot:SetText(string.format("#%d (empty)\n    click to add a Pokemon", i))
            slot:SetNormalFontObject("GameFontNormalLeft")
            rm:Hide()
        end
    end
    -- Show the starter-team button only when the team is completely empty
    if frame.starterBtn then
        if #team == 0 then frame.starterBtn:Show() else frame.starterBtn:Hide() end
    end
    TeamBuilder:RefreshBrowser()
end

function TeamBuilder:RefreshBrowser()
    local content = frame.browserContent
    for _, btn in ipairs(frame.browserButtons) do btn:Hide() end
    frame.browserButtons = {}
    local y = -4
    local count = 0
    local total = 0
    for _, species in ipairs(speciesList()) do
        if searchText == "" or species.name:lower():find(searchText, 1, true) then
            total = total + 1
            if count < 60 then
                local btn = CreateFrame("Button", nil, content)
                btn:SetSize(370, 22)
                btn:SetPoint("TOPLEFT", 4, y)
                btn:SetText(string.format("%03d %s (%s)", species.id, species.name, table.concat(species.types, "/")))
                btn:SetNormalFontObject("GameFontNormalLeft")
                btn:SetHighlightFontObject("GameFontHighlightLeft")
                btn:SetScript("OnClick", function()
                    frame.selectedSpeciesId = species.id
                    for _, b in ipairs(frame.browserButtons) do b:UnlockHighlight() end
                    btn:LockHighlight()
                    TeamBuilder:RefreshMovePicker(species.id)
                end)
                btn:Show()
                frame.browserButtons[#frame.browserButtons + 1] = btn
                y = y - 24
                count = count + 1
            end
        end
    end
    -- "N more" hint when the list is truncated
    if total > count then
        local more = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        more:SetPoint("TOPLEFT", 4, y)
        more:SetText(string.format("... %d more — refine your search", total - count))
        more:SetTextColor(0.8, 0.8, 0.4)
        y = y - 20
    end
    content:SetHeight(math.max(400, count * 24 + math.max(0, total - count) * 20 + 8))
end

-- Show the legal moves for the selected species as 4 toggle buttons.
function TeamBuilder:RefreshMovePicker(speciesId)
    local level = tonumber(frame.levelBox:GetText()) or 100
    level = math.max(1, math.min(Stats.MAX_LEVEL, level))
    local species = PokemonData.get(speciesId)
    local legal = BattleEngine.legalMoves(species, level)
    frame.selectedMoves = frame.selectedMoves or {}
    -- keep only still-legal selections
    local kept = {}
    for _, id in ipairs(frame.selectedMoves) do
        for _, l in ipairs(legal) do
            if l == id then kept[#kept + 1] = id break end
        end
    end
    frame.selectedMoves = kept
    -- store legal list for the dropdown
    frame.legalMoves = legal
    for i = 1, 4 do
        local btn = frame.moveButtons[i]
        local sel = frame.selectedMoves[i]
        if sel then
            btn:SetText(Moves.displayName(sel))
            btn:Show()
        else
            btn:SetText("(move " .. i .. ")")
            btn:Show()
        end
        btn:SetScript("OnClick", function()
            TeamBuilder:OpenMoveDropdown(i, legal)
        end)
    end
end

function TeamBuilder:OpenMoveDropdown(slotIndex, legal)
    local menu = { { text = "Choose a move", isTitle = true, notCheckable = true } }
    for _, id in ipairs(legal) do
        local mv = Moves.get(id)
        local label = Moves.displayName(id)
        if mv then
            local cat = mv.cat or Types.categoryFor(mv.type) or "physical"
            label = string.format("%s (%s %d/%d)", label, cat, mv.power or 0, mv.acc or 100)
        end
        menu[#menu + 1] = {
            text = label,
            notCheckable = true,
            func = function()
                -- replace or append up to 4
                frame.selectedMoves = frame.selectedMoves or {}
                frame.selectedMoves[slotIndex] = id
                -- trim trailing nils
                while #frame.selectedMoves > 0 and not frame.selectedMoves[#frame.selectedMoves] do
                    table.remove(frame.selectedMoves)
                end
                TeamBuilder:RefreshMovePicker(frame.selectedSpeciesId)
            end,
        }
    end
    if frame.selectedMoves and frame.selectedMoves[slotIndex] then
        menu[#menu + 1] = { text = "---", notCheckable = true, disabled = true }
        menu[#menu + 1] = {
            text = "Remove this move",
            notCheckable = true,
            func = function()
                frame.selectedMoves[slotIndex] = nil
                while #frame.selectedMoves > 0 and not frame.selectedMoves[#frame.selectedMoves] do
                    table.remove(frame.selectedMoves)
                end
                TeamBuilder:RefreshMovePicker(frame.selectedSpeciesId)
            end,
        }
    end
    menu[#menu + 1] = { text = "Cancel", notCheckable = true, func = function() end }
    EasyMenu(menu, CreateFrame("Frame", "ShowdownCloneMoveMenu", UIParent, "UIDropDownMenuTemplate"), "cursor", 0, 0, "MENU")
end

-- Add the selected species (with chosen moves) to the editing slot.
function TeamBuilder:EditSlot(slotIndex)
    frame.editingSlot = slotIndex
    if not frame.selectedSpeciesId then
        print("|cffff0000Showdown:|r Select a Pokemon from the list first.")
        return
    end
    local team = getTeam()
    local existing = team[slotIndex]
    -- Confirm before overwriting a filled slot (one misclick shouldn't
    -- destroy a carefully-built Pokemon)
    if existing then
        local species = PokemonData.get(existing.id)
        local name = species and species.name or "?"
        StaticPopupDialogs["SHOWDOWN_CLONE_OVERWRITE"] = {
            text = string.format("Replace %s (slot #%d) with the selected Pokemon?", name, slotIndex),
            button1 = "Replace",
            button2 = "Cancel",
            OnAccept = function()
                TeamBuilder:CommitSlot(slotIndex)
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("SHOWDOWN_CLONE_OVERWRITE")
        return
    end
    self:CommitSlot(slotIndex)
end

function TeamBuilder:CommitSlot(slotIndex)
    local level = tonumber(frame.levelBox:GetText()) or 100
    level = math.max(1, math.min(Stats.MAX_LEVEL, level))
    local moves = frame.selectedMoves and #frame.selectedMoves > 0 and frame.selectedMoves or nil
    local p = BattleEngine.newPokemon(frame.selectedSpeciesId, level, { moves = moves })
    local team = getTeam()
    team[slotIndex] = Serializer.encodePokemon(p)
    -- compact (remove holes)
    local compact = {}
    for _, e in ipairs(team) do if e then compact[#compact + 1] = e end end
    setTeam(compact)
    self:Refresh()
end

function TeamBuilder:RemoveSlot(slotIndex)
    local team = getTeam()
    local existing = team[slotIndex]
    if not existing then return end
    local species = PokemonData.get(existing.id)
    local name = species and species.name or "this Pokemon"
    StaticPopupDialogs["SHOWDOWN_CLONE_REMOVE"] = {
        text = string.format("Remove %s from slot #%d?", name, slotIndex),
        button1 = "Remove",
        button2 = "Cancel",
        OnAccept = function()
            local t = getTeam()
            table.remove(t, slotIndex)
            setTeam(t)
            TeamBuilder:Refresh()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("SHOWDOWN_CLONE_REMOVE")
end

-- Fill the team with the default starter team (Bulbasaur/Charmander/Squirtle).
-- Explicit action only — never a silent write to SavedVariables.
function TeamBuilder:UseStarterTeam()
    local team = {}
    for _, id in ipairs({ 1, 4, 7 }) do
        local p = BattleEngine.newPokemon(id, 100)
        team[#team + 1] = Serializer.encodePokemon(p)
    end
    setTeam(team)
    self:Refresh()
end

function TeamBuilder:GetLiveTeam()
    local saved = getTeam()
    return Serializer.decodeTeam(saved, BattleEngine)
end

_G["ShowdownClone_TeamBuilder"] = TeamBuilder
return TeamBuilder
