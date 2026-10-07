---
name: ThoughtVault
description: ThoughtVault recording, transcription & notulen studio. Native macOS/iOS + Windows, one shared design language.
colors:
  brand-primary: "#9048F0"
  brand-primary-dark: "#7830D8"
  brand-secondary: "#6048F0"
  brand-lavender: "#D890F0"
  brand-accent: "#009F3C"
  brand-orange: "#F39200"
  neon-blue: "#8F6BFF"
  surface-primary: "#FFFFFF"
  surface-secondary: "#F5F5F7"
  surface-tertiary: "#EBEBF0"
  text-primary: "#333338"
  text-secondary: "#6B6B73"
  text-tertiary: "#99999F"
  border-primary: "#E0E0E6"
  border-secondary: "#EDEDF0"
  status-error: "#EF4444"
  status-warning: "#F9A500"
  status-success: "#009F3C"
typography:
  large-title:
    fontFamily: "SF Pro Rounded, Segoe UI Variable, system-ui, sans-serif"
    fontSize: "34px"
    fontWeight: 700
    lineHeight: 1.1
    letterSpacing: "normal"
  title:
    fontFamily: "SF Pro Rounded, Segoe UI Variable, system-ui, sans-serif"
    fontSize: "28px"
    fontWeight: 600
    lineHeight: 1.15
    letterSpacing: "normal"
  title2:
    fontFamily: "SF Pro Rounded, Segoe UI Variable, system-ui, sans-serif"
    fontSize: "22px"
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "normal"
  title3:
    fontFamily: "SF Pro Rounded, Segoe UI Variable, system-ui, sans-serif"
    fontSize: "20px"
    fontWeight: 600
    lineHeight: 1.25
    letterSpacing: "normal"
  headline:
    fontFamily: "SF Pro Rounded, Segoe UI Variable, system-ui, sans-serif"
    fontSize: "17px"
    fontWeight: 600
    lineHeight: 1.3
    letterSpacing: "normal"
  body:
    fontFamily: "SF Pro, Segoe UI, -apple-system, system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.4
    letterSpacing: "normal"
  caption:
    fontFamily: "SF Pro, Segoe UI, -apple-system, system-ui, sans-serif"
    fontSize: "12px"
    fontWeight: 400
    lineHeight: 1.45
    letterSpacing: "normal"
  label:
    fontFamily: "SF Pro, Segoe UI, -apple-system, system-ui, sans-serif"
    fontSize: "10px"
    fontWeight: 700
    lineHeight: 1.3
    letterSpacing: "0.08em"
  mono:
    fontFamily: "SF Mono, Cascadia Code, Segoe UI Mono, monospace"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.4
    letterSpacing: "normal"
rounded:
  xs: "6px"
  sm: "12px"
  md: "16px"
  lg: "20px"
  xl: "25px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "16px"
  lg: "24px"
  xl: "32px"
  xxl: "48px"
components:
  button-primary:
    backgroundColor: "{colors.brand-primary}"
    textColor: "#FFFFFF"
    typography: "{typography.body}"
    rounded: "{rounded.sm}"
    padding: "10px 24px"
  button-primary-hover:
    backgroundColor: "{colors.brand-primary}"
    textColor: "#FFFFFF"
    rounded: "{rounded.sm}"
    padding: "10px 24px"
  button-secondary:
    backgroundColor: "{colors.surface-secondary}"
    textColor: "{colors.brand-primary}"
    border: "{colors.brand-primary}"
    typography: "{typography.body}"
    rounded: "{rounded.sm}"
    padding: "10px 24px"
  button-ghost:
    backgroundColor: "#00000000"
    textColor: "{colors.text-secondary}"
    typography: "{typography.body}"
    rounded: "{rounded.sm}"
    padding: "10px 24px"
  input:
    backgroundColor: "{colors.surface-primary}"
    textColor: "{colors.text-primary}"
    typography: "{typography.body}"
    rounded: "{rounded.sm}"
    padding: "10px 14px"
  card:
    backgroundColor: "{colors.surface-primary}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.md}"
    padding: "16px"
  filter-pill:
    backgroundColor: "{colors.surface-primary}"
    textColor: "{colors.text-secondary}"
    typography: "{typography.caption}"
    rounded: "{rounded.xl}"
    padding: "6px 12px"
  status-badge:
    backgroundColor: "{colors.surface-tertiary}"
    textColor: "{colors.text-secondary}"
    typography: "{typography.label}"
    rounded: "{rounded.xs}"
    padding: "2px 10px"
---

# Design System: ThoughtVault

## 1. Overview

**Creative North Star: "The Thought Vault"**

ThoughtVault is a branded workspace, not a neutral utility. It is unmistakably ThoughtVault the moment it loads: the lavender-to-indigo gradient bar, the glowing violet record orb, violet gradients on every primary action. But it earns that brand confidence by sitting inside a calm, Apple-native shell: `SF Pro Rounded` headings, glass surfaces, spring physics on every interaction. The brand is the personality; the platform is the manners.

The single most important fact about this system is that it is **one design language rendered twice**. The macOS/iOS app (SwiftUI, `TS.Spacing`/`TS.Radius`/`TS.Font` tokens, `Color.brandPrimary`) and the Windows app (Tauri, CSS custom properties in `globals.css`, Tailwind) carry **identical** hex values, spacing scale, radii, and animation curves. The Windows CSS is annotated line-by-line as "matches macOS." Any change to a token must land on both platforms or the parity breaks. That discipline is the system.

The aesthetic is warm-friendly-professional: rounded display type and 12-20px radii keep it approachable, glassmorphic cards keep it modern, and the restrained surface palette keeps the violet loud where it matters. It explicitly rejects the generic "dark-mode SaaS dashboard" look (neon-on-charcoal, sharp corners, dense data grids) and the flat-corporate-blue enterprise tool. Depth comes from translucency and soft shadow, never from heavy chrome.

**Key Characteristics:**
- **Cross-platform parity is law** — every token exists identically in `Color+Brand.swift`/`Theme.swift` and `globals.css`.
- **ThoughtVault violet `#9048F0` leads** every primary action, usually as a 135° gradient into `#7830D8`.
- **Glass surfaces** (`backdrop-filter: blur(20px)`, translucent fill) carry the entire card system on both platforms.
- **`SF Pro Rounded`** for headings/titles gives the friendly voice; system sans for body keeps it legible.
- **8pt spacing grid**, continuous-corner radii, spring/ease-out motion — Apple HIG rhythm throughout.
- **Full light + dark** adaptive palettes, both first-class.

## 2. Colors

A violet-family brand palette (sampled from the logo: lavender, violet, indigo) riding on a near-neutral surface system, with violet as the dominant action color and indigo as the interactive/navigation color.

### Primary
- **ThoughtVault Violet** (`#9048F0`): The brand's voice and the app's primary action color. Every primary button, the record orb, active accents and focus rings. Often rendered as a 135° gradient `#9048F0 → #7830D8` with a colored drop shadow.
- **Violet Deep** (`#7830D8`): The gradient terminus and pressed/active state for violet surfaces.
- **Lavender** (`#D890F0`): The light end of the brand gradient (brand bar, waveform, gradient headlines).

### Secondary
- **Indigo** (`#6048F0`): The *interactive* color: navigation selection, active sidebar items, tabs, links, input focus rings, filter pills. Violet acts; indigo navigates. Keeping these two roles separate is deliberate.

### Tertiary
- **Green** (`#009F3C`): Semantic accent, doubles as `status-success`. Success badges, completed steps.
- **Orange** (`#F39200`): Semantic accent for warnings and accent tints; `status-warning` is a near-sibling `#F9A500`.
- **Neon Violet** (`#8F6BFF`): Reserved exclusively for the recording waveform glow.

### Neutral
- **Surface Primary** (`#FFFFFF` light / `#1A1C29` dark): Cards, sidebar, inputs, the raised plane.
- **Surface Secondary** (`#F5F5F7` light / `#212433` dark): The app canvas / page background.
- **Surface Tertiary** (`#EBEBF0` light / `#282A3D` dark): Recessed fills, neutral badges, table headers.
- **Text Primary** (`#333338` light / `#F2F2F7` dark): Body and headings. Note: not pure black — a soft near-ink for warmth.
- **Text Secondary** (`#6B6B73` light / `#9E9EA6` dark): Labels, captions, secondary copy.
- **Text Tertiary** (`#99999F` light / `#6C6C74` dark): Placeholders, metadata, disabled hints.
- **Border Primary** (`#E0E0E6` light / `#383B4D` dark) / **Border Secondary** (`#EDEDF0` light / `#2C2E40` dark): Dividers and card strokes, always 1px.

### Status
- **Error** (`#EF4444`), **Warning** (`#F9A500`), **Success** (`#009F3C` = brand green). Status colors shift in dark mode (error → `#FF6B6B`, success → `#34D058`) for contrast.

### Named Rules
**The Two-Voice Rule.** Violet acts, indigo navigates. Primary actions and recording are violet; selection, tabs, links, and focus-within-navigation are indigo. Never use violet for a nav-selection state or indigo for a primary CTA.

**The Parity Rule.** No color exists on one platform only. Every value here lives identically in `Color+Brand.swift` and `globals.css`. A new color is added to both or it does not exist.

## 3. Typography

**Display Font:** SF Pro Rounded (fallback Segoe UI Variable on Windows, then `system-ui`)
**Body Font:** SF Pro / system sans (`-apple-system`, Segoe UI)
**Mono Font:** SF Mono (fallback Cascadia Code, Segoe UI Mono) — timestamps, codes, the recording timer.

**Character:** The rounded display family is the friendly half of the brand: titles feel soft and human, never corporate. Body falls back to the crisp platform system sans for maximum legibility at small sizes. The contrast is rounded-warm headings over neutral-sharp body.

### Hierarchy
- **Large Title** (700, 34px, ~1.1): Hero / login title, rendered in the brand gradient.
- **Title** (600, 28px): Screen titles.
- **Title2 / Title3** (600, 22px / 20px): Major and minor section titles; rounded design.
- **Headline** (600, 17px, rounded): Card headers.
- **Body** (400, 14px web / ~17pt macOS, line-height 1.4): Primary content. macOS uses Dynamic Type `.body`; web pins 14px.
- **Caption** (400, 12px): Metadata, timestamps, secondary descriptions.
- **Label** (700, 10px, `letter-spacing: 0.08em`, UPPERCASE): Section labels, status-badge text, recording-control labels. The one place uppercase is allowed.
- **Mono** (400, 14px): The 56px ultra-light recording timer is the signature exception — `font-weight: 100`, tabular-nums.

### Named Rules
**The Rounded-Heading Rule.** Anything title-tier and up uses the rounded design (`.rounded` on macOS, `SF Pro Rounded` on web). Body and controls use plain system sans. Don't render body copy in the rounded face.

**The Uppercase-Label-Only Rule.** Uppercase + tracked is reserved for ≤2-word labels and badges at the 10px micro size. Never uppercase a sentence or a button.

## 4. Elevation

A **glass-and-soft-shadow** system. Surfaces are not flat: the entire card vocabulary is glassmorphic — translucent fill plus `backdrop-filter: blur(20px)` over the gray canvas, with a 1px translucent border and a soft ambient shadow. On macOS 26+ this is the native `.glassEffect`; on older macOS and on Windows it's the `.ultraThinMaterial` / `backdrop-blur` fallback. Depth is conveyed by blur and translucency first, shadow second — never by heavy borders or dark drop shadows.

### Shadow Vocabulary
- **Card ambient** (`box-shadow: 0 3px 8px rgba(0,0,0,0.06)`): Resting state of every card.
- **Card hover** (`box-shadow: 0 6px 16px rgba(0,0,0,0.12)`): Paired with `transform: scale(1.02)` and a violet/indigo border tint on hover.
- **Brand action shadow** (`0 3px 8px rgba(144,72,240,0.30)` → `0 4px 12px ...0.40` hover): The colored glow under violet buttons and the record orb.

### Named Rules
**The Glass-Default Rule.** Cards, flyouts, badges, and the sidebar are glass over the canvas. Solid opaque panels are the exception, not the default. Dark mode deepens shadows (`rgba(0,0,0,0.20)`), it does not remove the glass.

**The Lift-On-Hover Rule.** Interactive surfaces respond to hover with a ~1.02 scale + shadow bump + accent border tint, on a 180ms ease. A card that doesn't lift reads as inert; use `.card-static` only where lift is wrong.

## 5. Components

### Buttons
- **Shape:** 12px radius (`rounded.sm`), continuous corners on macOS.
- **Primary (`.btn-accent` / `PrimaryButtonStyle`):** 135° gradient `#9048F0 → #7830D8`, white text, weight 600, violet glow shadow, `10px 24px` padding (`lg` horizontal + `sm+2` vertical on macOS).
- **Hover / Active:** Hover deepens the shadow; active scales to 0.97 with reduced opacity and a deeper gradient. 150ms quick ease.
- **Secondary (`.btn-secondary` / `SecondaryButtonStyle`):** Violet-tinted translucent fill (`rgba(144,72,240,0.08)`), violet text, 1px violet border: the outlined variant.
- **Ghost (`.btn-ghost`):** Transparent, secondary-text color, fills with the indigo subtle tint on hover.
- **Destructive:** Same as primary but red (`status-error`) gradient and glow.

### Filter Pills & Tag Chips
- **Filter pill:** Capsule (`rounded.xl`, 25px), transparent with 1px border at rest; active fills solid indigo with white text. Hover shifts border + text to indigo.
- **Quick-start pill:** Violet-outlined capsule (1.5px violet border, faint violet wash) for hero entry points.
- **Tag chip:** Small capsule, indigo-tinted background + indigo text; "add" variant uses a dashed border.

### Cards / Containers
- **Corner Style:** 16px (`rounded.md`); elevated/large variants use 20px (`rounded.lg`).
- **Background:** Glass — `rgba(255,255,255,0.72)` + `blur(20px)` (dark: `rgba(33,36,51,0.72)`).
- **Border:** 1px translucent (`--card-border`), shifts to a violet tint on hover.
- **Shadow:** Card-ambient at rest, card-hover on hover (see Elevation).
- **Padding:** 16px (`md`) internal default.

### Inputs / Fields
- **Style:** Solid surface fill, 1px border-primary, 12px radius, `10px 14px` padding.
- **Focus:** Border shifts to indigo + a 3px `rgba(96,72,240,0.12)` ring. Placeholders use text-tertiary.

### Navigation (Sidebar)
- **Style:** 210px (web) collapsible sidebar; on macOS a custom 52px-icon ↔ full sidebar toggled with `Shift+Cmd+S`. Items are footnote-size, 6px radius, default weight.
- **States:** Hover → indigo subtle tint + indigo text; **active → solid indigo fill, white text, weight 600, soft indigo shadow.**

### Status Badges
- Micro (10px) uppercase label in a 6px-radius tinted pill: accent (violet), success (green), warning (orange), neutral (gray). Each uses a 10%-opacity fill + a 0.5px tint border in its own hue.

### Signature Components
- **The Record Orb:** A glowing violet radial-gradient orb with concentric rings and an ambient Siri-waveform. The emotional center of the app (hero on Home, mic button while recording).
- **The Brand Bar:** The logo's lavender → violet → indigo gradient as a slim horizontal bar (`BrandBar` on both platforms). The footer reads "Developed by BuildMind" (`BrandFooter`).
- **The 56px Timer:** Ultra-light (weight 100) tabular-nums monospace recording clock — the one deliberately oversized type moment.
- **The Live Badge:** A pulsing red dot (`live-pulse` 1.2s) + uppercase "LIVE" label; pauses to amber when recording is paused.

## 6. Do's and Don'ts

### Do:
- **Do** keep every token identical across `Color+Brand.swift`/`Theme.swift` and `globals.css` — parity is the system (The Parity Rule).
- **Do** use violet `#9048F0` for actions and the record orb, indigo `#6048F0` for navigation/selection/focus (The Two-Voice Rule).
- **Do** render primary buttons and the record orb with the violet gradient and colored glow shadow.
- **Do** build surfaces as glass over the gray canvas, with 1px translucent borders and soft ambient shadow (The Glass-Default Rule).
- **Do** use `SF Pro Rounded` for titles and headlines; plain system sans for body and controls (The Rounded-Heading Rule).
- **Do** stay on the 8pt spacing grid (`TS.Spacing` / `--space-*`) and the 6/12/16/20/25px radius ladder.
- **Do** give interactive surfaces a ~1.02 hover lift + shadow + accent-border tint (The Lift-On-Hover Rule), and ship a `prefers-reduced-motion` fallback.
- **Do** support light and dark equally; both palettes are first-class.

### Don't:
- **Don't** let this drift into a generic dark-mode SaaS dashboard (neon-on-charcoal, sharp corners, dense grids) — that's the explicit anti-reference.
- **Don't** use a `border-left`/`border-right` colored stripe as a card or callout accent. (A colored left-border on a card is legacy, not a pattern to repeat.)
- **Don't** introduce gradient *text* (`background-clip: text`); gradients belong on fills and buttons only.
- **Don't** add flat opaque panels where a glass card belongs, or convey depth with heavy/dark drop shadows.
- **Don't** set body or button copy in UPPERCASE — uppercase is the 10px tracked label/badge size only (The Uppercase-Label-Only Rule).
- **Don't** swap the action/navigation colors (violet nav-selection or indigo primary CTA).
- **Don't** add a color, radius, or spacing value to one platform without adding the identical value to the other.
- **Don't** introduce a third display typeface; the rounded + system-sans pairing is the whole type system.
