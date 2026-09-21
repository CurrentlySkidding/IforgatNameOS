return {
  id = "monitor",
  name = "System",
  summary = "Processes, devices, storage and the kernel log",
  keywords = "task manager processes performance log devices disk",
  category = "System",
  main = "main.lua",
  singleton = true,
  char = "\254",
  window = { w = 46, h = 16 },
  icon = {
    colour = colours.red,
    glyphColour = colours.white,
    accent = colours.pink,
    art = {
      "......##",
      "...##.##",
      "..###.##",
      "##.##.##",
      "########",
    },
  },
}
