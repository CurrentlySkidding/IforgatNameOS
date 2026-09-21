--[[ aurora.lib.knowledge ----------------------------------------------------
     What the assistant knows about Minecraft.

     Plain data plus a fuzzy lookup.  Everything here is the sort of thing you
     would otherwise alt-tab to a wiki for: recipes, mob stats, where ores
     actually spawn, what an enchantment tops out at, and how to brew things.
----------------------------------------------------------------------------]]

local util = arequire("lib.util")

local knowledge = {}

------------------------------------------------------------------ recipes --

knowledge.recipes = {
  torch = { how = "Coal or charcoal on top of a stick.", yields = "4 torches" },
  ["crafting table"] = { how = "Four planks in a square.", yields = "1" },
  furnace = { how = "Eight cobblestone in a ring, middle empty.", yields = "1" },
  chest = { how = "Eight planks in a ring, middle empty.", yields = "1" },
  ["ender chest"] = { how = "Eight obsidian in a ring with an eye of ender in the middle.",
                      yields = "1", note = "Shares one inventory across every ender chest you own." },
  bed = { how = "Three wool on top of three planks. The wool must match.", yields = "1" },
  pickaxe = { how = "Three of your material across the top, two sticks down the middle.",
              yields = "1" },
  axe = { how = "Two material in the top-left L shape, two sticks down the middle.", yields = "1" },
  sword = { how = "Two of your material stacked, a stick underneath.", yields = "1" },
  shovel = { how = "One material on top, two sticks below it.", yields = "1" },
  hoe = { how = "Two material across the top-left, two sticks down the middle.", yields = "1" },
  shield = { how = "Six planks in a Y and one iron ingot in the top middle.", yields = "1" },
  bucket = { how = "Three iron ingots in a V.", yields = "1" },
  ["enchanting table"] = {
    how = "A book in the top middle, two diamonds either side of an obsidian, "
       .. "then three obsidian along the bottom.",
    yields = "1",
    note = "Surround it with 15 bookshelves, two blocks away, for level 30.",
  },
  anvil = { how = "Three iron blocks across the top, one iron ingot in the middle, "
                .. "three iron ingots along the bottom.", yields = "1",
            note = "That is 31 iron in total." },
  beacon = { how = "Three glass across the top, a nether star between two glass, "
                .. "three obsidian along the bottom.", yields = "1",
             note = "Needs a pyramid of iron, gold, diamond, emerald or netherite blocks under it." },
  hopper = { how = "Five iron ingots in a V with a chest in the middle.", yields = "1" },
  piston = { how = "Three planks on top, cobble-iron-cobble in the middle, "
                .. "cobble-redstone-cobble along the bottom.", yields = "1" },
  observer = { how = "Three cobblestone on top, redstone-redstone-quartz in the middle, "
                  .. "three cobblestone along the bottom.", yields = "1" },
  repeater = { how = "Two redstone torches with redstone dust between them, "
                  .. "on three stone.", yields = "1" },
  comparator = { how = "Three redstone torches in a T with nether quartz in the middle, "
                    .. "on three stone.", yields = "1" },
  ["redstone torch"] = { how = "Redstone dust on top of a stick.", yields = "1" },
  rail = { how = "Six iron ingots down both sides with a stick in the middle.", yields = "16" },
  ["powered rail"] = { how = "Six gold ingots down both sides, a stick and redstone "
                          .. "in the middle column.", yields = "6" },
  ["brewing stand"] = { how = "A blaze rod on top of three cobblestone.", yields = "1" },
  cauldron = { how = "Seven iron ingots in a U.", yields = "1" },
  tnt = { how = "Five gunpowder and four sand in a checkerboard.", yields = "1" },
  ["daylight sensor"] = { how = "Three glass on top, three nether quartz, "
                             .. "three wooden slabs along the bottom.", yields = "1" },
  cake = { how = "Three milk buckets, then sugar-egg-sugar, then three wheat.", yields = "1" },
  ["golden carrot"] = { how = "Eight gold nuggets around a carrot.", yields = "1" },
  ["glistering melon"] = { how = "Eight gold nuggets around a melon slice.", yields = "1" },
  ["netherite ingot"] = { how = "Four netherite scrap and four gold ingots.", yields = "1",
                          note = "Then use a smithing table with a netherite upgrade template." },
  ["blast furnace"] = { how = "Five iron ingots, a furnace and three smooth stone.", yields = "1" },
  smoker = { how = "A furnace with four logs around it.", yields = "1" },
  lectern = { how = "Four wooden slabs and a bookshelf.", yields = "1" },
  ["smithing table"] = { how = "Two iron ingots on top of four planks.", yields = "1" },
  ["nether portal"] = { how = "Not a recipe: a frame of at least 10 obsidian, "
                           .. "lit with flint and steel.", yields = "1 portal" },
  ["eye of ender"] = { how = "An ender pearl and blaze powder.", yields = "1" },
  ["fire charge"] = { how = "Blaze powder, coal and gunpowder.", yields = "3" },
}

--------------------------------------------------------------------- mobs --

knowledge.mobs = {
  creeper = { hp = 20, damage = "up to 49 at point blank",
              drops = "gunpowder, and a music disc if a skeleton kills it",
              weakness = "Cats and ocelots scare them off. Hit and step back.",
              note = "Charged by lightning they are four times worse." },
  zombie = { hp = 20, damage = "2.5 hearts on hard", drops = "rotten flesh, rarely iron or carrots",
             weakness = "Burns in daylight.", note = "Can break down wooden doors on hard." },
  skeleton = { hp = 20, damage = "2 hearts per arrow", drops = "bones and arrows",
               weakness = "Burns in daylight. Close the distance and it cannot aim.",
               note = "Bones make bone meal." },
  spider = { hp = 16, damage = "1.5 hearts", drops = "string and spider eyes",
             weakness = "Neutral in bright light. They cannot fit through a 1-high gap under a slab.",
             note = "They climb walls, so an overhang stops them." },
  enderman = { hp = 40, damage = "3.5 hearts", drops = "ender pearls",
               weakness = "Water, rain, and standing under a 2-high ceiling so it cannot reach you.",
               note = "Only angry if you look at its head or hit it." },
  witch = { hp = 26, damage = "splash potions", drops = "sticks, glass bottles, redstone, sugar",
            weakness = "Drinks healing potions, so burst it down fast." },
  blaze = { hp = 20, damage = "fireballs, three in a burst", drops = "blaze rods",
            weakness = "Snowballs do real damage to it.",
            note = "Blaze rods make blaze powder, which makes eyes of ender." },
  ghast = { hp = 10, damage = "fireballs", drops = "ghast tears and gunpowder",
            weakness = "Punch or shoot its fireball back at it." },
  ["wither skeleton"] = { hp = 20, damage = "wither effect", drops = "coal, bones, rarely a skull",
                          weakness = "Milk clears the wither effect.",
                          note = "Three skulls plus four soul sand summons the Wither." },
  piglin = { hp = 16, damage = "3 hearts", drops = "whatever they barter",
             weakness = "Wear one piece of gold armour and they ignore you.",
             note = "They turn hostile if you open a chest or mine gold near them." },
  warden = { hp = 500, damage = "one-shots most armour", drops = "a sculk catalyst",
             weakness = "It is blind. Throw a snowball to pull it away, then leave.",
             note = "Do not fight it. Sneak, and stay off sculk sensors." },
  ["ender dragon"] = { hp = 200, damage = "heavy", drops = "12,000 experience and a dragon egg",
                       weakness = "Break the end crystals first, ideally with a bow.",
                       note = "Bring a bed for the perch phase, and water for the fall." },
  wither = { hp = 300, damage = "wither and explosions", drops = "a nether star",
             weakness = "Smite enchantments. Fight it in a small tunnel in the End." },
  villager = { hp = 20, damage = "none", drops = "nothing",
               note = "Trades reset a few times a day. A zombie-cured villager trades very cheap." },
  ["iron golem"] = { hp = 100, damage = "up to 10 hearts", drops = "iron ingots and poppies",
                     note = "Spawns naturally in villages, or build one from four iron blocks "
                         .. "and a carved pumpkin." },
  phantom = { hp = 20, damage = "1.5 hearts", drops = "phantom membranes",
              weakness = "Sleep. They only come after three nights awake.",
              note = "Cats scare them off." },
}

--------------------------------------------------------------------- ores --

knowledge.ores = {
  diamond = { best = "Y -59", range = "Y -64 to 16", tool = "iron pickaxe or better",
              note = "Avoid lava level; -59 is the peak. Fortune III gives up to 4 per ore." },
  iron = { best = "Y 15 and Y 232", range = "Y -64 to 320", tool = "stone pickaxe or better",
           note = "Huge deposits appear in mountains." },
  gold = { best = "Y -16", range = "Y -64 to 32", tool = "iron pickaxe or better",
           note = "Badlands biomes have gold right near the surface." },
  redstone = { best = "Y -59", range = "Y -64 to 16", tool = "iron pickaxe or better" },
  lapis = { best = "Y 0", range = "Y -64 to 64", tool = "stone pickaxe or better" },
  copper = { best = "Y 48", range = "Y -16 to 112", tool = "stone pickaxe or better",
             note = "Dripstone caves are full of it." },
  emerald = { best = "Y 232", range = "mountains only", tool = "iron pickaxe or better",
              note = "Only generates in mountain biomes. Trading is usually faster." },
  coal = { best = "Y 96", range = "Y 0 to 320", tool = "any pickaxe" },
  ["ancient debris"] = { best = "Y 15", range = "Y 8 to 22 in the Nether",
                         tool = "diamond pickaxe or better",
                         note = "Blast-resistant: bed explosions or TNT find it fast." },
  quartz = { best = "anywhere in the Nether", range = "Nether", tool = "any pickaxe" },
}

------------------------------------------------------------- enchantments --

knowledge.enchants = {
  sharpness = { max = "V", what = "More melee damage against everything." },
  smite = { max = "V", what = "Extra damage to undead: zombies, skeletons, the Wither." },
  ["bane of arthropods"] = { max = "V", what = "Extra damage to spiders and silverfish." },
  looting = { max = "III", what = "More and rarer mob drops." },
  ["fire aspect"] = { max = "II", what = "Sets what you hit on fire." },
  knockback = { max = "II", what = "Pushes mobs further away." },
  ["sweeping edge"] = { max = "III", what = "Stronger sweep attack. Java only." },
  efficiency = { max = "V", what = "Mine faster." },
  fortune = { max = "III", what = "More drops from ore, crops and glowstone." },
  ["silk touch"] = { max = "I", what = "Blocks drop themselves. Cannot mix with Fortune." },
  unbreaking = { max = "III", what = "Gear lasts far longer." },
  mending = { max = "I", what = "Experience repairs the item. The best enchantment in the game." },
  protection = { max = "IV", what = "Less damage from everything." },
  ["feather falling"] = { max = "IV", what = "Much less fall damage." },
  ["depth strider"] = { max = "III", what = "Walk faster underwater." },
  respiration = { max = "III", what = "Breathe underwater for longer." },
  ["aqua affinity"] = { max = "I", what = "Mine at full speed underwater." },
  thorns = { max = "III", what = "Hurts whatever hits you, at the cost of durability." },
  power = { max = "V", what = "More bow damage." },
  infinity = { max = "I", what = "Never run out of arrows. Cannot mix with Mending." },
  flame = { max = "I", what = "Arrows set targets on fire." },
  punch = { max = "II", what = "Arrows knock targets back." },
  loyalty = { max = "III", what = "Your trident comes back." },
  riptide = { max = "III", what = "Launches you when wet. Cannot mix with Loyalty." },
  channeling = { max = "I", what = "Summons lightning in a storm." },
  impaling = { max = "V", what = "Extra trident damage to things in water." },
  multishot = { max = "I", what = "Crossbow fires three arrows." },
  piercing = { max = "IV", what = "Crossbow arrows go through mobs." },
  ["quick charge"] = { max = "III", what = "Reload a crossbow faster." },
  ["soul speed"] = { max = "III", what = "Run fast on soul sand." },
  ["swift sneak"] = { max = "III", what = "Sneak at nearly walking speed." },
}

------------------------------------------------------------------ potions --

knowledge.potions = {
  awkward = { base = "Nether wart in a water bottle.",
              note = "Every useful potion starts here." },
  healing = { base = "Glistering melon in an awkward potion." },
  strength = { base = "Blaze powder in an awkward potion." },
  swiftness = { base = "Sugar in an awkward potion." },
  ["fire resistance"] = { base = "Magma cream in an awkward potion.",
                          note = "Essential before the Nether." },
  ["night vision"] = { base = "Golden carrot in an awkward potion." },
  invisibility = { base = "Fermented spider eye in a night vision potion." },
  ["water breathing"] = { base = "Pufferfish in an awkward potion." },
  leaping = { base = "Rabbit's foot in an awkward potion." },
  regeneration = { base = "Ghast tear in an awkward potion." },
  poison = { base = "Spider eye in an awkward potion." },
  weakness = { base = "Fermented spider eye in a water bottle.",
               note = "Weakness plus a golden apple cures a zombie villager." },
  ["slow falling"] = { base = "Phantom membrane in an awkward potion." },
  ["turtle master"] = { base = "Turtle shell in an awkward potion." },
}

knowledge.brewingModifiers = {
  "Redstone makes a potion last longer.",
  "Glowstone makes it stronger but shorter.",
  "Gunpowder turns it into a splash potion.",
  "Dragon's breath turns a splash potion into a lingering one.",
  "A fermented spider eye corrupts a potion into its opposite.",
}

--------------------------------------------------------------------- tips --

knowledge.tips = {
  redstone = {
    "Redstone dust carries 15 blocks, then dies. A repeater resets it to 15.",
    "A repeater also delays signals: 1 to 4 ticks, right-click to change.",
    "A comparator reads containers: the fuller the chest, the stronger the signal.",
    "Put a comparator in subtract mode (front torch lit) to compare two signals.",
    "Observers fire a one-tick pulse when the block in front changes.",
    "Sticky pistons drop the block back unless the pulse is exactly one tick.",
  },
  nether = {
    "Every block in the Nether is 8 blocks in the Overworld. Build your rail there.",
    "Fire resistance and a gold helmet make the Nether nearly safe.",
    "Never carry a bed into the Nether unless you want the explosion.",
    "Ghast fireballs can be punched straight back.",
  },
  survival = {
    "Dig a 1x2 hole and place a block over your head. That is a safe night.",
    "Never dig straight down. Stagger two blocks instead.",
    "Carry water: it stops fall damage and puts out fire.",
    "Sleep every night or phantoms start turning up after three days.",
    "Food: a steady farm of wheat and cows feeds you forever.",
  },
  computercraft = {
    "Turtles need fuel: coal, charcoal, lava buckets. refuel() burns what it holds.",
    "A wireless modem reaches 64 blocks, further the higher you are, and less in storms.",
    "An ender modem reaches any distance, across dimensions.",
    "Monitors tile: place them in a rectangle and they become one big screen.",
    "Attach peripherals with wired modems and a network cable to use them at range.",
    "Disk drives share files between computers, and boot them from a floppy.",
  },
}

------------------------------------------------------------------ lookup ---

local CATEGORIES = {
  { key = "recipes", label = "recipe" },
  { key = "mobs", label = "mob" },
  { key = "ores", label = "ore" },
  { key = "enchants", label = "enchantment" },
  { key = "potions", label = "potion" },
}

--- Strip the filler words people put around a question.
function knowledge.subject(text)
  local subject = tostring(text or ""):lower()
  subject = subject:gsub("[%?%.!,]", " ")
  local patterns = {
    "^.*how do i make ", "^.*how do you make ", "^.*how to make ",
    "^.*how do i craft ", "^.*how to craft ", "^.*recipe for ",
    "^.*what is the recipe for ", "^.*how do i get ", "^.*where do i find ",
    "^.*where can i find ", "^.*what level is ", "^.*what y level is ",
    "^.*tell me about ", "^.*what is a ", "^.*what is an ", "^.*what is ",
    "^.*what are ", "^.*how do i beat ", "^.*how do i kill ", "^.*how to kill ",
    "^.*how do i brew ", "^.*how to brew ", "^.*whats ", "^.*what's ",
    "^.*what does ", "^.*what do ", "^.*how does ", "^.*how good is ",
    "^.*is there ", "^.*do i need ",
  }
  for _, pattern in ipairs(patterns) do
    subject = subject:gsub(pattern, "")
  end
  -- "what does mending do" leaves a trailing verb behind
  for _, tail in ipairs({ " do$", " work$", " mean$", " does$", " good for$",
                          " used for$", " for$" }) do
    subject = subject:gsub(tail, "")
  end
  subject = subject:gsub("^%s*a ", ""):gsub("^%s*an ", ""):gsub("^%s*the ", "")
  subject = subject:gsub("^%s*some ", ""):gsub("%s+", " ")
  return util.trim(subject)
end

--- Find the best entry for a subject across every category.
--- Returns category, key, entry.
function knowledge.find(subject)
  subject = util.trim(tostring(subject or ""):lower())
  if subject == "" then return nil end

  -- exact, then plural, then substring both ways
  for _, category in ipairs(CATEGORIES) do
    local table_ = knowledge[category.key]
    if table_[subject] then return category.label, subject, table_[subject] end
  end
  local singular = subject:gsub("s$", "")
  for _, category in ipairs(CATEGORIES) do
    local table_ = knowledge[category.key]
    if table_[singular] then return category.label, singular, table_[singular] end
  end
  local best, bestKey, bestCategory, bestScore = nil, nil, nil, 0
  for _, category in ipairs(CATEGORIES) do
    for key, entry in pairs(knowledge[category.key]) do
      local score = 0
      if key:find(subject, 1, true) then score = #subject / #key end
      if subject:find(key, 1, true) then score = math.max(score, #key / #subject) end
      if score > bestScore then
        best, bestKey, bestCategory, bestScore = entry, key, category.label, score
      end
    end
  end
  if bestScore >= 0.45 then return bestCategory, bestKey, best end
  return nil
end

--- Format an entry as lines of text for the assistant to say.
function knowledge.describe(category, key, entry)
  local lines = {}
  if category == "recipe" then
    lines[#lines + 1] = entry.how
    if entry.yields then lines[#lines + 1] = "Makes " .. entry.yields .. "." end
  elseif category == "mob" then
    lines[#lines + 1] = ("%s has %d health and deals %s."):format(
      key:sub(1, 1):upper() .. key:sub(2), entry.hp, entry.damage)
    if entry.drops then lines[#lines + 1] = "Drops: " .. entry.drops .. "." end
    if entry.weakness then lines[#lines + 1] = entry.weakness end
  elseif category == "ore" then
    lines[#lines + 1] = ("Best at %s (found %s)."):format(entry.best, entry.range)
    lines[#lines + 1] = "You need a " .. entry.tool .. "."
  elseif category == "enchantment" then
    lines[#lines + 1] = ("%s goes up to %s."):format(
      key:sub(1, 1):upper() .. key:sub(2), entry.max)
    lines[#lines + 1] = entry.what
  elseif category == "potion" then
    lines[#lines + 1] = entry.base
  end
  if entry.note then lines[#lines + 1] = entry.note end
  return lines
end

--- A random tip, optionally from one topic.
function knowledge.tip(topic)
  local pool = {}
  if topic and knowledge.tips[topic] then
    pool = knowledge.tips[topic]
  else
    for _, list in pairs(knowledge.tips) do
      for _, tip in ipairs(list) do pool[#pool + 1] = tip end
    end
  end
  if #pool == 0 then return nil end
  return pool[math.random(1, #pool)]
end

function knowledge.count()
  local total = 0
  for _, category in ipairs(CATEGORIES) do
    for _ in pairs(knowledge[category.key]) do total = total + 1 end
  end
  return total
end

return knowledge
