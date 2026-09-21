// Style values for the UI tree: plain immutable structs a caller builds from
// `defaults()` and hands to layout and paint. `validate` is the single guard --
// every length finite and, for padding and the size bounds, non-negative; a
// margin may be negative; a `Px` minimum never above a `Px` maximum; opacity in
// `[0, 1]`; the background brush as `paint.validate` sees it. There is no
// cascade, selector or inheritance: a style is what its fields say.

use e.gfx.geometry
use e.gfx.paint

type Length = union enum u8 { Auto, Px: f32, Percent: f32, Flex: f32 }
type EdgeLengths = struct { left: Length, top: Length, right: Length, bottom: Length }
type Display = enum u8 { Flex, Grid, Stack, None }
type Position = enum u8 { Flow, Absolute }
type Overflow = enum u8 { Visible, Clip, Scroll }
type Style = struct { display: Display, position: Position, width: Length, height: Length, min_width: Length, min_height: Length, max_width: Length, max_height: Length, margin: EdgeLengths, padding: EdgeLengths, background: paint.Brush, opacity: f32, overflow: Overflow }
error Invalid

fn finite(v: f32) -> bool {
    ret v - v == 0.0
}

// A length's number when it has one; `Auto` answers zero and true.
fn amount(l: Length) -> (f32, bool) {
    switch l {
    case .Auto:
        ret (0.0, true)
    case .Px as v:
        ret (v, finite(v))
    case .Percent as v:
        ret (v, finite(v))
    case .Flex as v:
        ret (v, finite(v))
    }
    ret (0.0, false)
}

fn length_ok(l: Length, allow_negative: bool) -> bool {
    let (v, fin) = amount(l)
    if !fin { ret false }
    if !allow_negative && v < 0.0 { ret false }
    ret true
}

fn edges_ok(e: EdgeLengths, allow_negative: bool) -> bool {
    ret length_ok(e.left, allow_negative) && length_ok(e.top, allow_negative) && length_ok(e.right, allow_negative) && length_ok(e.bottom, allow_negative)
}

fn px_of(l: Length) -> (f32, bool) {
    switch l {
    case .Px as v:
        ret (v, true)
    case .Auto:
        ret (0.0, false)
    case .Percent as v:
        ret (v, false)
    case .Flex as v:
        ret (v, false)
    }
    ret (0.0, false)
}

fn defaults() -> Style {
    let none = Length { Px: 0.0 }
    let auto: Length = .Auto
    ret Style {
        display: .Flex,
        position: .Flow,
        width: auto,
        height: auto,
        min_width: auto,
        min_height: auto,
        max_width: auto,
        max_height: auto,
        margin: EdgeLengths { left: none, top: none, right: none, bottom: none },
        padding: EdgeLengths { left: none, top: none, right: none, bottom: none },
        background: paint.Brush { Solid: paint.rgba(0.0, 0.0, 0.0, 0.0) },
        opacity: 1.0,
        overflow: .Visible,
    }
}

fn validate(value: *const Style) -> err {
    if !length_ok(value.width, false) || !length_ok(value.height, false) { ret Invalid }
    if !length_ok(value.min_width, false) || !length_ok(value.min_height, false) { ret Invalid }
    if !length_ok(value.max_width, false) || !length_ok(value.max_height, false) { ret Invalid }
    if !edges_ok(value.margin, true) || !edges_ok(value.padding, false) { ret Invalid }
    let (min_w, has_min_w) = px_of(value.min_width)
    let (max_w, has_max_w) = px_of(value.max_width)
    if has_min_w && has_max_w && min_w > max_w { ret Invalid }
    let (min_h, has_min_h) = px_of(value.min_height)
    let (max_h, has_max_h) = px_of(value.max_height)
    if has_min_h && has_max_h && min_h > max_h { ret Invalid }
    if !finite(value.opacity) || value.opacity < 0.0 || value.opacity > 1.0 { ret Invalid }
    if paint.validate(&value.background) != ok { ret Invalid }
    ret ok
}

// ------------------------------------------------------------ theme tokens (D805)
//
// A theme is a value: colour roles, text roles, spacing, radii, borders, elevation,
// motion and control metrics, with the palette, presentation profile and text
// direction it was made for. A component resolves its own look during build from
// the tokens it is handed -- `resolve` for a control's state -- and an adaptation
// (size class, host capabilities, profile) makes a new value from an old one. No
// selector, cascade or lookup by name: a role is an enum and a token is a field.

type ColorRole = enum u8 { Background, Surface, SurfaceVariant, Primary, OnPrimary, Secondary, OnSecondary, Text, TextMuted, Border, Focus, Error, OnError, Selection }
type TextRole = enum u8 { Body, BodySmall, Title, Heading, Label, Caption, Code }
type TextStyle = struct { size: f32, line_height: f32, weight: u16, italic: bool }
type Spacing = struct { xs: f32, sm: f32, md: f32, lg: f32, xl: f32 }
type Radii = struct { sm: f32, md: f32, lg: f32, full: f32 }
type Borders = struct { hairline: f32, regular: f32, thick: f32 }
type Motion = struct { fast_ms: u32, normal_ms: u32, slow_ms: u32, reduced: bool }
type Metrics = struct { hit_target: f32, control_height: f32, density: f32, focus_ring: f32, focus_offset: f32 }
type Palette = enum u8 { Light, Dark, HighContrast, Custom }
type Profile = enum u8 { Neper, DesktopDense, Touch, MaterialLike, CupertinoLike }
type Direction = enum u8 { LeftToRight, RightToLeft }
type ThemeTokens = struct { palette: Palette, profile: Profile, direction: Direction, colors: [14]paint.Color, text: [7]TextStyle, spacing: Spacing, radii: Radii, borders: Borders, elevation: [4]f32, motion: Motion, metrics: Metrics }
type ControlState = struct { hovered: bool, pressed: bool, focused: bool, selected: bool, disabled: bool, read_only: bool, invalid: bool }
type ControlVariant = enum u8 { Filled, Outlined, Plain }
type ResolvedControl = struct { background: paint.Color, foreground: paint.Color, border: paint.Color, border_width: f32, focus_ring: f32, opacity: f32, radius: f32 }
type SizeClass = enum u8 { Compact, Medium, Expanded }
type Capabilities = struct { hover: bool, fine_pointer: bool, keyboard: bool, touch: bool, pen: bool, resizable: bool, multi_window: bool, insets: geometry.Insets }
type Adaptation = struct { size: SizeClass, capabilities: Capabilities, profile: Profile }

fn color_index(role: ColorRole) -> usize {
    if role == .Surface { ret 1usize }
    if role == .SurfaceVariant { ret 2usize }
    if role == .Primary { ret 3usize }
    if role == .OnPrimary { ret 4usize }
    if role == .Secondary { ret 5usize }
    if role == .OnSecondary { ret 6usize }
    if role == .Text { ret 7usize }
    if role == .TextMuted { ret 8usize }
    if role == .Border { ret 9usize }
    if role == .Focus { ret 10usize }
    if role == .Error { ret 11usize }
    if role == .OnError { ret 12usize }
    if role == .Selection { ret 13usize }
    ret 0usize
}

fn text_index(role: TextRole) -> usize {
    if role == .BodySmall { ret 1usize }
    if role == .Title { ret 2usize }
    if role == .Heading { ret 3usize }
    if role == .Label { ret 4usize }
    if role == .Caption { ret 5usize }
    if role == .Code { ret 6usize }
    ret 0usize
}

fn color(t: *const ThemeTokens, role: ColorRole) -> paint.Color {
    ret t.colors[color_index(role)]
}

fn text_style(t: *const ThemeTokens, role: TextRole) -> TextStyle {
    ret t.text[text_index(role)]
}

// The reference theme: the Neper profile in one of the three built-in palettes.
// `Custom` starts from Light for a caller to overwrite.
fn reference(palette: Palette) -> ThemeTokens {
    var t: ThemeTokens = zero
    t.palette = palette
    t.profile = .Neper
    t.direction = .LeftToRight
    let dark = palette == .Dark
    let contrast = palette == .HighContrast
    var c: [14]paint.Color = zero
    if dark {
        c[0] = paint.rgba(0.07, 0.07, 0.09, 1.0)
        c[1] = paint.rgba(0.12, 0.12, 0.15, 1.0)
        c[2] = paint.rgba(0.18, 0.18, 0.22, 1.0)
        c[3] = paint.rgba(0.45, 0.62, 1.0, 1.0)
        c[4] = paint.rgba(0.05, 0.05, 0.08, 1.0)
        c[5] = paint.rgba(0.62, 0.55, 0.95, 1.0)
        c[6] = paint.rgba(0.05, 0.05, 0.08, 1.0)
        c[7] = paint.rgba(0.93, 0.93, 0.95, 1.0)
        c[8] = paint.rgba(0.62, 0.62, 0.68, 1.0)
        c[9] = paint.rgba(0.28, 0.28, 0.34, 1.0)
        c[10] = paint.rgba(0.55, 0.72, 1.0, 1.0)
        c[11] = paint.rgba(1.0, 0.42, 0.42, 1.0)
        c[12] = paint.rgba(0.08, 0.02, 0.02, 1.0)
        c[13] = paint.rgba(0.25, 0.38, 0.65, 1.0)
    } else {
        if contrast {
            c[0] = paint.rgba(1.0, 1.0, 1.0, 1.0)
            c[1] = paint.rgba(1.0, 1.0, 1.0, 1.0)
            c[2] = paint.rgba(0.92, 0.92, 0.92, 1.0)
            c[3] = paint.rgba(0.0, 0.0, 0.6, 1.0)
            c[4] = paint.rgba(1.0, 1.0, 1.0, 1.0)
            c[5] = paint.rgba(0.35, 0.0, 0.55, 1.0)
            c[6] = paint.rgba(1.0, 1.0, 1.0, 1.0)
            c[7] = paint.rgba(0.0, 0.0, 0.0, 1.0)
            c[8] = paint.rgba(0.2, 0.2, 0.2, 1.0)
            c[9] = paint.rgba(0.0, 0.0, 0.0, 1.0)
            c[10] = paint.rgba(0.0, 0.0, 0.0, 1.0)
            c[11] = paint.rgba(0.75, 0.0, 0.0, 1.0)
            c[12] = paint.rgba(1.0, 1.0, 1.0, 1.0)
            c[13] = paint.rgba(0.0, 0.0, 0.6, 1.0)
        } else {
            c[0] = paint.rgba(0.98, 0.98, 0.99, 1.0)
            c[1] = paint.rgba(1.0, 1.0, 1.0, 1.0)
            c[2] = paint.rgba(0.94, 0.94, 0.96, 1.0)
            c[3] = paint.rgba(0.15, 0.4, 0.9, 1.0)
            c[4] = paint.rgba(1.0, 1.0, 1.0, 1.0)
            c[5] = paint.rgba(0.42, 0.33, 0.8, 1.0)
            c[6] = paint.rgba(1.0, 1.0, 1.0, 1.0)
            c[7] = paint.rgba(0.1, 0.1, 0.12, 1.0)
            c[8] = paint.rgba(0.42, 0.42, 0.48, 1.0)
            c[9] = paint.rgba(0.8, 0.8, 0.84, 1.0)
            c[10] = paint.rgba(0.15, 0.4, 0.9, 1.0)
            c[11] = paint.rgba(0.82, 0.16, 0.16, 1.0)
            c[12] = paint.rgba(1.0, 1.0, 1.0, 1.0)
            c[13] = paint.rgba(0.7, 0.82, 1.0, 1.0)
        }
    }
    t.colors = c
    var s: [7]TextStyle = zero
    s[0] = TextStyle { size: 14.0, line_height: 20.0, weight: 400u16, italic: false }
    s[1] = TextStyle { size: 12.0, line_height: 16.0, weight: 400u16, italic: false }
    s[2] = TextStyle { size: 20.0, line_height: 28.0, weight: 600u16, italic: false }
    s[3] = TextStyle { size: 28.0, line_height: 36.0, weight: 700u16, italic: false }
    s[4] = TextStyle { size: 13.0, line_height: 18.0, weight: 500u16, italic: false }
    s[5] = TextStyle { size: 11.0, line_height: 14.0, weight: 400u16, italic: false }
    s[6] = TextStyle { size: 13.0, line_height: 18.0, weight: 400u16, italic: false }
    t.text = s
    t.spacing = Spacing { xs: 4.0, sm: 8.0, md: 12.0, lg: 16.0, xl: 24.0 }
    t.radii = Radii { sm: 4.0, md: 8.0, lg: 12.0, full: 9999.0 }
    var hairline: f32 = 1.0
    if contrast { hairline = 2.0 }
    t.borders = Borders { hairline: hairline, regular: hairline, thick: hairline + 1.0 }
    var e: [4]f32 = zero
    e[1] = 0.08
    e[2] = 0.14
    e[3] = 0.22
    t.elevation = e
    t.motion = Motion { fast_ms: 100u32, normal_ms: 200u32, slow_ms: 350u32, reduced: false }
    t.metrics = Metrics { hit_target: 32.0, control_height: 32.0, density: 1.0, focus_ring: 2.0, focus_offset: 2.0 }
    ret t
}

fn validate_theme(t: *const ThemeTokens) -> err {
    var i = 0usize
    while i < 14usize {
        if !paint.color_ok(t.colors[i]) { ret Invalid }
        i += 1usize
    }
    i = 0usize
    while i < 7usize {
        let s = t.text[i]
        if !finite(s.size) || !(s.size > 0.0) || !finite(s.line_height) || s.line_height < s.size { ret Invalid }
        if s.weight < 100u16 || s.weight > 900u16 { ret Invalid }
        i += 1usize
    }
    if !(t.spacing.xs >= 0.0) || !(t.spacing.sm >= t.spacing.xs) || !(t.spacing.md >= t.spacing.sm) || !(t.spacing.lg >= t.spacing.md) || !(t.spacing.xl >= t.spacing.lg) { ret Invalid }
    if !(t.radii.sm >= 0.0) || !(t.radii.md >= t.radii.sm) || !(t.radii.lg >= t.radii.md) || !(t.radii.full >= t.radii.lg) { ret Invalid }
    if !(t.borders.hairline > 0.0) || !(t.borders.regular >= t.borders.hairline) || !(t.borders.thick >= t.borders.regular) { ret Invalid }
    i = 0usize
    while i < 4usize {
        if !(t.elevation[i] >= 0.0) || t.elevation[i] > 1.0 { ret Invalid }
        i += 1usize
    }
    if t.motion.fast_ms > t.motion.normal_ms || t.motion.normal_ms > t.motion.slow_ms { ret Invalid }
    if !(t.metrics.hit_target > 0.0) || !(t.metrics.control_height > 0.0) || !(t.metrics.density > 0.0) || !(t.metrics.focus_ring >= 0.0) || !(t.metrics.focus_offset >= 0.0) { ret Invalid }
    ret ok
}

fn mix(a: paint.Color, b: paint.Color, share: f32) -> paint.Color {
    ret paint.Color { red: a.red + (b.red - a.red) * share, green: a.green + (b.green - a.green) * share, blue: a.blue + (b.blue - a.blue) * share, alpha: a.alpha + (b.alpha - a.alpha) * share }
}

// A control's look under its state, resolved once at build: pressed darkens toward
// the background, hover tints toward the text colour, selection tints, invalid
// borders in the error colour, focus draws the ring, disabled halves the opacity,
// read-only takes the variant surface with the muted text. The three variants are
// the fills the catalogue's buttons and fields are built from.
fn resolve(t: *const ThemeTokens, variant: ControlVariant, state: ControlState) -> ResolvedControl {
    var background = color(t, .Primary)
    var foreground = color(t, .OnPrimary)
    var border = color(t, .Primary)
    var border_width: f32 = 0.0
    if variant == .Outlined {
        background = color(t, .Surface)
        foreground = color(t, .Primary)
        border = color(t, .Border)
        border_width = t.borders.regular
    }
    if variant == .Plain {
        background = paint.rgba(0.0, 0.0, 0.0, 0.0)
        foreground = color(t, .Primary)
        border = paint.rgba(0.0, 0.0, 0.0, 0.0)
    }
    if state.read_only {
        background = color(t, .SurfaceVariant)
        foreground = color(t, .TextMuted)
    }
    if state.selected { background = mix(background, color(t, .Selection), 0.5) }
    if state.hovered && !state.pressed { background = mix(background, color(t, .Text), 0.08) }
    if state.pressed { background = mix(background, color(t, .Background), 0.2) }
    if state.invalid {
        border = color(t, .Error)
        if border_width < t.borders.regular { border_width = t.borders.regular }
    }
    var focus_ring: f32 = 0.0
    if state.focused { focus_ring = t.metrics.focus_ring }
    var opacity: f32 = 1.0
    if state.disabled { opacity = 0.5 }
    ret ResolvedControl { background: background, foreground: foreground, border: border, border_width: border_width, focus_ring: focus_ring, opacity: opacity, radius: t.radii.md }
}

// The size class of a width in logical pixels: the breakpoints most catalogues share.
fn size_class(width: f32) -> SizeClass {
    if width < 600.0 { ret .Compact }
    if width < 840.0 { ret .Medium }
    ret .Expanded
}

// The theme adapted to a host: the touch profile, or touch without a fine pointer,
// grows the hit target to 44 and the controls with it; the dense desktop profile
// shrinks them; a compact size class tightens the spacing; the profile is recorded.
fn adapt(t: *const ThemeTokens, a: Adaptation) -> ThemeTokens {
    var out = *t
    out.profile = a.profile
    let touch_first = a.profile == .Touch || (a.capabilities.touch && !a.capabilities.fine_pointer)
    if touch_first {
        out.metrics.hit_target = 44.0
        out.metrics.control_height = 44.0
        out.metrics.density = 1.25
        out.spacing = Spacing { xs: 6.0, sm: 10.0, md: 16.0, lg: 20.0, xl: 28.0 }
    }
    if a.profile == .DesktopDense {
        out.metrics.hit_target = 24.0
        out.metrics.control_height = 24.0
        out.metrics.density = 0.85
        out.spacing = Spacing { xs: 2.0, sm: 4.0, md: 8.0, lg: 12.0, xl: 16.0 }
    }
    if a.size == .Compact && !touch_first {
        out.spacing = Spacing { xs: t.spacing.xs, sm: t.spacing.sm, md: t.spacing.sm, lg: t.spacing.md, xl: t.spacing.lg }
    }
    ret out
}
