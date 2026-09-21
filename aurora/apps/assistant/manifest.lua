return {
  id = "assistant",
  name = "Aria",
  summary = "Ask about Minecraft, run the computer, check the base",
  keywords = "ai assistant help chat bot ask aria question recipe",
  category = "Utilities",
  main = "main.lua",
  singleton = true,
  char = "\002",
  window = { w = 42, h = 16 },
  icon = {
    colour = colours.purple,
    glyphColour = colours.white,
    accent = colours.magenta,
    art = {
      "..####..",
      ".#.##.#.",
      ".######.",
      ".#....#.",
      "..#..#..",
    },
  },
}
