# Showdown Clone — WoW AddOn

A simplified clone of the popular **Pokemon Showdown** browser game, built as a
World of Warcraft AddOn. Features the original **151 Pokemon** (Gen 1), wild
encounters while exploring, trainer battles, catching, leveling, EVs/IVs, and
PvP duels against other players who have the addon.

## Features

- All 151 original Pokemon with base stats, types, and learnsets (level-up moves).
- Turn-based battle engine with the Gen 1 type chart, STAB, critical hits,
  accuracy/evasion stages, and the classic Gen 1 move pool (simplified).
- Wild encounters in outdoor zones (higher level Pokemon in harder zones),
  with a shiny chance and a "run away" option.
- Catching with Pokeballs (better balls = better catch rate).
- Trainer battles: NPC-style trainers with themed teams, rewarding money and XP.
- Leveling up to 100 with EXP, EVs, stat recalculation, and move learning.
- PvP duels: challenge nearby players with the addon (`/showdown duel <name>`).
  Battles are fully deterministic on both clients from a shared seed.
- Team of up to 6 Pokemon, stored per character.
- UI: minimap button, team builder, battle window, encounter popups.

## Slash commands

| Command | Description |
| --- | --- |
| `/showdown` or `/showdown ui` | Open the team builder |
| `/showdown battle` | Open the battle window |
| `/showdown wild` | Force a wild encounter (outdoors) |
| `/showdown trainer` | Challenge a random trainer |
| `/showdown duel <player>` | Challenge a player to a PvP duel |
| `/showdown accept` | Accept a pending duel challenge |
| `/showdown decline` | Decline a pending duel challenge |
| `/showdown team` | Print your team to chat |

## Project layout

```
ShowdownClone.toc     AddOn manifest
ShowdownClone.lua     Entry point: events, slash commands, saved variables
Core/
  Libs/Json.lua       Small dependency-free JSON encoder/decoder
  Data/Types.lua      Gen 1 type chart
  Data/Moves.lua      Move definitions (power, accuracy, pp, effect)
  Data/Pokemon.lua    All 151 Pokemon: stats, types, learnsets
  Data/Trainers.lua   Trainer archetypes and themed teams
  Util/PRNG.lua       Deterministic RNG (mulberry32) for reproducible battles
  Util/Serializer.lua Serialize/deserialize Pokemon instances
  Stats.lua           Stat calculation, EXP/EV/IV math
  BattleEngine.lua    Turn-based battle simulation (PvE + deterministic PvP)
  Encounters.lua      Wild/trainer encounter generation, catching
  Net.lua             Chat-channel based PvP protocol (addon messages)
UI/
  MinimapButton.lua   Draggable minimap button
  TeamBuilder.lua     Team management window
  BattleUI.lua        Battle window: HP bars, move buttons, log
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
pip install lupa luaparser
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
- No EV/IV influence in PvP (teams are normalized); EVs still matter for
  your in-game progression.
- Status moves and stat stages are simplified; no sleep/freeze RNG beyond the
  shared deterministic PRNG.
