--- The gate's reserved chords (doc/development/decisions/
--- input.md, D-RESERVE-TABLE), the one list both the gate
--- (controller.lua) and the key cards read. `name` is the
--- gate's action for it; `release`: it acts on its key's
--- release. A surface's words say what the chord does there,
--- by state: a state with none lists it among the other keys,
--- and a surface with none leaves it off its card (Ctrl+Pause
--- works only while a program runs in front; the profiling
--- keys only in a profiling build).
return {
  { chord = 'ctrl+t', name = 'quickswitch', card = 'Ctrl+T',
    --- refused during an edit
    editor = { browsing = 'run the project' },
    console = { idle = 'to the editor', live = 'to the editor' },
  },
  { chord = 'ctrl+q', name = 'stop', card = 'Ctrl+Q',
    editor = { browsing = 'to the console' },
    --- with no program it does nothing
    console = { live = 'exit program' },
  },
  { chord = 'ctrl+alt+r', name = 'restart', card = 'Ctrl+Alt+R',
    editor = { browsing = 'run anew' },
    console = { idle = 'run anew', live = 'run anew' },
  },
  { chord = 'ctrl+escape', name = 'exit', card = 'Ctrl+Esc',
    release = true,
    editor = { browsing = 'quit the IDE',
      inserting = 'quit the IDE', replacing = 'quit the IDE' },
    console = { idle = 'quit the IDE', live = 'quit the IDE' },
  },
  { chord = 'ctrl+pause', name = 'suspend' },
  { chord = 'ctrl+alt+p', name = 'profile_start' },
  { chord = 'ctrl+alt+shift+p', name = 'profile_stop' },
  { chord = 'f10', name = 'overlay' },
}
