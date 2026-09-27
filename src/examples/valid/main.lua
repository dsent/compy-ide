function min_length(n)
  return function(s)
    local l = string.ulen(s)
    if n < l then
      return true
    end
    return false, Error("too short!", l)
  end
end

function max_length(n)
  return function(s)
    if string.len(s) <= n then
      return true
    end
    return false, Error("too long!", n + 1)
  end
end

function keepScanning(ret, i, l)
  return ret and i <= l
end

function notUpper(s, i)
  local v = string.usub(s, i, i)
  return v ~= string.upper(v)
end

function scanUpper(s)
  local ret = true
  local l = string.ulen(s)
  local err_c
  local i = 1
  while keepScanning(ret, i, l) do
    if notUpper(s, i) then
      ret = false
      err_c = i
    end
    i = i + 1
  end
  return ret, err_c
end

function is_upper(s)
  local ret, err_c = scanUpper(s)
  if ret then
    return true
  end
  return false, Error("should be all uppercase", err_c)
end

function is_lower(s)
  local ok, err_c = string.forall(s, Char.is_lower)
  if ok then
    return true
  end
  return false, Error("should be lowercase", err_c)
end

function is_number(s)
  local sign = string.usub(s, 1, 1)
  local offset = 0
  if sign == "-" then
    offset = 1
  end
  local digits = string.usub(s, 1 + offset)
  local ok, err_c = string.forall(digits, Char.is_digit)
  if ok then
    return true
  end
  return false, Error("NaN", err_c + offset)
end

function is_natural(s)
  local is_num, err = is_number(s)
  if not is_num then
    return false, err
  end
  local n = tonumber(s)
  if n < 0 then
    return false, Error("It's negative!", 1)
  end
end

-- Continuous-session idiom (doc/input_api.md, "Submit
-- lifecycle"): consume the text in on_text_entered. The widget
-- stays shown by default and submit clears the field, so the
-- next line starts empty with no callback and no re-show. The
-- line validator prevents invalid lines from reaching the
-- submit callback. No lifecycle flag is configured here: the
-- defaults are what a continuous prompt wants.
compy.input.show({
  validator = LineValidators({
    min_length(2),
    is_lower
  }),
  on_text_entered = function(text)
    print(text)
  end
})
