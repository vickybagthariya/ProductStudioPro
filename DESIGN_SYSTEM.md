# Product Studio — Design System

Product Studio’s design language targets **premium, professional, fast, calm, and minimal** retail catalog workflows. The system should feel like an Apple first-party app while keeping the charcoal + mint brand identity.

This document describes the **new reusable design system** (`PSDesign*` types). Existing screens still use legacy `DS` tokens until they are migrated screen-by-screen.

---

## Philosophy

| Principle | Application |
|-----------|---------------|
| **Calm** | Generous whitespace, soft springs, muted secondary text |
| **Fast** | Snappy press feedback, loading states on every async action |
| **Minimal** | Three corner radii, one spacing grid, restrained shadows |
| **Professional** | Dynamic Type, semantic colors, consistent SF Symbols |
| **Premium** | Subtle elevation, brand accent used sparingly |

### Animation philosophy

- **Snappy springs** (`PSDesignMotion.springSnappy`) for taps, chips, and buttons
- **Soft springs** (`PSDesignMotion.springSoft`) for cards, sheets, and selection changes
- **No gratuitous motion** — animate state changes, not decoration
- **Haptics paired with interaction** — selection for chips, tap for buttons, success/error for outcomes

---

## Colors

Access via `PSDesignColors` or `PSDesignSystem.Colors`.

| Token | Usage |
|-------|-------|
| `primaryAccent` | Links, icons, selected borders — charcoal (light) / mint (dark) |
| `secondaryAccent` | Highlights, secondary fills |
| `background` | Root screen surface |
| `elevatedBackground` | Sheets, grouped sections, raised panels |
| `cardBackground` | Cards, list rows, chips (unselected) |
| `divider` | Hairlines, card strokes |
| `success` | Completed export, valid barcode |
| `warning` | Soft cap, validation hints |
| `error` | Failures, destructive emphasis |
| `textPrimary` | Headlines, body |
| `textSecondary` | Subtitles, metadata |
| `textTertiary` | Placeholders, footnotes |

### Brand palette (underlying)

- **Charcoal** `#283F3B` — structural accent in light mode
- **Mint** `#99DDC8` — accent in dark mode, brand highlight

---

## Typography

All styles use **Dynamic Type** and scale with accessibility settings.

| Style | Modifier | Font |
|-------|----------|------|
| Large Title | `.psLargeTitle()` | `.largeTitle.bold` |
| Title | `.psTitle()` | `.title2.semibold` |
| Headline | `.psHeadline()` | `.headline` |
| Body | `.psBody()` | `.body` |
| Callout | `.psCallout()` | `.callout` |
| Caption | `.psCaption()` | `.caption.medium` |
| Footnote | `.psFootnote()` | `.footnote` |

```swift
Text("Summer Catalog")
    .psTitle()

Text("42 products queued")
    .psCaption()
```

---

## Spacing

8-point grid via `PSDesignSpacing`:

| Token | Value | Typical use |
|-------|-------|-------------|
| `xs` | 4pt | Icon gaps, chip padding |
| `sm` | 8pt | Compact stacks |
| `md` | 16pt | Card padding, section gaps |
| `lg` | 24pt | Section separation |
| `xl` | 32pt | Major breaks |
| `xxl` | 48pt | Empty states, hero spacing |

---

## Corner radius

**Only three values are permitted:**

| Token | Value | Use |
|-------|-------|-----|
| `PSDesignRadius.sm` | 12pt | Chips, list rows, compact controls |
| `PSDesignRadius.md` | 18pt | Buttons, selection cards |
| `PSDesignRadius.lg` | 24pt | Feature cards, hero panels |

Do not introduce ad-hoc radii (8, 14, 16, etc.) in new screens.

---

## Shadows

| Token | Use |
|-------|-----|
| `PSDesignShadow.small` | List rows, inline cards |
| `PSDesignShadow.medium` | Feature cards, dashboard tiles |
| `PSDesignShadow.floating` | Toolbars, modals, action sheets |

Apply with `.psShadowSmall()`, `.psShadowMedium()`, or `.psShadowFloating()`.

---

## Components

### Buttons

| Component | When to use |
|-----------|-------------|
| `PrimaryButton` | Main CTA — Export, Capture, Apply |
| `SecondaryButton` | Alternate path — Cancel pair, secondary export |
| `GhostButton` | Tertiary / inline — Learn more, dismiss text |
| `CircularIconButton` | Toolbar icons — back, home, settings |

All buttons support:

- `isDisabled`
- `isLoading`
- Haptic feedback on press
- Optional SF Symbol via `systemImage`

```swift
PrimaryButton("Export ZIP", systemImage: PSDesignIcons.export, isLoading: isExporting) {
    export()
}
```

### Cards

| Component | When to use |
|-----------|-------------|
| `FeatureCard` | Dashboard actions, onboarding, hero content |
| `SelectionCard` | Presets, templates, mode pickers (selected state) |
| `ListCard` | Queue rows, settings rows, compact lists |

### Chips

| Component | When to use |
|-----------|-------------|
| `StatusChip` | Read-only badges — Ready, Processing, Exported |
| `FilterChip` | Toggle filters — angle, format, background |
| `CategoryChip` | Taxonomy — marketplace, category, tags |

---

## Haptics

Centralized in `PSDesignHaptics` (respects Settings → Vibrate):

| Method | When |
|--------|------|
| `tap()` | Button press |
| `selection()` | Chip / picker change |
| `success()` | Export complete, save succeeded |
| `warning()` | Soft cap, validation |
| `error()` | Failure, blocked action |

---

## Icons

Use `PSDesignIcons` constants and `PSDesignIcons.resolved(_:)` for consistency.

### Recommended replacements

| Legacy | Use instead |
|--------|-------------|
| `photo`, `photo.fill` | `photo.on.rectangle.angled` |
| `camera` | `camera.fill` |
| `gear` | `gearshape.fill` |
| `wand.and.stars`, `sparkle` | `sparkles` |
| `house` | `house.fill` |
| `chevron.backward` | `chevron.left` |

Always prefer **filled** variants for primary navigation and **monochrome** rendering in toolbars.

---

## Naming conventions

| Layer | Prefix | Example |
|-------|--------|---------|
| Design tokens | `PSDesign` | `PSDesignColors`, `PSDesignSpacing` |
| Components | Plain names | `PrimaryButton`, `FeatureCard` |
| Private styles | `PS` prefix | `PSPrimaryButtonStyle` |
| Legacy (do not extend) | `DS` | `DSPrimaryButton`, `DS.ColorToken` |

### File layout

```
DesignSystem/
  Tokens/
    PSDesignColors.swift
    PSDesignTypography.swift
    PSDesignSpacing.swift
    PSDesignRadius.swift
    PSDesignShadow.swift
    PSDesignMotion.swift
    PSDesignHaptics.swift
  Components/
    PSButtons.swift
    PSCards.swift
    PSChips.swift
  PSDesignIcons.swift
  PSDesignSystem.swift
  DESIGN_SYSTEM.md
```

---

## Migration guide

When redesigning a screen:

1. Replace hardcoded colors with `PSDesignColors`
2. Replace fixed font sizes with typography modifiers (`.psHeadline()`, etc.)
3. Replace ad-hoc padding with `PSDesignSpacing` constants
4. Swap legacy `DSPrimaryButton` → `PrimaryButton` when touching that screen
5. Use `PSDesignIcons` for any new or updated symbols
6. Preview with `PSDesignSystemPreviewGallery` in Xcode (#Preview)

**Do not** bulk-migrate all screens at once. Migrate incrementally to reduce regression risk.

---

## Preview

Open `PSDesignSystem.swift` in Xcode and run the **Design System Gallery** preview to inspect tokens and components together.
