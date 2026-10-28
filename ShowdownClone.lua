ShowdownClone = ShowdownClone or {}

local ADDON = "ShowdownClone"

local BattleEngine = require("Core.BattleEngine")
local PokemonData = require("Core.Data.Pokemon")
local Moves = require("Core.Data.Moves")
local Bot = require("Core.Bot")
local PRNG = require("Core.Util.PRNG")
local Serializer = require("Core.Util.Serializer")
local Net = require("Core.Net")

local TeamBuilder = require("UI.TeamBuilder")
local BattleUI = require("UI.BattleUI")
local MinimapButton = require("UI.MinimapButton")
local Options = require("UI.Options")

ShowdownClone.TeamBuilder = TeamBuilder
ShowdownClone.BattleUI = BattleUI
ShowdownClone.MinimapButton = MinimapButton
ShowdownClone.Options = Options

local eventFrame = CreateFrame("Frame")
ShowdownClone.eventFrame = eventFrame

local state = {
    rng = nil,
    activeBattle = nil,       -- BattleEngine instance
    battleMode = nil,         -- "bot" | "pvp"
    battleContext = nil,      -- bot def or pvp info
    awaitingPlayerChoice = false,
    battleUiHidden = false,   -- true if the battle window was auto-hidden on combat
    pvp = {
        pendingChallenge = nil,    -- { from, to, teamSize }
        challengeExpiry = nil,     -- GetTime() when the pending challenge expires
        challengeTimer = nil,      -- timer handle for the expiry check
        activeDuel = nil,          -- { opponent, seed, isChallenger, myChoice, foeChoice, turn }
    },
}
ShowdownClone.state = state

-- How long a duel challenge stays open waiting for a response (seconds)
local CHALLENGE_TIMEOUT = 60

local function printMsg(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[Showdown]|r " .. msg)
end
ShowdownClone.Print = printMsg

function ShowdownClone:EnsureRng()
    if not state.rng then state.rng = PRNG.new(PRNG.randomSeed()) end
    return state.rng
end

function ShowdownClone:OnInitialize()
    ShowdownCloneDB = ShowdownCloneDB or {}
    ShowdownCloneDB.team = ShowdownCloneDB.team or {}
    ShowdownCloneDB.settings = ShowdownCloneDB.settings or {}
    local s = ShowdownCloneDB.settings
    if s.minimapShown == nil then s.minimapShown = true end
    if s.defaultLevel == nil then s.defaultLevel = 100 end
    if s.loadMessage == nil then s.loadMessage = true end
    ShowdownCloneDB.minimap = ShowdownCloneDB.minimap or { angle = 45 }
    ShowdownCloneDB.record = ShowdownCloneDB.record or { wins = 0, losses = 0 }
    state.rng = PRNG.new(PRNG.randomSeed())
end

function ShowdownClone:OnEnable()
    Options:Register()
    MinimapButton:Create(function()
        TeamBuilder:Show()
    end)
    -- Respect the minimap setting
    if ShowdownCloneDB.settings and ShowdownCloneDB.settings.minimapShown == false then
        MinimapButton:Hide()
    end

    eventFrame:RegisterEvent("ADDON_LOADED")
    eventFrame:RegisterEvent("CHAT_MSG_ADDON")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED") -- entering combat
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")  -- leaving combat

    RegisterAddonMessagePrefix(Net.PREFIX)

    SLASH_SHOWDOWNCLONE1 = "/showdown"
    SLASH_SHOWDOWNCLONE2 = "/sdc"
    SlashCmdList["SHOWDOWNCLONE"] = function(msg)
        ShowdownClone:SlashHandler(msg)
    end

    self:OnInitialize()
    local s = ShowdownCloneDB.settings or {}
    if s.loadMessage ~= false then
        printMsg("Loaded. Type |cffffff00/showdown|r to build your team, |cffffff00/showdown bot|r to battle a bot, or |cffffff00/showdown duel <name>|r to PvP.")
    end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == ADDON then
            ShowdownClone:OnEnable()
        end
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, text, _, sender = ...
        if prefix == Net.PREFIX then
            ShowdownClone:OnAddonMessage(sender, text)
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        ShowdownClone:OnEnterCombat()
    elseif event == "PLAYER_REGEN_ENABLED" then
        ShowdownClone:OnLeaveCombat()
    end
end)

function ShowdownClone:SlashHandler(msg)
    local args = {}
    for word in (msg or ""):gmatch("%S+") do args[#args + 1] = word end
    local cmd = (args[1] or "ui"):lower()
    table.remove(args, 1)

    if cmd == "ui" or cmd == "team" then
        if cmd == "team" and #args == 0 then
            self:PrintTeam()
        else
            TeamBuilder:Show()
        end
    elseif cmd == "starter" then
        self:UseStarterTeam()
    elseif cmd == "bot" then
        local idx = tonumber(args[1])
        self:StartBotBattle(idx)
    elseif cmd == "bots" then
        self:ListBots()
    elseif cmd == "duel" then
        local target = table.concat(args, " ")
        self:ChallengePlayer(target)
    elseif cmd == "accept" then
        self:AcceptChallenge()
    elseif cmd == "decline" then
        self:DeclineChallenge()
    elseif cmd == "cancel" then
        self:CancelChallenge()
    elseif cmd == "record" then
        local r = ShowdownCloneDB.record or { wins = 0, losses = 0 }
        printMsg(string.format("Record: %d wins, %d losses", r.wins, r.losses))
    elseif cmd == "help" then
        self:PrintHelp()
    else
        self:PrintHelp()
    end
end

function ShowdownClone:PrintHelp()
    printMsg("Commands:")
    printMsg("/showdown ui - open the team builder")
    printMsg("/showdown starter - get the default starter team (Bulbasaur/Charmander/Squirtle)")
    printMsg("/showdown bot [n] - battle a practice bot (list with /showdown bots)")
    printMsg("/showdown bots - list practice bots")
    printMsg("/showdown duel <player> - PvP duel")
    printMsg("/showdown accept|decline - respond to a duel")
    printMsg("/showdown cancel - cancel your pending duel challenge")
    printMsg("/showdown team - print your team")
    printMsg("/showdown record - show your win/loss record")
end

function ShowdownClone:PrintTeam()
    local team = self:GetLiveTeam()
    if #team == 0 then
        printMsg("Your team is empty. Open the team builder with /showdown ui.")
        return
    end
    printMsg("Your team:")
    for i, p in ipairs(team) do
        local moveNames = {}
        for _, m in ipairs(p.moves) do moveNames[#moveNames + 1] = Moves.displayName(m.id) end
        printMsg(string.format("  %d. %s Lv%d - %s", i, p.name, p.level, table.concat(moveNames, ", ")))
    end
end

-- Live team accessor. A Showdown team is exactly what the builder saved.
-- Returns an empty list (not a default team) if the player hasn't built one;
-- the starter team is only ever created via an explicit /showdown starter
-- or the "Use starter team" button in the builder.
function ShowdownClone:GetLiveTeam()
    local saved = ShowdownCloneDB.team or {}
    return Serializer.decodeTeam(saved, BattleEngine)
end

-- Explicitly give the player the default starter team.
function ShowdownClone:UseStarterTeam()
    local team = {}
    for _, id in ipairs({ 1, 4, 7 }) do
        team[#team + 1] = Serializer.encodePokemon(BattleEngine.newPokemon(id, 100))
    end
    ShowdownCloneDB.team = team
    printMsg("Starter team ready: Bulbasaur, Charmander, Squirtle (Lv100). Customize with /showdown ui.")
end

function ShowdownClone:SaveTeam(team)
    ShowdownCloneDB.team = Serializer.encodeTeam(team)
end

-- List practice bots
function ShowdownClone:ListBots()
    printMsg("Practice bots:")
    for i, def in ipairs(Bot.TEAMS) do
        printMsg(string.format("  %d. %s - %s (%d Pokemon)", i, def.name, def.flavor, #def.team))
    end
    printMsg("Battle one with: /showdown bot <number>")
end

-- Bot battle (practice)
function ShowdownClone:StartBotBattle(index)
    if not self:CanStartBattle() then return end
    local team = self:GetLiveTeam()
    if #team == 0 then
        printMsg("You need a team first! Use /showdown starter for a default team, or /showdown ui to build one.")
        return
    end
    local idx, def
    if index then
        idx = index
        def = Bot.get(index)
    else
        idx, def = Bot.random(state.rng, state.battleContext and state.battleContext.botIndex)
    end
    printMsg(def.name .. " challenges you! \"" .. def.flavor .. "\"")
    local botTeam = Bot.buildTeam(def)
    local seed = state.rng:nextInt(1, 4294967295)
    local battle = BattleEngine.newBattle(team, botTeam, {
        mode = "bot",
        seed = seed,
        nameA = UnitName("player"),
        nameB = def.name,
        onLog = function(m) BattleUI:AppendLog(m) end,
    })
    state.activeBattle = battle
    state.battleMode = "bot"
    state.battleContext = { bot = def, botIndex = idx }
    state.awaitingPlayerChoice = true
    BattleUI:Open(battle, "bot", { flavor = def.name .. " wants to battle!" })
end

-- Player chose an action (move/switch/forfeit)
function ShowdownClone.OnPlayerChoice(choice)
    local b = state.activeBattle
    if not b or b.over then return end

    -- Forfeit: end immediately, notify opponent in PvP
    if choice.type == "forfeit" then
        if state.battleMode == "pvp" and state.pvp.activeDuel then
            local msg = Net.buildResign(UnitName("player"), state.pvp.activeDuel.opponent)
            ShowdownClone:SendAddonMessage(msg, state.pvp.activeDuel.opponent)
        end
        b.over = true
        b.winner = (state.battleMode == "pvp" and state.pvp.activeDuel and not state.pvp.activeDuel.isChallenger) and 1 or 2
        BattleUI:AppendLog("You forfeited the battle!")
        BattleUI:Refresh()
        if state.battleMode == "pvp" then
            printMsg("You forfeited the duel.")
            state.pvp.activeDuel = nil
        end
        ShowdownClone:OnBattleEnd(b)
        return
    end

    if state.battleMode == "pvp" and state.pvp.activeDuel then
        local duel = state.pvp.activeDuel
        duel.myChoice = choice
        local msg = Net.buildChoice(UnitName("player"), duel.opponent, duel.turn, choice)
        ShowdownClone:SendAddonMessage(msg, duel.opponent)
        BattleUI:AppendLog("Waiting for " .. duel.opponent .. "...")
        state.awaitingPlayerChoice = false
        ShowdownClone:MaybeRunPvpTurn()
        return
    end

    -- bot mode: player choice vs bot choice
    state.awaitingPlayerChoice = false
    local botChoice = Bot.chooseMove(b, 2)
    local over = b:runTurn({ [1] = choice, [2] = botChoice })
    BattleUI:Refresh()
    if over then
        ShowdownClone:OnBattleEnd(b)
    else
        state.awaitingPlayerChoice = true
    end
end

function ShowdownClone:OnBattleEnd(b)
    state.activeBattle = nil
    state.awaitingPlayerChoice = false
    state.battleUiHidden = false
    BattleUI:Refresh()
    local mySide = (state.battleMode == "pvp" and state.pvp.activeDuel and not state.pvp.activeDuel.isChallenger) and 2 or 1
    if b.winner == mySide then
        ShowdownCloneDB.record.wins = (ShowdownCloneDB.record.wins or 0) + 1
        printMsg("You won! Record: " .. ShowdownCloneDB.record.wins .. "W / " .. (ShowdownCloneDB.record.losses or 0) .. "L")
    elseif b.winner ~= nil then
        ShowdownCloneDB.record.losses = (ShowdownCloneDB.record.losses or 0) + 1
        printMsg("You lost. Record: " .. (ShowdownCloneDB.record.wins or 0) .. "W / " .. ShowdownCloneDB.record.losses .. "L")
    else
        printMsg("The battle was a draw.")
    end
end

----------------------------------------------------------------------
-- Combat safety: refuse to start battles in combat; auto-hide the
-- battle window while in combat and restore it afterwards.
----------------------------------------------------------------------
function ShowdownClone:OnEnterCombat()
    if state.activeBattle and BattleUI:IsOpen() then
        BattleUI:Hide()
        state.battleUiHidden = true
    end
end

function ShowdownClone:OnLeaveCombat()
    if state.battleUiHidden and state.activeBattle then
        BattleUI:Show()
        BattleUI:Refresh()
    end
    state.battleUiHidden = false
end

-- Returns true if the player can start a battle right now.
function ShowdownClone:CanStartBattle()
    if InCombatLockdown() then
        printMsg("You can't start a Pokemon battle while in combat!")
        return false
    end
    return true
end

-- PvP
function ShowdownClone:ChallengePlayer(targetName)
    if not targetName or targetName == "" then
        printMsg("Usage: /showdown duel <player name>")
        return
    end
    if not self:CanStartBattle() then return end
    local myName = UnitName("player")
    if targetName:lower() == myName:lower() then
        printMsg("You can't duel yourself!")
        return
    end
    local team = self:GetLiveTeam()
    if #team == 0 then
        printMsg("You need a team first! Use /showdown starter for a default team, or /showdown ui to build one.")
        return
    end
    local msg = Net.buildChallenge(myName, targetName, #team)
    self:SendAddonMessage(msg, targetName)
    state.pvp.pendingChallenge = { from = myName, to = targetName, teamSize = #team }
    state.pvp.challengeExpiry = GetTime() + CHALLENGE_TIMEOUT
    self:StartChallengeTimer()
    printMsg("Challenge sent to " .. targetName .. ". Waiting for response... (expires in " .. CHALLENGE_TIMEOUT .. "s, or /showdown cancel)")
end

-- Poll the pending outgoing challenge; expire it after CHALLENGE_TIMEOUT.
function ShowdownClone:StartChallengeTimer()
    if state.pvp.challengeTimer then return end
    local timer = CreateFrame("Frame")
    state.pvp.challengeTimer = timer
    timer:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = (self.elapsed or 0) + elapsed
        if self.elapsed < 1 then return end
        self.elapsed = 0
        local pvp = state.pvp
        if not pvp.pendingChallenge or not pvp.challengeExpiry then
            self:Hide()
            state.pvp.challengeTimer = nil
            return
        end
        if GetTime() >= pvp.challengeExpiry then
            printMsg("Your duel challenge to " .. pvp.pendingChallenge.to .. " expired (no response).")
            pvp.pendingChallenge = nil
            pvp.challengeExpiry = nil
            self:Hide()
            state.pvp.challengeTimer = nil
        end
    end)
end

function ShowdownClone:StopChallengeTimer()
    if state.pvp.challengeTimer then
        state.pvp.challengeTimer:Hide()
        state.pvp.challengeTimer = nil
    end
    state.pvp.challengeExpiry = nil
end

-- /showdown cancel — cancel our own outgoing challenge
function ShowdownClone:CancelChallenge()
    local ch = state.pvp.pendingChallenge
    if not ch then
        printMsg("No pending challenge to cancel.")
        return
    end
    local myName = UnitName("player")
    local msg = Net.buildChallengeResponse(myName, ch.to, false, "cancelled")
    self:SendAddonMessage(msg, ch.to)
    state.pvp.pendingChallenge = nil
    self:StopChallengeTimer()
    printMsg("Challenge to " .. ch.to .. " cancelled.")
end

function ShowdownClone:AcceptChallenge()
    local ch = state.pvp.pendingChallenge
    if not ch then
        printMsg("No pending challenge.")
        return
    end
    if not self:CanStartBattle() then
        printMsg("You can't accept a duel while in combat!")
        return
    end
    local myName = UnitName("player")
    local msg = Net.buildChallengeResponse(myName, ch.from, true)
    self:SendAddonMessage(msg, ch.from)
    state.pvp.pendingChallenge = nil
    printMsg("Challenge accepted! Waiting for the duel to start...")
end

function ShowdownClone:DeclineChallenge()
    local ch = state.pvp.pendingChallenge
    if not ch then
        printMsg("No pending challenge.")
        return
    end
    local myName = UnitName("player")
    local msg = Net.buildChallengeResponse(myName, ch.from, false, "declined")
    self:SendAddonMessage(msg, ch.from)
    state.pvp.pendingChallenge = nil
    printMsg("Challenge declined.")
end

function ShowdownClone:StartDuelAsChallenger(opponentName)
    local team = self:GetLiveTeam()
    local seed = state.rng:nextInt(1, 4294967295)
    local snapshot = Serializer.encodeTeam(team)
    local msg = Net.buildStart(UnitName("player"), opponentName, seed, snapshot)
    self:SendAddonMessage(msg, opponentName)
    local opponentTeam = Serializer.decodeTeam(snapshot, BattleEngine)
    local battle = BattleEngine.newBattle(team, opponentTeam, {
        mode = "pvp",
        seed = seed,
        nameA = UnitName("player"),
        nameB = opponentName,
        onLog = function(m) BattleUI:AppendLog(m) end,
    })
    state.activeBattle = battle
    state.battleMode = "pvp"
    state.battleContext = { opponent = opponentName }
    state.pvp.activeDuel = {
        opponent = opponentName, seed = seed, isChallenger = true,
        myChoice = nil, foeChoice = nil, turn = 0,
    }
    state.awaitingPlayerChoice = true
    BattleUI:Open(battle, "pvp", { flavor = "PvP duel vs " .. opponentName })
    printMsg("Duel started vs " .. opponentName .. "!")
end

function ShowdownClone:StartDuelAsOpponent(challengerName, seed, foeSnapshot)
    local opponentTeam = Serializer.decodeTeam(foeSnapshot, BattleEngine)
    local myTeam = self:GetLiveTeam()
    -- Challenger is side 1, we are side 2
    local battle = BattleEngine.newBattle(opponentTeam, myTeam, {
        mode = "pvp",
        seed = seed,
        nameA = challengerName,
        nameB = UnitName("player"),
        onLog = function(m) BattleUI:AppendLog(m) end,
    })
    state.activeBattle = battle
    state.battleMode = "pvp"
    state.battleContext = { opponent = challengerName }
    state.pvp.activeDuel = {
        opponent = challengerName, seed = seed, isChallenger = false,
        myChoice = nil, foeChoice = nil, turn = 0,
    }
    state.awaitingPlayerChoice = true
    BattleUI:Open(battle, "pvp", { flavor = "PvP duel vs " .. challengerName })
    printMsg("Duel started vs " .. challengerName .. "!")
end

function ShowdownClone:OnAddonMessage(sender, text)
    local msgType, data, ok = Net.decode(text)
    if not ok then return end
    local myName = UnitName("player")
    if data.to and data.to:lower() ~= myName:lower() then return end

    if msgType == Net.MSG.CHALLENGE then
        state.pvp.pendingChallenge = { from = data.from, to = data.to, teamSize = data.teamSize }
        printMsg(data.from .. " challenges you to a Pokemon duel! Type /showdown accept or /showdown decline.")
    elseif msgType == Net.MSG.CHALLENGE_RESP then
        if not data.accepted then
            if state.pvp.pendingChallenge and state.pvp.pendingChallenge.to:lower() == sender:lower() then
                if data.reason == "cancelled" then
                    printMsg(data.from .. " cancelled the duel challenge.")
                else
                    printMsg(data.from .. " declined your duel.")
                end
                state.pvp.pendingChallenge = nil
                self:StopChallengeTimer()
            end
        elseif state.pvp.pendingChallenge and state.pvp.pendingChallenge.to:lower() == sender:lower() then
            self:StartDuelAsChallenger(sender)
            state.pvp.pendingChallenge = nil
            self:StopChallengeTimer()
        end
    elseif msgType == Net.MSG.START then
        self:StartDuelAsOpponent(data.from, data.seed, data.team)
    elseif msgType == Net.MSG.CHOICE then
        self:OnFoeChoice(data)
    elseif msgType == Net.MSG.RESIGN then
        printMsg(data.from .. " resigned. You win the duel!")
        if state.activeBattle and not state.activeBattle.over then
            -- Determine which side the resigning player controls
            local duel = state.pvp.activeDuel
            local mySide = (duel and not duel.isChallenger) and 2 or 1
            state.activeBattle.over = true
            state.activeBattle.winner = mySide
            BattleUI:Refresh()
            self:OnBattleEnd(state.activeBattle)
        end
        state.pvp.activeDuel = nil
        state.activeBattle = nil
    end
end

function ShowdownClone:SendAddonMessage(msg, target)
    if target and target ~= "" then
        SendAddonMessage(Net.PREFIX, msg, "WHISPER", target)
    else
        SendAddonMessage(Net.PREFIX, msg, "PARTY")
    end
end

function ShowdownClone:OnFoeChoice(data)
    local duel = state.pvp.activeDuel
    if not duel or data.from:lower() ~= duel.opponent:lower() then return end
    duel.foeChoice = data.choice
    duel.turn = data.turn
    ShowdownClone:MaybeRunPvpTurn()
end

function ShowdownClone:MaybeRunPvpTurn()
    local duel = state.pvp.activeDuel
    local b = state.activeBattle
    if not duel or not b or b.over then return end
    if not duel.myChoice or not duel.foeChoice then return end
    local mySide = duel.isChallenger and 1 or 2
    local foeSide = duel.isChallenger and 2 or 1
    local choices = {}
    choices[mySide] = duel.myChoice
    choices[foeSide] = duel.foeChoice
    duel.myChoice = nil
    duel.foeChoice = nil
    duel.turn = duel.turn + 1
    local over = b:runTurn(choices)
    BattleUI:Refresh()
    if over then
        local winnerName = b.winner and b.sides[b.winner].name or nil
        local msg = Net.buildResult(UnitName("player"), duel.opponent, b.winner, b.turn)
        ShowdownClone:SendAddonMessage(msg, duel.opponent)
        printMsg(winnerName and (winnerName .. " won the duel!") or "The duel ended in a draw!")
        state.pvp.activeDuel = nil
        state.activeBattle = nil
        self:OnBattleEnd(b)
    else
        state.awaitingPlayerChoice = true
    end
end

function ShowdownClone.ToggleTeamBuilder()
    TeamBuilder:Toggle()
end

ShowdownClone.eventFrame = eventFrame
return ShowdownClone
