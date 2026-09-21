return {
  id = "snake",
  name = "Snake",
  summary = "Eat, grow, do not bite yourself",
  keywords = "game snake arcade play fun",
  category = "Games",
  main = "main.lua",
  singleton = true,
  char = "\7",
  window = { w = 40, h = 15, resizable = true },
  icon = {
    colour = colours.green,
    glyphColour = colours.lime,
    accent = colours.red,
    art = {
      "####....",
      "...#....",
      "...####.",
      "......#.",
      "....+.#.",
    },
  },
}
