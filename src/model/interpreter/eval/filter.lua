local class = require('util.class')
require('model.lang.lua.error')

--- AST scope, i.e. where a validation applies
--- @class Scope

--- @alias ValidatorFilter fun(string): boolean, string|Error?
--- @alias AstValidatorFilter fun(AST): boolean, string|Error?
--- @alias TransformerFilter fun(string): string

--- @class Filters
--- @field line_validators ValidatorFilter[]
--- @field astValidators AstValidatorFilter[]
--- @field transformers TransformerFilter[]
--- @field validators_only function
--- @field validate function

Filters = class.create(function(v, av, tf)
  return {
    line_validators = v,
    astValidators = av,
    transformers = tf,
  }
end)

--- @param flt function|function[]
--- @return Filters
function Filters.validators_only(flt)
  local fs = {}
  if type(flt) == 'function' then
    fs = { flt }
  end
  if type(flt) == 'table' then
    for _, v in ipairs(flt) do
      if type(v) == 'function' then
        table.insert(fs, v)
      end
    end
  end
  return Filters(fs)
end

--- Run line validators over a text, collecting one Error per
--- offending line. A one-line text is validated as a whole and its
--- errors carry that text's own position.
--- @param validators ValidatorFilter[]
--- @param s string[]
--- @return boolean valid
--- @return Error[] errors
function Filters.validate(validators, s)
  local errors = {}
  local valid = true

  for _, fv in ipairs(validators or {}) do
    if #s == 1 then
      local ok, verr = fv(s[1])
      if not ok and verr then
        valid = false
        table.insert(errors, Error.wrap(verr))
      end
    else
      for i, l in ipairs(s) do
        local ok, verr = fv(l)
        if not ok and verr then
          valid = false
          local e = Error.wrap(verr)
          --- A validator that reports a bare message is reporting on
          --- the line it was handed. One that builds its own Error
          --- has already said where it is.
          if type(verr) == 'string' then e.l = i end
          table.insert(errors, e)
        end
      end
    end
  end
  return valid, errors
end
