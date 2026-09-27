-- Continuous-session idiom (doc/input_api.md, "Submit
-- lifecycle"): consume the text in on_text_entered. The widget
-- stays shown by default and submit clears the field, so the
-- next line starts empty with no callback and no re-show. No
-- lifecycle flag is configured here: the defaults are exactly
-- what a continuous prompt wants.
compy.input.show({
  on_text_entered = function(text)
    print(text)
  end
})
