return {
  id = "terminal",
  name = "Terminal",
  summary = "A full CraftOS shell in a window",
  keywords = "shell console command prompt craftos lua",
  category = "System",
  main = "main.lua",
  singleton = false,
  char = "\016",
  handles = { "code" },
  window = { w = 44, h = 15 },
  icon = {
    colour = colours.black,
    glyphColour = colours.lime,
    art = {
      "#.......",
      ".#......",
      "..#.....",
      ".#......",
      "#...####",
    },
  },
}
