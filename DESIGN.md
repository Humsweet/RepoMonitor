# RepoMonitor — Design Tokens

Warm-dark "terminal" aesthetic: neutral charcoal surfaces, a single red
accent, earthy muted text, and status collapsed to three signals
(clean / attention / error). Source of truth is `RepoMonitor/Views/Theme.swift`;
this document mirrors it so designers and agents have a flat reference.

## Color

### Surfaces
| Token | Hex | Use |
|---|---|---|
| `bg` | `#141414` | Window background, table body rows |
| `bgSecondary` | `#1C1C1C` | Table header row, control surfaces |
| `bgTertiary` | `#242424` | Raised surfaces |
| `bgCard` | `#1C1C1C` | Inputs, cards (search field, gear button) |
| `bgHover` | `#242424` | Row / control hover fill |

### Text (earthy, low-chroma)
| Token | Hex | Use |
|---|---|---|
| `textPrimary` | `#E8E6E3` | Repo names, primary labels |
| `textSecondary` | `#7A7672` | Secondary text, last-scan timestamps |
| `textTertiary` | `#4A4845` | Dim labels, placeholders, zero-value sync, empty states |

### Accent (single red)
| Token | Hex | Use |
|---|---|---|
| `accent` | `#C0392B` | Scan button, active sort arrow, primary action |
| `accentHover` | `#D95F50` | Action-button hover foreground |
| `accentSoft` | `rgba(192,57,43,0.15)` | Action-button hover fill |

### Status — three signals only
| Level | Token | Hex | Meaning |
|---|---|---|---|
| clean | `statusClean` | `#7DAA6E` (green) | Up to date, no local changes |
| attention | `statusDirty` / `statusBehind` | `#C9963A` (amber) | Dirty working tree, or behind remote |
| error | `statusError` | `#D95F50` (red) | Fetch/pull failed |

Sync arrows: `syncAhead` = amber `#C9963A`, `syncBehind` = red `#D95F50`
(both fall back to `textTertiary` when the count is 0).

### Borders
| Token | Value |
|---|---|
| `border` | `rgba(255,255,255,0.07)` — row dividers |
| `borderFocused` | `rgba(255,255,255,0.12)` — card outline, header underline, focus |

### Tag (group) palette
Each distinct group folder (e.g. `Github Personal`, `Bitbucket`, `Github Work`)
gets a **stable** tint via a hash of its name, so badges are distinguishable
without becoming a rainbow. Deliberately desaturated:

`#8A8580` warm gray · `#9A7B5A` tan · `#6E8A7D` sage · `#A06A6A` dusty rose ·
`#7D7A9A` muted periwinkle · `#9A8F5A` olive gold

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
