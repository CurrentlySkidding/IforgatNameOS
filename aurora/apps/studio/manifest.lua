return {
  id = "studio",
  name = "Studio",
  summary = "Write SimpleLang, build it, run it",
  keywords = "code ide develop build compile simplelang sl program project app",
  category = "Development",
  main = "main.lua",
  singleton = false,
  char = "\187",
  handles = { "code" },
  window = { w = 48, h = 17 },
  icon = {
    colour = colours.magenta,
    glyphColour = colours.white,
    accent = colours.purple,
    art = {
      "..#...#.",
      ".#.....#",
      "#..###..",
      ".#.....#",
      "..#...#.",
    },
  },
}
