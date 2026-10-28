local Trainers = {}

-- Trainer archetypes with themed teams of species ids and levels.
-- money: base money reward (scaled slightly by average level)
Trainers.list = {
    { name = "Youngster",   flavor = "Bug catchers unite!", money = 16,
      teams = {
        { { 10, 5 }, { 13, 5 } },
        { { 19, 6 }, { 16, 6 } },
        { { 21, 7 }, { 19, 5 } },
      } },
    { name = "Bug Catcher", flavor = "Bugs are the best!", money = 10,
      teams = {
        { { 10, 7 }, { 10, 7 }, { 13, 7 } },
        { { 14, 8 }, { 15, 9 } },
        { { 12, 10 }, { 11, 9 } },
      } },
    { name = "Lass",        flavor = "My Pokemon are cute!", money = 15,
      teams = {
        { { 16, 7 }, { 17, 8 } },
        { { 31, 10 }, { 35, 9 } },
        { { 113, 12 } },
      } },
    { name = "Sailor",      flavor = "Anchors aweigh!", money = 20,
      teams = {
        { { 56, 9 }, { 57, 10 } },
        { { 54, 11 }, { 60, 9 } },
        { { 98, 12 }, { 99, 11 } },
      } },
    { name = "Camper",      flavor = "Let's camp out!", money = 12,
      teams = {
        { { 27, 9 }, { 74, 9 } },
        { { 63, 10 }, { 66, 9 } },
        { { 4, 11 }, { 7, 10 } },
      } },
    { name = "Picnicker",   flavor = "Tea time!", money = 12,
      teams = {
        { { 43, 10 }, { 69, 10 } },
        { { 1, 12 }, { 4, 11 }, { 7, 11 } },
        { { 60, 13 } },
      } },
    { name = "Hiker",       flavor = "Rocks rock!", money = 25,
      teams = {
        { { 74, 11 }, { 95, 11 } },
        { { 27, 10 }, { 28, 12 } },
        { { 66, 13 }, { 67, 12 } },
      } },
    { name = "Biker",       flavor = "Vroom vroom!", money = 20,
      teams = {
        { { 88, 12 }, { 109, 12 } },
        { { 20, 14 }, { 48, 13 } },
        { { 29, 14 }, { 32, 14 } },
      } },
    { name = "Fisherman",   flavor = "Something's biting!", money = 20,
      teams = {
        { { 129, 10 }, { 129, 10 }, { 129, 10 } },
        { { 118, 14 }, { 120, 13 } },
        { { 130, 16 } },
      } },
    { name = "Swimmer",     flavor = "Swim for your life!", money = 10,
      teams = {
        { { 72, 12 }, { 73, 13 } },
        { { 86, 15 }, { 116, 14 } },
        { { 90, 16 }, { 120, 16 } },
      } },
    { name = "Cue Ball",    flavor = "No mercy!", money = 25,
      teams = {
        { { 28, 15 }, { 34, 15 } },
        { { 66, 14 }, { 68, 14 }, { 67, 13 } },
        { { 106, 16 }, { 107, 16 } },
      } },
    { name = "Gambler",     flavor = "Feeling lucky!", money = 70,
      teams = {
        { { 53, 16 }, { 53, 16 } },
        { { 52, 17 }, { 35, 15 } },
        { { 100, 18 }, { 82, 17 } },
      } },
    { name = "Beauty",      flavor = "Pretty Pokemon!", money = 70,
      teams = {
        { { 120, 17 }, { 121, 17 } },
        { { 84, 18 }, { 85, 18 } },
        { { 71, 19 }, { 44, 18 } },
      } },
    { name = "Psychic",     flavor = "I see... your defeat.", money = 25,
      teams = {
        { { 96, 18 }, { 63, 16 }, { 79, 17 } },
        { { 122, 19 }, { 65, 18 } },
        { { 103, 20 }, { 79, 19 } },
      } },
    { name = "Rocker",      flavor = "Let's jam!", money = 25,
      teams = {
        { { 81, 19 }, { 100, 19 } },
        { { 82, 21 }, { 101, 20 } },
        { { 25, 20 }, { 26, 21 } },
      } },
    { name = "Juggler",     flavor = "Watch closely!", money = 35,
      teams = {
        { { 64, 21 }, { 63, 20 } },
        { { 100, 22 }, { 81, 22 }, { 82, 22 } },
        { { 122, 24 } },
      } },
    { name = "Tamer",       flavor = "My beasts are fierce!", money = 40,
      teams = {
        { { 28, 22 }, { 105, 23 } },
        { { 58, 23 }, { 59, 23 } },
        { { 127, 24 }, { 115, 23 } },
      } },
    { name = "Bird Keeper", flavor = "Fly free!", money = 25,
      teams = {
        { { 16, 20 }, { 17, 20 }, { 18, 21 } },
        { { 21, 22 }, { 22, 22 } },
        { { 83, 24 }, { 84, 24 }, { 85, 24 } },
      } },
    { name = "Blackbelt",   flavor = "Train your spirit!", money = 25,
      teams = {
        { { 66, 24 }, { 67, 24 }, { 68, 24 } },
        { { 56, 25 }, { 57, 25 }, { 106, 25 } },
        { { 107, 26 }, { 68, 26 } },
      } },
    { name = "Rival",       flavor = "You can't beat me!", money = 35,
      teams = {
        { { 16, 18 }, { 19, 16 }, { 4, 17 } },
        { { 17, 20 }, { 19, 18 }, { 5, 19 } },
        { { 18, 22 }, { 20, 20 }, { 6, 21 } },
      } },
    { name = "Scientist",   flavor = "For science!", money = 50,
      teams = {
        { { 81, 22 }, { 82, 22 }, { 132, 22 } },
        { { 100, 24 }, { 101, 24 }, { 137, 24 } },
        { { 35, 23 }, { 64, 23 }, { 65, 23 } },
      } },
    { name = "Boss",        flavor = "You're not ready.", money = 90,
      teams = {
        { { 24, 25 }, { 109, 25 }, { 110, 25 } },
        { { 34, 26 }, { 110, 26 }, { 89, 26 } },
        { { 111, 28 }, { 112, 28 }, { 115, 27 } },
      } },
    { name = "Team Rocket", flavor = "Prepare for trouble!", money = 30,
      teams = {
        { { 23, 20 }, { 24, 21 }, { 109, 21 } },
        { { 19, 22 }, { 42, 23 }, { 110, 24 } },
        { { 41, 24 }, { 42, 24 }, { 88, 24 }, { 89, 25 } },
      } },
    { name = "Cooltrainer", flavor = "I never lose!", money = 45,
      teams = {
        { { 36, 26 }, { 21, 26 }, { 24, 26 } },
        { { 118, 27 }, { 120, 27 }, { 128, 27 } },
        { { 31, 28 }, { 34, 28 }, { 80, 28 } },
      } },
    { name = "Bruno",       flavor = "My Fighting Pokemon are the strongest!", money = 99,
      teams = {
        { { 66, 30 }, { 68, 32 }, { 107, 34 }, { 106, 34 }, { 68, 36 } },
      } },
    { name = "Misty",       flavor = "Water Pokemon are tough!", money = 99,
      teams = {
        { { 54, 28 }, { 120, 30 }, { 121, 34 }, { 73, 36 } },
      } },
    { name = "LtSarge",     flavor = "Electric Pokemon shock!", money = 99,
      teams = {
        { { 25, 30 }, { 82, 32 }, { 101, 34 }, { 26, 36 } },
      } },
    { name = "Sabrina",     flavor = "Psychic power wins!", money = 99,
      teams = {
        { { 64, 32 }, { 122, 34 }, { 63, 34 }, { 65, 38 } },
      } },
    { name = "Blaine",     flavor = "Fire Pokemon burn!", money = 99,
      teams = {
        { { 58, 34 }, { 77, 36 }, { 78, 38 }, { 59, 40 } },
      } },
    { name = "Giovanni",    flavor = "The strongest trainer!", money = 99,
      teams = {
        { { 111, 38 }, { 51, 36 }, { 112, 40 }, { 31, 40 }, { 95, 42 } },
      } },
    { name = "Lorelei",     flavor = "Ice Pokemon freeze!", money = 99,
      teams = {
        { { 87, 40 }, { 80, 42 }, { 86, 42 }, { 91, 44 }, { 124, 44 } },
      } },
    { name = "Agatha",      flavor = "Ghost Pokemon haunt!", money = 99,
      teams = {
        { { 92, 42 }, { 94, 44 }, { 93, 44 }, { 42, 46 }, { 94, 48 } },
      } },
    { name = "Lance",       flavor = "Dragon Pokemon are invincible!", money = 99,
      teams = {
        { { 148, 44 }, { 149, 46 }, { 147, 46 }, { 142, 48 }, { 149, 50 } },
      } },
    { name = "Champion",    flavor = "The ultimate challenge!", money = 99,
      teams = {
        { { 59, 48 }, { 65, 48 }, { 68, 48 }, { 71, 48 }, { 103, 48 }, { 149, 50 } },
      } },
}

-- Build a concrete trainer instance: { name, flavor, money, team = { pokemonSpec... } }
-- pokemonSpec = { id, level }
function Trainers.generate(rng, options)
    options = options or {}
    local pool = Trainers.list
    if options.gymOnly then
        pool = {}
        for _, t in ipairs(Trainers.list) do
            if t.gym then pool[#pool + 1] = t end
        end
        if #pool == 0 then pool = Trainers.list end
    end
    local def = pool[rng:nextInt(1, #pool)]
    local teams = def.teams
    local teamDef = teams[rng:nextInt(1, #teams)]
    local team = {}
    for _, member in ipairs(teamDef) do
        local id, level = member[1], member[2]
        if options.levelScale then
            level = math.max(1, math.floor(level * options.levelScale))
        end
        team[#team + 1] = { id = id, level = level }
    end
    return {
        name = def.name,
        flavor = def.flavor,
        money = def.money,
        team = team,
    }
end

function Trainers.getByName(name)
    for _, t in ipairs(Trainers.list) do
        if t.name:lower() == name:lower() then return t end
    end
    return nil
end

return Trainers
