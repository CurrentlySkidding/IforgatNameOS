return {
  id = "settings",
  name = "Settings",
  summary = "Appearance, displays, printers, network and system",
  keywords = "preferences config theme wallpaper accent monitor printer about",
  category = "System",
  main = "main.lua",
  singleton = true,
  char = "\004",
  window = { w = 48, h = 17 },
  icon = {
    colour = colours.lightGrey,
    glyphColour = colours.white,
    accent = colours.white,
    art = {
      "..####..",
      ".######.",
      "##.##.##",
      ".######.",
      "..####..",
    },
  },
}
