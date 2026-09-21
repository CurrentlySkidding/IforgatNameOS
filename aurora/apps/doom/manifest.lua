return {
  id = "doom",
  name = "Doom",
  summary = "Shoot your way through a raycast demon maze",
  keywords = "game 3d doom fps maze shooter first person play",
  category = "Games",
  main = "main.lua",
  singleton = true,
  char = "\16",
  window = { w = 44, h = 16, resizable = true },
  icon = {
    colour = colours.red,
    glyphColour = colours.orange,
    accent = colours.yellow,
    art = {
      "#......#",
      ".#....#.",
      "..#++#..",
      ".#....#.",
      "#......#",
    },
  },
}
