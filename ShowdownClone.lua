ShowdownClone = ShowdownClone or {}

local ADDON = "ShowdownClone"

local BattleEngine = require("Core.BattleEngine")
local Encounters = require("Core.Encounters")
local PokemonData = require("Core.Data.Pokemon")
local Moves = require("Core.Data.Moves")
local Stats = require("Core.Stats")
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
    battleMode = nil,         -- "wild" | "trainer" | "pvp"
    battleContext = nil,      -- encounter/trainer/pvp info
    awaitingPlayerChoice = false,
    pvp = {
        pendingChallenge = nil, -- { from, to, teamSize }
        activeDuel = nil,       -- { opponent, seed, isChallenger, myChoice, foeChoice, turn }
    },
    money = 0,
    pokeballs = { pokeball = 20, greatball = 5, ultraball = 2, masterball = 0 },
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

-- Saved variables bootstrap
function ShowdownClone:OnInitialize()
    ShowdownCloneDB = ShowdownCloneDB or {}
    ShowdownCloneDB.team = ShowdownCloneDB.team or {}
    ShowdownCloneDB.settings = ShowdownCloneDB.settings or { minimapShown = true }
    ShowdownCloneDB.minimap = ShowdownCloneDB.minimap or { angle = 45 }
    ShowdownCloneDB.pokeballs = ShowdownCloneDB.pokeballs or state.pokeballs
    ShowdownCloneDB.money = ShowdownCloneDB.money or 0
    state.pokeballs = ShowdownCloneDB.pokeballs
    state.money = ShowdownCloneDB.money
    state.rng = PRNG.new(PRNG.randomSeed())
end

function ShowdownClone:OnEnable()
    MinimapButton:Create(function()
        TeamBuilder:Show()
    end)

    eventFrame:RegisterEvent("ADDON_LOADED")
    eventFrame:RegisterEvent("PLAYER_LOGOUT")
    eventFrame:RegisterEvent("CHAT_MSG_ADDON")
    eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

    RegisterAddonMessagePrefix(Net.PREFIX)

    SLASH_SHOWDOWNCLONE1 = "/showdown"
    SLASH_SHOWDOWNCLONE2 = "/sdc"
    SlashCmdList["SHOWDOWNCLONE"] = function(msg)
        ShowdownClone:SlashHandler(msg)
    end

    self:OnInitialize()
    printMsg("Loaded. Type |cffffff00/showdown|r to open the team builder.")
end

-- Persist on logout
function ShowdownClone:OnLogout()
    ShowdownCloneDB.pokeballs = state.pokeballs
    ShowdownCloneDB.money = state.money
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == ADDON then
            ShowdownClone:OnEnable()
        end
    elseif event == "PLAYER_LOGOUT" then
        ShowdownClone:OnLogout()
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, text, channel, sender = ...
        if prefix == Net.PREFIX then
            ShowdownClone:OnAddonMessage(sender, text, channel)
        end
    end
end)

-- Slash commands
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
    elseif cmd == "battle" then
        BattleUI:Build()
        printMsg("Open a battle via /showdown wild or /showdown trainer.")
    elseif cmd == "wild" then
        self:StartWildEncounter()
    elseif cmd == "trainer" then
        self:StartTrainerBattle()
    elseif cmd == "duel" then
        local target = table.concat(args, " ")
        self:ChallengePlayer(target)
    elseif cmd == "accept" then
        self:AcceptChallenge()
    elseif cmd == "decline" then
        self:DeclineChallenge()
    elseif cmd == "team" then
        self:PrintTeam()
    elseif cmd == "bag" or cmd == "balls" then
        self:PrintBag()
    elseif cmd == "help" then
        self:PrintHelp()
    else
        self:PrintHelp()
    end
end

function ShowdownClone:PrintHelp()
    printMsg("Commands:")
    printMsg("/showdown ui - open team builder")
    printMsg("/showdown wild - start a wild encounter")
    printMsg("/showdown trainer - challenge a trainer")
    printMsg("/showdown duel <player> - PvP duel")
    printMsg("/showdown accept|decline - respond to a duel")
    printMsg("/showdown team - print your team")
    printMsg("/showdown bag - print Pokeballs and money")
end

function ShowdownClone:PrintTeam()
    local team = TeamBuilder:GetLiveTeam()
    if #team == 0 then
        printMsg("Your team is empty. Open the team builder with /showdown ui.")
        return
    end
    printMsg("Your team:")
    for i, p in ipairs(team) do
        printMsg(string.format("  %d. %s Lv%d (%d/%d HP)", i, p.name, p.level, p.hp, p.maxHp))
    end
end

function ShowdownClone:PrintBag()
    printMsg(string.format("Money: %dg", state.money))
    for ball, count in pairs(state.pokeballs) do
        printMsg(string.format("  %s: %d", ball, count))
    end
end

-- Live team accessor
function ShowdownClone:GetLiveTeam()
    local team = TeamBuilder:GetLiveTeam()
    if #team == 0 then
        -- auto-give a starter if empty
        local starterId = state.rng:nextInt(1, 3) -- 1-3 = Bulbasaur/Charmander/Squirtle
        local p = BattleEngine.newPokemon(starterId, 5)
        ShowdownCloneDB.team = { Serializer.encodePokemon(p) }
        printMsg("You received a starter Pokemon: " .. p.name .. "!")
        return { p }
    end
    return team
end

function ShowdownClone:SaveTeam(team)
    local saved = {}
    for i, p in ipairs(team) do
        saved[i] = Serializer.encodePokemon(p)
    end
    ShowdownCloneDB.team = saved
end

-- Wild encounter
function ShowdownClone:StartWildEncounter()
    local team = self:GetLiveTeam()
    local mapId = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local zoneType = Encounters.zoneForInstance(mapId)
    local playerLevel = self:AverageTeamLevel(team)
    local enc = Encounters.generateWild(state.rng, zoneType, playerLevel)
    local wild = enc.pokemon
    printMsg("A wild " .. wild.name .. " (Lv" .. wild.level .. (wild.shiny and " SHINY!" or "") .. ") appeared!")
    local seed = state.rng:nextInt(1, 4294967295)
    local battle = BattleEngine.newBattle(team, { wild }, {
        mode = "pve",
        seed = seed,
        nameA = UnitName("player"),
        nameB = "Wild " .. wild.name,
        onLog = function(msg) BattleUI:AppendLog(msg) end,
    })
    state.activeBattle = battle
    state.battleMode = "wild"
    state.battleContext = { encounter = enc, zone = zoneType }
    state.awaitingPlayerChoice = true
    BattleUI:Open(battle, "wild", { flavor = "A wild " .. wild.name .. " appeared!" })
end

-- Trainer battle
function ShowdownClone:StartTrainerBattle()
    local team = self:GetLiveTeam()
    local playerLevel = self:AverageTeamLevel(team)
    local scale = 0.6 + (playerLevel / Stats.MAX_LEVEL) * 0.8
    local gen = Encounters.generateTrainer(state.rng, scale)
    printMsg("Trainer " .. gen.trainer.name .. " challenges you! \"" .. gen.trainer.flavor .. "\"")
    local seed = state.rng:nextInt(1, 4294967295)
    local battle = BattleEngine.newBattle(team, gen.team, {
        mode = "pve",
        seed = seed,
        nameA = UnitName("player"),
        nameB = gen.trainer.name,
        onLog = function(msg) BattleUI:AppendLog(msg) end,
    })
    state.activeBattle = battle
    state.battleMode = "trainer"
    state.battleContext = { trainer = gen.trainer }
    state.awaitingPlayerChoice = true
    BattleUI:Open(battle, "trainer", { flavor = gen.trainer.name .. " wants to battle!" })
end

function ShowdownClone:AverageTeamLevel(team)
    if #team == 0 then return 5 end
    local sum = 0
    for _, p in ipairs(team) do sum = sum + p.level end
    return math.floor(sum / #team)
end

-- Player chose an action (move/switch/flee)
function ShowdownClone.OnPlayerChoice(choice)
    local b = state.activeBattle
    if not b or b.over then return end
    state.awaitingPlayerChoice = false

    if choice.type == "flee" then
        local over = b:runTurn({ [1] = choice })
        BattleUI:Refresh()
        if over then
            ShowdownClone:OnBattleEnd(b)
        else
            state.awaitingPlayerChoice = true
            ShowdownClone:RunAiTurn()
        end
        return
    end

    -- PvE: player choice vs AI choice
    local aiChoice = Encounters.aiChooseMove(b, 2)
    local over = b:runTurn({ [1] = choice, [2] = aiChoice })
    BattleUI:Refresh()
    if over then
        ShowdownClone:OnBattleEnd(b)
    else
        -- check for switch need
        state.awaitingPlayerChoice = true
    end
end

function ShowdownClone:RunAiTurn()
    -- called when player fled but battle continues; AI acts alone
    local b = state.activeBattle
    if not b or b.over then return end
    local aiChoice = Encounters.aiChooseMove(b, 2)
    local over = b:runTurn({ [2] = aiChoice })
    BattleUI:Refresh()
    if over then
        ShowdownClone:OnBattleEnd(b)
    end
end

-- Catch attempt (wild battles only)
function ShowdownClone.OnCatchAttempt()
    local b = state.activeBattle
    if not b or state.battleMode ~= "wild" then return end
    local wild = b:active(2)
    local ball = "pokeball"
    if state.pokeballs.ultraball > 0 then ball = "ultraball"
    elseif state.pokeballs.greatball > 0 then ball = "greatball" end
    if state.pokeballs.masterball > 0 and wild.shiny then ball = "masterball" end
    if (state.pokeballs[ball] or 0) <= 0 then
        printMsg("You have no " .. ball .. "s left!")
        return
    end
    state.pokeballs[ball] = state.pokeballs[ball] - 1
    local result = Encounters.attemptCatch(state.rng, wild, ball, ShowdownClone:AverageTeamLevel(TeamBuilder:GetLiveTeam()))
    BattleUI:AppendLog("You threw a " .. ball .. "! (chance " .. math.floor(result.chance * 100) .. "%)")
    for i = 1, result.shakes do
        BattleUI:AppendLog("...shake " .. i)
    end
    if result.success then
        BattleUI:AppendLog("Gotcha! " .. wild.name .. " was caught!")
        -- add to team
        local team = TeamBuilder:GetLiveTeam()
        if #team < BattleEngine.MAX_TEAM then
            team[#team + 1] = wild
            self:SaveTeam(team)
            printMsg(wild.name .. " joined your team!")
        else
            printMsg(wild.name .. " was caught, but your team is full. It was released.")
        end
        b.over = true
        b.winner = 1
        b.caught = true
        BattleUI:Refresh()
        ShowdownClone:OnBattleEnd(b)
    else
        BattleUI:AppendLog("Oh no! " .. wild.name .. " broke free!")
        -- the throw consumed the player's turn: only the wild Pokemon acts
        local aiChoice = Encounters.aiChooseMove(b, 2)
        local over = b:runFoeOnlyTurn(2, aiChoice)
        BattleUI:Refresh()
        if over then
            ShowdownClone:OnBattleEnd(b)
        else
            state.awaitingPlayerChoice = true
        end
    end
end

function ShowdownClone:OnBattleEnd(b)
    state.activeBattle = nil
    state.awaitingPlayerChoice = false
    BattleUI:Refresh()
    if b.winner == 1 and not b.caught then
        self:OnBattleWon(b)
    elseif b.winner == 2 then
        printMsg("You blacked out! Your Pokemon were healed at the Pokemon Center.")
        self:HealTeam()
    end
end

function ShowdownClone:OnBattleWon(b)
    local ctx = state.battleContext or {}
    if state.battleMode == "wild" then
        local wild = b.sides[2].team[1]
        if wild and not wild.fainted then return end -- escaped/caught handled elsewhere
        local rewards = BattleEngine.rewardsFor(wild, 0)
        local team = TeamBuilder:GetLiveTeam()
        local leveled = {}
        for _, p in ipairs(team) do
            if not p.fainted then
                local ms = BattleEngine.gainExp(p, rewards.exp)
                for _, m in ipairs(ms) do
                    leveled[#leveled + 1] = p.name .. " grew to Lv" .. m.to .. "!"
                    for _, mv in ipairs(m.newMoves) do
                        leveled[#leveled + 1] = p.name .. " learned " .. mv .. "!"
                    end
                end
            end
        end
        self:SaveTeam(team)
        for _, line in ipairs(leveled) do printMsg(line) end
        printMsg("Gained " .. rewards.exp .. " EXP and " .. rewards.money .. " money!")
        state.money = state.money + rewards.money
    elseif state.battleMode == "trainer" then
        local trainer = ctx.trainer
        local team = TeamBuilder:GetLiveTeam()
        for _, p in ipairs(team) do
            if not p.fainted then
                BattleEngine.gainExp(p, math.floor(trainer.team[1].level * 30))
            end
        end
        self:SaveTeam(team)
        local reward = trainer.money * math.max(1, math.floor(self:AverageTeamLevel(team) / 10))
        state.money = state.money + reward
        printMsg("You defeated " .. trainer.name .. "! Won " .. reward .. " money.")
        -- Pokeball loot
        local loot = state.rng:nextInt(1, 3)
        state.pokeballs.pokeball = (state.pokeballs.pokeball or 0) + loot
        printMsg("Found " .. loot .. " Pokeballs!")
    end
end

function ShowdownClone:HealTeam()
    local team = TeamBuilder:GetLiveTeam()
    for _, p in ipairs(team) do
        p.hp = p.maxHp
        p.status = nil
        p.fainted = false
        p.stages = { atk = 0, def = 0, spa = 0, spd = 0, spe = 0, acc = 0, eva = 0 }
        p.volatile = {}
    end
    self:SaveTeam(team)
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
    local liveTeam = TeamBuilder:GetLiveTeam()
    local opponentTeam = Serializer.decodeTeam(snapshot, BattleEngine)
    local battle = BattleEngine.newBattle(liveTeam, opponentTeam, {
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
        opponent = opponentName,
        seed = seed,
        isChallenger = true,
        myChoice = nil,
        foeChoice = nil,
        turn = 0,
    }
    state.awaitingPlayerChoice = true
    BattleUI:Open(battle, "pvp", { flavor = "PvP duel vs " .. opponentName })
    printMsg("Duel started vs " .. opponentName .. "!")
end

function ShowdownClone:StartDuelAsOpponent(challengerName, seed, foeSnapshot)
    local opponentTeam = Serializer.decodeTeam(foeSnapshot, BattleEngine)
    local myTeam = TeamBuilder:GetLiveTeam()
    -- Opponent (challenger) is side 1, we are side 2
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
        opponent = challengerName,
        seed = seed,
        isChallenger = false,
        myChoice = nil,
        foeChoice = nil,
        turn = 0,
    }
    state.awaitingPlayerChoice = true
    BattleUI:Open(battle, "pvp", { flavor = "PvP duel vs " .. challengerName })
    printMsg("Duel started vs " .. challengerName .. "!")
end

function ShowdownClone:OnAddonMessage(sender, text, channel)
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
        else
            -- accepted: challenger starts the duel
            if state.pvp.pendingChallenge and state.pvp.pendingChallenge.to:lower() == sender:lower() then
                self:StartDuelAsChallenger(sender)
                state.pvp.pendingChallenge = nil
            end
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
        end
        state.pvp.activeDuel = nil
        state.activeBattle = nil
    elseif msgType == Net.MSG.RESULT then
        -- verification echo
    end
end

function ShowdownClone:SendAddonMessage(msg, target)
    -- Prefer whisper channel for targeted duels; fall back to party/raid.
    if target and target ~= "" then
        SendAddonMessage(Net.PREFIX, msg, "WHISPER", target)
    else
        SendAddonMessage(Net.PREFIX, msg, "PARTY")
    end
end

-- PvP turn flow: when the player makes a choice, send it and wait for foe's.
local origOnPlayerChoice = ShowdownClone.OnPlayerChoice
function ShowdownClone.OnPlayerChoice(choice)
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
    origOnPlayerChoice(choice)
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
    -- side 1 = challenger, side 2 = us (if we are the opponent)
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
    else
        state.awaitingPlayerChoice = true
    end
end

-- Expose for UI
function ShowdownClone.ToggleTeamBuilder()
    TeamBuilder:Toggle()
end

ShowdownClone.eventFrame = eventFrame
return ShowdownClone
