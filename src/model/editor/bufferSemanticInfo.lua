require('util.table')

--- @alias blocknum integer

--- @class RequireCall
--- @field line integer
--- @field name string
--- @field file boolean? --- dofile's: the name is the file
--- @field block blocknum

--- @class BufferSemanticInfo
--- @field requires RequireCall[]

--- The files a buffer names, each with its block
--- @param refs table[] --- luaLayer.references
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
