--- The syntax processors (rulings.md, "The syntax
--- processor"): a module per language or format that
--- answers the syntax API for the editor, the formatter and
--- the console's `tidy()`. A file's syntax is chosen by its
--- name's extension; any other name is text.
---
--- The syntax API, which every processor answers:
--- * `name` --- its name
--- * `spans_lines` --- whether a block may span lines
--- * `blocks(lines)` --- a file's blocks, tiling lines 1 to n;
---   nil when the syntax cannot split the text
--- * `submit(lines, width, max_block)` --- a draft's verdict
---   (SyntaxVerdict): its blocks when accepted, else a
---   failure or a refusal
--- * `format(lines, width)` --- the text formatted:
---   text, ok, and when not ok why
--- * `loads(lines)` --- whether the file holds together after
---   a change: ok, why, merges
--- * `highlight(lines)` --- the text's colors, or nil
--- * `references(lines)` --- the files the text names
--- * `evaluator()` --- the editor field's evaluator

local M = {}

--- extension to processor module
local BY_EXTENSION = {
  lua = 'model.syntax.lua',
  md = 'model.syntax.markdown',
}

--- processors registered at run time, by extension
local registered = {}

--- The syntax of a file by its name
--- @param name string?
--- @return table
function M.for_name(name)
  local ext = name and string.match(name, '%.([^%.]+)$')
  if ext and registered[ext] then return registered[ext] end
  return require(ext and BY_EXTENSION[ext] or 'model.syntax.text')
end

--- Give the files whose name ends in `.ext` a syntax of
--- their own; nil takes it back
--- @param ext string
--- @param processor table?
function M.register(ext, processor)
  registered[ext] = processor
end

return M
