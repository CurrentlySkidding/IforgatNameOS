return {
  id = "slides",
  name = "Slides",
  summary = "Build decks and present them on a monitor wall",
  keywords = "presentation deck slideshow present monitor office",
  category = "Office",
  main = "main.lua",
  singleton = false,
  char = "\254",
  handles = { "slides" },
  window = { w = 48, h = 17 },
  icon = {
    colour = colours.orange,
    glyphColour = colours.white,
    accent = colours.yellow,
    art = {
      "########",
      "#......#",
      "#.####.#",
      "########",
      "...##...",
    },
  },
}
