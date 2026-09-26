require('util.string.string')

--- A text file as the editor and the formatters keep it: its
--- lines, each ended by a newline in the file. The newline
--- after the last line belongs to that line, so a file that
--- ends in one reads as its lines alone, and a blank line at
--- its end is a line like any other.
local M = {}

--- @param text string?
--- @return string[]
function M.lines(text)
  local lines = string.lines(text or '')
  if lines[#lines] == '' then table.remove(lines) end
  return lines
end

--- The file holding these lines: a newline after every one,
--- the last one too, and nothing at all for no lines
--- @param lines string[]
--- @return string
function M.text(lines)
  if #lines == 0 then return '' end
  return string.unlines(lines) .. '\n'
end

return M
