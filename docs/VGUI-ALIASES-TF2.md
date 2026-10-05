# Team Fortress 2 VGUI2 UI ↔ Font Alias Map

## Table of contents

1. [Document scope and interpretation principles](#1-document-scope-and-interpretation-principles)
2. [Core HUD](#2-core-hud)
3. [Scoreboard, round results, match HUD](#3-scoreboard-round-results-match-hud)
4. [Spectating, freeze cam, coach](#4-spectating-freeze-cam-coach)
5. [Game chat, lobby chat](#5-game-chat-lobby-chat)
6. [Developer console, engine UI](#6-developer-console-engine-ui)
7. [net_graph, FPS, debug UI](#7-net_graph-fps-debug-ui)
8. [Team selection, class selection, Intro, Map Info](#8-team-selection-class-selection-intro-map-info)
9. [Main menu, GameUI](#9-main-menu-gameui)
10. [Inventory, loadout, item UI](#10-inventory-loadout-item-ui)
11. [Achievements, Stats](#11-achievements-stats)
12. [Matchmaking, Lobby, Competitive](#12-matchmaking-lobby-competitive)
13. [Mann vs. Machine](#13-mann-vs-machine)
14. [Symbol / icon aliases](#14-symbol--icon-aliases)
15. [Reverse index: alias → actual usage](#15-reverse-index-alias--actual-usage)
16. [Design considerations](#16-design-considerations)

---

## 1. Document scope and interpretation principles

This document maps the relationship between actual on-screen elements and Scheme
font aliases in Team Fortress 2's VGUI2-based UI.

Scope:

- In-game HUD
- Target ID / player info
- Kill feed
- Chat
- Scoreboard
- Spectator / freeze cam
- Console and Source engine base UI
- Team / class selection
- Main menu and GameUI
- Inventory / loadout / item UI
- Matchmaking / Lobby / Competitive
- Mann vs. Machine
- Major debug / net_graph UI

Out of scope:

- The Steam Overlay's own UI
- HTML/MOTD content served by servers
- Arbitrary custom VGUI embedded in BSPs
- Source developer tools UI

Key principles:

- Screen element ↔ alias is not a 1:1 relationship.
- One alias can serve many screen elements.
- One screen element can use several aliases together.
- Identical alias strings under different schemes must be treated as separate
  setting nodes.
- The natural settings key is `(Scheme, Alias, glyph set)`.

---

## 2. Core HUD

| Screen element | Scheme | Alias | Notes |
|---|---|---|---|
| Top-right kill feed: player names/text | ClientScheme | `Default` | `HudDeathNotice.TextFont` default |
| Kill feed weapon/kill icons | ClientScheme | icon font family | not a plain text font |
| Aimed target name / Target ID direct rendering | ClientScheme | `TargetID` | C++ calls `GetFont("TargetID")` directly |
| Target ID name label | ClientScheme | `HudFontSmall` | `resource/ui/targetid.res` |
| Target ID minmode name | ClientScheme | `TFFontLarge` | resolution/minmode glyph set |
| Target ID owner/secondary text | ClientScheme | `FontStoreOriginalPrice` | target owner/item related display |
| Target ID small auxiliary info | ClientScheme | `DefaultVerySmall` | small status info |
| Target ID misc auxiliary info | ClientScheme | `TFFontMedium` | varies by situation |
| Health number | ClientScheme | `HudClassHealth` | `hudplayerhealth.res` |
| Health panel secondary text | ClientScheme | `DefaultSmall` | same panel |
| Current ammo/clip large number | ClientScheme | `HudFontGiantBold` | `hudammoweapons.res` |
| Ammo secondary text | ClientScheme | `HudFontMediumSmall` | by resolution/state |
| Ammo secondary text | ClientScheme | `HudFontMedium` | by resolution/state |
| Ammo secondary text | ClientScheme | `HudFontSmall` | minmode etc. |
| Player class/carried items | ClientScheme | `ReplayBrowserSmallest` | `hudplayerclass.res` |
| Player class/carried items | ClientScheme | `TFFontMedium` | same |
| Player class/carried items | ClientScheme | `TFFontSmall` | same |
| Player class/carried items | ClientScheme | `FontStoreOriginalPrice` | same |
| Damage/heal numbers etc. account panel | ClientScheme | `HudFontMediumSmall` | `hudaccountpanel.res` |
| Damage/heal numbers etc. account panel | ClientScheme | `HudFontMedium` | same |
| Medic ÜberCharge meter | ClientScheme | `HudFontSmallest` | `hudmediccharge.res` |
| Medic ÜberCharge secondary | ClientScheme | `Default` | same |
| Weapon/item effect meter | ClientScheme | `TFFontSmall` | `huditemeffectmeter.res` |
| Effect meter misc | ClientScheme | `Default` | same |
| HUD warning/alert | ClientScheme | `HudFontSmallBold` | `hudalert.res` |
| Team objective/goal emphasis | ClientScheme | `HudFontSmallBold` | `hudteamgoal.res` |
| Team objective/goal regular | ClientScheme | `HudFontSmall` | same |
| Hint message | ClientScheme | `HudHintText` | used directly from code |
| Small hint | ClientScheme | `HudHintTextSmall` | used directly from code |
| Large hint | ClientScheme | `HudHintTextLarge` | used directly from code |
| Center HUD_PRINTCENTER | ClientScheme | `CenterPrintText` | center system messages |
| Generic HudMessage | ClientScheme | dynamically chosen | the text-message definition picks the alias |
| HudMenu / selection menu | ClientScheme | `Default` | default HudLayout |
| Halloween spell menu | ClientScheme | `Default` | default HudLayout |
| Training objective | ClientScheme | `GoalText` | `hudtraining.res` |
| Training description | ClientScheme | `InstructionalText` | same |
| Training small text | ClientScheme | `TFFontSmall` | same |
| Training message | ClientScheme | `HudFontSmall` | `hudtrainingmsg.res` |
| Item inspect HUD | ClientScheme | `DefaultSmall` | `hudinspectpanel.res` |

---

## 3. Scoreboard, round results, match HUD

| Screen element | Scheme | Alias | Notes |
|---|---|---|---|
| Scoreboard team name | ClientScheme | `ScoreboardTeamNameNew` | default scoreboard |
| Scoreboard team score | ClientScheme | `ScoreboardTeamScoreNew` | default scoreboard |
| Scoreboard team player count | ClientScheme | `ScoreboardTeamCountNew` | default scoreboard |
| Scoreboard row small text | ClientScheme | `ScoreboardVerySmall` | player rows/details |
| Scoreboard medium-small text | ClientScheme | `ScoreboardMediumSmall` | default scoreboard |
| Scoreboard medium text | ClientScheme | `ScoreboardMedium` | default scoreboard |
| Scoreboard small text | ClientScheme | `ScoreboardSmall` | default scoreboard |
| Scoreboard auxiliary info | ClientScheme | `HudFontSmallest` | some status/auxiliary |
| Scoreboard buttons | ClientScheme | `GameUIButtons` | some buttons |
| Legacy/some scoreboard entries | ClientScheme | `Default` | code/panel fallback |
| Win panel team name | ClientScheme | `ScoreboardTeamName` | `winpanel.res` |
| Win panel team score | ClientScheme | `ScoreboardTeamScore` | same |
| Win panel regular text | ClientScheme | `ScoreboardMedium` | same |
| Win panel small text | ClientScheme | `ScoreboardVerySmall` | same |
| Vote body | ClientScheme | `ScoreboardSmall` | `votehud.res` |
| Vote small body | ClientScheme | `ScoreboardVerySmall` | same |
| Vote title | ClientScheme | `HudFontMediumBold` | same |
| Vote small emphasis | ClientScheme | `HudFontSmallestBold` | same |
| Vote emphasis | ClientScheme | `HudFontSmallBold` | same |
| Match status countdown | ClientScheme | `HudFontGiant` | `hudmatchstatus.res` |
| Match status rank/label | ClientScheme | `HudFontMediumSmallBold` | same |
| Match status regular | ClientScheme | `HudFontMediumSmall` | same |
| Match status regular | ClientScheme | `HudFontSmall` | same |
| Match status regular | ClientScheme | `HudFontMedium` | same |
| Match status small text | ClientScheme | `DefaultVerySmall` | same |
| Match status fallback | ClientScheme | `Default` | same |
| Match status player name | ClientScheme | `PlayerPanelPlayerName` | same |
| Match status small auxiliary | ClientScheme | `DefaultSmall` | same |
| Competitive team name | ClientScheme | `CompMatchStartTeamNames` | same |
| Match summary team scores | ClientScheme | `MatchSummaryTeamScores` | `hudmatchsummary.res` |
| MvM scoreboard title/main | ClientScheme | `ScoreboardMedium` | `mvmscoreboard.res` |
| MvM scoreboard details | ClientScheme | `HudFontSmallest` | same |
| MvM scoreboard emphasis | ClientScheme | `HudFontSmallBold` | same |
| MvM scoreboard auxiliary | ClientScheme | `HudFontMediumSmall` | same |
| MvM scoreboard regular | ClientScheme | `HudFontSmall` | same |

---

## 4. Spectating, freeze cam, coach

| Screen element | Scheme | Alias | Notes |
|---|---|---|---|
| Spectated player/status large text | ClientScheme | `HudFontMediumSmallSecondary` | `spectator.res` |
| Spectator regular text | ClientScheme | `HudFontSmall` | same |
| Spectator large status | ClientScheme | `HudFontMedium` | same |
| Spectator key hints | ClientScheme | `SpectatorKeyHints` | same |
| Spectator detail info | ClientScheme | `HudFontSmallest` | same |
| Spectator small info | ClientScheme | `DefaultVerySmall` | same |
| Spectator auxiliary info | ClientScheme | `DefaultSmall` | same |
| Freeze cam primary info | ClientScheme | `HudFontMediumSmall` | `freezepanel_basic.res` |
| Freeze cam regular info | ClientScheme | `HudFontSmall` | same |
| Freeze cam small info | ClientScheme | `DefaultSmall` | same |
| Freeze cam key hints | ClientScheme | `SpectatorKeyHints` | same |
| Coach name | ClientScheme | `HudFontMediumSmallSecondary` | `coachedbypanel.res` |
| Coach name minmode | ClientScheme | `TFFontLarge` | same |

---

## 5. Game chat, lobby chat

| Screen element | Scheme | Alias | Notes |
|---|---|---|---|
| In-game chat log | ChatScheme | `ChatFont` | `ChatScheme.res` loaded separately |
| Chat input prompt | ChatScheme | `ChatFont` | same |
| Chat input text | ChatScheme | `ChatFont` | same |
| Some lobby chat | ClientScheme | `ChatFont` | used from lobby resources |
| Lobby mini RichText chat | ClientScheme | `ChatMiniFont` | used directly from code |
| Global chat panel | ClientScheme | `HudFontSmallest` | `globalchat.res` |
| Chat popup | ClientScheme | `HudFontSmallest` | `chatpopup.res` |

Note: `ChatScheme::ChatFont` and `ClientScheme::ChatFont` must be treated as
separate settings even though the alias string is identical.

---

## 6. Developer console, engine UI

| Screen element | Scheme | Alias | Notes |
|---|---|---|---|
| Developer console body/history | SourceScheme | `ConsoleText` | used directly by ConsoleDialog |
| Console completion list | SourceScheme | `DefaultSmall` | same |
| Generic RichText | current scheme | `Default` | common VGUI control |
| RichText underline / URL | current scheme | `DefaultUnderline` | common |
| Tooltip | current scheme | `DefaultSmall` | common |
| TextEntry default input | current scheme | `Default` | common |
| TextEntry small font | current scheme | `DefaultVerySmall` | common |
| ListPanel regular | current scheme | `Default` | common |
| ListPanel header/small text | current scheme | `DefaultSmall` | common |
| CheckButton glyph | current scheme | `Marlett` / `MarlettSmall` | symbol font |
| Scrollbar arrow | current scheme | `Marlett` | symbol font |
| ComboBox arrow | current scheme | `Marlett` | symbol font |
| Frame/window glyph | current scheme | `Marlett` family | symbol font |

---

## 7. net_graph, FPS, debug UI

| Screen element | Scheme | Alias | Notes |
|---|---|---|---|
| `net_graph` | Client/engine scheme | `DefaultFixedOutline` | netgraph panel |
| net_graph small info | Client/engine scheme | `DefaultVerySmall` | same |
| FPS panel | Client/engine scheme | `DefaultFixedOutline` | FPS panel |
| FPS panel partial fallback | Client/engine scheme | `Default` | per code path |
| Debug overlay | ClientScheme | `DebugOverlay` | debug overlay panel |
| HUD animation debug label | ClientScheme | `DebugFixed` | animation info |
| HUD animation debug item | ClientScheme | `DebugFixedSmall` | same |
| Generic message chars | ClientScheme | `Default` | engine message panel |

---

## 8. Team selection, class selection, Intro, Map Info

| Screen element | Scheme | Alias | Notes |
|---|---|---|---|
| Team menu large title | ClientScheme | `MenuMainTitle` | `teammenu.res` |
| Team menu small text | ClientScheme | `MenuSmallFont` | same |
| Team menu smallest text | ClientScheme | `MenuSmallestFont` | same |
| Team menu emphasis | ClientScheme | `TeamMenuBold` | same |
| Cap/player count | ClientScheme | `CapPlayerFont` | same |
| Class selection keys | ClientScheme | `MenuKeys` | `classselection.res` |
| Class bucket/name | ClientScheme | `MenuClassBuckets` | same |
| Class selection large title | ClientScheme | `MenuMainTitle` | same |
| Class selection emphasis | ClientScheme | `HudFontSmallBold` | same |
| Class description | ClientScheme | `HudFontMediumSmallSecondary` | same |
| Class description small text | ClientScheme | `HudFontSmall` | same |
| Intro menu | ClientScheme | `MenuSmallFont` | `intromenu.res` |
| Intro caption | ClientScheme | `IntroMenuCaption` | same |
| Map info title | ClientScheme | `ChalkboardTitle` | `mapinfomenu.res` |
| Map info body | ClientScheme | `ChalkboardText` | same |
| Map info buttons | ClientScheme | `MenuSmallFont` | same |
| MOTD/TextWindow title | ClientScheme | `ChalkboardTitle` | `textwindow.res` |
| MOTD/TextWindow body | ClientScheme | `ChalkboardText` | same |
| MOTD/TextWindow buttons | ClientScheme | `MenuSmallFont` | same |

---

## 9. Main menu, GameUI

| Screen element | Scheme | Alias | Notes |
|---|---|---|---|
| Main menu | Source/GameUI | `MainMenuFont` | GameUI BasePanel |
| Generic large menu text | Source/GameUI | `MenuLarge` | GameUI common |
| GameUI buttons | Source/GameUI | `GameUIButtons` | MessageDialog, options, etc. |
| Generic dialog text | Source/GameUI | `MenuLarge` | MessageDialog etc. |
| Generic options/controls | Source/GameUI | `Default` | control default font |
| Options/list small text | Source/GameUI | `DefaultSmall` | per control |

---

## 10. Inventory, loadout, item UI

| Screen element | Scheme | Alias | Notes |
|---|---|---|---|
| Character Info title | ClientScheme | `HudFontMediumBold` | `charinfopanel.res` |
| Character Info tab/emphasis | ClientScheme | `HudFontMediumSmallBold` | same |
| Character Info small emphasis | ClientScheme | `HudFontSmallBold` | same |
| Class loadout attributes | ClientScheme | `ItemFontAttribLarge` | `classloadoutpanel.res` |
| Class loadout emphasis | ClientScheme | `HudFontSmallBold` | same |
| Class loadout small emphasis | ClientScheme | `HudFontSmallestBold` | same |
| Class loadout title | ClientScheme | `HudFontMediumBold` | same |
| Class loadout regular | ClientScheme | `HudFontSmall` | same |
| Item quick switch emphasis | ClientScheme | `HudFontSmallestBold` | `itemquickswitch.res` |
| Item quick switch name | ClientScheme | `ItemFontNameSmallest` | same |
| Item options | ClientScheme | `HudFontSmallBold` | `itemoptionspanel.res` |
| Crafting small emphasis | ClientScheme | `HudFontSmallestBold` | `craftingpanel.res` |
| Crafting keys | ClientScheme | `MenuKeys` | same |
| Crafting emphasis | ClientScheme | `HudFontSmallBold` | same |
| Crafting attributes | ClientScheme | `ItemFontAttribLarge` | same |
| Crafting title | ClientScheme | `HudFontMediumBold` | same |
| Crafting small regular | ClientScheme | `HudFontSmallest` | same |
| Backpack sort control | ClientScheme | `HudFontSmallestBold` | used directly from code |
| Item/store original price/auxiliary | ClientScheme | `FontStoreOriginalPrice` | several econ UIs |
| Store price | ClientScheme | `FontStorePrice` | econ UI |
| Item name family | ClientScheme | `ItemFontName*` | dedicated to item UI |
| Item attribute family | ClientScheme | `ItemFontAttrib*` | dedicated to item UI |
| Econ family | ClientScheme | `EconFont*` | economy/item UI |

---

## 11. Achievements, Stats

| Screen element | Scheme | Alias | Notes |
|---|---|---|---|
| Achievement dialog description | ClientScheme | `AchievementItemDescription` | `achievementsdialog.res` |
| Achievement notification | ClientScheme | `AchievementNotification*` family | per notification panel/resource |
| Competitive/stats small links | ClientScheme | `HudFontSmallestBold` | `compstats.res` etc. |
| Stats/ranking header | ClientScheme | `RankingDialogHeaders` family | related panels |

---

## 12. Matchmaking, Lobby, Competitive

| Screen element | Scheme | Alias | Notes |
|---|---|---|---|
| Lobby small status/party text | ClientScheme | `HudFontSmallestBold` | `lobbypanel.res` |
| Lobby large title | ClientScheme | `HudFontMediumBold` | same |
| Lobby regular info | ClientScheme | `HudFontSmall` | same |
| Lobby emphasis | ClientScheme | `HudFontSmallBold` | same |
| Lobby chat | ClientScheme | `ChatFont` | same |
| Lobby mini chat | ClientScheme | `ChatMiniFont` | used directly from code |
| Competitive links/buttons | ClientScheme | `HudFontSmallestBold` | `compstats.res` |
| Competitive rank headers | ClientScheme | `RankingDialogHeaders*` | related panels |

---

## 13. Mann vs. Machine

| Screen element | Scheme | Alias | Notes |
|---|---|---|---|
| MvM scoreboard | ClientScheme | `ScoreboardMedium` | `mvmscoreboard.res` |
| MvM scoreboard small info | ClientScheme | `HudFontSmallest` | same |
| MvM scoreboard emphasis | ClientScheme | `HudFontSmallBold` | same |
| MvM scoreboard auxiliary | ClientScheme | `HudFontMediumSmall` | same |
| MvM scoreboard regular | ClientScheme | `HudFontSmall` | same |
| MvM criteria title | ClientScheme | `HudFontMediumSmallBold` | `mvmcriteria.res` |
| MvM criteria/status | ClientScheme | `HudFontSmall` | same |
| Wave status | ClientScheme | `HudFontSmallestBold` | `wavestatuspanel.res` |
| Victory panel header | ClientScheme | `HudFontMediumBold` | `mvmvictorypanel.res` |
| Victory splash | ClientScheme | `HudFontGiantBold` | `mvmvictorysplash.res` |
| Upgrade panel title/emphasis | ClientScheme | `HudFontSmallBold` | `hudupgradepanel.res` |
| Upgrade panel regular | ClientScheme | `HudFontSmall` | same |
| Upgrade buy entries | ClientScheme | `HudFontSmallest` | `upgradebuypanel.res` |
| Upgrade buy regular | ClientScheme | `HudFontSmall` | same |

---

## 14. Symbol / icon aliases

The aliases/families below must be kept separate from regular text fonts. It is
safest to exclude them from automatic replacement.

| Alias / family | Role | Recommended handling |
|---|---|---|
| `Marlett` | scrollbar, checkbox, combobox, frame glyphs | exclude from automatic replacement |
| `MarlettSmall` | small control glyphs | exclude from automatic replacement |
| `WeaponIcons` | weapon icons | exclude from automatic replacement |
| `WeaponIconsSmall` | small weapon icons | exclude from automatic replacement |
| `WeaponIconsSelected` | selected weapon icons | exclude from automatic replacement |
| `Icons` | TF icon font | exclude from automatic replacement |
| `TFTypeDeath` | death/kill special glyphs | exclude from automatic replacement |
| `Buttons` | controller/button bitmap font | exclude from automatic replacement |
| `ButtonsSC` | Steam Controller button bitmap font | exclude from automatic replacement |
| `MenuKeys` | key display/special input glyph character | protect by default |
| BitmapFontFiles family | VBF-based UI glyphs | exclude from automatic replacement |

---

## 15. Reverse index: alias → actual usage

| Alias | Representative usage |
|---|---|
| `Default` | kill feed, HudMenu, spell menu, generic VGUI, some scoreboard/match UI |
| `DefaultSmall` | console completion, tooltips, freeze cam, spectator auxiliary, inspect |
| `DefaultVerySmall` | spectator, target info, net_graph, small controls |
| `DefaultUnderline` | URL/RichText underline |
| `TargetID` | Target ID direct rendering |
| `HudFontSmall` | Target ID label, objective, spectator, lobby, MvM, etc. |
| `HudFontSmallBold` | alert, goal, vote, inventory, crafting, etc. |
| `HudFontSmallest` | spectator, matchmaking, MvM, global chat, etc. |
| `HudFontSmallestBold` | lobby, inventory, competitive, wave status, etc. |
| `HudFontMedium` | ammo, account/damage, spectator, match HUD |
| `HudFontMediumSmall` | ammo, freeze cam, match status, MvM |
| `HudFontMediumSmallSecondary` | spectator, coach, class description |
| `HudFontMediumSmallBold` | match status, MvM criteria/result |
| `HudFontMediumBold` | vote header, inventory title, lobby title, MvM victory |
| `HudFontGiant` | match countdown |
| `HudFontGiantBold` | ammo, MvM victory splash |
| `ChatFont` | in-game chat, some lobby |
| `ChatMiniFont` | lobby mini chat |
| `ConsoleText` | developer console body |
| `ScoreboardVerySmall` | scoreboard rows, vote, win panel |
| `ScoreboardSmall` | scoreboard/vote |
| `ScoreboardMedium` | scoreboard, win panel, MvM |
| `ScoreboardTeamName*` | team names |
| `ScoreboardTeamScore*` | team scores |
| `SpectatorKeyHints` | spectator/freezecam key hints |
| `ChalkboardTitle` | map info/MOTD title |
| `ChalkboardText` | map info/MOTD body |
| `MenuMainTitle` | team/class selection |
| `MenuSmallFont` | team/intro/map info |
| `GameUIButtons` | GameUI buttons/some scoreboard |
| `MainMenuFont` | main menu |
| `MenuLarge` | generic large GameUI text |
| `ItemFontAttrib*` | item attributes/loadout/crafting |
| `ItemFontName*` | item names |
| `FontStoreOriginalPrice` | store/item/owner related labels |

---

## 16. Design considerations

### 16.1 The same alias string under a different scheme is a different setting

Every scheme keeps a private alias table, so identical strings under different
schemes never merge; see [VGUI-NOTES](VGUI-NOTES.md) ("Alias resolution") for
the engine-level evidence. The settings model must therefore key on the
combination, not on the alias string alone.

Recommended internal identifier:

```text
SchemeId::Alias::GlyphSetKey
```

Example:

```text
ClientScheme::Default::3
ClientScheme::TargetID::1
ChatScheme::ChatFont::1
SourceScheme::ConsoleText::1
```

### 16.2 UI ↔ alias is a many-to-many relationship

For example, the user-facing concept of a "player name" splits like this:

```text
Aimed target      → TargetID / HudFontSmall
Kill feed         → Default
Scoreboard        → Scoreboard*
Spectating        → HudFontMediumSmallSecondary / HudFontSmall
Freeze cam        → HudFontMediumSmall
Names in chat     → ChatFont
```

Therefore, grouping everything under a single "Player Name" in the UI makes it
hard to express the actual impact accurately.

### 16.3 Some aliases have a very wide impact

Notably `Default`, `HudFontSmall`, `HudFontSmallestBold` and friends are reused
across many screens.

When the user edits an alias, an impact summary like the following is useful:

```text
ClientScheme::Default

Used by:
- Kill Feed
- HudMenu
- Spell Menu
- Generic Labels
- Misc HUD

Risk: High impact
```

### 16.4 Symbol / icon fonts must not be auto-replaced

`Marlett`, `WeaponIcons`, `TFTypeDeath`, `Buttons` and friends draw UI glyphs,
not actual text.

Replacing them with a regular sans-serif can break buttons, icons, checkboxes
and weapon indicators.

### 16.5 Keep the static usage map as documentation; detect actual usage from resources

Custom HUDs are free to change alias usage and resource structure.

Therefore the tool should automatically extract the `font`, `TextFont` and
`font_*` properties from:

```text
resource/*.res
resource/ui/*.res
scripts/HudLayout.res
```

and use the semantic map in this document as human-readable documentation and
baseline category metadata.

### 16.6 Recommended final UI structure

Bidirectional navigation is the most useful.

```text
[By UI]
HUD
 ├─ Kill Feed
 │   └─ ClientScheme::Default
 ├─ Target ID
 │   ├─ ClientScheme::TargetID
 │   └─ ClientScheme::HudFontSmall
 ├─ Chat
 │   └─ ChatScheme::ChatFont
 └─ Scoreboard
     ├─ ScoreboardTeamNameNew
     ├─ ScoreboardVerySmall
     └─ ...
```

And the other way around:

```text
[By alias]
ClientScheme::HudFontSmall
 ├─ Target ID
 ├─ Objective/Goal
 ├─ Spectator
 ├─ Lobby
 └─ MvM
```

This connects the per-alias/glyph-set editor to the actual on-screen impact most
accurately.
