# Showdown Clone — WoW AddOn

A simplified clone of the popular **Pokemon Showdown** browser game, built as a
World of Warcraft AddOn. Like Showdown, the game is **teambuilding + battling**:
you build a team of the original **151 Pokemon** (Gen 1), then battle practice
bots or duel other players who have the addon. There is no catching, no
leveling, no money — exactly like Showdown.

## The base principles (what this addon does)

1. **Teambuilding** — pick up to 6 Pokemon, choose up to 4 legal moves for each
   (moves the species can actually learn at that level), set a level (1–100).
   Your team is saved per character.
2. **Battling** — turn-based 6v6 combat. Each turn both sides choose a move or
   a switch. First to KO all 6 opposing Pokemon wins. The engine implements
   the Gen 1 damage formula, type chart, STAB, critical hits, accuracy/evasion
   stages, status (burn/poison/paralysis/sleep/freeze/confusion), residual
   damage, Struggle, and a 200-turn endurance cap.
3. **Practice vs bots** — fight themed bot teams (Youngster → Champion Blue).
   Bots use a simple "pick the highest-damage move" AI.
4. **PvP duels** — challenge a nearby player with the addon
   (`/showdown duel <name>`). Battles are **fully deterministic on both
   clients** from a shared seed, so both sides always agree on the outcome.

## Slash commands

| Command | Description |
| --- | --- |
| `/showdown` or `/showdown ui` | Open the team builder |
| `/showdown bot [n]` | Battle a practice bot (random, or bot #n) |
| `/showdown bots` | List all practice bots |
| `/showdown duel <player>` | Challenge a player to a PvP duel |
| `/showdown accept` / `/showdown decline` | Respond to a duel challenge |
| `/showdown team` | Print your team to chat |
| `/showdown record` | Show your win/loss record |

## Project layout

```
ShowdownClone.toc     AddOn manifest
ShowdownClone.lua     Entry point: events, slash commands, saved variables
Core/
  Libs/Json.lua       Small dependency-free JSON encoder/decoder
  Data/Types.lua      Gen 1 type chart
  Data/Moves.lua      Move definitions (power, accuracy, pp, effect)
  Data/Pokemon.lua    All 151 Pokemon: stats, types, learnsets
  Util/PRNG.lua       Deterministic RNG (mulberry32) for reproducible battles
  Util/Serializer.lua Serialize/deserialize team members
  Stats.lua           Stat calculation (Showdown-style, level-only)
  BattleEngine.lua    Turn-based battle simulation (bot + deterministic PvP)
  Bot.lua             Practice bot teams + simple move-choice AI
  Net.lua             Chat-channel based PvP protocol (addon messages)
UI/
  MinimapButton.lua   Draggable minimap button
  TeamBuilder.lua     Team builder: 6 slots, species browser, legal move picker
  BattleUI.lua        Battle window: HP bars, move buttons, switch/forfeit, log
tests/                Headless test runner (LuaJIT via lupa, or any Lua 5.1)
```

All game logic lives in `Core/` and is written against plain Lua 5.1 (the WoW
client's Lua) with **no WoW API dependencies**, so the entire engine can be
unit-tested headlessly. WoW API usage is isolated to `ShowdownClone.lua` and
`UI/`.

## Running the tests

The engine has no WoW dependencies, so tests run under any Lua 5.1+ runtime.
With Python + [lupa](https://pypi.org/project/lupa/) (LuaJIT):

```bash
pip install lupa
python3 tests/run_tests.py
```

Or with a standalone Lua interpreter:

```bash
lua5.1 tests/run_tests.lua
# or
luajit tests/run_tests.lua
```

## Battle determinism (PvP)

PvP battles are simulated identically on both clients: when a duel starts, the
challenger generates a random seed and sends it (plus the team snapshot) to
the opponent over the addon chat channel. Both clients then run the same
`BattleEngine` simulation turn by turn, applying the moves chosen by each
player. Because the engine is a pure function of (teams, seed, move choices),
both sides always agree on the outcome.

## Simplifications vs. Pokemon Showdown

- Gen 1 only (151 Pokemon), no abilities, no held items, no natures.
- Simplified move effects: a curated subset of Gen 1 moves with straightforward
  damage / status / stat-stage effects. No complex volatile states.
- No EV/IV investment; stats are a function of base stats and level only.
- Status moves and stat stages are simplified; all RNG is deterministic from
  the shared seed.
