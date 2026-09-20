return {
  id = "files",
  name = "Files",
  summary = "Browse, organise and open your documents",
  keywords = "folder directory explorer browse disk storage trash",
  category = "System",
  main = "main.lua",
  singleton = false,
  char = "\254",
  handles = { "folder" },
  window = { w = 46, h = 16 },
  icon = {
    colour = colours.blue,
    glyphColour = colours.white,
    accent = colours.lightBlue,
    art = {
      "###.....",
      "########",
      "#......#",
      "#......#",
      "########",
    },
  },
}
