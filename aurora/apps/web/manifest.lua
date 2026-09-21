return {
  id = "web",
  name = "Web",
  summary = "Browse and host sites on your world's network",
  keywords = "internet browser site page host www network surf",
  category = "Network",
  main = "main.lua",
  singleton = false,
  char = "\015",
  handles = { "page" },
  window = { w = 44, h = 16 },
  icon = {
    colour = colours.cyan,
    glyphColour = colours.white,
    accent = colours.lightBlue,
    art = {
      "..####..",
      ".#.##.#.",
      "########",
      ".#.##.#.",
      "..####..",
    },
  },
}
