# Smart Editor Plugin Test Project

This is a tiny Godot project for developing and testing the Smart Editor plugin outside of a real game project.

The addon lives in:

```text
addons/smart-editor-plugin/
```

The lightweight parser test runner lives in:

```text
tests/test_runner.tscn
tests/test_runner.gd
```

Run the lightweight runner with:

```bash
'/Applications/Godot.app/Contents/MacOS/Godot' --path /Users/evgenii/dev/games/smart-editor-plugin --headless res://tests/test_runner.tscn --quit
```

The GdUnit parser tests live in:

```text
test/unit/gdscript_selection_parser_test.gd
```

Run the GdUnit suite with:

```bash
'/Applications/Godot.app/Contents/MacOS/Godot' --path /Users/evgenii/dev/games/smart-editor-plugin -s -d res://addons/gdUnit4/bin/GdUnitCmdTool.gd --ignoreHeadlessMode -a res://test/unit/gdscript_selection_parser_test.gd
```

For now the tests focus on `gdscript_selection_parser.gd`, because expand selection is the part that benefits most from a clear fixture suite.

Note: the installed GdUnit4 `6.0.0` copy needed one local Godot 4.6.1 compatibility patch in `addons/gdUnit4/src/core/GdUnitFileAccess.gd`: `FileAccess.get_as_text(true)` was changed to `FileAccess.get_as_text()`.
