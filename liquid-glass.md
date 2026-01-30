# Implementing Liquid Glass and the iOS 26 Design System in SwiftUI

> Updated: 2026-01-24


## Table of contents
- Mental model
- Patterns observed in Apple apps (and what to copy)
- Core SwiftUI APIs you should now treat as part of the Liquid Glass toolbox
- iOS 26 structural UI updates you should align with
- Toolbars, icons, grouping, and badges
- Search patterns (toolbar search vs dedicated Search tab)
- Scroll edge effects
- Concentricity: the “nested corner radius” rule
- Variant selection and legibility
- Practical “Do / Don’t” checklist
- Key Apple resources to consult
- Human Interface Guidelines deep dive (practical summary)
- Quick “Apple look” checklist for an existing app

This is an updated skill reference for adopting **Liquid Glass** and the broader **iOS 26 / macOS Tahoe-era** design system in SwiftUI, with particular attention to patterns visible in Apple’s stock apps (floating tab bars, bottom accessories like mini players, inset sheets, map overlays, and dense “calendar-like” layouts).

---

## Mental model

### Liquid Glass is a functional UI layer
Liquid Glass is intended to be a **floating functional layer** above content: it should provide structure and affordance without stealing attention from the content beneath it.

### Glass is not “just blur”
You should think of Liquid Glass as a system material that:
- adapts to what’s behind it,
- creates separation for legibility,
- morphs/merges based on layout and transitions,
- responds to interaction when configured to be interactive.

---

## Patterns observed in Apple apps (and what to copy)

### 1) Floating tab bar + persistent mini player (Podcasts-like)
- Tab bar visually “floats” above content.
- A **mini player** sits above the tab bar and persists across tabs.
- Search is commonly a **dedicated tab** in multi-tab apps.
- Scrolling can minimize the tab bar on iPhone for more content.

**SwiftUI mapping**
- `TabView`
- `.tabBarMinimizeBehavior(...)`
- `.tabViewBottomAccessory { ... }` for the mini player accessory
- Use Liquid Glass for the accessory surface and/or controls.

### 2) Map + inset Liquid Glass bottom sheet (Find My–like)
- Content (map) continues behind a translucent, rounded, inset sheet.
- Sheet contains lists, primary/secondary actions, and a clear hierarchy.

**SwiftUI mapping**
- Default iOS 26 partial-height sheets are inset with Liquid Glass.
- Keep controls legible and avoid stacking extra blur overlays.

### 3) Dense “calendar-like” screens
- Many floating UI elements benefit from **stronger scroll edge separation**.
- A “harder” edge effect can improve clarity in dense layouts.

**SwiftUI mapping**
- `.scrollEdgeEffectStyle(.hard, for: ...)` for dense, control-heavy views.

---

## Core SwiftUI APIs you should now treat as part of the Liquid Glass toolbox

### `glassEffect`
Use Liquid Glass on custom components.

```swift
Text("Hello")
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .glassEffect()
```

Shape customization:

```swift
Text("Hello")
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .glassEffect(.regular, in: .rect(cornerRadius: 16))
```

Key config:
- `Glass.regular`
- `Glass.clear` (only when you can guarantee readability over rich backgrounds)
- `Glass.identity` (effectively “no glass” — useful for conditional enablement)
- `.tint(...)`
- `.interactive(...)`

### `GlassEffectContainer`
Use this any time multiple nearby glass elements should look coherent or morph together.

Why: **glass cannot sample other glass**, so separate sampling regions can look inconsistent.

```swift
GlassEffectContainer(spacing: 20) {
    HStack(spacing: 12) {
        Button { } label: { Image(systemName: "heart.fill") }
            .buttonStyle(.glass)

        Button { } label: { Image(systemName: "bookmark.fill") }
            .buttonStyle(.glass)
    }
}
```

### Morphing and unions
Morphing relies on:
- a shared `GlassEffectContainer`
- a shared namespace
- stable IDs

```swift
@Namespace private var glassNS
@State private var expanded = false

var body: some View {
    GlassEffectContainer(spacing: 24) {
        HStack(spacing: 12) {
            if expanded {
                Image(systemName: "play.fill")
                    .frame(width: 56, height: 44)
                    .glassEffect()
                    .glassEffectID("player", in: glassNS)
            } else {
                Image(systemName: "play.fill")
                    .frame(width: 44, height: 44)
                    .glassEffect()
                    .glassEffectID("player", in: glassNS)
            }
        }
    }
    .onTapGesture { withAnimation(.spring) { expanded.toggle() } }
}
```

If you need multiple views to contribute to the *same* glass shape:

```swift
@Namespace private var glassNS

GlassEffectContainer(spacing: 16) {
    HStack(spacing: 10) {
        ForEach(0..<4) { i in
            Circle()
                .frame(width: 18, height: 18)
                .glassEffect()
                .glassEffectUnion(id: "dots", namespace: glassNS)
        }
    }
}
```

### `glassEffectTransition`
Use when you need explicit control over what happens as glass enters/leaves the hierarchy.

```swift
MyView()
    .glassEffect()
    .glassEffectTransition(.identity)
```

(Choose transitions sparingly; default behavior is often best.)

### `glassBackgroundEffect`
Use when you want a dedicated **background** glass treatment (thickness/specularity/shadows) behind content.

This is often relevant for:
- app chrome surfaces,
- panels,
- accessory bars,
- custom sheets/panels.

---

## iOS 26 structural UI updates you should align with

### Tab bar minimization
```swift
TabView {
    Tab("Home", systemImage: "house") { Home() }
    Tab("Search", systemImage: "magnifyingglass", role: .search) { Search() }
    Tab("Library", systemImage: "books.vertical") { Library() }
}
.tabBarMinimizeBehavior(.onScrollDown)
```

### Bottom accessory (mini player)
```swift
struct RootTabs: View {
    @State private var showPlayer = true
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") { Home() }
            Tab("Search", systemImage: "magnifyingglass", role: .search) { Search() }
            Tab("Library", systemImage: "books.vertical") { Library() }
        }
        .tabViewBottomAccessory {
            if showPlayer {
                MiniPlayer()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        }
    }
}

struct MiniPlayer: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "music.note")
            Text("Now Playing")
                .lineLimit(1)
            Spacer(minLength: 8)
            Button { } label: { Image(systemName: "play.fill") }
                .buttonStyle(.glass)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
    }
}
```

Tip: Use `tabViewBottomAccessoryPlacement` to adjust spacing/layout when the tab bar is minimized vs normal.

---

## Toolbars, icons, grouping, and badges

### Let the system group items
Toolbar items automatically group on a floating Liquid Glass surface. Prefer grouping via the proper SwiftUI APIs, not manual backgrounds.

### Separate items from the shared background
If you have an item that should not share the grouped background (like an avatar), use shared background visibility to isolate it.

### Badge a toolbar item
```swift
.toolbar {
    ToolbarItem(placement: .topBarTrailing) {
        Button { } label: { Image(systemName: "bell") }
            .badge(1)
    }
}
```

### Tint icons only for meaning
Default monochrome icons reduce visual noise. Use tint to convey action/meaning, not decoration.

---

## Search patterns (toolbar search vs dedicated Search tab)

### Toolbar search across an entire split view
```swift
NavigationSplitView {
    Sidebar()
} detail: {
    Detail()
}
.searchable(text: $query)
```

### Opt into minimized search
Use `searchToolbarBehavior` when search isn’t central.

---

## Scroll edge effects

Scroll edge effects are how the system maintains legibility where content scrolls under floating UI.

For dense layouts, tune it:

```swift
ScrollView {
    content
}
.scrollEdgeEffectStyle(.hard, for: .top)
```

General guidance:
- Use **soft** most of the time (iOS/iPadOS).
- Use **hard** where you need extra clarity (dense layouts, macOS-like panes).
- Avoid mixing/stacking multiple edge effects on the same view.

---

## Concentricity: the “nested corner radius” rule

A huge part of the iOS 26 look is **concentricity**: nested rounded shapes whose corner arcs share a common center, so they feel “made together” rather than eyeballed.

### Apple references (deep links)
- **Get to know the new design system** — introduces the three shape types (fixed / capsule / concentric) and the idea that concentric shapes “calculate their radius by subtracting padding from the parent’s.” (3:49)  
  https://developer.apple.com/videos/play/wwdc2025/356/?time=229
- **Get to know the new design system** — calls out “pinched or flared” corners and explicitly points to nested containers (artwork in a card) as a common failure case. (5:19)  
  https://developer.apple.com/videos/play/wwdc2025/356/?time=319
- **Meet Liquid Glass** — notes that glass controls nest into rounded window/display corners, maintaining concentricity across the UI. (8:01)  
  https://developer.apple.com/videos/play/wwdc2025/219/?time=481

### The math rule an agent can use

If an inner rounded rect is inset by **d** points (padding/margin) from an outer rounded rect with corner radius **R**, then the concentric inner radius **r** is:

> **r = max(0, R − d)**

This is exactly what “subtract padding from the parent’s” means in concrete terms.

#### Worked examples
- Outer radius **R = 24**, padding **d = 8** → inner radius **r = 16**
- Outer radius **R = 20**, padding **d = 16** → inner radius **r = 4**
- Outer radius **R = 12**, padding **d = 16** → inner radius **r = 0** (becomes square)

#### Multiple nesting levels
If you have multiple layers of insets, sum them:

> **rₙ = max(0, R − (d₁ + d₂ + … + dₙ))**

Example: R=28 with padding 8 then 6 then 4 → r₃ = 28 − 18 = 10.

#### Per-corner radii (non-uniform)
If the outer shape has per-corner radii **Rᵢ**, apply the same rule per corner:

> **rᵢ = max(0, Rᵢ − dᵢ)**

In most UI layouts, **dᵢ** is the local inset at that corner (typically your uniform padding). If the horizontal/vertical insets differ, you generally can’t keep a perfect shared-center circle for every corner — prefer system concentric APIs (below) instead of manual math.

#### Borders / strokes (common pitfall)
If you draw a border, the visually “available” corner radius shrinks. Prefer `strokeBorder` (draws inside) and treat the inset as:

> **d = padding + borderWidth**

If you use `stroke` (draws centered on the path), treat it as approximately:

> **d = padding + borderWidth / 2**

### SwiftUI-first way (preferred over manual math)

**Don’t guess radii** if the system can infer them.

#### 1) Set a container shape on the parent
This tells container-relative/concentric shapes what they’re nesting inside.

```swift
VStack { ... }
    .padding(16)
    .background {
        RoundedRectangle(cornerRadius: 24).fill(.background)
    }
    .containerShape(RoundedRectangle(cornerRadius: 24))
```

#### 2) Use concentric inner shapes
```swift
VStack { ... }
    .padding(16)
    .background {
        RoundedRectangle(cornerRadius: 24).fill(.background)
    }
    .containerShape(RoundedRectangle(cornerRadius: 24))
    .overlay {
        ConcentricRectangle()
            .strokeBorder(.separator, lineWidth: 1)
    }
```

#### 3) Use concentric corners without `ConcentricRectangle`
```swift
Text("Tag")
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(.thinMaterial, in: .rect(corners: .concentric(minimum: 12), isUniform: true))
```

### Explicit corner radii: a simple system (only if you must)

Apple doesn’t publish a universal “use 12pt here, 20pt there” table — the *system* prefers you use the three shape types (fixed, capsule, concentric) and let containers define geometry.

But when you’re building a custom component library and you **must** pick fixed radii, a small explicit scale helps agents stay consistent:

**Suggested fixed-radius scale (points):**
- **8**  — tiny chips, small badges
- **12** — compact controls (≈ 32–44pt tall)
- **16** — standard cards / grouped rows
- **20** — prominent cards / panels
- **24** — large surfaces inside content (hero cards)
- **28** — very large cards on iPad / desktop-like layouts

**Rule of thumb to choose one:**
1. Let **h** = component height (or shortest side for non-square rectangles).
2. Choose a fixed radius near **h × 0.28**, rounded to the nearest 4, clamped to **[8, 28]**.
3. If it should feel “button-like” and touch-first, prefer `.capsule` instead of a fixed radius.

Once you pick the outer radius, compute inner radii via **r = max(0, R − d)** (or use concentric shapes).

---

## Variant selection and legibility

### Regular vs clear
- **Regular** is the default and most versatile.
- **Clear** should be reserved for cases where the background is visually rich and you can still guarantee readable foreground content.

Avoid mixing variants within a tight area unless you have a strong reason.

### User settings may change perceived glass
Apple has iterated on Liquid Glass opacity during iOS 26 betas and introduced user-facing controls (clear vs tinted) in at least some 26.1 builds.

Implication:
- Don’t hard-code designs that only work for one “exact” opacity.
- Validate in Light/Dark, Increased Contrast, and Reduced Transparency.
- Make sure text/icons have enough contrast regardless of how “glassy” glass becomes.

---

## Practical “Do / Don’t” checklist

### Do
- Use system bars, tab views, sheets, and toolbars “as-is” first; remove old custom chrome.
- Use **layout and grouping** for hierarchy; use tint for meaning.
- Put nearby glass elements into a `GlassEffectContainer`.
- Use `glassEffectID` + `@Namespace` for morphing transitions.
- Use `tabViewBottomAccessory` for persistent mini-player style UI.
- Use `scrollEdgeEffectStyle` to maintain legibility in dense layouts.
- Adopt **concentricity** (`containerShape`, `ConcentricRectangle`) for nested UI polish.

### Don’t
- Add extra backgrounds/dimming behind toolbars/tab bars that fight the system edge effect.
- Stack multiple glass layers (glass can’t sample other glass → inconsistent results).
- Use clear glass on text-heavy UI over busy backgrounds.
- Treat Liquid Glass as purely decorative; it’s a functional layer.

---

## Key Apple resources to consult

- WWDC25: **Meet Liquid Glass**
- WWDC25: **Get to know the new design system**
- WWDC25: **Build a SwiftUI app with the new design**
- Apple Human Interface Guidelines (focus areas):
  - Materials
  - Toolbars
  - Sidebars
  - Scroll views
  - Icons

(Keep these resources in your “first stop” loop whenever updating an app that has custom chrome or heavy styling.)


---

## Human Interface Guidelines deep dive (practical summary)

This section distills the parts of Apple’s interface guidance that most directly affect how “native” your app feels when adopting Liquid Glass and the new system UI.

### Structure: make the first 5 seconds obvious
Design each screen to answer, quickly:
- **Where am I?**
- **What can I do?**
- **Where can I go from here?**

Practical tactics:
- Reduce or merge features that don’t deserve first-class placement.
- Rename things until they read clearly without a tutorial.
- Group related functionality so your navigation becomes predictable.

### Navigation: tabs are for places, not actions
- Use **TabView** to navigate between the *primary sections* of your app.
- Keep the number of tabs small; each extra tab increases decision load.
- Don’t put “Add / Create / Compose” in the tab bar unless it’s actually a *destination*; make actions contextual.

Use toolbars for screen-specific actions:
- Titles orient users while they scroll.
- A small number of recognizable icon actions (SF Symbols) is usually enough.
- If you have too many actions, that’s a signal to move secondary actions into a menu.

### Content: reduce choice overload with progressive disclosure + grouping
Progressive disclosure:
- Show “just enough” content to get started.
- Reveal more content behind a “See all” / disclosure affordance when it becomes relevant.

Grouping patterns that work across many apps:
- **Time** (recent, seasonal, “up next”)
- **Progress** (continue, drafts, “incomplete”)
- **Similarity/patterns** (genres, categories, “related”)

Layout choice:
- Prefer **List** for structured information people need to scan quickly.
- Use carousels/collections for highly visual content (photos, products, media artwork) with restrained text.

### Visual design: hierarchy comes from layout first, not decoration
- Use size, spacing, alignment, and grouping to express hierarchy.
- Treat color/tint as meaningful emphasis, not ornament.
- Ensure the most important content becomes the “visual anchor” at a glance.

### Materials and effects: keep glass in the navigation layer
- Reserve Liquid Glass for the **floating navigation/control layer**, not the main content layer.
- Avoid **glass-on-glass**. If elements must sit above glass, prefer fills, transparency, and vibrancy so they feel like part of the same material.
- Choose variants intentionally:
  - **Regular** for most UI (adaptive, legible in more contexts).
  - **Clear** only when the background is visually rich *and* you can keep foreground content bold + readable.

### Accessibility and settings: design for “less glassy” too
Liquid Glass adapts, and users may prefer less transparency.
Practical checklist:
- Validate legibility in **Light/Dark**.
- Validate with **Increase Contrast** and **Reduce Transparency**.
- Don’t rely on subtle lensing to convey state; include clear text/iconography and layout changes.

---

## Quick “Apple look” checklist for an existing app

1) **Build with the latest SDK** and inspect what the system now does for free.
2) **Remove custom chrome**:
   - custom nav bar backgrounds
   - extra borders behind toolbar items
   - manual tab bar backgrounds
3) Adopt new structure affordances where appropriate:
   - dedicated Search tab pattern
   - `tabBarMinimizeBehavior`
   - `tabViewBottomAccessory` for persistent controls
4) Audit corner radii + nesting:
   - move toward container-driven concentricity
5) Only then add custom Liquid Glass elements:
   - `glassEffect`
   - `GlassEffectContainer`
   - morphing with `glassEffectID`
