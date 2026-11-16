--- The gate's reserved chords (doc/development/decisions/
--- input.md, D-RESERVE-TABLE), the one list both the gate
--- (controller.lua) and the key cards read. `name` is the
--- gate's action for it; `release`: it acts on its key's
--- release. A surface's words say what the chord does there,
--- by state: a state with none lists it among the other keys,
--- and a surface with none leaves it off its card (Ctrl+Pause
--- works only while a program runs in front; the profiling
--- keys only in a profiling build). `repeats`: a held chord
--- acts on its repeats too, where it reaches a natural stop
--- (the maintainer's ruling of November 16, 2026); Ctrl+T and
--- Ctrl+R act once per press, since each repeat would switch
--- or run anew again.
return {
  { chord = 'ctrl+t', name = 'quickswitch', card = 'Ctrl+T',
    --- refused during an edit
    editor = { browsing = 'run the project' },
    console = { idle = 'to the editor', live = 'to the editor' },
  },
  { chord = 'ctrl+q', name = 'stop', card = 'Ctrl+Q',
    repeats = true,
    editor = { browsing = 'to the console' },
    --- with no program it does nothing
    console = { live = 'exit program' },
  },
  --- run anew (the maintainer's ruling of November 14, late:
  --- Ctrl is the family of the global keys)
  { chord = 'ctrl+r', name = 'restart', card = 'Ctrl+R',
    editor = { browsing = 'run anew' },
    console = { idle = 'run anew', live = 'run anew' },
  },
  { chord = 'ctrl+escape', name = 'exit', card = 'Ctrl+Esc',
    release = true,
    editor = { browsing = 'quit the IDE',
      inserting = 'quit the IDE', replacing = 'quit the IDE' },
    console = { idle = 'quit the IDE', live = 'quit the IDE' },
  },
  { chord = 'ctrl+pause', name = 'suspend', repeats = true },
  { chord = 'ctrl+alt+p', name = 'profile_start' },
  { chord = 'ctrl+alt+shift+p', name = 'profile_stop' },
  { chord = 'f10', name = 'overlay' },
}
