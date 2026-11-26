# DESIGN.md, the flat design language

This is the one visual and motion language every surface follows. The README covers what
each piece does; this covers how it all looks and moves. Read it before restyling anything,
or you'll end up with twelve surfaces that don't agree with each other.

It's **flat** (minimal depth: one subtle shadow lifts floating surfaces, otherwise no depth
tricks) and **palette-driven** (every color comes from the active wallust scheme via
`Theme.qml` reading `colors.json` live through `FileView{watchChanges}`). Nothing's tied to a
fixed hue. It has to look right across all 18 schemes, light ones included. Motion is matched
1:1 to the Hyprland config so the shell and the compositor move like one thing.

Heads up: design work is structural work, so verify it from a clean `qs kill` + relaunch. The
hot-reload happily reloads token values but keeps rendering the old layout for structural
edits (see the README gotchas). Never trust a screenshot of a restyle without a fresh restart.

## principles

1. **Flat, minimal depth.** No gradients, glows, or blur, anywhere. Surfaces are solid fills
   or subtle flat tints. The one allowed depth cue is a single soft drop shadow on *floating*
   surfaces (the island, popout panels) so they lift off the wallpaper. It's tokenized
   (`shadow`/`shadowBlur`/`shadowY`) and identical everywhere. Layering between *stacked*
   surfaces is shown with a step in fill plus a hairline (plus a flat dim for modals), never
   stacked shadows.
2. **Hierarchy from color, weight, and space.** With depth off the table, contrast,
   typography, and spacing do all the work. Getting the spacing rhythm and type hierarchy
   right *is* the design now.
3. **One accent, only for meaning.** The scheme's accent marks exactly one thing per surface:
   active, focused, playing, or the primary action. Everything else is ink on surface. If the
   accent is just decorating, kill it.
4. **Calm, physical motion.** Springs matched to the compositor, near-critically-damped, no
   bounce. Spatial stuff uses the spatial spring, fades use the effects spring. It should feel
   like Hyprland, not like a toy.
5. **Quiet by default, expressive on interaction.** Idle and collapsed states stay minimal;
   the richness shows up on hover/open. The notch is the whole idea: a bare clock until you
   ask for more.
6. **Crisp over fancy.** The polish is precise edges, solid color, tight spacing, confident
   type. Not effects. The one indulgence is the "alive" cues (EQ bars, a breathing dot) plus
   the accent, all rendered flat.

## tokens, the `Theme.qml` backbone

Everything below lives in `Theme.qml` as a token that every component reads. Zero literals in
modules. Derive from the wallust palette so a theme swap restyles all of it live.

**Color roles** (from `colors.json`)
- `bg`, `fg`, `accent`: straight from the scheme.
- `accentDeep`: `accent` darkened ~12%, for pressed/active.
- `onAccent`: readable ink *on* the accent, near-black or near-white by `accent` luminance,
  so accent fills work in every scheme.
- Surfaces (flat layering by fill step, not shadow): `surface` = `mix(bg, fg, .04)`,
  `surfaceRaised` = `mix(bg, fg, .08)`, `surfaceOverlay` = `mix(bg, fg, .12)`. A panel reads
  as "on top" because its fill is a step lighter than what's behind it. That's the whole
  layering mechanism.
- Ink: `inkPrimary` = `fg`, `inkDim` = `fg @ .60`, `inkFaint` = `fg @ .35`.
- Fill tints (solid-looking tints, not glass, nothing blurs behind 'em): `fillLow` =
  `fg @ .06`, `fillHigh` = `fg @ .13` (button/chip/row backgrounds), `hairline` = `fg @ .14`
  (borders and dividers). Deriving these from `fg` is exactly what makes the language adapt to
  light themes for free.
- `scrim`: a flat translucent *black* dim (~50%) behind modals. On purpose not palette-tinted,
  its job is to push the background back. No blur.
- `shadow` / `shadowBlur` / `shadowY` / `shadowBlurMax`: the single soft drop shadow for
  floating surfaces. Flat black, low alpha, small vertical offset, no spread creep. The only
  depth effect in the system. Never used for stacked layering (that's fill step + hairline),
  never blurred.
- Semantic (muted, palette-mapped): `good`, `warn`, `bad`, for battery-low, errors,
  destructive confirms. Used rarely.

**Radii:** `rSm` 10 (inner controls), `rMd` 14 (cards/inner), `rLg` 18 (surfaces/panels),
`rPill` 999. Surfaces use `rLg`, inner elements `rMd`, pills/toggles `rPill`. Keep 'em steady;
flat reads best with consistent, moderate corners.

**Spacing:** base unit 4. Scale `s1` to `s6` = 4 / 8 / 12 / 16 / 24 / 32. Surface padding at
least `s4`, inner gaps `s2` to `s3`. Consistency matters more than ever now that spacing
carries the hierarchy.

**Typography:** two shell UI families (separate from whatever the apps' wallust themes do).
- `fontDisplay` = SF Mono (numerals and data labels: clock, OSD values). `fontBody` = SF Pro
  (everything else). `fontGlyph` = JetBrainsMono Nerd Font (icon glyphs).
- Scale (relative to `Theme.fontSize` so the settings slider scales all of it): `display`
  (clock), `title`, `body`, `label`, `caption`. Weights 400 / 500 only.
- Any live-updating number uses tabular figures (the mono face, or `font.features` tnum) so
  the width never twitches as it ticks.

**Motion:** matched to the Hyprland `hl.curve` definitions, same `{mass, stiffness, damping}`
trio driving the shell and the compositor.
- `springSpatial` = `md3_spatial_fast`, `{ mass 1, stiffness 600, damping 49 }` (about 387ms,
  no overshoot). Everything spatial: notch expand/collapse, panel open/close, song-switch,
  list reflow, morphs.
- `springEffects` = `md3_effects_default`, `{ mass 1, stiffness 1600, damping 80 }` (about
  233ms). Opacity and color: fades, borders.
- Layer surfaces appearing/disappearing are the *compositor's* job, not QML's. They follow the
  Hyprland `layers` curves. The shell inherits these for free, so don't go re-animating the
  surface itself in QML.
- `stagger` about 80ms: revealed content fades in just after the surface settles, on
  `springEffects`. A small cascade, no more.
- No overshoot anywhere. These springs are critically damped on purpose, which is exactly the
  calm the flat look wants.
- Honor a `reducedMotion` flag (collapse the durations).

**Iconography:** one stroke set, consistent weight (~1.8px), 15 to 20px inline (24 max).
`inkPrimary`/`inkDim`, never multicolor. Filled glyphs use solid flat fills.

## how the language scales per surface

- **Bar / notch** (`modules/bar/Bar.qml`). Floating island: solid fill, `hairline`, the soft
  floating `shadow`. Spring-expands on hover/pin; collapsed it's the clock plus a mini accent
  EQ viz while playing; expanded it's media, hero clock/date, and a status pill. Fades on
  `springEffects`.
- **Popout panels:** launcher, control center, notification history. `surfaceRaised` fill,
  `hairline`, the floating `shadow`, no blur. Open on `springSpatial`, content staggers in,
  accent marks selection/focus, focus-grab dismiss. Same material as the notch so they read as
  siblings.
- **Transient OSDs:** a mini-notch. Small solid pill, the changing value drawn flat in
  `accent` as a level bar, spring-out auto-hide.
- **Auth and confirm:** lock, polkit, logout. Full attention: the flat `scrim` dims the
  desktop (no blur), centered `surfaceOverlay` card plus `hairline`. Accent only on the
  primary control. Polkit still has to show the real action and keep exclusive keyboard focus.
- **Lock (full-screen):** wallpaper dimmed by the flat `scrim`, one centered card, big
  `fontDisplay` clock, minimal.
- **Content-forward pickers:** wallpaper and theme switchers. The thumbnails/swatches *are*
  the UI, chrome recedes. Selection is an accent ring/border, hover is a flat `fillLow` tint
  or a 1px accent outline (not a lift or shadow), current item clearly marked.
- **Settings:** the most "UI" surface. Sectioned `surfaceRaised` panels split by `hairline`s,
  generous spacing, reuse the shared controls, legibility over flourish. It's long, so
  consistency beats wow.

## shared primitives

The whole thing leans on `components/`. Build those to the flat tokens once and most
components match for free, since they're just composed from these: `Scrim` (flat dim, no
blur), `Surface`/`Card` (solid fill + `hairline`), `IconButton`, `StyledButton` (ghost =
`fillLow` to `fillHigh` on hover, accent = solid `accent` fill), `Toggle`, `Slider`,
`SearchField`, `ListRow` (hover = `fillLow`, selected = accent marker), `StyledText` (the type
scale), `Pill` (the notch/OSD shell). Every other component is assembled from these, not
styled ad hoc. That's what keeps "make everything match" from turning into a dozen bespoke
restyles.

## a component is done when it

1. uses only `Theme` tokens, no inline colors/sizes/radii/durations;
2. is built from the shared primitives, not bespoke chrome;
3. is flat: no gradient/glow/blur, depth limited to the one floating `shadow` token, stacked
   layering via fill step + `hairline` (+ `scrim` for modals);
4. moves on the matched springs (`springSpatial` for movement, `springEffects` for fades) with
   the small content stagger, no overshoot;
5. uses the accent for one meaning only;
6. sits next to the notch in a screenshot without looking foreign;
7. still looks right in a second palette (test a contrasting one, light if you've got it);
8. was verified from a clean `qs` restart, not a hot-reload.
