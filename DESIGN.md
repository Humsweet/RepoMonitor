# RepoMonitor — Design Tokens

Warm "terminal" aesthetic in **two appearances** that share one identity:
neutral surfaces, a single red accent, earthy muted text, and status collapsed
to three signals (clean / attention / error). The **dark** side is the original
warm-charcoal terminal look; the **light** side is a warm "paper" tone (ivory
surfaces, espresso text) tuned for readability on bright screens. Source of
truth is `RepoMonitor/Views/Theme.swift`; this document mirrors it so designers
and agents have a flat reference.

## Appearance modes
A single `ThemeManager` (persisted in `UserDefaults`, key
`RepoMonitor.themeMode`) drives the whole app from one switch — `NSApp.appearance`
— so every window, the menu-bar popover, sheets, and system controls flip
together. `ThemeMode` is `system` (follow macOS) / `light` / `dark`, chosen in
Settings › Appearance and applied immediately (no Save).

Each token below is a **dynamic color** with a light and a dark value (see
`Color.themed(_:_:)`); views reference tokens only and never branch on mode.

## Color

### Surfaces
| Token | Light | Dark | Use |
|---|---|---|---|
| `bg` | `#F7F3EC` | `#141414` | Window background, table body rows |
| `bgSecondary` | `#EFEAE0` | `#1C1C1C` | Table header row, control surfaces |
| `bgTertiary` | `#E7E1D4` | `#242424` | Raised surfaces |
| `bgCard` | `#FFFDF9` | `#1C1C1C` | Inputs, cards (search field, gear button) |
| `bgHover` | `#EBE4D6` | `#242424` | Row / control hover fill |

### Text (earthy, low-chroma)
| Token | Light | Dark | Use |
|---|---|---|---|
| `textPrimary` | `#2B2723` | `#E8E6E3` | Repo names, primary labels |
| `textSecondary` | `#6E6760` | `#7A7672` | Secondary text, last-scan timestamps |
| `textTertiary` | `#968D80` | `#4A4845` | Dim labels, placeholders, zero-value sync, empty states |

### Accent (single red)
| Token | Light | Dark | Use |
|---|---|---|---|
| `accent` | `#C0392B` | `#C0392B` | Scan button, active sort arrow, primary action |
| `accentHover` | `#9E2E22` | `#D95F50` | Action-button hover foreground |
| `accentSoft` | red @ 12% | red @ 15% | Action-button hover fill |

### Status — three signals only
| Level | Token | Light | Dark | Meaning |
|---|---|---|---|---|
| clean | `statusClean` | `#3F7A35` | `#7DAA6E` | Up to date, no local changes |
| attention | `statusDirty` / `statusBehind` | `#9A6B16` | `#C9963A` | Dirty working tree, or behind remote |
| error | `statusError` | `#BE3B2C` | `#D95F50` | Fetch/pull failed |

Sync arrows: `syncAhead` = amber (`#9A6B16` / `#C9963A`), `syncBehind` = red
(`#BE3B2C` / `#D95F50`); both fall back to `textTertiary` when the count is 0.

### Borders
| Token | Light | Dark | Use |
|---|---|---|---|
| `border` | black @ 10% | white @ 7% | Row dividers |
| `borderFocused` | black @ 16% | white @ 12% | Card outline, header underline, focus |

### Tag (group) palette
Each distinct group folder (e.g. `Github Personal`, `Bitbucket`, `Github Work`)
gets a **stable** tint via a hash of its name, so badges are distinguishable
without becoming a rainbow. Deliberately desaturated; light tints are deepened
so colored text stays legible on the ivory surface (light / dark):

`#6B655D`/`#8A8580` warm gray · `#8A6536`/`#9A7B5A` tan · `#43705B`/`#6E8A7D` sage ·
`#8F4B4B`/`#A06A6A` dusty rose · `#565380`/`#7D7A9A` muted periwinkle ·
`#756A2C`/`#9A8F5A` olive gold

Rendered as: text = tint, fill = tint @ 12%, border = tint @ 28%.

## Typography
System font throughout (SF). Monospaced (`.monospaced`) for counts and
timestamps.

| Role | Size / weight | Notes |
|---|---|---|
| Window title | 18 / bold | Top bar "RepoMonitor" |
| Column header | 10 / medium | Uppercase, `tracking` 0.7, `textTertiary`; active → `textPrimary` + accent arrow |
| Repo name | 13 / medium | `textPrimary`, middle truncation |
| Sync count | 11 / mono | Semibold when non-zero |
| Tag badge | 10 / regular | |
| Issue pill | 11 / regular | |
| Last scan | 11 / mono | `textSecondary` |
| Body / controls | 13–14 | Search, buttons |

## Radius & metrics
- Card / panel radius: **8**
- Tag badge radius: **3**; issue pill: **capsule**; action button: **5**
- Status dot: **7×7** circle
- Action button: **26×26**, transparent → `accentSoft` fill on hover
  (danger variant → `statusError` @ 15%)

### Table column widths (pt)
Defined once in `Col` (RepoTableView.swift) so header and rows stay aligned.

| Column | Width | Align |
|---|---|---|
| Tag | 104 | leading |
| Repo (dot + name) | flexible, min 200 — absorbs slack | leading |
| Sync (`↑n · ↓n`) | 112 | leading |
| Issues (pill) | 196 | leading |
| Last scan | 132 | leading |
| Actions | 196 | trailing |

Row padding: 16 horizontal / 9 vertical. Header padding: 16 / 7.

## Component conventions
- **Row hover**: solid `bgHover` fill (no opacity blend).
- **Path**: not a column — shown in the row's hover tooltip alongside branch,
  upstream, remote, and divergence detail.
- **Issues pill**: clean rows show an outlined `✓ —`; attention = amber
  triangle + text; error = red octagon + text. Fill = tint @ 12%, border @ 30%.
- **Action buttons**: flat single row (no grouping/separators) —
  Scan · Pull · Finder · VS Code · Terminal · Unwatch (danger).
- **Default sort**: by Tag group, ascending. Sort key excludes status, so rows
  cluster by group and never reorder mid-scan.

## Anti-patterns (don't reintroduce)
- More than three status colors. Behind and dirty both map to amber.
- A standalone Path column (use the tooltip).
- Splitting action buttons into separated groups.
- Saturated / bright tag colors. Keep them muted.
