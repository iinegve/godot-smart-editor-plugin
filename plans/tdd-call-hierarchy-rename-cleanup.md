# TDD Plan: Call Hierarchy Guards, Comment Parsing, Rename Edit Offsets

## Summary

Fix three small correctness/cleanup items from the static review using TDD. Keep `prepareRename` behavior unchanged for now because a failed prepare request may still be followed by useful rename edits from Godot's LSP.

Items:

- **a. Call hierarchy editor access guards**: make current editor/script helpers safe when the editor API is unavailable or returns non-script/non-CodeEdit values.
- **b. Call hierarchy comment parsing**: replace plain `find("#")` comment stripping with quote-aware line scanning so `#` inside strings is not treated as a comment.
- **c. Rename workspace edit offsets**: make `line_col_to_offset()` reject columns outside the specific target line instead of allowing offsets to cross newline boundaries.

## Step 1: TDD Red Tests

### a. Call hierarchy editor access guards

Add focused tests in `test/unit/editor/call_hierarchy_controller_test.gd` for new private helper seams:

- `_current_code_edit_from_script_editor(null)` returns `null`.
- `_current_code_edit_from_script_editor(fake_editor_without_current_editor)` returns `null`.
- `_current_code_edit_from_script_editor(fake_editor_with_non_code_base)` returns `null`.
- `_current_code_edit_from_script_editor(fake_editor_with_code_edit_base)` returns that `CodeEdit`.
- `_current_script_path_from_script_editor(null)` returns `""`.
- `_current_script_path_from_script_editor(fake_editor_without_script)` returns `""`.
- `_current_script_path_from_script_editor(fake_editor_with_gd_script)` returns the script resource path.
- `_current_script_path_from_script_editor(fake_editor_with_non_gd_or_empty_path)` returns `""`.

Use small fake `RefCounted` classes inside the test file with `get_current_editor()`, `get_base_editor()`, and `get_current_script()` methods. These tests should be red first because the helper seams do not exist yet.

Run only:

```sh
'/Applications/Godot.app/Contents/MacOS/Godot' --path /Users/evgenii/dev/games/smart-editor-plugin --headless --script addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://test/unit/editor/call_hierarchy_controller_test.gd
```

Expected red reason: missing helper methods or unsafe helper behavior.

### b. Call hierarchy quote-aware comment parsing

Add focused tests in `test/unit/editor/call_hierarchy_controller_test.gd`:

- `_strip_line_comment("var label := \"value # still string\"")` returns the whole line.
- `_strip_line_comment("var label := \"value # still string\" # real comment")` returns `var label := "value # still string" `.
- `_strip_line_comment("var label := 'value # still string' # real comment")` returns `var label := 'value # still string' `.
- `_strip_line_comment("var label := \"escaped \\\"#\\\"\" # real comment")` keeps the escaped quoted `#` and strips only the real comment.
- Existing constructor-column behavior for a real full-line comment still passes: `# var player := Player.new()` produces no constructor columns.

Run only:

```sh
'/Applications/Godot.app/Contents/MacOS/Godot' --path /Users/evgenii/dev/games/smart-editor-plugin --headless --script addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://test/unit/editor/call_hierarchy_controller_test.gd
```

Expected red reason: current `_strip_line_comment()` uses plain `line.find("#")`.

### c. Rename line/column offset bounds

Add focused tests in `test/unit/editor/smart_rename_workspace_edit_test.gd`:

- `line_col_to_offset("ab\ncde", 0, 0)` returns `0`.
- `line_col_to_offset("ab\ncde", 0, 2)` returns `2`.
- `line_col_to_offset("ab\ncde", 1, 3)` returns `6`.
- `line_col_to_offset("ab\ncde", 0, 3)` returns `-1` because column 3 crosses the first line's newline.
- `line_col_to_offset("ab\ncde", 1, 4)` returns `-1` because column 4 is beyond the second line.
- `apply_text_edits_to_text()` ignores a malformed same-line edit whose start/end columns are outside that line.

Run only:

```sh
'/Applications/Godot.app/Contents/MacOS/Godot' --path /Users/evgenii/dev/games/smart-editor-plugin --headless --script addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://test/unit/editor/smart_rename_workspace_edit_test.gd
```

Expected red reason: current `line_col_to_offset()` validates absolute `offset + column`, not the target line length.

## Step 2: Fixes

### a. Call hierarchy editor access guards

Implement the tested helper seams in `features/call_hierarchy/call_hierarchy_controller.gd`:

- `_get_current_code_edit()` should get `EditorInterface.get_script_editor()` and delegate to `_current_code_edit_from_script_editor(script_editor)`.
- `_current_code_edit_from_script_editor(script_editor)` should return `null` unless the script editor, current editor, and base editor are valid and the base editor is a `CodeEdit`.
- `_get_current_script_path()` should get `EditorInterface.get_script_editor()` and delegate to `_current_script_path_from_script_editor(script_editor)`.
- `_current_script_path_from_script_editor(script_editor)` should return a non-empty `.gd` script resource path only; otherwise `""`.

No behavior change is intended when Godot returns the expected editor/script objects.

### b. Call hierarchy quote-aware comment parsing

Replace `_strip_line_comment()` with a single-line scanner:

- Scan left-to-right.
- Track whether the scanner is inside a string and which quote opened it (`"` or `'`).
- Treat backslash as an escape only inside strings.
- Return text before the first `#` found outside a string.
- Return the original line when no outside-string `#` is found.

Do not move this into shared parser infrastructure in this pass. Keep the fix local to call hierarchy.

### c. Rename line/column offset bounds

Update `SmartRenameWorkspaceEdit.line_col_to_offset()`:

- Reject negative line/column as today.
- Walk to the requested line start as today.
- Determine the requested line end as either the next newline offset or `text.length()`.
- Return `-1` when `column > line_end - line_start`.
- Allow `column == line_length` because LSP ranges can point to end-of-line.
- Keep `apply_text_edits_to_text()` behavior unchanged except that malformed edits are ignored more strictly through the corrected offset helper.

## Final Verification

Run:

```sh
git diff --check
'/Applications/Godot.app/Contents/MacOS/Godot' --path /Users/evgenii/dev/games/smart-editor-plugin --headless --script addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://test/unit/editor/call_hierarchy_controller_test.gd
'/Applications/Godot.app/Contents/MacOS/Godot' --path /Users/evgenii/dev/games/smart-editor-plugin --headless --script addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://test/unit/editor/smart_rename_workspace_edit_test.gd
'/Applications/Godot.app/Contents/MacOS/Godot' --path /Users/evgenii/dev/games/smart-editor-plugin --editor --headless --quit
```

Expected result: all tests pass, no parse/load errors. Existing GdUnit report UID duplicate warnings may still appear and are out of scope.

## Assumptions

- `prepareRename` remains unchanged.
- Cosmetic rename-controller leftovers (`pass` lines and commented old validation) are not part of this TDD cleanup.
- This plan avoids broad call hierarchy refactoring; it only adds tested guard seams and fixes comment parsing.
