return {
  id = "builder",
  name = "App Builder",
  summary = "Design, code and publish real Aurora apps",
  keywords = "develop ide designer create app project export github",
  category = "Development",
  main = "main.lua",
  singleton = false,
  char = "\254",
  handles = { "code" },
  window = { w = 50, h = 18 },
  icon = {
    colour = colours.magenta,
    glyphColour = colours.white,
    accent = colours.purple,
    art = {
      "..####..",
      "..#..#..",
      "####..##",
      "..#..#..",
      "..####..",
    },
  },
}
