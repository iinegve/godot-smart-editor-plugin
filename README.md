# Smart Editor

Smart Editor is a Godot editor plugin that adds small IDE-style conveniences to the built-in script editor.

## Demo

[![Watch the Smart Editor demo](https://img.youtube.com/vi/nbvFcb0kw1I/hqdefault.jpg)](https://www.youtube.com/watch?v=nbvFcb0kw1I)

## Features

- Smart expand/shrink selection for GDScript expressions, statements, blocks, function bodies, comments, multiline calls, arrays, dictionaries, and function signatures.
- Highlights stripe, a narrow mark strip beside the script editor scrollbar showing usages of the symbol under the caret in the current file.
- Highlights in the visible editor area for the symbol under the caret.
- Function boundary guides that draw subtle horizontal lines between functions to make indentation-based code easier to scan.
- Indent guides that draw subtle vertical lines along block indentation levels.
- Call Hierarchy, a lazy dockable view that shows callers of the function under the caret.
- Extract Local Variable for selected expressions.
- Inline Variable for simple local variable declarations.
- Rename Symbol for the symbol under the caret, including symbols used across multiple files.

## Known Limitations

Smart Editor does not try to be a full semantic refactoring engine. Its refactorings are intentionally lightweight and editor-focused.

- `Rename Symbol` depends on Godot's code analysis service. Renames that affect one open file can be undone as one editor undo action. Renames that affect multiple files cannot revert the whole cross-file rename or changes made to closed files.
- Variable rename requires a variable declaration. Variables that are left without an explicit declaration cannot be renamed.
- `Call Hierarchy` is a static call-site view and does not follow string-based dynamic calls such as `call("method")` or `Callable(object, "method")`.
- `Extract Local Variable` and `Inline Variable` operate on recognized GDScript text patterns. They do not perform complete semantic analysis.
- Smart selection is based on a custom parser for practical editor selection ranges, not Godot's compiler AST. Some unusual syntax can still need more test cases.
- Highlights are focused on the currently open script, not a project-wide usage view. Occurrences must be fully visible in the editor viewport to be painted; partially clipped symbols may not be highlighted.

## Shortcuts

Default shortcuts are listed in [SHORTCUTS.md](SHORTCUTS.md). They can be changed in `Editor Settings` under `Plugin` -> `Smart Editor`.

## Editor Settings

Editor settings are listed in [SETTINGS.md](SETTINGS.md). They are available in `Editor Settings` under `Plugin` -> `Smart Editor`.

## Installation

From the Godot Asset Library, install the addon into your project and enable `Smart Editor` in `Project` -> `Project Settings` -> `Plugins`.

For manual installation, download the latest release zip from [GitHub Releases](https://github.com/iinegve/godot-smart-editor-plugin/releases), then import that zip through Godot's `AssetLib` tab.

Then enable `Smart Editor` from the Plugins tab.

## Compatibility

Smart Editor is developed and tested with Godot `4.6.1`. Other Godot `4.6.x` releases may work, but `4.6.1` is the supported version for the first Asset Library release.

## License

Smart Editor is available under the MIT license. See `LICENSE` for details.
