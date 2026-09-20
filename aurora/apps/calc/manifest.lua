return {
  id = "calc",
  name = "Calculator",
  summary = "Arithmetic with a tape of everything you worked out",
  keywords = "maths math arithmetic compute numbers",
  category = "Utilities",
  main = "main.lua",
  singleton = true,
  char = "\254",
  window = { w = 26, h = 14, resizable = true },
  icon = {
    colour = colours.cyan,
    glyphColour = colours.white,
    art = {
      "########",
      "#.####.#",
      "#......#",
      "#.#.#.#.",
      "########",
    },
  },
}
