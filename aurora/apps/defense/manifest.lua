return {
  id = "defense",
  name = "Defense",
  summary = "Arm the base, drive doors and traps, watch for intruders",
  keywords = "security alarm base military door trap turret redstone guard",
  category = "Network",
  main = "main.lua",
  singleton = true,
  char = "\030",
  window = { w = 44, h = 16 },
  icon = {
    colour = colours.red,
    glyphColour = colours.white,
    accent = colours.orange,
    art = {
      "..####..",
      ".######.",
      "########",
      ".######.",
      "..####..",
    },
  },
}
