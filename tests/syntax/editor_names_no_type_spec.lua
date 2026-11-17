-- The editor names no file type: what differs between Lua,
-- Markdown and text is the syntax's to say (rulings.md, "The
-- syntax processor"). The editor's controllers, its models
-- and its views are read as source.
--
-- Nor do the editor and the field know an unfinished draft:
-- what one comes to is the syntax's to say (rulings.md, "An
-- unfinished draft is the syntax's to continue"). They and
-- the field's controller, model and view are read as source,
-- comments included.

local FILES = "ls src/controller/editor*.lua"
    .. " src/model/editor/bufferModel.lua"
    .. " src/model/editor/editorModel.lua"
    .. " src/view/editor/*.lua"

--- Lua patterns of a file type named in source
local NAMES = {
  "content_type",
  "['\"]lua['\"]",
  "['\"]md['\"]",
  "['\"]markdown['\"]",
  "['\"]plain['\"]",
  "%%%.lua%$",
}

local FIELD = FILES
    .. " src/controller/userInputController.lua"
    .. " src/model/input/userInputModel.lua"
    .. " src/view/input/*.lua"

--- Lua patterns of a draft's continuation named in source
local CONTINUATION = {
  "%f[%w_]at_end%f[^%w_]",
  "[Uu]nfinished",
  "continue_line",
}

--- @param files string --- a shell glob of the files
--- @param patterns string[]
--- @return string[] found --- path:line: text of each match
--- @return integer files
local function scan(files, patterns)
  local list = assert(io.popen(files))
  local found, n = { }, 0
  for path in list:lines() do
    n = n + 1
    local ln = 0
    for line in io.lines(path) do
      ln = ln + 1
      for _, p in ipairs(patterns) do
        if string.find(line, p) then
          found[#found + 1] = path .. ":" .. ln .. ": " .. line
        end
      end
    end
  end
  list:close()
  return found, n
end

describe("the editor's source #syntax", function()
  it("names no file type", function()
    local found, files = scan(FILES, NAMES)
    assert.is_true(8 <= files)
    assert.same({ }, found)
  end)

  it("leaves an unfinished draft to the syntax", function()
    local found, files = scan(FIELD, CONTINUATION)
    assert.is_true(11 <= files)
    assert.same({ }, found)
  end)
end)
