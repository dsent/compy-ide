require('util.table')

--- @alias blocknum integer

--- @class RequireCall
--- @field line integer
--- @field name string --- as the text writes it
--- @field file string --- the file it names
--- @field block blocknum

--- @class BufferSemanticInfo
--- @field requires RequireCall[]

--- The files a buffer names, each with its block
--- @param refs table[] --- the syntax's references
--- @param rev table --- source line to block
--- @return BufferSemanticInfo
local function convert(refs, rev)
  local blockmap = function(a)
    local r = table.clone(a)
    r.block = rev[a.line]
    return r
  end
  return {
    requires = table.map(refs, blockmap),
  }
end

return {
  convert = convert,
}
