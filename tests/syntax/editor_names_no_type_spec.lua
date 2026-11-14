-- The editor names no file type: what differs between Lua,
-- Markdown and text is the syntax's to say (rulings.md, "The
-- syntax processor"). The editor's controllers, its models
-- and its views are read as source.

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

describe("the editor's source #syntax", function()
  it("names no file type", function()
    local list = assert(io.popen(FILES))
    local found, files = { }, 0
    for path in list:lines() do
      files = files + 1
      local ln = 0
      for line in io.lines(path) do
        ln = ln + 1
        for _, p in ipairs(NAMES) do
          if string.find(line, p) then
            found[#found + 1] = path .. ":" .. ln .. ": " .. line
          end
        end
      end
    end
    list:close()
    assert.is_true(8 <= files)
    assert.same({ }, found)
  end)
end)
