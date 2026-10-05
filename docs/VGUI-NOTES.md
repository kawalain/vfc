# Source VGUI notes

Facts about how Source-engine VGUI2 games resolve and register fonts, learned
while building VGUIFontChanger.

## Game support boundary

- Only games that declare a game/VGUI `custom/*` search path in `gameinfo.txt`
  are supported. Source 2 and games without a declared custom mount are outside
  this implementation.
- SearchPaths order, custom wildcard ordering, VPK paths, `gameinfo_path`,
  `all_source_engine_paths` and installed `appid_N` mounts are resolved.
  Unsupported tokens and nested wildcards are reported rather than silently
  approximated.

## Scheme discovery

- Output lives at `<game-directory>/custom/!VGUIFontChanger/resource/…Scheme.res`.
- ClientScheme, SourceScheme and ChatScheme are included when present;
  additional `resource/**/*scheme*.res` files in loose directories/VPKs are
  discovered, and nested virtual paths are preserved in output.
- Nonstandard Scheme filenames, external engine mounts and branch-specific font
  backends require per-game testing; no Source fork is guaranteed to render
  identically.
- The collected definitions come from the winning Scheme files, not from every
  font in every mounted archive. For example, a HUD replacing TF2 Secondary with
  tf2secondary_fix shows the latter; the shadowed stock definition is not
  included.
- Source HUD files are never modified. `!VGUIFontChanger` and the legacy
  `!fonts` folders are excluded from build inputs.
- Missing optional HUD `#base` dependencies produce warnings; flattening cannot
  restore files absent from the current installation.

## The custom flag

- Generated Scheme files set `custom=0`. Forcing `custom=1` bypassed the Asian
  compatibility fallback and caused missing Korean glyphs in reported use.

## Font registration

- Selecting a family — even the original family — copies its actual font file
  into `resource/fonts/vguifontchanger/` under its full SHA-256 and extension.
  Unresolved selections fail Apply instead of silently depending on fonts
  installed in Windows.
- Game/HUD `CustomFontFiles` assets are copied as well, and their paths are
  rewritten into this folder. The whole generated folder is portable to another
  Windows PC's custom directory for the same game; replacement fonts need no
  installation there. Glyph coverage and the target engine's font backend still
  affect rendering.
- Every selected family receives its own registration and UI-language BMP
  ranges, including separate families inside one TTC. Resolvable original
  families are copied too, preserving their existing language ranges and
  fallback behavior.
- Engine aliases without separate font files are logged; their declared game
  font assets remain bundled.

## Font sizes

- Outline fonts scale `tall`, `tall_lodef` and `tall_hidef`. Bitmap fonts also
  scale the engine's `scalex` and `scaley`.
- Absolute sizes are VGUI `tall` units, applied before the engine's screen
  scaling. Engine screen scaling and minimum/maximum font heights mean the
  runtime size is not necessarily the raw `tall` value.

## Variable fonts

- For families with an `fvar` table, the build also generates
  `resource/FontInfo.kv` with the selected family set to `freetype2`. This
  follows the existing GorDIN configuration in the examined engine and preserves
  upstream entries. Switching back to static fonts restores the upstream backend
  configuration. `FontInfo.kv` is engine configuration, not a second script or
  an external dependency.

## Alias resolution

- Every scheme file becomes its own scheme with a private alias table
  (verified against the published engine source). Definitions in different
  files never shadow each other; the binding that matters is the one in the
  scheme the drawing panel uses.
- The HUD and most game UI load `ClientScheme.res`. The engine's own panels
  (console, loading screens, dialogs) use the default scheme — the first one
  loaded, `SourceScheme.res` — which is also the fallback for any panel
  without an explicit scheme. Stock TF2's `ClientScheme.res` does not define
  `ConsoleText` at all; it is native to `SourceSchemeBase.res`, so the
  console font always comes from the SourceScheme chain. Dedicated schemes
  such as `itemtest_scheme.res` only apply to the specific panels that load
  them.
- Within one scheme file a duplicated alias name keeps its first definition:
  the alias dictionary allows duplicate keys, but lookup and glyph setup both
  read the first entry.
- Custom HUDs replace existing aliases through search path precedence: the
  game's `gameinfo.txt` lists `custom/*` first, and a custom mod's files win
  over VPK content. A custom mod may also use a stub file with `#base` to
  redirect (e.g. maxihud's `sourcescheme.res` stub pointing at
  `sourcescheme_maxihud.res`).
- The font list therefore shows only the effective alias: `ClientScheme`
  definitions first, the engine default `SourceScheme` second, and niche
  dedicated schemes last.
- `vgui_spew_fonts` (engine console command) dumps every scheme's
  alias→font table and is the definitive in-game check.

## Fallback flag

The fallback flag is documented in Valve's public ISurface.h:
https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/public/vgui/ISurface.h
