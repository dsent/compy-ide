require("util.string.string")
local End = require('util.program_end')

--- @param err string
--- @return integer?
--- @return string?
local function parse_call_error(err)
  if string.is_non_empty_string(err) then
    local line = string.gmatch(err, ':[0-9]+:')()
    if line then
      local ln = tonumber(string.split(line, ':')[2])
      local parts = string.split(err, line)
      if ln then
        return ln, string.trim(parts[2])
      end
    else
      return nil, err
    end
  end
end

--- @param err string
--- @return string
local function get_call_error(err)
  if not err then return '' end
  local ln, msg = parse_call_error(err)
  if ln then
    return 'L' .. ln .. ':' .. msg
  else
    return err
  end
end

--- @param s string
--- @return any
local function eval(s)
  local expr = loadstring('return ' .. s)
  if not expr then return end
  local ok, res = pcall(expr)
  if ok then return res end
  --- a lifecycle call in the expression ends the code that
  --- asked for the eval too (util.program_end)
  if End.is(res) then error(res, 0) end
end

--- @param s string
local function print_eval(s)
  local r = eval(s)
  if r then
    print(r)
  end
  return r
end


return {
  parse_call_error = parse_call_error,
  get_call_error = get_call_error,
  eval = eval,
  print_eval = print_eval,
}
