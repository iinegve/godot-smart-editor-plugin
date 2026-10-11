# Smart Editor Shortcuts

Configurable shortcuts can be changed in `Editor Settings` under `Plugin` -> `Smart Editor`.

## Editor Commands

- `Expand Selection`: `Meta+D` (`Command+D` on macOS)
- `Shrink Selection`: `Meta+Shift+D` (`Command+Shift+D` on macOS)
- `Extract Local Variable`: `Meta+Ctrl+V` (`Command+Control+V` on macOS)
- `Inline Variable`: `Meta+Ctrl+N` (`Command+Control+N` on macOS)
- `Rename Symbol`: `Meta+Ctrl+R` (`Command+Control+R` on macOS)

## Quick Navigation

- `Go to File (All)`: Double Shift (two taps within 400 ms). Ordinary Shift combinations and held Shift do not trigger it. An additional single shortcut can be assigned in settings.
- `Go to Scene`: `Command+N` on macOS, `Ctrl+N` elsewhere.
- `Go to GDScript`: `Command+Shift+N` on macOS, `Ctrl+Shift+N` elsewhere.
- `Go to Resource`: `Command+Alt+Shift+N` on macOS, `Ctrl+Alt+Shift+N` elsewhere.
- `Go to Other File`: no default shortcut; assign one in settings or use the Other tab.
- `Go to Symbol`: `Command+O` on macOS, `Ctrl+O` elsewhere. Member fields and constants appear first, followed by a separator and methods with parameter and return type signatures. Fields show declared types; lock icons use the `_` private naming convention. Search filters both groups at once.
- Inside either popup: arrows and Page Up/Down select; Enter or double-click opens; Escape closes. Typing searches without changing the selected file or caret. In the file popup, `Ctrl+Tab` / `Ctrl+Shift+Tab` switch tabs.

These commands take precedence over Godot commands with the same keys. Disable Script-IDE to avoid overlapping navigation shortcuts.

## Call Hierarchy

- `Show Call Hierarchy`: `Ctrl+Alt+H`
- `Select Call Site`: arrow keys
- `Go to Selected Call Hierarchy Method`: `F4` or double-click
- `Return Focus to Script Editor`: `Esc`
- `Move Call Hierarchy`: right-click its tab and choose a side dock, the bottom panel, or a floating window.
