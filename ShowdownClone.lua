ShowdownClone = ShowdownClone or {}

local ADDON = "ShowdownClone"

local BattleEngine = require("Core.BattleEngine")
local PokemonData = require("Core.Data.Pokemon")
local Bot = require("Core.Bot")
local PRNG = require("Core.Util.PRNG")
local Serializer = require("Core.Util.Serializer")
local Net = require("Core.Net")

local TeamBuilder = require("UI.TeamBuilder")
local BattleUI = require("UI.BattleUI")
local MinimapButton = require("UI.MinimapButton")

ShowdownClone.TeamBuilder = TeamBuilder
ShowdownClone.BattleUI = BattleUI
ShowdownClone.MinimapButton = MinimapButton

local eventFrame = CreateFrame("Frame")
ShowdownClone.eventFrame = eventFrame

local state = {
    rng = nil,
    activeBattle = nil,       -- BattleEngine instance
    battleMode = nil,         -- "bot" | "pvp"
    battleContext = nil,      -- bot def or pvp info
    awaitingPlayerChoice = false,
    pvp = {
        pendingChallenge = nil, -- { from, to, teamSize }
        activeDuel = nil,       -- { opponent, seed, isChallenger, myChoice, foeChoice, turn }
    },
}
ShowdownClone.state = state

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
    ShowdownCloneDB.settings = ShowdownCloneDB.settings or { minimapShown = true }
    ShowdownCloneDB.minimap = ShowdownCloneDB.minimap or { angle = 45 }
    ShowdownCloneDB.record = ShowdownCloneDB.record or { wins = 0, losses = 0 }
    state.rng = PRNG.new(PRNG.randomSeed())
end

function ShowdownClone:OnEnable()
    MinimapButton:Create(function()
        TeamBuilder:Show()
    end)

    eventFrame:RegisterEvent("ADDON_LOADED")
    eventFrame:RegisterEvent("PLAYER_LOGOUT")
    eventFrame:RegisterEvent("CHAT_MSG_ADDON")

    RegisterAddonMessagePrefix(Net.PREFIX)

    SLASH_SHOWDOWNCLONE1 = "/showdown"
    SLASH_SHOWDOWNCLONE2 = "/sdc"
    SlashCmdList["SHOWDOWNCLONE"] = function(msg)
        ShowdownClone:SlashHandler(msg)
    end

    self:OnInitialize()
    printMsg("Loaded. Type |cffffff00/showdown|r to build your team, |cffffff00/showdown bot|r to battle a bot, or |cffffff00/showdown duel <name>|r to PvP.")
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
    printMsg("/showdown bot [n] - battle a practice bot (list with /showdown bots)")
    printMsg("/showdown bots - list practice bots")
    printMsg("/showdown duel <player> - PvP duel")
    printMsg("/showdown accept|decline - respond to a duel")
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
        local moveIds = {}
        for _, m in ipairs(p.moves) do moveIds[#moveIds + 1] = m.id end
        printMsg(string.format("  %d. %s Lv%d - %s", i, p.name, p.level, table.concat(moveIds, ", ")))
    end
end

-- Live team accessor. A Showdown team is exactly what the builder saved.
function ShowdownClone:GetLiveTeam()
    local saved = ShowdownCloneDB.team or {}
    if #saved == 0 then
        -- give a default starter team so a new player can battle immediately
        saved = {
            Serializer.encodePokemon(BattleEngine.newPokemon(1, 100)),
            Serializer.encodePokemon(BattleEngine.newPokemon(4, 100)),
            Serializer.encodePokemon(BattleEngine.newPokemon(7, 100)),
        }
        ShowdownCloneDB.team = saved
        printMsg("You received a default team (Bulbasaur, Charmander, Squirtle). Customize it with /showdown ui.")
    end
    return Serializer.decodeTeam(saved, BattleEngine)
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
    local team = self:GetLiveTeam()
    if #team == 0 then
        printMsg("You need a team first! Open the team builder with /showdown ui.")
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

-- PvP
function ShowdownClone:ChallengePlayer(targetName)
    if not targetName or targetName == "" then
        printMsg("Usage: /showdown duel <player name>")
        return
    end
    local myName = UnitName("player")
    if targetName:lower() == myName:lower() then
        printMsg("You can't duel yourself!")
        return
    end
    local team = self:GetLiveTeam()
    if #team == 0 then
        printMsg("You need a team first!")
        return
    end
    local msg = Net.buildChallenge(myName, targetName, #team)
    self:SendAddonMessage(msg, targetName)
    state.pvp.pendingChallenge = { from = myName, to = targetName, teamSize = #team }
    printMsg("Challenge sent to " .. targetName .. ". Waiting for response...")
end

function ShowdownClone:AcceptChallenge()
    local ch = state.pvp.pendingChallenge
    if not ch then
        printMsg("No pending challenge.")
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
            printMsg(data.from .. " declined your duel.")
            state.pvp.pendingChallenge = nil
        elseif state.pvp.pendingChallenge and state.pvp.pendingChallenge.to:lower() == sender:lower() then
            self:StartDuelAsChallenger(sender)
            state.pvp.pendingChallenge = nil
        end
    elseif msgType == Net.MSG.START then
        self:StartDuelAsOpponent(data.from, data.seed, data.team)
    elseif msgType == Net.MSG.CHOICE then
        self:OnFoeChoice(data)
    elseif msgType == Net.MSG.RESIGN then
        printMsg(data.from .. " resigned. You win the duel!")
        if state.activeBattle then
            state.activeBattle.over = true
            state.activeBattle.winner = 2
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
