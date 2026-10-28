local BattleUI = {}

local Moves = require("Core.Data.Moves")
local BattleEngine = require("Core.BattleEngine")

local frame
local currentBattle = nil
local pendingChoice = nil
local mode = nil -- "bot" | "pvp"
local context = nil

local function hpText(p)
    return string.format("%d/%d", p.hp, p.maxHp)
end

local function statusText(p)
    if p.status then return " [" .. p.status .. "]" end
    return ""
end

function BattleUI:IsOpen()
    return frame and frame:IsShown()
end

function BattleUI:Open(battle, battleMode, ctx)
    currentBattle = battle
    mode = battleMode
    context = ctx or {}
    if not frame then self:Build() end
    self:Refresh()
    frame:Show()
end

function BattleUI:Close()
    if frame then frame:Hide() end
    currentBattle = nil
end

function BattleUI:Hide()
    if frame then frame:Hide() end
end

function BattleUI:Show()
    if frame then frame:Show() end
end

function BattleUI:Build()
    frame = CreateFrame("Frame", "ShowdownCloneBattleFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(560, 420)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame.TitleBg:SetHeight(30)
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOPLEFT", frame.TitleBg, "TOPLEFT", 12, -8)
    frame.title:SetText("Showdown Clone - Battle")

    -- Close button + Esc-to-close
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", frame.TitleBg, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function()
        -- Hiding mid-battle doesn't forfeit; the battle continues in the
        -- background and the player can reopen it. We just hide the window.
        BattleUI:Hide()
    end)
    frame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            BattleUI:Hide()
            self:SetPropagateKeyboardInput(false)
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    frame:SetPropagateKeyboardInput(true)
    tinsert(UISpecialFrames, frame:GetName())

    -- Foe area (top)
    frame.foeName = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.foeName:SetPoint("TOPLEFT", 16, -40)
    frame.foeHp = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.foeHp:SetPoint("TOPLEFT", frame.foeName, "BOTTOMLEFT", 0, -4)
    frame.foeBar = self:MakeHpBar(frame, "TOPLEFT", 16, -80, 240)
    frame.foeBarText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.foeBarText:SetPoint("LEFT", frame.foeBar, "RIGHT", 8, 0)

    -- Player area (bottom)
    frame.playerName = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.playerName:SetPoint("BOTTOMLEFT", 16, 150)
    frame.playerHp = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.playerHp:SetPoint("TOPLEFT", frame.playerName, "BOTTOMLEFT", 0, -4)
    frame.playerBar = self:MakeHpBar(frame, "BOTTOMLEFT", 16, 110, 240)
    frame.playerBarText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.playerBarText:SetPoint("LEFT", frame.playerBar, "RIGHT", 8, 0)

    -- Log (right side)
    local logFrame = CreateFrame("Frame", nil, frame, "InsetFrameTemplate3")
    logFrame:SetSize(280, 300)
    logFrame:SetPoint("TOPRIGHT", -12, -32)
    local logScroll = CreateFrame("ScrollFrame", "ShowdownCloneBattleLog", logFrame, "UIPanelScrollFrameTemplate")
    logScroll:SetPoint("TOPLEFT", 4, -8)
    logScroll:SetPoint("BOTTOMRIGHT", -26, 6)
    local logContent = CreateFrame("Frame")
    logContent:SetSize(250, 600)
    logContent.height = 0
    logScroll:SetScrollChild(logContent)
    frame.logContent = logContent
    frame.logScroll = logScroll

    -- Move buttons (bottom right)
    frame.moveButtons = {}
    for i = 1, 4 do
        local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        btn:SetSize(130, 28)
        local x = 300 + ((i - 1) % 2) * 135
        local y = -180 - math.floor((i - 1) / 2) * 32
        btn:SetPoint("TOPLEFT", x, y)
        btn:SetScript("OnClick", function()
            BattleUI:ChooseMove(i)
        end)
        btn:SetScript("OnEnter", function(self)
            local slot = my and my.moves[i]
            if not slot then return end
            local mv = Moves.get(slot.id)
            if not mv then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(Moves.displayName(slot.id), 1, 1, 1)
            GameTooltip:AddLine(string.format("Type: %s  Power: %d  Acc: %d%%",
                mv.type, mv.power or 0, mv.acc or 100), 0.8, 0.8, 0.8)
            GameTooltip:AddLine(string.format("PP: %d/%d", slot.pp, slot.maxPp or mv.pp), 0.8, 0.8, 0.8)
            local cat = mv.cat or "physical"
            GameTooltip:AddLine("Category: " .. cat, 0.6, 0.8, 1)
            if mv.effect then
                local e = mv.effect
                local parts = {}
                if e.status then parts[#parts + 1] = e.status .. (e.statusChance and e.statusChance < 100 and (" (" .. e.statusChance .. "%)") or "") end
                if e.boost then parts[#parts + 1] = "boost " .. e.boost.stat .. (e.boost.stages > 0 and "+" or "") .. e.boost.stages end
                if e.recoil then parts[#parts + 1] = math.floor(e.recoil * 100) .. "% recoil" end
                if e.drain then parts[#parts + 1] = math.floor(e.drain * 100) .. "% drain" end
                if e.flinchChance then parts[#parts + 1] = e.flinchChance .. "% flinch" end
                if e.highCrit then parts[#parts + 1] = "high crit" end
                if #parts > 0 then
                    GameTooltip:AddLine("Effect: " .. table.concat(parts, ", "), 1, 0.8, 0.4)
                end
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        frame.moveButtons[i] = btn
    end

    -- Switch + Forfeit buttons
    frame.switchBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.switchBtn:SetSize(90, 26)
    frame.switchBtn:SetPoint("TOPLEFT", 300, -290)
    frame.switchBtn:SetText("Switch")
    frame.switchBtn:SetScript("OnClick", function() BattleUI:ShowSwitchMenu() end)

    frame.forfeitBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.forfeitBtn:SetSize(90, 26)
    frame.forfeitBtn:SetPoint("LEFT", frame.switchBtn, "RIGHT", 8, 0)
    frame.forfeitBtn:SetText("Forfeit")
    frame.forfeitBtn:SetScript("OnClick", function() BattleUI:Forfeit() end)

    frame.statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.statusText:SetPoint("BOTTOM", 0, 12)

    frame:Hide()
end

function BattleUI:MakeHpBar(parent, point, x, y, width)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetSize(width, 14)
    bar:SetPoint(point, x, y)
    bar:SetStatusBarTexture("Interface/TargetingFrame/UI-StatusBar")
    bar:SetStatusBarColor(0.2, 0.8, 0.2) -- green; Refresh recolors by HP fraction
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(100)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.2, 0.2, 0.2, 1)
    return bar
end

-- Green/yellow/red HP bar color by remaining fraction
function BattleUI:ColorHpBar(bar, hp, maxHp)
    local frac = maxHp > 0 and (hp / maxHp) or 0
    if frac > 0.5 then
        bar:SetStatusBarColor(0.2, 0.8, 0.2)
    elseif frac > 0.2 then
        bar:SetStatusBarColor(0.9, 0.8, 0.1)
    else
        bar:SetStatusBarColor(0.9, 0.2, 0.2)
    end
end

function BattleUI:AppendLog(msg)
    if not frame then return end
    local content = frame.logContent
    local fs = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", content, "TOPLEFT", 4, content.height)
    fs:SetWidth(240)
    fs:SetJustifyH("LEFT")
    fs:SetText(msg)
    content.height = content.height - 14
    content:SetHeight(math.abs(content.height) + 14)
    frame.logScroll:UpdateScrollChildRect()
    frame.logScroll:SetVerticalScroll(frame.logScroll:GetVerticalScrollRange() or 0)
end

-- Determine which side the local player controls.
function BattleUI:MySide()
    if not currentBattle then return 1 end
    if mode == "pvp" and ShowdownClone.state.pvp.activeDuel
        and not ShowdownClone.state.pvp.activeDuel.isChallenger then
        return 2
    end
    return 1
end

function BattleUI:Refresh()
    if not currentBattle then return end
    local b = currentBattle
    local mySide = self:MySide()
    local foeSide = b:opponentOf(mySide)
    local my = b:active(mySide)
    local foe = b:active(foeSide)
    if my then
        frame.playerName:SetText(my.name .. " Lv" .. my.level .. statusText(my))
        frame.playerHp:SetText(hpText(my))
        frame.playerBar:SetMinMaxValues(0, my.maxHp)
        frame.playerBar:SetValue(my.hp)
        frame.playerBarText:SetText(hpText(my))
        self:ColorHpBar(frame.playerBar, my.hp, my.maxHp)
    end
    if foe then
        frame.foeName:SetText(foe.name .. " Lv" .. foe.level .. statusText(foe))
        frame.foeHp:SetText(hpText(foe))
        frame.foeBar:SetMinMaxValues(0, foe.maxHp)
        frame.foeBar:SetValue(foe.hp)
        frame.foeBarText:SetText(hpText(foe))
        self:ColorHpBar(frame.foeBar, foe.hp, foe.maxHp)
    end
    -- Enable move buttons only when we actually need a player choice.
    -- This prevents the PvP double-click bug where a second click would
    -- overwrite duel.myChoice and desync the two clients.
    local awaiting = false
    if not b.over then
        awaiting = true
        if ShowdownClone and ShowdownClone.state then
            awaiting = ShowdownClone.state.awaitingPlayerChoice == true
        end
    end
    for i = 1, 4 do
        local btn = frame.moveButtons[i]
        local slot = my and my.moves[i]
        if slot then
            btn:SetText(Moves.displayName(slot.id) .. " (" .. slot.pp .. ")")
            if awaiting and slot.pp > 0 then
                btn:Enable()
            else
                btn:Disable()
            end
        else
            btn:SetText("--")
            btn:Disable()
        end
    end
    if b.over then
        local msg
        if b.winner == nil then msg = "Draw!"
        elseif b.winner == mySide then msg = "You won!"
        else msg = "You lost!" end
        frame.statusText:SetText(msg)
        for i = 1, 4 do frame.moveButtons[i]:Disable() end
        frame.switchBtn:Disable()
    else
        if awaiting then
            frame.statusText:SetText(context.flavor or "Choose a move!")
        else
            frame.statusText:SetText("Waiting for opponent...")
        end
        frame.switchBtn:Enable()
    end
end

function BattleUI:ChooseMove(index)
    if not currentBattle or currentBattle.over then return end
    -- Guard: don't accept a second choice while we're waiting (PvP lockstep)
    if ShowdownClone and ShowdownClone.state
        and not ShowdownClone.state.awaitingPlayerChoice then
        return
    end
    pendingChoice = { type = "move", index = index }
    if ShowdownClone and ShowdownClone.OnPlayerChoice then
        ShowdownClone.OnPlayerChoice(pendingChoice)
    end
    self:Refresh()
end

function BattleUI:ChooseSwitch(index)
    if not currentBattle or currentBattle.over then return end
    if ShowdownClone and ShowdownClone.state
        and not ShowdownClone.state.awaitingPlayerChoice then
        return
    end
    pendingChoice = { type = "switch", index = index }
    if ShowdownClone and ShowdownClone.OnPlayerChoice then
        ShowdownClone.OnPlayerChoice(pendingChoice)
    end
    self:Refresh()
end

function BattleUI:Forfeit()
    if not currentBattle or currentBattle.over then return end
    pendingChoice = { type = "forfeit" }
    if ShowdownClone and ShowdownClone.OnPlayerChoice then
        ShowdownClone.OnPlayerChoice(pendingChoice)
    end
    self:Refresh()
end

function BattleUI:ShowSwitchMenu()
    if not currentBattle then return end
    local mySide = self:MySide()
    local team = currentBattle.sides[mySide].team
    local menu = { { text = "Switch Pokemon", isTitle = true, notCheckable = true } }
    for i, p in ipairs(team) do
        if i ~= currentBattle.sides[mySide].active and not p.fainted then
            menu[#menu + 1] = {
                text = p.name .. " Lv" .. p.level .. " (" .. hpText(p) .. ")",
                notCheckable = true,
                func = function() BattleUI:ChooseSwitch(i) end,
            }
        end
    end
    menu[#menu + 1] = { text = "Cancel", notCheckable = true, func = function() end }
    EasyMenu(menu, CreateFrame("Frame", "ShowdownCloneSwitchMenu", UIParent, "UIDropDownMenuTemplate"), "cursor", 0, 0, "MENU")
end

function BattleUI:GetPendingChoice()
    return pendingChoice
end

function BattleUI:ClearPendingChoice()
    pendingChoice = nil
end

_G["ShowdownClone_BattleUI"] = BattleUI
return BattleUI
