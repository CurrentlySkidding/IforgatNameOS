return {
  id = "editor",
  name = "Text Editor",
  summary = "Edit code and plain text with syntax highlighting",
  keywords = "code lua text edit source script notepad",
  category = "Utilities",
  main = "main.lua",
  singleton = false,
  char = "\187",
  handles = { "text", "code", "*" },
  window = { w = 46, h = 16 },
  icon = {
    colour = colours.purple,
    glyphColour = colours.white,
    accent = colours.magenta,
    art = {
      "########",
      "........",
      "#####...",
      "........",
      "######..",
    },
  },
}
