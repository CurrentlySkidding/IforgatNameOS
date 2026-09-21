return {
  id = "messages",
  name = "Messages",
  summary = "Encrypted chat with the computers on your network",
  keywords = "chat talk message im rednet friends network send",
  category = "Network",
  main = "main.lua",
  singleton = true,
  char = "\004",
  window = { w = 40, h = 15 },
  icon = {
    colour = colours.green,
    glyphColour = colours.white,
    accent = colours.lime,
    art = {
      "########",
      "#......#",
      "#......#",
      "###..###",
      "..##....",
    },
  },
}
