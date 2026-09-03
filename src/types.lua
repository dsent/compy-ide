--- @alias Mode
--- | 'ide'
--- | 'play'
--- | 'test'
--- | 'harmony'
--- @alias Testflags { auto: boolean?, draw: boolean?, size: boolean? }

--- @class Start
--- @field mode Mode
--- @field testflags Testflags?
--- @field path string?

--- @class PathInfo table
--- @field storage_path string
--- @field project_path string
--- @field play_path string

--- @class CursorInfo table
--- @field cursor Cursor

--- @class Point table
--- @field x number
--- @field y number

---@alias VerticalDir
---| 'up'
---| 'down'

---@alias InputType
---| 'lua'
---| 'text'

---@alias ContentType
---| 'plain'
---| 'lua'
---| 'md'

---@alias Fac # scaling
---| 1
---| 2

--- @class BlinkConfig table
--- @field enable boolean
--- @field period number
--- @field duty number

--- @class ViewConfig table
--- @field font love.Font
--- @field iconfont love.Font
--- @field statusline_border integer
--- @field fh integer -- font height
--- @field fw integer -- font width
--- @field lh integer -- line height
--- @field lines integer
--- @field input_max integer
--- @field show_append_hl boolean
--- @field show_debug_timer boolean
--- @field labelfont love.Font
--- @field h integer
--- @field w integer
--- @field colors Colors
--- @field blink BlinkConfig
--- @field debugheight integer
--- @field debugwidth integer
--- @field drawableWidth number
--- @field drawableChars integer
--- @field fold_lines integer
--- @field drawtest boolean
--- @field sizedebug boolean

--- @class EditorConfig table
--- @field mouse_enabled boolean
--- @field touch_enabled boolean

--- @class Config table
--- @field view ViewConfig
--- @field editor EditorConfig
--- @field autotest boolean
--- @field mode Mode

--- @alias More {up: boolean, down: boolean}

--- @alias PromptTone 'default'|'warning'|'error'|'special'

--- @class StyledPromptLabel table
--- @field text string
--- @field tone PromptTone?

--- @alias PromptLabel string|StyledPromptLabel

--- @class Status table
--- @field label PromptLabel?
--- @field cursor Cursor?
--- @field n_lines integer
--- @field input_more More
--- @field custom CustomStatus?

--- @class InputDTO table
--- @field text InputText
--- @field highlight Highlight
--- @field wrapped_error string[]
--- @field selection InputSelection
--- @field visible VisibleContent

--- @class ViewData table
--- @field w_error string[]

--- @class Highlight table
--- @field parse_err Error?
--- @field hl SyntaxColoring

--- @alias TokenType
--- | 'kw_single'
--- | 'kw_multi'
--- | 'number'
--- | 'string'
--- | 'identifier'

--- @alias LexType
--- | TokenType
--- | 'comment'
--- | 'error'

--- @class UserInput table
--- @field M UserInputModel
--- @field V UserInputView
--- @field C UserInputController

--- @alias AppState
--- | 'starting'
--- | 'title'
--- | 'ready'
--- | 'project_open'
--- | 'editor'
--- | 'running'
--- | 'inspect'
--- | 'shutdown'

--- @class BufferState table
--- @field filename string
--- @field selection integer
--- @field offset integer

--- @class EditorState table
--- @field buffer BufferState
--- @field clipboard string?
--- @field moved integer?

--- @class LoveState table
--- @field testing boolean
--- @field has_removable boolean?
--- @field user_input UserInput?
--- @field app_state AppState
--- @field prev_state AppState?
--- @field editor EditorState?
--- @field suspend_msg string?

--- @class LoveDebug table
--- @field show_snapshot boolean
--- @field show_terminal boolean
--- @field show_canvas boolean
--- @field show_input boolean
--- @field once integer

--- @class LuaEnv : table

--- @class ResultsDTO table
--- @field results table[]
--- @field selection integer


--- @alias ParseResult<T> T|Error

--- @alias Chunker fun(s: string[], integer, boolean?): boolean, Block[], ParseResult
--- @alias Highlighter fun(c: str): SyntaxColoring
--- @alias Printer fun(c: string[], integer?): string[]?

--- @class Parser
--- @field parse fun(code: string[]): ParseResult
--- @field chunker Chunker
--- @field pprint Printer?
---
--- @field tokenize fun(str): table
--- @field syntax_hl fun(table): SyntaxColoring

---@alias FPSC
---| 'T_L"
---| 'T_R"
---| 'off'
---| 'T_L_B"
---| 'T_R_B"

--- @class Profile
--- @field report table
--- @field frame integer
--- @field n_frames integer
--- @field n_rows integer
--- @field fpsc FPSC

--- @class InputShowConfig table
--- @field prompt string?
--- @field text str?
--- @field cursor integer[]?
--- @field force boolean?
--- @field clear_on_submit boolean?
--- @field hide_on_submit boolean?
--- @field clear_on_cancel boolean?
--- @field hide_on_cancel boolean?
--- @field validator function?
--- @field highlighter function?
--- @field on_text_entered function?
--- @field on_limit_reached function?

--- @class InputCallbacks table
--- @field on_text_entered function?
--- @field on_limit_reached function?
--- @field validator function?
--- @field highlighter function?
--- @field before_submit function?
--- @field after_submit function?
--- @field before_cancel function?
--- @field after_cancel function?

--- @class InputShortcuts table
--- @field keypressed table
--- @field keyreleased table
--- @field textinput table

--- @class InputHooks table
--- @field keypressed function?
--- @field keyreleased function?
--- @field textinput function?
--- @field mousepressed function?
--- @field mousereleased function?
--- @field mousemoved function?
--- @field wheelmoved function?
--- @field touchpressed function?
--- @field touchreleased function?
--- @field touchmoved function?
--- @field singleclick function?
--- @field doubleclick function?

--- @class InputFn table
--- @field ignore_repeat function
--- @field stop_here function
--- @field side_run function

--- @class CompyInput table
--- @field show fun(cfg: InputShowConfig?)
--- @field hide fun()
--- @field is_shown fun(): boolean
--- @field get_cursor fun(): integer?, integer?
--- @field get_text fun(): string?
--- @field set_cursor fun(line: integer, col: integer)
--- @field set_text fun(text: str, keep_cursor: boolean?)
--- configure takes InputShowConfig minus the show-only keys —
--- `text`, `cursor` and `force`; passing one raises. Everything
--- else, the four lifecycle flags included, is project-owned
--- and reaches both calls.
--- @field configure fun(cfg: InputShowConfig?)
--- @field clear fun()
--- @field shortcuts InputShortcuts
--- @field hooks InputHooks
--- @field callbacks InputCallbacks
--- @field fn InputFn

--- @class Compy
--- @field input CompyInput
--- @field before_exit function
--- @field terminal table?
--- @field audio table?
--- @field font table?
