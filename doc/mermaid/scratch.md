> **Historical — a design-era sketch, not a description of the current code.**
> See [`README.md`](README.md) in this directory.

```scala
case class More(
  up: Boolean,
  down: Boolean
)
enum ContentType
  case Plain
  case Lua

enum Block(val tag: String, pos: Range):
  case Empty
  case Chunk(lines: Seq[String])

type Content = Seq[String] | Seq[Block]

class WrappedText(
  text: Seq[String],
  w: Int,
  wrap_forward: Map[Int, Seq[Int]],
  wrap_reverse: Seq[Int],
  n_breaks: Int,
):
  def wrap(text: Seq[String]): Unit
  def get_text(): Seq[String]
  def get_line(): String
  def get_text_length(): Int

class VisibleContent(
  range: Option[Range],
  overscroll: Int, overscroll_max: Int
) extends WrappedText:
  def set_range(r: Range): Unit
  def get_range(): Range
  def move_range(Int): Int
  def get_text(): Seq[String]
  def get_content_length(): Int

class VisibleStructuredContent(
  range: Option[Range],
  blocks: Seq[Block],
  qoverscroll: Int, overscroll_max: Int,
) extends WrappedText:
  def set_range(r: Range): Unit
  def get_range(): Range
  def move_range(Int): Int
  def get_text(): Seq[String]
  def get_content_length(): Int

```

#### plain

```mermaid
sequenceDiagram

participant EditorController

create participant EditorView
EditorController->>EditorView: new()
create participant BufferModel
EditorController->>BufferModel: open()
create participant string[]
BufferModel-->>string[]: <new>
string[]-->>BufferModel: <ok>
create participant BufferView
EditorView->>BufferView: open()
create participant VisibleContent
BufferView-->>VisibleContent: <>

%% BufferModel->>EditorController:  a
```

### Scrolling

```mermaid
classDiagram

class Scrollable {
  range: Range
  overscroll: integer
  overscroll_max: integer
  size: integer
  size_max: integer
  content_length: integer

  full_range()
  follow_focus()

  calculate_end_range()
}

class WrappedText {
  text: string[]
  wrap_w: integer
  wrap_forward: integer[][]
  wrap_reverse: integer[]
  n_breaks: integer

  wrap()
  get_text()
  get_line()
  get_text_length()
}


class VisibleContent {
  scroll: Scrollable

  move_range()
  get_visible()
  get_content_length()
}

class VisibleStructuredContent {
  scroll: Scrollable

  blocks: Block[]
  visible_blocks: Block[]
  reverse_map: ReverseMap

  get_visible()
  get_content_length()
}

WrappedText <|-- VisibleContent
WrappedText <|-- VisibleStructuredContent

Scrollable *-- VisibleContent
Scrollable *-- VisibleStructuredContent


```

```lua
if content_length < size_max then full_range() end
```

### Input scrolling

```mermaid
flowchart TD;
  A[EditorController:load❨❩] ---> B[set_text❨❩];
  B --> C[jump_end❨❩];
  B --> D[text_change❨❩];
  D --> E[visible:to_end❨❩];
  E --> F[scrollable.calculate_end_range❨❩];
```

##### ex

```mermaid
graph TD;
  A[Start] --> B[Step 1];
  B --> C{Decision};
  C -->|Yes| D[Step 2];
  C -->|No| E[Step 3];
  D --> F[End];
  E --> F;

```
