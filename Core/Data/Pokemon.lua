local PokemonData = {}

-- Gen 1 base stats. In Gen 1 "Special" is a single stat, so spa == spd.
-- Entry: { name, types = {t1, t2?}, base = {hp,atk,def,spa,spd,spe},
--          learnset = { {level, "MoveId"}, ... } (sorted by level) }

local P = {}

local function add(id, name, t1, t2, hp, atk, def, spc, spe, learnset)
    P[id] = {
        id = id,
        name = name,
        types = t2 and { t1, t2 } or { t1 },
        base = { hp = hp, atk = atk, def = def, spa = spc, spd = spc, spe = spe },
        learnset = learnset,
    }
end

-- 001-010
add(1, "Bulbasaur", "Grass", "Poison", 45, 49, 49, 65, 45,
    { {1,"Tackle"}, {3,"Growl"}, {7,"LeechSeed"}, {10,"VineWhip"}, {15,"PoisonSting"}, {20,"RazorLeaf"}, {27,"SleepPowder"}, {34,"SolarBeam"} })
add(2, "Ivysaur", "Grass", "Poison", 60, 62, 63, 80, 60,
    { {1,"Tackle"}, {3,"Growl"}, {7,"LeechSeed"}, {10,"VineWhip"}, {15,"PoisonSting"}, {22,"RazorLeaf"}, {30,"SleepPowder"}, {38,"SolarBeam"} })
add(3, "Venusaur", "Grass", "Poison", 80, 82, 83, 100, 80,
    { {1,"Tackle"}, {3,"Growl"}, {7,"LeechSeed"}, {10,"VineWhip"}, {15,"PoisonSting"}, {22,"RazorLeaf"}, {30,"SleepPowder"}, {43,"SolarBeam"} })
add(4, "Charmander", "Fire", nil, 39, 52, 43, 50, 65,
    { {1,"Scratch2"}, {9,"Ember"}, {15,"Leer"}, {22,"Rage2"}, {30,"Slash"}, {38,"Flamethrower"} })
add(5, "Charmeleon", "Fire", nil, 58, 64, 58, 65, 80,
    { {1,"Scratch2"}, {9,"Ember"}, {15,"Leer"}, {24,"Rage2"}, {33,"Slash"}, {42,"Flamethrower"} })
add(6, "Charizard", "Fire", "Flying", 78, 84, 78, 85, 100,
    { {1,"Scratch2"}, {9,"Ember"}, {15,"Leer"}, {24,"Rage2"}, {36,"Slash"}, {46,"Flamethrower"} })
add(7, "Squirtle", "Water", nil, 44, 48, 65, 50, 43,
    { {1,"Tackle"}, {8,"Withdraw"}, {15,"WaterGun"}, {22,"Bite2"}, {28,"HydroPump"}, {35,"SkullBash2"} })
add(8, "Wartortle", "Water", nil, 59, 63, 80, 65, 58,
    { {1,"Tackle"}, {8,"Withdraw"}, {15,"WaterGun"}, {24,"Bite2"}, {31,"HydroPump"}, {39,"SkullBash2"} })
add(9, "Blastoise", "Water", nil, 79, 83, 100, 85, 78,
    { {1,"Tackle"}, {8,"Withdraw"}, {15,"WaterGun"}, {24,"Bite2"}, {31,"HydroPump"}, {42,"SkullBash2"} })
add(10, "Caterpie", "Bug", nil, 45, 30, 35, 20, 45,
    { {1,"Tackle"}, {15,"StringShot"} })

-- 011-020
add(11, "Metapod", "Bug", nil, 50, 20, 55, 25, 30,
    { {1,"Harden"} })
add(12, "Butterfree", "Bug", "Flying", 60, 45, 50, 80, 70,
    { {10,"Confusion"}, {13,"PoisonSting"}, {14,"StunSpore"}, {15,"SleepPowder"}, {18,"Supersonic"}, {23,"Gust"}, {28,"Psybeam"}, {34,"Psychic"} })
add(13, "Weedle", "Bug", "Poison", 40, 35, 30, 20, 50,
    { {1,"PoisonSting"} })
add(14, "Kakuna", "Bug", "Poison", 45, 25, 50, 25, 35,
    { {1,"Harden"} })
add(15, "Beedrill", "Bug", "Poison", 65, 80, 40, 45, 75,
    { {10,"Twineedle"}, {15,"FocusEnergy2"}, {20,"HornAttack2"}, {25,"PinMissile"}, {30,"Agility"} })
add(16, "Pidgey", "Normal", "Flying", 40, 45, 40, 35, 56,
    { {1,"Gust"}, {5,"SandAttack2"}, {12,"QuickAttack"}, {19,"Whirlwind2"}, {28,"WingAttack"}, {36,"Agility"} })
add(17, "Pidgeotto", "Normal", "Flying", 63, 60, 55, 50, 71,
    { {1,"Gust"}, {5,"SandAttack2"}, {12,"QuickAttack"}, {21,"Whirlwind2"}, {31,"WingAttack"}, {40,"Agility"} })
add(18, "Pidgeot", "Normal", "Flying", 83, 80, 75, 70, 91,
    { {1,"Gust"}, {5,"SandAttack2"}, {12,"QuickAttack"}, {21,"Whirlwind2"}, {31,"WingAttack"}, {44,"Agility"} })
add(19, "Rattata", "Normal", nil, 30, 56, 35, 25, 72,
    { {1,"Tackle"}, {7,"QuickAttack"}, {14,"HyperFang2"}, {23,"FocusEnergy2"}, {34,"SuperFang2"} })
add(20, "Raticate", "Normal", nil, 55, 81, 60, 50, 97,
    { {1,"Tackle"}, {7,"QuickAttack"}, {14,"HyperFang2"}, {27,"FocusEnergy2"}, {41,"SuperFang2"} })

-- 021-030
add(21, "Spearow", "Normal", "Flying", 40, 60, 30, 31, 70,
    { {1,"Peck"}, {9,"Leer"}, {15,"FuryAttack2"}, {22,"MirrorMove2"}, {29,"DrillPeck"}, {36,"Agility"} })
add(22, "Fearow", "Normal", "Flying", 65, 90, 65, 61, 100,
    { {1,"Peck"}, {9,"Leer"}, {15,"FuryAttack2"}, {25,"MirrorMove2"}, {34,"DrillPeck"}, {43,"Agility"} })
add(23, "Ekans", "Poison", nil, 35, 60, 44, 40, 55,
    { {1,"Wrap2"}, {10,"Leer"}, {17,"PoisonSting"}, {24,"Bite2"}, {31,"Acid"}, {38,"Screech"} })
add(24, "Arbok", "Poison", nil, 60, 85, 69, 65, 80,
    { {1,"Wrap2"}, {10,"Leer"}, {17,"PoisonSting"}, {27,"Bite2"}, {36,"Acid"}, {47,"Screech"} })
add(25, "Pikachu", "Electric", nil, 35, 55, 30, 50, 90,
    { {1,"ThunderShock"}, {9,"ThunderWave"}, {16,"QuickAttack"}, {26,"Swift"}, {33,"Agility"}, {43,"Thunderbolt"} })
add(26, "Raichu", "Electric", nil, 60, 90, 55, 90, 100,
    { {1,"ThunderShock"}, {9,"ThunderWave"}, {16,"QuickAttack"}, {26,"Swift"}, {33,"Agility"}, {47,"Thunderbolt"} })
add(27, "Sandshrew", "Ground", nil, 50, 75, 85, 30, 40,
    { {1,"Scratch2"}, {10,"Leer"}, {17,"SandAttack2"}, {24,"PoisonSting"}, {31,"Swift"}, {38,"Dig"} })
add(28, "Sandslash", "Ground", nil, 75, 100, 110, 55, 65,
    { {1,"Scratch2"}, {10,"Leer"}, {17,"SandAttack2"}, {24,"PoisonSting"}, {35,"Swift"}, {47,"Dig"} })
add(29, "Nidoran F", "Poison", nil, 55, 47, 52, 40, 41,
    { {1,"Scratch2"}, {8,"TailWhip"}, {14,"PoisonSting"}, {21,"Bite2"}, {29,"FurySwipes2"}, {36,"DoubleKick"} })
add(30, "Nidorina", "Poison", nil, 70, 62, 67, 55, 56,
    { {1,"Scratch2"}, {8,"TailWhip"}, {14,"PoisonSting"}, {23,"Bite2"}, {32,"FurySwipes2"}, {41,"DoubleKick"} })

-- 031-040
add(31, "Nidoqueen", "Poison", "Ground", 90, 82, 87, 75, 76,
    { {1,"Scratch2"}, {8,"TailWhip"}, {14,"PoisonSting"}, {23,"BodySlam"}, {35,"Earthquake"}, {46,"DoubleKick"} })
add(32, "Nidoran M", "Poison", nil, 46, 57, 40, 40, 50,
    { {1,"Leer"}, {8,"HornAttack2"}, {14,"PoisonSting"}, {21,"FocusEnergy2"}, {29,"FuryAttack2"}, {36,"HornDrill2"} })
add(33, "Nidorino", "Poison", nil, 61, 72, 57, 55, 65,
    { {1,"Leer"}, {8,"HornAttack2"}, {14,"PoisonSting"}, {23,"FocusEnergy2"}, {32,"FuryAttack2"}, {41,"HornDrill2"} })
add(34, "Nidoking", "Poison", "Ground", 81, 92, 77, 75, 85,
    { {1,"Leer"}, {8,"HornAttack2"}, {14,"PoisonSting"}, {23,"BodySlam"}, {35,"Earthquake"}, {46,"HornDrill2"} })
add(35, "Clefairy", "Normal", nil, 70, 45, 48, 60, 35,
    { {1,"Tackle"}, {13,"Metronome2"}, {18,"Sing2"}, {24,"DoubleSlap2"}, {31,"DefenseCurl2"}, {39,"LightScreen2"} })
add(36, "Clefable", "Normal", nil, 95, 70, 73, 85, 60,
    { {1,"Tackle"}, {13,"Metronome2"}, {18,"Sing2"}, {24,"DoubleSlap2"}, {31,"DefenseCurl2"}, {43,"LightScreen2"} })
add(37, "Vulpix", "Fire", nil, 38, 41, 40, 65, 65,
    { {1,"Ember"}, {10,"TailWhip"}, {18,"QuickAttack"}, {23,"ConfuseRay"}, {30,"Flamethrower"} })
add(38, "Ninetales", "Fire", nil, 73, 76, 75, 100, 100,
    { {1,"Ember"}, {10,"TailWhip"}, {18,"QuickAttack"}, {23,"ConfuseRay"}, {35,"Flamethrower"} })
add(39, "Jigglypuff", "Normal", nil, 115, 45, 20, 25, 20,
    { {1,"Sing2"}, {14,"DefenseCurl2"}, {19,"DoubleSlap2"}, {27,"Rest"}, {32,"BodySlam"}, {40,"HyperBeam"} })
add(40, "Wigglytuff", "Normal", nil, 140, 70, 45, 50, 45,
    { {1,"Sing2"}, {14,"DefenseCurl2"}, {19,"DoubleSlap2"}, {27,"Rest"}, {32,"BodySlam"}, {45,"HyperBeam"} })

-- 041-050
add(41, "Zubat", "Poison", "Flying", 40, 45, 35, 40, 55,
    { {1,"LeechLife2"}, {10,"Supersonic"}, {15,"Bite2"}, {21,"ConfuseRay"}, {28,"WingAttack"}, {36,"Haze2"} })
add(42, "Golbat", "Poison", "Flying", 75, 80, 70, 75, 90,
    { {1,"LeechLife2"}, {10,"Supersonic"}, {15,"Bite2"}, {21,"ConfuseRay"}, {32,"WingAttack"}, {43,"Haze2"} })
add(43, "Oddish", "Grass", "Poison", 45, 50, 55, 75, 30,
    { {1,"Absorb"}, {15,"PoisonSting"}, {17,"StunSpore"}, {19,"SleepPowder"}, {24,"Acid"}, {33,"SolarBeam"} })
add(44, "Gloom", "Grass", "Poison", 60, 65, 70, 85, 40,
    { {1,"Absorb"}, {15,"PoisonSting"}, {17,"StunSpore"}, {19,"SleepPowder"}, {28,"Acid"}, {38,"SolarBeam"} })
add(45, "Vileplume", "Grass", "Poison", 75, 80, 85, 100, 50,
    { {1,"Absorb"}, {15,"PoisonSting"}, {17,"StunSpore"}, {19,"SleepPowder"}, {28,"Acid"}, {44,"SolarBeam"} })
add(46, "Paras", "Bug", "Grass", 35, 70, 55, 55, 25,
    { {1,"Scratch2"}, {13,"StunSpore"}, {19,"LeechLife2"}, {25,"Spore2"}, {31,"Slash"}, {37,"Growth2"} })
add(47, "Parasect", "Bug", "Grass", 60, 95, 80, 80, 30,
    { {1,"Scratch2"}, {13,"StunSpore"}, {19,"LeechLife2"}, {27,"Spore2"}, {35,"Slash"}, {43,"Growth2"} })
add(48, "Venonat", "Bug", "Poison", 60, 55, 50, 40, 45,
    { {1,"Tackle"}, {11,"Supersonic"}, {19,"Confusion"}, {22,"PoisonSting"}, {27,"LeechLife2"}, {30,"StunSpore"}, {35,"Psybeam"} })
add(49, "Venomoth", "Bug", "Poison", 70, 65, 60, 90, 90,
    { {1,"Tackle"}, {11,"Supersonic"}, {19,"Confusion"}, {22,"PoisonSting"}, {27,"LeechLife2"}, {30,"StunSpore"}, {38,"Psybeam"}, {47,"Psychic"} })
add(50, "Diglett", "Ground", nil, 10, 55, 25, 45, 95,
    { {1,"Scratch2"}, {15,"Growl"}, {19,"Dig"}, {24,"SandAttack2"}, {31,"Slash"}, {40,"Earthquake"} })

-- 051-060
add(51, "Dugtrio", "Ground", nil, 35, 80, 50, 70, 120,
    { {1,"Scratch2"}, {15,"Growl"}, {19,"Dig"}, {24,"SandAttack2"}, {35,"Slash"}, {47,"Earthquake"} })
add(52, "Meowth", "Normal", nil, 40, 45, 35, 40, 90,
    { {1,"Scratch2"}, {12,"Growl"}, {17,"Bite2"}, {24,"PayDay2"}, {33,"Slash"}, {44,"FurySwipes2"} })
add(53, "Persian", "Normal", nil, 65, 70, 60, 65, 115,
    { {1,"Scratch2"}, {12,"Growl"}, {17,"Bite2"}, {24,"PayDay2"}, {37,"Slash"}, {51,"FurySwipes2"} })
add(54, "Psyduck", "Water", nil, 50, 52, 48, 50, 55,
    { {1,"Scratch2"}, {5,"TailWhip"}, {10,"Disable"}, {16,"Confusion"}, {22,"FurySwipes2"}, {28,"HydroPump"} })
add(55, "Golduck", "Water", nil, 80, 82, 78, 80, 85,
    { {1,"Scratch2"}, {5,"TailWhip"}, {10,"Disable"}, {16,"Confusion"}, {22,"FurySwipes2"}, {31,"HydroPump"} })
add(56, "Mankey", "Fighting", nil, 40, 80, 35, 35, 70,
    { {1,"Scratch2"}, {9,"Leer"}, {15,"LowKick"}, {21,"KarateChop"}, {27,"FurySwipes2"}, {33,"FocusEnergy2"}, {39,"SeismicToss"} })
add(57, "Primeape", "Fighting", nil, 65, 105, 60, 60, 95,
    { {1,"Scratch2"}, {9,"Leer"}, {15,"LowKick"}, {21,"KarateChop"}, {27,"FurySwipes2"}, {36,"FocusEnergy2"}, {45,"SeismicToss"} })
add(58, "Growlithe", "Fire", nil, 55, 70, 45, 50, 60,
    { {1,"Bite2"}, {18,"Ember"}, {23,"Leer"}, {30,"TakeDown"}, {39,"Agility"}, {50,"Flamethrower"} })
add(59, "Arcanine", "Fire", nil, 90, 110, 80, 80, 95,
    { {1,"Bite2"}, {18,"Ember"}, {23,"Leer"}, {30,"TakeDown"}, {44,"Agility"}, {55,"Flamethrower"} })
add(60, "Poliwag", "Water", nil, 40, 50, 40, 40, 90,
    { {1,"Bubble2"}, {16,"Hypnosis"}, {19,"WaterGun"}, {25,"DoubleSlap2"}, {31,"BodySlam"}, {36,"HydroPump"} })

-- 061-070
add(61, "Poliwhirl", "Water", nil, 65, 65, 65, 50, 90,
    { {1,"Bubble2"}, {16,"Hypnosis"}, {19,"WaterGun"}, {25,"DoubleSlap2"}, {33,"BodySlam"}, {41,"HydroPump"} })
add(62, "Poliwrath", "Water", "Fighting", 90, 85, 95, 70, 70,
    { {1,"Bubble2"}, {16,"Hypnosis"}, {19,"WaterGun"}, {25,"DoubleSlap2"}, {33,"BodySlam"}, {41,"HydroPump"}, {41,"Submission"} })
add(63, "Abra", "Psychic", nil, 25, 20, 15, 105, 90,
    { {1,"Teleport2"} })
add(64, "Kadabra", "Psychic", nil, 40, 35, 30, 120, 105,
    { {1,"Teleport2"}, {16,"Confusion"}, {20,"Disable"}, {27,"Psybeam"}, {31,"Recover"}, {38,"Psychic"}, {42,"Reflect2"} })
add(65, "Alakazam", "Psychic", nil, 55, 50, 45, 135, 120,
    { {1,"Teleport2"}, {16,"Confusion"}, {20,"Disable"}, {27,"Psybeam"}, {31,"Recover"}, {38,"Psychic"}, {46,"Reflect2"} })
add(66, "Machop", "Fighting", nil, 70, 80, 50, 35, 35,
    { {1,"KarateChop"}, {15,"Leer"}, {21,"LowKick"}, {27,"FocusEnergy2"}, {33,"SeismicToss"}, {39,"Submission"} })
add(67, "Machoke", "Fighting", nil, 80, 100, 70, 50, 45,
    { {1,"KarateChop"}, {15,"Leer"}, {21,"LowKick"}, {27,"FocusEnergy2"}, {36,"SeismicToss"}, {44,"Submission"} })
add(68, "Machamp", "Fighting", nil, 90, 130, 80, 65, 55,
    { {1,"KarateChop"}, {15,"Leer"}, {21,"LowKick"}, {27,"FocusEnergy2"}, {36,"SeismicToss"}, {44,"Submission"} })
add(69, "Bellsprout", "Grass", "Poison", 50, 75, 35, 70, 40,
    { {1,"VineWhip"}, {13,"Wrap2"}, {15,"PoisonSting"}, {18,"SleepPowder"}, {21,"StunSpore"}, {26,"Acid"}, {33,"RazorLeaf"} })
add(70, "Weepinbell", "Grass", "Poison", 65, 90, 50, 85, 55,
    { {1,"VineWhip"}, {13,"Wrap2"}, {15,"PoisonSting"}, {18,"SleepPowder"}, {21,"StunSpore"}, {26,"Acid"}, {36,"RazorLeaf"} })

-- 071-080
add(71, "Victreebel", "Grass", "Poison", 80, 105, 65, 100, 70,
    { {1,"VineWhip"}, {13,"Wrap2"}, {15,"PoisonSting"}, {18,"SleepPowder"}, {21,"StunSpore"}, {26,"Acid"}, {39,"RazorLeaf"} })
add(72, "Tentacool", "Water", "Poison", 40, 40, 35, 100, 70,
    { {1,"PoisonSting"}, {6,"Supersonic"}, {12,"Wrap2"}, {19,"Acid"}, {25,"BubbleBeam"}, {30,"Barrier"}, {35,"Screech"} })
add(73, "Tentacruel", "Water", "Poison", 80, 70, 65, 120, 100,
    { {1,"PoisonSting"}, {6,"Supersonic"}, {12,"Wrap2"}, {19,"Acid"}, {25,"BubbleBeam"}, {30,"Barrier"}, {39,"Screech"}, {47,"HydroPump"} })
add(74, "Geodude", "Rock", "Ground", 40, 80, 100, 30, 20,
    { {1,"Tackle"}, {11,"DefenseCurl2"}, {16,"RockThrow"}, {21,"SelfDestruct"}, {26,"Harden"}, {31,"Earthquake"}, {36,"Explosion"} })
add(75, "Graveler", "Rock", "Ground", 55, 95, 115, 45, 35,
    { {1,"Tackle"}, {11,"DefenseCurl2"}, {16,"RockThrow"}, {21,"SelfDestruct"}, {29,"Harden"}, {36,"Earthquake"}, {43,"Explosion"} })
add(76, "Golem", "Rock", "Ground", 80, 110, 130, 55, 45,
    { {1,"Tackle"}, {11,"DefenseCurl2"}, {16,"RockThrow"}, {21,"SelfDestruct"}, {29,"Harden"}, {36,"Earthquake"}, {46,"Explosion"} })
add(77, "Ponyta", "Fire", nil, 50, 85, 55, 65, 90,
    { {1,"Ember"}, {32,"FireSpin"}, {35,"Stomp2"}, {39,"Agility"}, {43,"FireBlast"} })
add(78, "Rapidash", "Fire", nil, 65, 100, 70, 80, 105,
    { {1,"Ember"}, {32,"FireSpin"}, {35,"Stomp2"}, {39,"Agility"}, {47,"FireBlast"} })
add(79, "Slowpoke", "Water", "Psychic", 90, 65, 65, 40, 15,
    { {1,"Confusion"}, {18,"Disable"}, {22,"Headbutt2"}, {27,"Growl"}, {33,"WaterGun"}, {40,"Amnesia"}, {48,"Psychic"} })
add(80, "Slowbro", "Water", "Psychic", 95, 75, 110, 80, 30,
    { {1,"Confusion"}, {18,"Disable"}, {22,"Headbutt2"}, {27,"Growl"}, {33,"WaterGun"}, {37,"Amnesia"}, {49,"Psychic"} })

-- 081-090
add(81, "Magnemite", "Electric", nil, 25, 35, 70, 95, 45,
    { {1,"Tackle"}, {21,"ThunderShock"}, {25,"Supersonic"}, {29,"ThunderWave"}, {35,"Swift"}, {41,"Screech"} })
add(82, "Magneton", "Electric", nil, 50, 60, 95, 120, 70,
    { {1,"Tackle"}, {21,"ThunderShock"}, {25,"Supersonic"}, {29,"ThunderWave"}, {38,"Swift"}, {46,"Screech"} })
add(83, "Farfetch'd", "Normal", "Flying", 52, 65, 55, 58, 60,
    { {1,"Peck"}, {7,"SandAttack2"}, {15,"Leer"}, {23,"FuryAttack2"}, {31,"SwordsDance2"}, {39,"Agility"}, {47,"Slash"} })
add(84, "Doduo", "Normal", "Flying", 35, 85, 45, 35, 75,
    { {1,"Peck"}, {20,"Growl"}, {24,"FuryAttack2"}, {30,"DrillPeck"}, {36,"Agility"}, {40,"TriAttack"} })
add(85, "Dodrio", "Normal", "Flying", 60, 110, 70, 60, 100,
    { {1,"Peck"}, {20,"Growl"}, {24,"FuryAttack2"}, {30,"DrillPeck"}, {39,"Agility"}, {44,"TriAttack"} })
add(86, "Seel", "Water", nil, 65, 45, 55, 70, 45,
    { {1,"Headbutt2"}, {30,"Growl"}, {35,"AuroraBeam"}, {40,"Rest"}, {45,"IceBeam"} })
add(87, "Dewgong", "Water", "Ice", 90, 70, 80, 95, 70,
    { {1,"Headbutt2"}, {30,"Growl"}, {35,"AuroraBeam"}, {43,"Rest"}, {51,"IceBeam"} })
add(88, "Grimer", "Poison", nil, 80, 80, 50, 40, 25,
    { {1,"PoisonSting2"}, {30,"Minimize2"}, {33,"Sludge"}, {37,"Screech"}, {42,"Acid"}, {48,"SludgeBomb"} })
add(89, "Muk", "Poison", nil, 105, 105, 75, 65, 50,
    { {1,"PoisonSting2"}, {30,"Minimize2"}, {33,"Sludge"}, {37,"Screech"}, {45,"Acid"}, {53,"SludgeBomb"} })
add(90, "Shellder", "Water", nil, 30, 65, 100, 45, 40,
    { {1,"Tackle"}, {18,"Withdraw"}, {23,"Supersonic"}, {30,"AuroraBeam"}, {39,"Leer"}, {50,"HydroPump"} })

-- 091-100
add(91, "Cloyster", "Water", "Ice", 50, 95, 180, 85, 70,
    { {1,"Tackle"}, {18,"Withdraw"}, {23,"Supersonic"}, {30,"AuroraBeam"}, {39,"SpikeCannon2"}, {50,"IceBeam"} })
add(92, "Gastly", "Ghost", "Poison", 30, 35, 30, 100, 80,
    { {1,"ConfuseRay"}, {27,"NightShade"}, {35,"Hypnosis"} })
add(93, "Haunter", "Ghost", "Poison", 45, 50, 45, 115, 95,
    { {1,"ConfuseRay"}, {29,"NightShade"}, {38,"Hypnosis"} })
add(94, "Gengar", "Ghost", "Poison", 60, 65, 60, 130, 110,
    { {1,"ConfuseRay"}, {29,"NightShade"}, {38,"Hypnosis"}, {48,"DreamEater"} })
add(95, "Onix", "Rock", "Ground", 35, 45, 160, 30, 70,
    { {1,"Tackle"}, {15,"Screech"}, {19,"Bind2"}, {25,"RockThrow"}, {33,"Harden"}, {43,"Earthquake"}, {53,"DoubleEdge"} })
add(96, "Drowzee", "Psychic", nil, 60, 48, 45, 90, 42,
    { {1,"Pound2"}, {12,"Hypnosis"}, {17,"Disable"}, {24,"Confusion"}, {29,"Headbutt2"}, {32,"PoisonSting2"}, {37,"Psychic"} })
add(97, "Hypno", "Psychic", nil, 85, 73, 70, 115, 67,
    { {1,"Pound2"}, {12,"Hypnosis"}, {17,"Disable"}, {24,"Confusion"}, {33,"Headbutt2"}, {37,"PoisonSting2"}, {45,"Psychic"} })
add(98, "Krabby", "Water", nil, 30, 105, 90, 25, 50,
    { {1,"Bubble2"}, {12,"Leer"}, {16,"ViseGrip2"}, {23,"Harden"}, {30,"Stomp2"}, {38,"Crabhammer2"} })
add(99, "Kingler", "Water", nil, 55, 130, 115, 50, 75,
    { {1,"Bubble2"}, {12,"Leer"}, {16,"ViseGrip2"}, {23,"Harden"}, {30,"Stomp2"}, {42,"Crabhammer2"} })
add(100, "Voltorb", "Electric", nil, 40, 30, 50, 55, 100,
    { {1,"Tackle"}, {17,"SonicBoom2"}, {22,"SelfDestruct"}, {29,"Swift"}, {36,"Explosion"}, {43,"MirrorCoat2"} })

-- 101-110
add(101, "Electrode", "Electric", nil, 60, 50, 70, 80, 140,
    { {1,"Tackle"}, {17,"SonicBoom2"}, {22,"SelfDestruct"}, {29,"Swift"}, {40,"Explosion"}, {50,"MirrorCoat2"} })
add(102, "Exeggcute", "Grass", "Psychic", 60, 40, 80, 60, 40,
    { {1,"Barrage2"}, {28,"Hypnosis"}, {32,"PoisonSting"}, {37,"StunSpore"}, {42,"SolarBeam"} })
add(103, "Exeggutor", "Grass", "Psychic", 95, 95, 85, 125, 55,
    { {1,"Barrage2"}, {28,"Hypnosis"}, {32,"PoisonSting"}, {37,"StunSpore"}, {48,"SolarBeam"} })
add(104, "Cubone", "Ground", nil, 50, 50, 95, 40, 35,
    { {1,"Growl"}, {10,"TailWhip"}, {13,"Headbutt2"}, {18,"Leer"}, {25,"FocusEnergy2"}, {31,"Bonemerang"}, {38,"SkullBash2"} })
add(105, "Marowak", "Ground", nil, 60, 80, 110, 50, 45,
    { {1,"Growl"}, {10,"TailWhip"}, {13,"Headbutt2"}, {18,"Leer"}, {25,"FocusEnergy2"}, {33,"Bonemerang"}, {41,"SkullBash2"} })
add(106, "Hitmonlee", "Fighting", nil, 50, 120, 53, 35, 87,
    { {1,"DoubleKick"}, {33,"HiJumpKick"}, {38,"JumpKick"}, {43,"RollingKick"}, {48,"FocusEnergy2"} })
add(107, "Hitmonchan", "Fighting", nil, 50, 105, 79, 35, 76,
    { {1,"CometPunch2"}, {33,"FirePunch"}, {38,"IcePunch"}, {43,"ThunderPunch"}, {48,"MegaPunch"} })
add(108, "Lickitung", "Normal", nil, 90, 55, 75, 60, 30,
    { {1,"Lick2"}, {7,"Supersonic"}, {15,"Stomp2"}, {23,"Wrap2"}, {31,"Disable"}, {39,"Slam2"} })
add(109, "Koffing", "Poison", nil, 40, 65, 95, 60, 35,
    { {1,"Tackle"}, {32,"Sludge"}, {37,"Smog"}, {40,"SelfDestruct"}, {45,"Haze2"}, {48,"Explosion"} })
add(110, "Weezing", "Poison", nil, 65, 90, 120, 85, 60,
    { {1,"Tackle"}, {32,"Sludge"}, {37,"Smog"}, {40,"SelfDestruct"}, {49,"Haze2"}, {53,"Explosion"} })

-- 111-120
add(111, "Rhyhorn", "Ground", "Rock", 80, 85, 95, 30, 25,
    { {1,"HornAttack2"}, {30,"Stomp2"}, {35,"TailWhip"}, {40,"FuryAttack2"}, {45,"HornDrill2"}, {50,"Earthquake"} })
add(112, "Rhydon", "Ground", "Rock", 105, 130, 120, 45, 40,
    { {1,"HornAttack2"}, {30,"Stomp2"}, {35,"TailWhip"}, {40,"FuryAttack2"}, {48,"HornDrill2"}, {55,"Earthquake"} })
add(113, "Chansey", "Normal", nil, 250, 5, 5, 105, 50,
    { {1,"Pound2"}, {12,"TailWhip"}, {24,"SoftBoiled"}, {30,"DoubleSlap2"}, {38,"Minimize2"}, {44,"DefenseCurl2"}, {48,"LightScreen2"} })
add(114, "Tangela", "Grass", nil, 65, 55, 115, 100, 60,
    { {1,"Absorb"}, {24,"Bind2"}, {27,"StunSpore"}, {29,"PoisonSting"}, {32,"SleepPowder"}, {36,"Slam2"}, {41,"Growth2"} })
add(115, "Kangaskhan", "Normal", nil, 105, 95, 80, 40, 90,
    { {1,"CometPunch2"}, {26,"Bite2"}, {31,"TailWhip"}, {36,"MegaPunch"}, {41,"Leer"}, {46,"DizzyPunch2"} })
add(116, "Horsea", "Water", nil, 30, 40, 70, 70, 60,
    { {1,"Bubble2"}, {19,"Smokescreen2"}, {24,"Leer"}, {30,"WaterGun"}, {37,"Agility"}, {45,"HydroPump"} })
add(117, "Seadra", "Water", nil, 55, 65, 95, 95, 85,
    { {1,"Bubble2"}, {19,"Smokescreen2"}, {24,"Leer"}, {30,"WaterGun"}, {41,"Agility"}, {52,"HydroPump"} })
add(118, "Goldeen", "Water", nil, 45, 67, 60, 50, 63,
    { {1,"Peck"}, {19,"Supersonic"}, {24,"HornAttack2"}, {30,"FuryAttack2"}, {37,"Waterfall"}, {45,"HornDrill2"} })
add(119, "Seaking", "Water", nil, 80, 92, 65, 80, 68,
    { {1,"Peck"}, {19,"Supersonic"}, {24,"HornAttack2"}, {30,"FuryAttack2"}, {39,"Waterfall"}, {48,"HornDrill2"} })
add(120, "Staryu", "Water", nil, 30, 45, 55, 70, 85,
    { {1,"Tackle"}, {17,"WaterGun"}, {22,"Harden"}, {27,"Recover"}, {32,"Swift"}, {37,"Minimize2"}, {42,"HydroPump"} })

-- 121-130
add(121, "Starmie", "Water", "Psychic", 60, 75, 85, 100, 115,
    { {1,"Tackle"}, {17,"WaterGun"}, {22,"Harden"}, {27,"Recover"}, {32,"Swift"}, {37,"Minimize2"}, {42,"HydroPump"}, {47,"Psychic"} })
add(122, "MrMime", "Psychic", nil, 40, 45, 65, 100, 90,
    { {1,"Barrier"}, {15,"Confusion"}, {23,"DoubleSlap2"}, {31,"Meditate"}, {39,"Substitute2"}, {47,"Psychic"} })
add(123, "Scyther", "Bug", "Flying", 70, 110, 80, 55, 105,
    { {1,"QuickAttack"}, {17,"Leer"}, {24,"FocusEnergy2"}, {29,"DoubleTeam2"}, {35,"Slash"}, {42,"SwordsDance2"}, {50,"Agility"} })
add(124, "Jynx", "Ice", "Psychic", 65, 50, 35, 95, 95,
    { {1,"Pound2"}, {18,"Lick"}, {23,"DoubleSlap2"}, {31,"IcePunch"}, {39,"BodySlam"}, {47,"LovelyKiss2"}, {55,"Blizzard"} })
add(125, "Electabuzz", "Electric", nil, 65, 83, 57, 85, 105,
    { {1,"QuickAttack"}, {34,"ThunderShock"}, {37,"LightScreen2"}, {42,"ThunderPunch"}, {49,"Thunder"} })
add(126, "Magmar", "Fire", nil, 65, 95, 57, 85, 93,
    { {1,"Ember"}, {36,"Leer"}, {39,"Smokescreen2"}, {43,"FirePunch"}, {48,"Smog"}, {54,"Flamethrower"} })
add(127, "Pinsir", "Bug", nil, 65, 125, 100, 55, 85,
    { {1,"ViseGrip2"}, {25,"Bind2"}, {30,"SeismicToss"}, {36,"Harden"}, {43,"Slash"}, {49,"Submission"} })
add(128, "Tauros", "Normal", nil, 75, 100, 95, 70, 110,
    { {1,"Tackle"}, {21,"Stomp2"}, {28,"TailWhip"}, {35,"Leer"}, {44,"Rest"}, {51,"HyperBeam"} })
add(129, "Magikarp", "Water", nil, 20, 10, 55, 20, 80,
    { {1,"Splash2"}, {15,"Tackle"} })
add(130, "Gyarados", "Water", "Flying", 95, 125, 79, 100, 81,
    { {1,"Splash2"}, {20,"Tackle"}, {25,"Leer"}, {32,"Waterfall"}, {41,"HydroPump"}, {52,"HyperBeam"} })

-- 131-140
add(131, "Lapras", "Water", "Ice", 130, 85, 80, 95, 60,
    { {1,"WaterGun"}, {16,"Growl"}, {20,"Sing2"}, {27,"Mist2"}, {34,"BodySlam"}, {41,"ConfuseRay"}, {48,"IceBeam"}, {55,"HydroPump"} })
add(132, "Ditto", "Normal", nil, 48, 48, 48, 48, 48,
    { {1,"Transform2"} })
add(133, "Eevee", "Normal", nil, 55, 55, 50, 65, 55,
    { {1,"Tackle"}, {8,"SandAttack2"}, {16,"Growl"}, {23,"QuickAttack"}, {30,"Bite2"}, {36,"TakeDown"} })
add(134, "Vaporeon", "Water", nil, 130, 65, 60, 110, 65,
    { {1,"Tackle"}, {8,"SandAttack2"}, {16,"WaterGun"}, {23,"QuickAttack"}, {30,"AuroraBeam"}, {36,"Haze2"}, {42,"AcidArmor2"}, {47,"HydroPump"} })
add(135, "Jolteon", "Electric", nil, 65, 65, 60, 110, 130,
    { {1,"Tackle"}, {8,"SandAttack2"}, {16,"ThunderShock"}, {23,"QuickAttack"}, {30,"DoubleKick"}, {36,"PinMissile"}, {42,"Agility"}, {47,"Thunder"} })
add(136, "Flareon", "Fire", nil, 65, 130, 60, 110, 65,
    { {1,"Tackle"}, {8,"SandAttack2"}, {16,"Ember"}, {23,"QuickAttack"}, {30,"Leer"}, {36,"FireSpin"}, {42,"Smog"}, {47,"Flamethrower"} })
add(137, "Porygon", "Normal", nil, 65, 60, 70, 75, 40,
    { {1,"Tackle"}, {23,"Psybeam"}, {28,"Agility"}, {35,"Recover"}, {42,"HyperBeam"} })
add(138, "Omanyte", "Rock", "Water", 35, 40, 100, 90, 35,
    { {1,"WaterGun"}, {34,"HornAttack2"}, {39,"Leer"}, {46,"SpikeCannon2"}, {53,"HydroPump"} })
add(139, "Omastar", "Rock", "Water", 70, 60, 125, 115, 55,
    { {1,"WaterGun"}, {34,"HornAttack2"}, {39,"Leer"}, {44,"SpikeCannon2"}, {53,"HydroPump"} })
add(140, "Kabuto", "Rock", "Water", 30, 80, 90, 45, 55,
    { {1,"Scratch2"}, {34,"Absorb"}, {39,"Leer"}, {44,"Harden"}, {49,"HydroPump"} })

-- 141-151
add(141, "Kabutops", "Rock", "Water", 60, 115, 105, 70, 80,
    { {1,"Scratch2"}, {34,"Absorb"}, {39,"Leer"}, {46,"Harden"}, {53,"Slash"}, {60,"HydroPump"} })
add(142, "Aerodactyl", "Rock", "Flying", 80, 105, 65, 60, 130,
    { {1,"WingAttack"}, {33,"Supersonic"}, {38,"Bite2"}, {45,"TakeDown"}, {54,"HyperBeam"} })
add(143, "Snorlax", "Normal", nil, 160, 110, 65, 65, 30,
    { {1,"Headbutt2"}, {35,"Rest"}, {41,"BodySlam"}, {48,"HyperBeam"} })
add(144, "Articuno", "Ice", "Flying", 90, 85, 100, 125, 85,
    { {1,"Peck"}, {51,"Blizzard"}, {55,"Agility"}, {60,"Reflect2"}, {65,"IceBeam"} })
add(145, "Zapdos", "Electric", "Flying", 90, 90, 85, 125, 100,
    { {1,"Peck"}, {51,"ThunderShock"}, {55,"DrillPeck"}, {60,"Agility"}, {65,"Thunder"} })
add(146, "Moltres", "Fire", "Flying", 90, 100, 90, 125, 90,
    { {1,"Peck"}, {51,"Ember"}, {55,"FireSpin"}, {60,"Agility"}, {65,"SkyAttack2"} })
add(147, "Dratini", "Dragon", nil, 41, 64, 45, 50, 50,
    { {1,"Wrap2"}, {10,"Leer"}, {20,"ThunderWave"}, {30,"Agility"}, {40,"Slam2"}, {50,"DragonRage"} })
add(148, "Dragonair", "Dragon", nil, 61, 84, 65, 70, 70,
    { {1,"Wrap2"}, {10,"Leer"}, {20,"ThunderWave"}, {30,"Agility"}, {40,"Slam2"}, {55,"DragonRage"} })
add(149, "Dragonite", "Dragon", "Flying", 91, 134, 95, 100, 80,
    { {1,"Wrap2"}, {10,"Leer"}, {20,"ThunderWave"}, {30,"Agility"}, {40,"Slam2"}, {55,"DragonRage"}, {60,"HyperBeam"} })
add(150, "Mewtwo", "Psychic", nil, 106, 110, 90, 154, 130,
    { {1,"Confusion"}, {22,"Disable"}, {33,"Swift"}, {44,"Psybeam"}, {55,"Recover"}, {66,"Psychic"}, {77,"Amnesia"}, {88,"Barrier"} })
add(151, "Mew", "Psychic", nil, 100, 100, 100, 100, 100,
    { {1,"Pound2"}, {10,"Transform2"} })

PokemonData.list = P

PokemonData.byName = {}
for id, p in pairs(P) do
    PokemonData.byName[p.name:lower()] = id
end

function PokemonData.get(id)
    return P[id]
end

function PokemonData.getByName(name)
    local id = PokemonData.byName[(name or ""):lower()]
    return id or nil
end

function PokemonData.count()
    local n = 0
    for _ in pairs(P) do n = n + 1 end
    return n
end

return PokemonData
