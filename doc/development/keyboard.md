# Compy Keyboard Keys

Physical key delivery on Compy's built-in keyboard:

| Label                | KeyConstant | ok?  |
| :------------------- | :---------- | :--- |
| Esc                  | escape      | ✓    |
| F1                   | f1          | ✓    |
| F2                   | f2          | ✓    |
| F3                   | volume down | ✗    |
| F4                   | volume up   | ✗    |
| F5                   | f5          | ✓    |
| F6                   | f6          | ✓    |
| F7                   | brightness- | ✗    |
| F8                   | brightness+ | ✗    |
| F9                   | f9          | ✓    |
| F10                  | f10         | ✓    |
| F11                  | f11         | ✓    |
| F12                  | f12         | ✓    |
| numlk                | code 143    | ✗    |
| Delete               | delete      | ✓    |
| Tab                  | tab         | ✓    |
| Enter                | return      | ✓    |
| Caps Lock            | capslock    | ✓    |
| ⇧ Shift              | lshift      | ✓    |
| Shift                | rshift      | ✓    |
| Ctrl                 | lctrl       | ✓    |
| Alt                  | lalt        | ✓    |
| PauseBreak           | pause       | ✓    |
| Menu                 | menu        | ✓    |
| Insert (Fn+F12)      | insert      | ✓    |
| Scroll Lock (Fn+F10) | scrolllock  | ✓    |
| Home (Fn+Left)       | home        | ✓    |
| End (Fn+Right)       | end         | ✓    |
| Mute (Fn+F5)         | code 164    | ✗    |
| PgUp (Fn+Up)         | pageup      | ✓    |
| PgDn (Fn+Down)       | pagedown    | ✓    |
| Next (Fn+F6)         | audioplay   | ✓    |
| Prev (Fn+F7)         | audioprev   | ✓    |
| Next (Fn+F8)         | audionext   | ✓    |

F3, F4, F7 and F8 are the keyboard's volume and brightness controls and do not
reach the IDE. Bare F10 is reserved by the IDE in profiling builds, and bare
F12 is reserved in both development and packaged playback (cycling the screen
in the console); either with a modifier reaches the running program. F1, F2,
F10 and F12 are verified on device; F5, F6, F9, F11 and Ctrl (`lctrl`) follow
from the keyboard hardware capture, key layout and Android SDL mapping and have
not been separately verified on physical presses in LÖVE. Other rows retain
earlier key measurements.
