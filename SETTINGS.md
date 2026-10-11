# Smart Editor Settings

Settings are available in `Editor Settings` under `Plugin` -> `Smart Editor`.

Git change markers, the highlights stripe, visible highlights, function boundary guides, and indent guides update automatically while editing and can be configured here.

## Highlights

- `Stripe Highlights Enabled`: show or hide the right-side highlights stripe.
- `In-Editor Highlights Enabled`: show or hide visible usage highlights.
- `Highlight Color`: background color for highlighted usages.
- `Current Highlight Color`: background color for the current usage.
- `Current Outline Color`: outline color for the current usage.

## Navigation

- `Show Script Tabs`: show a compact row of tabs above the script editor. Enabled by default. Click to switch; use the active tab's close button or middle-click to close through Godot's normal save confirmation. Right-click opens the native document menu. Tabs follow the document list's sorting and filter.
- `Double Shift Enabled`: open All after two separate Shift taps within 400 ms. Enabled by default.
- `Go to File`, `Go to Scene`, `Go to GDScript`, `Go to Resource`, `Go to Other File`, and `Go to Symbol`: configurable shortcuts. Go to File and Go to Other File have no default single shortcut.

File scope starts at Project each time the popup opens. Choose Project + Add-ons to include plugins. Search ignores case, accepts abbreviated names and space-separated terms, and ranks exact names, prefixes, and contiguous matches ahead of abbreviations and path-only matches.

Go to Symbol searches fields/constants and methods together. Fields appear first, then a separator and methods; search ranking applies within each group. Methods display parameter names, explicitly declared types, and return types; fields display explicitly declared types. Open/closed locks distinguish public names from names beginning with `_` by convention. The separator is skipped during keyboard navigation and appears only when both groups have matches.

## Git Changes

- `Show Change Markers`: show or hide Git-aware markers in the left script-editor gutter. Enabled by default; it uses `git` from `PATH` and stays inactive if that executable or a usable Git `HEAD` baseline is unavailable.

## Call Hierarchy

- `Enabled`: enable or disable the call hierarchy shortcut and dock.
- `Tree Font Size`: font size used in the call hierarchy tree. Defaults to 14.
- `Max Nodes`: maximum number of hierarchy nodes to load.

## Function Boundary Guides

- `Guide Color`: color for function separator and indent guide lines.
- `Show Function Separator Guides`: show or hide horizontal function separator lines.
- `Show Indent Guides`: show or hide vertical block indentation guide lines.
