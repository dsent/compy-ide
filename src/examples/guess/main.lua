math.randomseed(os.time())
N = 100
-- number_to_guess
ntg = 0

function init()
  print("Welcome to the guessing game!")
  ntg = math.random(N)
end

function is_natural(s)
  local digits = string.usub(s, 1)
  local ok, err_c = string.forall(digits, Char.is_digit)
  if ok then
    return true
  end
  return false, Error(
    "The guess should be a positive number",
    err_c
  )
end

function check(n)
  if not n then
    return
  end
  if ntg < n then
    print("The number is lower")
  elseif n < ntg then
    print("The number is higher")
  else
    print("Correct!")
    print("\n\n")
    init()
  end
end

-- Continuous-session idiom (doc/input_api.md, "Submit
-- lifecycle"): the widget stays shown by default (no
-- auto-close) and submit clears the field, so the next guess
-- starts empty with nothing to re-show and nothing to re-arm.
-- The line validator keeps invalid guesses out of the submit
-- callback. Escape is a no-op by default, so it cannot strand
-- this game's only input surface and needs no callback either.
-- This project therefore configures no lifecycle flag at
-- all — the defaults are what a continuous prompt wants.

init()

-- TODO: guess is input-only/live now (project_open ruling
-- a); rework check()'s print() feedback to go through the
-- on-screen input API / draw instead of the console terminal.
compy.input.show({
  prompt = "Guess a number:",
  validator = LineValidators({ is_natural }),
  on_text_entered = function(text)
    check(tonumber(text))
  end
})
