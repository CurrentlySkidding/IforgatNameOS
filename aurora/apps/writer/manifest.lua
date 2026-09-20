return {
  id = "writer",
  name = "Writer",
  summary = "Write, format and print documents",
  keywords = "word document office letter report print markdown",
  category = "Office",
  main = "main.lua",
  singleton = false,
  char = "\254",
  handles = { "doc", "text" },
  window = { w = 48, h = 17 },
  icon = {
    colour = colours.lightBlue,
    glyphColour = colours.white,
    accent = colours.blue,
    art = {
      "########",
      "#......#",
      "#.####.#",
      "#.##...#",
      "########",
    },
  },
}
