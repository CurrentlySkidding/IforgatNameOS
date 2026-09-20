return {
  id = "sheets",
  name = "Sheets",
  summary = "Spreadsheets with live formulas and charts",
  keywords = "spreadsheet table calc excel csv formula chart office",
  category = "Office",
  main = "main.lua",
  singleton = false,
  char = "\254",
  handles = { "sheet" },
  window = { w = 48, h = 17 },
  icon = {
    colour = colours.green,
    glyphColour = colours.white,
    accent = colours.lime,
    art = {
      "########",
      "##.##.##",
      "########",
      "##.##.##",
      "########",
    },
  },
}
