# Smart Editor

Smart Editor is a Godot editor plugin that adds small IDE-style conveniences to the built-in script editor.

## Demo

[![Watch the Smart Editor demo](https://img.youtube.com/vi/rqHHqKFbUds/hqdefault.jpg)](https://www.youtube.com/watch?v=rqHHqKFbUds)

## Features

- Script tabs above the main script editor for switching between open documents with the mouse. The active tab has a close button; middle-click also closes, and unsaved-change prompts remain handled by Godot. Tabs scroll when space is limited and follow Godot's document list order and filter.
- Quick file navigation with All, Scenes, GDScript, Resources, and Other tabs, plus Project / Project + Add-ons scope. Open All with Double Shift or GDScript with Command+Shift+N on macOS.
- Go to Symbol with member fields and constants first, a separator, then methods in one searchable list. Method signatures show parameter names, declared types, and return types; fields show declared types. Small open/closed locks mark public/private naming conventions, with `_` treated as private. Command+O on macOS opens symbols from the current GDScript buffer, including unsaved declarations, without line numbers or colored symbol badges.
- Git change markers in the left editor gutter: green for added lines, blue for modified lines, and gray for deleted-line boundaries. Click a marker to view the previous `HEAD` lines.
- Smart expand/shrink selection for GDScript expressions, statements, blocks, function bodies, comments, multiline calls, arrays, dictionaries, and function signatures.
- Highlights stripe, a narrow mark strip beside the script editor scrollbar showing usages of the symbol under the caret in the current file.
- Highlights in the visible editor area for the symbol under the caret.
- Function boundary guides that draw subtle horizontal lines between functions to make indentation-based code easier to scan.
- Indent guides that draw subtle vertical lines along block indentation levels and brighten the active guide when the caret is placed on it.
- Call Hierarchy, a movable dock view that shows callers of the function under the caret.
- Extract Local Variable for selected expressions.
- Inline Variable for simple local variable declarations.
- Rename Symbol for the symbol under the caret, including symbols used across multiple files.

## Known Limitations

Smart Editor does not try to be a full semantic refactoring engine. Its refactorings are intentionally lightweight and editor-focused.

- Quick file navigation uses Godot's resource filesystem. Files that Godot does not index are not listed; indexed files without a resource loader are selected in the FileSystem dock. Resources covers `.tres`, `.res`, `.gdshader`, and `.gdshaderinc`; other assets appear under Other. Script-IDE should be disabled when using the same navigation shortcuts.
- Go to Symbol lists named functions and member fields/constants declared in the current GDScript, including inner classes. It reads the live editor text; inherited members, local variables, anonymous functions, and implicit property accessors are not listed. Signatures show explicit type annotations without inferring types or displaying default values. Lock icons reflect naming conventions, not enforced access restrictions.
- `Rename Symbol` depends on Godot's code analysis service. Renames that affect one open file can be undone as one editor undo action. Renames that affect multiple files cannot revert the whole cross-file rename or changes made to closed files.
- Variable rename requires a variable declaration. Variables that are left without an explicit declaration cannot be renamed.
- `Call Hierarchy` is a static call-site view and does not follow string-based dynamic calls such as `call("method")` or `Callable(object, "method")`.
- `Extract Local Variable` and `Inline Variable` operate on recognized GDScript text patterns. They do not perform complete semantic analysis.
- Smart selection is based on a custom parser for practical editor selection ranges, not Godot's compiler AST. Some unusual syntax can still need more test cases.
- Highlights are focused on the currently open script, not a project-wide usage view. Occurrences must be fully visible in the editor viewport to be painted; partially clipped symbols may not be highlighted.
- Git change markers compare the current editor buffer to the file in `HEAD`, not to the Git index. Staged changes therefore remain marked until they are committed. The feature uses the default `git` executable from the editor process's `PATH`; if its one-time startup check fails, it reports a warning and remains inactive until the plugin or editor is reloaded. It also stays hidden for projects outside a Git repository or repositories without a commit.
- The previous-code popup sizes itself to the displayed content, with scrolling for wide lines or hunks longer than twelve lines. Common leading indentation is removed only in the preview; relative indentation, original line ranges, and Git data are preserved.
- A path absent from `HEAD`, including a renamed destination, is shown as entirely new. Rename detection, staging, reverting, committing, change navigation, and configurable marker colors are not included.

## Shortcuts

Default shortcuts are listed in [SHORTCUTS.md](SHORTCUTS.md). They can be changed in `Editor Settings` under `Plugin` -> `Smart Editor`.

## Editor Settings

Editor settings are listed in [SETTINGS.md](SETTINGS.md). They are available in `Editor Settings` under `Plugin` -> `Smart Editor`.

## Installation

From the Godot Asset Library, install the addon into your project and enable `Smart Editor` in `Project` -> `Project Settings` -> `Plugins`.

For manual installation, download the latest release zip from [GitHub Releases](https://github.com/iinegve/godot-smart-editor-plugin/releases), then import that zip through Godot's `AssetLib` tab.

Then enable `Smart Editor` from the Plugins tab.

## Compatibility

Smart Editor is developed and tested with Godot `4.7.x`. It may also work with Godot `4.6.x`, but that editor line is best-effort and not officially supported.

## License

Smart Editor is available under the MIT license. See `LICENSE` for details.

Quick file navigation adapts resource traversal from Marius Hanl's MIT-licensed Script-IDE. See `THIRD_PARTY_NOTICES.md` in the addon directory.
