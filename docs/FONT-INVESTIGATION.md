# VGUI Font Investigation

## Language ranges

The examined block belongs under `Scheme / CustomFontFiles / <entry>`. The
`font` field is a file path, while `name` is the font's actual family name. This
differs from placing equivalent fields inside a `Fonts` alias or glyph set.

The published [Source `Scheme.cpp`
implementation](https://github.com/nillerusr/source-engine/blob/master/vgui2/src/Scheme.cpp)
selects the child block matching the current game language, parses the two
`range` values as hexadecimal numbers, and stores the range for each family. It
later passes that range to glyph creation. This source tree is not Valve's
current complete TF2 source, so implementation analysis and in-game verification
must be treated separately.

`0x0000 0xFFFF` is the inclusive Unicode Basic Multilingual Plane. It is not a
file byte range, glyph count, or code-page identifier. It includes Hangul
syllables U+AC00-U+D7A3 and Hangul Jamo, but it neither creates missing glyphs
nor enables characters outside the BMP.

The published [Source `FontManager.cpp`
implementation](https://github.com/nillerusr/source-engine/blob/master/vgui2/vgui_surfacelib/FontManager.cpp)
assigns this range to the requested font and assigns characters outside it to
compatible fallback fonts. A full-BMP range therefore makes the requested font
responsible for Hangul on this code path. Loading the file and finding the
required glyphs remain separate requirements.

The language key represents the **current game UI language**, not the language
of the input text. The [official Steam language
codes](https://partner.steamgames.com/doc/store/localization/languages) include
`koreana`, `russian`, and `polish`. `ko-KR` is this application's locale and is
not a game language key. When Korean text is entered while the game uses an
English UI, the `english` registration is selected.

The Korean game language key is `koreana`, not `korean`. A `range` placed
directly under `Fonts` is not relied on for this purpose; registrations carry
the appropriate range for every supported game language under `CustomFontFiles`.

The generator uses English internal family names in engine files while retaining
the chosen localized labels in the user's profile.

## Family resolution

Direct Windows `FontFamily` checks resolve the localized Batang, BatangChe, and
Malgun Gothic names successfully; availability follows actual family resolution
rather than string comparison. Localized names are recognized, so a Korean name
resolving to an English family name is not considered missing. Registry lookup
also handles entries that group several families in one TTC file.

Bitmap-only families cannot be handled as TrueType fonts.
