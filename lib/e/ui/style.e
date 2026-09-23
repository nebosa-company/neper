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
// A border is painted inside the bounds; a radius rounds the background, the border
// and a clip alike; a shadow is the background's shape filled in its colour at its
// offset, under everything (D814).
type Border = struct { width: f32, color: paint.Color }
type Shadow = struct { offset: geometry.Point, color: paint.Color }
type Style = struct { display: Display, position: Position, width: Length, height: Length, min_width: Length, min_height: Length, max_width: Length, max_height: Length, margin: EdgeLengths, padding: EdgeLengths, background: paint.Brush, opacity: f32, overflow: Overflow, border: Border, radius: f32, shadow: Shadow }
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
        border: Border { width: 0.0, color: paint.rgba(0.0, 0.0, 0.0, 0.0) },
        radius: 0.0,
        shadow: Shadow { offset: geometry.Point { x: 0.0, y: 0.0 }, color: paint.rgba(0.0, 0.0, 0.0, 0.0) },
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
    if !finite(value.border.width) || value.border.width < 0.0 || !finite(value.radius) || value.radius < 0.0 { ret Invalid }
    if !finite(value.shadow.offset.x) || !finite(value.shadow.offset.y) { ret Invalid }
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

//
// The values are the Neper UI v2 design language (D937, docs/ux): a tonal palette
// seeded from the logo's ink in four palettes, fifteen type styles, a shape scale,
// six elevation levels, state-layer opacities, component sizes by density and the
// motion scale. The fourteen colour roles and seven text roles of D805 remain as
// aliases of v2 roles until every control draws its v2 specification.

type TextStyle = struct { size: f32, line_height: f32, weight: u16, italic: bool }
type Spacing = struct { xs: f32, sm: f32, md: f32, lg: f32, xl: f32 }
type Radii = struct { xs: f32, sm: f32, md: f32, lg: f32, xl: f32, full: f32 }
type Borders = struct { hairline: f32, regular: f32, thick: f32 }
type Motion = struct { fast_ms: u32, normal_ms: u32, slow_ms: u32, reduced: bool }
// The motion scale in milliseconds; `stagger` is the step between items entering.
type Durations = struct { short1: u32, short2: u32, short3: u32, short4: u32, medium1: u32, medium2: u32, medium3: u32, medium4: u32, long1: u32, long2: u32, stagger: u32 }
// State-layer opacities (the content colour over its container), the disabled
// container and content opacities, and the scrim's.
type States = struct { hover: f32, focus: f32, pressed: f32, dragged: f32, disabled_container: f32, disabled_content: f32, scrim: f32 }
// Control heights by density step (xs -2 ... xl touch), the minimum targets, the
// icon sizes, the divider and a focused outline's width.
type Sizes = struct { control_xs: f32, control_sm: f32, control_md: f32, control_lg: f32, control_xl: f32, target_touch: f32, target_pointer: f32, icon_xs: f32, icon_sm: f32, icon_md: f32, icon_lg: f32, divider: f32, outline_focused: f32 }
type Metrics = struct { hit_target: f32, control_height: f32, density: f32, focus_ring: f32, focus_offset: f32 }
type Palette = enum u8 { Light, Dark, HighContrast, Custom, HighContrastDark }
type Profile = enum u8 { Neper, DesktopDense, Touch, MaterialLike, CupertinoLike }
type Direction = enum u8 { LeftToRight, RightToLeft }
// ---- GENERATED from docs/ux/tokens.json by scripts/render_ux_theme.py; do not edit ----

type ColorRole = enum u8 { Background, Surface, SurfaceVariant, Primary, OnPrimary, Secondary, OnSecondary, Text, TextMuted, Border, Focus, Error, OnError, Selection, PrimaryContainer, OnPrimaryContainer, SecondaryContainer, OnSecondaryContainer, Tertiary, OnTertiary, TertiaryContainer, OnTertiaryContainer, ErrorContainer, OnErrorContainer, Success, OnSuccess, SuccessContainer, OnSuccessContainer, Warning, OnWarning, WarningContainer, OnWarningContainer, SurfaceDim, SurfaceBright, SurfaceContainerLowest, SurfaceContainerLow, SurfaceContainer, SurfaceContainerHigh, SurfaceContainerHighest, OnSurface, OnSurfaceVariant, Outline, OutlineVariant, InverseSurface, InverseOnSurface, InversePrimary, FocusRing, Scrim, Shadow, TextSelection, LinkVisited, Data1, Data2, Data3, Data4, Data5, Data6 }
type TextRole = enum u8 { Body, BodySmall, Title, Heading, Label, Caption, Code, DisplayLarge, DisplayMedium, DisplaySmall, HeadlineLarge, HeadlineMedium, HeadlineSmall, TitleLarge, TitleMedium, TitleSmall, BodyLarge, BodyMedium, LabelLarge, LabelMedium, LabelSmall }
type ThemeTokens = struct { palette: Palette, profile: Profile, direction: Direction, colors: [57]paint.Color, text: [21]TextStyle, spacing: Spacing, radii: Radii, borders: Borders, elevation: [6]f32, states: States, sizes: Sizes, motion: Motion, durations: Durations, metrics: Metrics }

// A role's slot in `ThemeTokens.colors`.
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
    if role == .PrimaryContainer { ret 14usize }
    if role == .OnPrimaryContainer { ret 15usize }
    if role == .SecondaryContainer { ret 16usize }
    if role == .OnSecondaryContainer { ret 17usize }
    if role == .Tertiary { ret 18usize }
    if role == .OnTertiary { ret 19usize }
    if role == .TertiaryContainer { ret 20usize }
    if role == .OnTertiaryContainer { ret 21usize }
    if role == .ErrorContainer { ret 22usize }
    if role == .OnErrorContainer { ret 23usize }
    if role == .Success { ret 24usize }
    if role == .OnSuccess { ret 25usize }
    if role == .SuccessContainer { ret 26usize }
    if role == .OnSuccessContainer { ret 27usize }
    if role == .Warning { ret 28usize }
    if role == .OnWarning { ret 29usize }
    if role == .WarningContainer { ret 30usize }
    if role == .OnWarningContainer { ret 31usize }
    if role == .SurfaceDim { ret 32usize }
    if role == .SurfaceBright { ret 33usize }
    if role == .SurfaceContainerLowest { ret 34usize }
    if role == .SurfaceContainerLow { ret 35usize }
    if role == .SurfaceContainer { ret 36usize }
    if role == .SurfaceContainerHigh { ret 37usize }
    if role == .SurfaceContainerHighest { ret 38usize }
    if role == .OnSurface { ret 39usize }
    if role == .OnSurfaceVariant { ret 40usize }
    if role == .Outline { ret 41usize }
    if role == .OutlineVariant { ret 42usize }
    if role == .InverseSurface { ret 43usize }
    if role == .InverseOnSurface { ret 44usize }
    if role == .InversePrimary { ret 45usize }
    if role == .FocusRing { ret 46usize }
    if role == .Scrim { ret 47usize }
    if role == .Shadow { ret 48usize }
    if role == .TextSelection { ret 49usize }
    if role == .LinkVisited { ret 50usize }
    if role == .Data1 { ret 51usize }
    if role == .Data2 { ret 52usize }
    if role == .Data3 { ret 53usize }
    if role == .Data4 { ret 54usize }
    if role == .Data5 { ret 55usize }
    if role == .Data6 { ret 56usize }
    ret 0usize
}

// A text role's slot in `ThemeTokens.text`.
fn text_index(role: TextRole) -> usize {
    if role == .BodySmall { ret 1usize }
    if role == .Title { ret 2usize }
    if role == .Heading { ret 3usize }
    if role == .Label { ret 4usize }
    if role == .Caption { ret 5usize }
    if role == .Code { ret 6usize }
    if role == .DisplayLarge { ret 7usize }
    if role == .DisplayMedium { ret 8usize }
    if role == .DisplaySmall { ret 9usize }
    if role == .HeadlineLarge { ret 10usize }
    if role == .HeadlineMedium { ret 11usize }
    if role == .HeadlineSmall { ret 12usize }
    if role == .TitleLarge { ret 13usize }
    if role == .TitleMedium { ret 14usize }
    if role == .TitleSmall { ret 15usize }
    if role == .BodyLarge { ret 16usize }
    if role == .BodyMedium { ret 17usize }
    if role == .LabelLarge { ret 18usize }
    if role == .LabelMedium { ret 19usize }
    if role == .LabelSmall { ret 20usize }
    ret 0usize
}

// Every role's colour in one of the four palettes (Custom starts from Light).
fn fill_palette(t: *ThemeTokens, palette: Palette) {
    if palette == .Dark {
        fill_dark(t)
        ret
    }
    if palette == .HighContrast {
        fill_highcontrast(t)
        ret
    }
    if palette == .HighContrastDark {
        fill_highcontrastdark(t)
        ret
    }
    fill_light(t)
}

fn fill_light(t: *ThemeTokens) {
    t.colors[0] = paint.rgba(0.9725, 0.9765, 1.0, 1.0)
    t.colors[1] = paint.rgba(1.0, 1.0, 1.0, 1.0)
    t.colors[2] = paint.rgba(0.8824, 0.8863, 0.9137, 1.0)
    t.colors[3] = paint.rgba(0.0784, 0.3647, 0.698, 1.0)
    t.colors[4] = paint.rgba(1.0, 1.0, 1.0, 1.0)
    t.colors[5] = paint.rgba(0.3176, 0.3725, 0.4706, 1.0)
    t.colors[6] = paint.rgba(1.0, 1.0, 1.0, 1.0)
    t.colors[7] = paint.rgba(0.102, 0.1059, 0.1255, 1.0)
    t.colors[8] = paint.rgba(0.2627, 0.2745, 0.3255, 1.0)
    t.colors[9] = paint.rgba(0.451, 0.4667, 0.5176, 1.0)
    t.colors[10] = paint.rgba(0.0784, 0.3647, 0.698, 1.0)
    t.colors[11] = paint.rgba(0.7059, 0.1412, 0.1922, 1.0)
    t.colors[12] = paint.rgba(1.0, 1.0, 1.0, 1.0)
    t.colors[13] = paint.rgba(0.8392, 0.8902, 1.0, 1.0)
    t.colors[14] = paint.rgba(0.8549, 0.8863, 1.0, 1.0)
    t.colors[15] = paint.rgba(0.0, 0.1059, 0.2392, 1.0)
    t.colors[16] = paint.rgba(0.8392, 0.8902, 1.0, 1.0)
    t.colors[17] = paint.rgba(0.0431, 0.1098, 0.1922, 1.0)
    t.colors[18] = paint.rgba(0.5804, 0.2902, 0.1373, 1.0)
    t.colors[19] = paint.rgba(1.0, 1.0, 1.0, 1.0)
    t.colors[20] = paint.rgba(1.0, 0.8588, 0.7961, 1.0)
    t.colors[21] = paint.rgba(0.1882, 0.0784, 0.0, 1.0)
    t.colors[22] = paint.rgba(1.0, 0.8549, 0.8392, 1.0)
    t.colors[23] = paint.rgba(0.2549, 0.0, 0.0, 1.0)
    t.colors[24] = paint.rgba(0.1412, 0.4196, 0.2275, 1.0)
    t.colors[25] = paint.rgba(1.0, 1.0, 1.0, 1.0)
    t.colors[26] = paint.rgba(0.6706, 0.9529, 0.7255, 1.0)
    t.colors[27] = paint.rgba(0.0, 0.1294, 0.0275, 1.0)
    t.colors[28] = paint.rgba(0.498, 0.3412, 0.0, 1.0)
    t.colors[29] = paint.rgba(1.0, 1.0, 1.0, 1.0)
    t.colors[30] = paint.rgba(1.0, 0.8667, 0.698, 1.0)
    t.colors[31] = paint.rgba(0.149, 0.098, 0.0, 1.0)
    t.colors[32] = paint.rgba(0.8471, 0.8549, 0.8784, 1.0)
    t.colors[33] = paint.rgba(0.9725, 0.9765, 1.0, 1.0)
    t.colors[34] = paint.rgba(1.0, 1.0, 1.0, 1.0)
    t.colors[35] = paint.rgba(0.949, 0.9529, 0.9804, 1.0)
    t.colors[36] = paint.rgba(0.9255, 0.9333, 0.9569, 1.0)
    t.colors[37] = paint.rgba(0.902, 0.9098, 0.9373, 1.0)
    t.colors[38] = paint.rgba(0.8824, 0.8863, 0.9137, 1.0)
    t.colors[39] = paint.rgba(0.102, 0.1059, 0.1255, 1.0)
    t.colors[40] = paint.rgba(0.2627, 0.2745, 0.3255, 1.0)
    t.colors[41] = paint.rgba(0.451, 0.4667, 0.5176, 1.0)
    t.colors[42] = paint.rgba(0.7647, 0.7765, 0.8353, 1.0)
    t.colors[43] = paint.rgba(0.1843, 0.1882, 0.2078, 1.0)
    t.colors[44] = paint.rgba(0.9373, 0.9412, 0.9686, 1.0)
    t.colors[45] = paint.rgba(0.702, 0.7725, 1.0, 1.0)
    t.colors[46] = paint.rgba(0.0784, 0.3647, 0.698, 1.0)
    t.colors[47] = paint.rgba(0.0, 0.0, 0.0, 1.0)
    t.colors[48] = paint.rgba(0.0, 0.0, 0.0, 1.0)
    t.colors[49] = paint.rgba(0.8549, 0.8863, 1.0, 1.0)
    t.colors[50] = paint.rgba(0.5804, 0.2902, 0.1373, 1.0)
    t.colors[51] = paint.rgba(0.0, 0.4902, 0.7373, 1.0)
    t.colors[52] = paint.rgba(0.702, 0.3804, 0.2157, 1.0)
    t.colors[53] = paint.rgba(0.0, 0.5333, 0.3569, 1.0)
    t.colors[54] = paint.rgba(0.5098, 0.4118, 0.7294, 1.0)
    t.colors[55] = paint.rgba(0.5765, 0.451, 0.1216, 1.0)
    t.colors[56] = paint.rgba(0.0, 0.5176, 0.5608, 1.0)
}

fn fill_dark(t: *ThemeTokens) {
    t.colors[0] = paint.rgba(0.0706, 0.0745, 0.0941, 1.0)
    t.colors[1] = paint.rgba(0.0471, 0.0549, 0.0784, 1.0)
    t.colors[2] = paint.rgba(0.2, 0.2078, 0.2275, 1.0)
    t.colors[3] = paint.rgba(0.702, 0.7725, 1.0, 1.0)
    t.colors[4] = paint.rgba(0.0, 0.1882, 0.3843, 1.0)
    t.colors[5] = paint.rgba(0.7255, 0.7804, 0.8941, 1.0)
    t.colors[6] = paint.rgba(0.1333, 0.1922, 0.2784, 1.0)
    t.colors[7] = paint.rgba(0.8824, 0.8863, 0.9137, 1.0)
    t.colors[8] = paint.rgba(0.7647, 0.7765, 0.8353, 1.0)
    t.colors[9] = paint.rgba(0.5529, 0.5647, 0.6196, 1.0)
    t.colors[10] = paint.rgba(0.702, 0.7725, 1.0, 1.0)
    t.colors[11] = paint.rgba(1.0, 0.702, 0.6784, 1.0)
    t.colors[12] = paint.rgba(0.4078, 0.0, 0.0706, 1.0)
    t.colors[13] = paint.rgba(0.2235, 0.2784, 0.3725, 1.0)
    t.colors[14] = paint.rgba(0.0, 0.2745, 0.5451, 1.0)
    t.colors[15] = paint.rgba(0.8549, 0.8863, 1.0, 1.0)
    t.colors[16] = paint.rgba(0.2235, 0.2784, 0.3725, 1.0)
    t.colors[17] = paint.rgba(0.8392, 0.8902, 1.0, 1.0)
    t.colors[18] = paint.rgba(1.0, 0.7137, 0.5725, 1.0)
    t.colors[19] = paint.rgba(0.3373, 0.1255, 0.0, 1.0)
    t.colors[20] = paint.rgba(0.4667, 0.1961, 0.0471, 1.0)
    t.colors[21] = paint.rgba(1.0, 0.8588, 0.7961, 1.0)
    t.colors[22] = paint.rgba(0.5725, 0.0, 0.1176, 1.0)
    t.colors[23] = paint.rgba(1.0, 0.8549, 0.8392, 1.0)
    t.colors[24] = paint.rgba(0.5608, 0.8431, 0.6196, 1.0)
    t.colors[25] = paint.rgba(0.0, 0.2235, 0.0863, 1.0)
    t.colors[26] = paint.rgba(0.0039, 0.3216, 0.1412, 1.0)
    t.colors[27] = paint.rgba(0.6706, 0.9529, 0.7255, 1.0)
    t.colors[28] = paint.rgba(0.9686, 0.7373, 0.3686, 1.0)
    t.colors[29] = paint.rgba(0.2627, 0.1725, 0.0, 1.0)
    t.colors[30] = paint.rgba(0.3765, 0.2549, 0.0, 1.0)
    t.colors[31] = paint.rgba(1.0, 0.8667, 0.698, 1.0)
    t.colors[32] = paint.rgba(0.0706, 0.0745, 0.0941, 1.0)
    t.colors[33] = paint.rgba(0.2196, 0.2235, 0.2431, 1.0)
    t.colors[34] = paint.rgba(0.0471, 0.0549, 0.0784, 1.0)
    t.colors[35] = paint.rgba(0.102, 0.1059, 0.1255, 1.0)
    t.colors[36] = paint.rgba(0.1176, 0.1216, 0.1412, 1.0)
    t.colors[37] = paint.rgba(0.1608, 0.1647, 0.1843, 1.0)
    t.colors[38] = paint.rgba(0.2, 0.2078, 0.2275, 1.0)
    t.colors[39] = paint.rgba(0.8824, 0.8863, 0.9137, 1.0)
    t.colors[40] = paint.rgba(0.7647, 0.7765, 0.8353, 1.0)
    t.colors[41] = paint.rgba(0.5529, 0.5647, 0.6196, 1.0)
    t.colors[42] = paint.rgba(0.2627, 0.2745, 0.3255, 1.0)
    t.colors[43] = paint.rgba(0.8824, 0.8863, 0.9137, 1.0)
    t.colors[44] = paint.rgba(0.1843, 0.1882, 0.2078, 1.0)
    t.colors[45] = paint.rgba(0.0784, 0.3647, 0.698, 1.0)
    t.colors[46] = paint.rgba(0.702, 0.7725, 1.0, 1.0)
    t.colors[47] = paint.rgba(0.0, 0.0, 0.0, 1.0)
    t.colors[48] = paint.rgba(0.0, 0.0, 0.0, 1.0)
    t.colors[49] = paint.rgba(0.0, 0.2745, 0.5451, 1.0)
    t.colors[50] = paint.rgba(1.0, 0.7137, 0.5725, 1.0)
    t.colors[51] = paint.rgba(0.3608, 0.7216, 1.0, 1.0)
    t.colors[52] = paint.rgba(0.9608, 0.6039, 0.4275, 1.0)
    t.colors[53] = paint.rgba(0.3137, 0.7725, 0.5686, 1.0)
    t.colors[54] = paint.rgba(0.7451, 0.6353, 0.9725, 1.0)
    t.colors[55] = paint.rgba(0.8235, 0.6706, 0.3412, 1.0)
    t.colors[56] = paint.rgba(0.0, 0.7647, 0.8275, 1.0)
}

fn fill_highcontrast(t: *ThemeTokens) {
    t.colors[0] = paint.rgba(1.0, 1.0, 1.0, 1.0)
    t.colors[1] = paint.rgba(1.0, 1.0, 1.0, 1.0)
    t.colors[2] = paint.rgba(0.8824, 0.8863, 0.9137, 1.0)
    t.colors[3] = paint.rgba(0.0, 0.2314, 0.4627, 1.0)
    t.colors[4] = paint.rgba(1.0, 1.0, 1.0, 1.0)
    t.colors[5] = paint.rgba(0.1804, 0.2353, 0.3255, 1.0)
    t.colors[6] = paint.rgba(1.0, 1.0, 1.0, 1.0)
    t.colors[7] = paint.rgba(0.0, 0.0, 0.0, 1.0)
    t.colors[8] = paint.rgba(0.1333, 0.1451, 0.1922, 1.0)
    t.colors[9] = paint.rgba(0.2196, 0.2314, 0.2784, 1.0)
    t.colors[10] = paint.rgba(0.0, 0.1882, 0.3843, 1.0)
    t.colors[11] = paint.rgba(0.4902, 0.0, 0.0941, 1.0)
    t.colors[12] = paint.rgba(1.0, 1.0, 1.0, 1.0)
    t.colors[13] = paint.rgba(0.8392, 0.8902, 1.0, 1.0)
    t.colors[14] = paint.rgba(0.8549, 0.8863, 1.0, 1.0)
    t.colors[15] = paint.rgba(0.0, 0.0, 0.0, 1.0)
    t.colors[16] = paint.rgba(0.8392, 0.8902, 1.0, 1.0)
    t.colors[17] = paint.rgba(0.0, 0.0, 0.0, 1.0)
    t.colors[18] = paint.rgba(0.4118, 0.149, 0.0, 1.0)
    t.colors[19] = paint.rgba(1.0, 1.0, 1.0, 1.0)
    t.colors[20] = paint.rgba(1.0, 0.8588, 0.7961, 1.0)
    t.colors[21] = paint.rgba(0.0, 0.0, 0.0, 1.0)
    t.colors[22] = paint.rgba(1.0, 0.8549, 0.8392, 1.0)
    t.colors[23] = paint.rgba(0.0, 0.0, 0.0, 1.0)
    t.colors[24] = paint.rgba(0.0, 0.2745, 0.1137, 1.0)
    t.colors[25] = paint.rgba(1.0, 1.0, 1.0, 1.0)
    t.colors[26] = paint.rgba(0.6706, 0.9529, 0.7255, 1.0)
    t.colors[27] = paint.rgba(0.0, 0.0, 0.0, 1.0)
    t.colors[28] = paint.rgba(0.3176, 0.2118, 0.0, 1.0)
    t.colors[29] = paint.rgba(1.0, 1.0, 1.0, 1.0)
    t.colors[30] = paint.rgba(1.0, 0.8667, 0.698, 1.0)
    t.colors[31] = paint.rgba(0.0, 0.0, 0.0, 1.0)
    t.colors[32] = paint.rgba(0.8824, 0.8863, 0.9137, 1.0)
    t.colors[33] = paint.rgba(1.0, 1.0, 1.0, 1.0)
    t.colors[34] = paint.rgba(1.0, 1.0, 1.0, 1.0)
    t.colors[35] = paint.rgba(0.9725, 0.9765, 1.0, 1.0)
    t.colors[36] = paint.rgba(0.9373, 0.9412, 0.9686, 1.0)
    t.colors[37] = paint.rgba(0.902, 0.9098, 0.9373, 1.0)
    t.colors[38] = paint.rgba(0.8824, 0.8863, 0.9137, 1.0)
    t.colors[39] = paint.rgba(0.0, 0.0, 0.0, 1.0)
    t.colors[40] = paint.rgba(0.1333, 0.1451, 0.1922, 1.0)
    t.colors[41] = paint.rgba(0.2196, 0.2314, 0.2784, 1.0)
    t.colors[42] = paint.rgba(0.4039, 0.4157, 0.4667, 1.0)
    t.colors[43] = paint.rgba(0.102, 0.1059, 0.1255, 1.0)
    t.colors[44] = paint.rgba(1.0, 1.0, 1.0, 1.0)
    t.colors[45] = paint.rgba(0.7804, 0.8275, 1.0, 1.0)
    t.colors[46] = paint.rgba(0.0, 0.1882, 0.3843, 1.0)
    t.colors[47] = paint.rgba(0.0, 0.0, 0.0, 1.0)
    t.colors[48] = paint.rgba(0.0, 0.0, 0.0, 1.0)
    t.colors[49] = paint.rgba(0.8549, 0.8863, 1.0, 1.0)
    t.colors[50] = paint.rgba(0.4118, 0.149, 0.0, 1.0)
    t.colors[51] = paint.rgba(0.0, 0.3412, 0.5176, 1.0)
    t.colors[52] = paint.rgba(0.5647, 0.2078, 0.0, 1.0)
    t.colors[53] = paint.rgba(0.0, 0.3725, 0.2431, 1.0)
    t.colors[54] = paint.rgba(0.349, 0.2549, 0.6353, 1.0)
    t.colors[55] = paint.rgba(0.4078, 0.3098, 0.0, 1.0)
    t.colors[56] = paint.rgba(0.0, 0.3608, 0.3922, 1.0)
}

fn fill_highcontrastdark(t: *ThemeTokens) {
    t.colors[0] = paint.rgba(0.0, 0.0, 0.0, 1.0)
    t.colors[1] = paint.rgba(0.0, 0.0, 0.0, 1.0)
    t.colors[2] = paint.rgba(0.149, 0.1569, 0.1765, 1.0)
    t.colors[3] = paint.rgba(0.8549, 0.8863, 1.0, 1.0)
    t.colors[4] = paint.rgba(0.0, 0.0, 0.0, 1.0)
    t.colors[5] = paint.rgba(0.8392, 0.8902, 1.0, 1.0)
    t.colors[6] = paint.rgba(0.0, 0.0, 0.0, 1.0)
    t.colors[7] = paint.rgba(1.0, 1.0, 1.0, 1.0)
    t.colors[8] = paint.rgba(0.8941, 0.9098, 0.9686, 1.0)
    t.colors[9] = paint.rgba(0.7647, 0.7765, 0.8353, 1.0)
    t.colors[10] = paint.rgba(0.8549, 0.8863, 1.0, 1.0)
    t.colors[11] = paint.rgba(1.0, 0.8549, 0.8392, 1.0)
    t.colors[12] = paint.rgba(0.0, 0.0, 0.0, 1.0)
    t.colors[13] = paint.rgba(0.1333, 0.1922, 0.2784, 1.0)
    t.colors[14] = paint.rgba(0.0, 0.1882, 0.3843, 1.0)
    t.colors[15] = paint.rgba(1.0, 1.0, 1.0, 1.0)
    t.colors[16] = paint.rgba(0.1333, 0.1922, 0.2784, 1.0)
    t.colors[17] = paint.rgba(1.0, 1.0, 1.0, 1.0)
    t.colors[18] = paint.rgba(1.0, 0.8588, 0.7961, 1.0)
    t.colors[19] = paint.rgba(0.0, 0.0, 0.0, 1.0)
    t.colors[20] = paint.rgba(0.3373, 0.1255, 0.0, 1.0)
    t.colors[21] = paint.rgba(1.0, 1.0, 1.0, 1.0)
    t.colors[22] = paint.rgba(0.4078, 0.0, 0.0706, 1.0)
    t.colors[23] = paint.rgba(1.0, 1.0, 1.0, 1.0)
    t.colors[24] = paint.rgba(0.6706, 0.9529, 0.7255, 1.0)
    t.colors[25] = paint.rgba(0.0, 0.0, 0.0, 1.0)
    t.colors[26] = paint.rgba(0.0, 0.2235, 0.0863, 1.0)
    t.colors[27] = paint.rgba(1.0, 1.0, 1.0, 1.0)
    t.colors[28] = paint.rgba(1.0, 0.8667, 0.698, 1.0)
    t.colors[29] = paint.rgba(0.0, 0.0, 0.0, 1.0)
    t.colors[30] = paint.rgba(0.2627, 0.1725, 0.0, 1.0)
    t.colors[31] = paint.rgba(1.0, 1.0, 1.0, 1.0)
    t.colors[32] = paint.rgba(0.0, 0.0, 0.0, 1.0)
    t.colors[33] = paint.rgba(0.1176, 0.1216, 0.1412, 1.0)
    t.colors[34] = paint.rgba(0.0, 0.0, 0.0, 1.0)
    t.colors[35] = paint.rgba(0.0706, 0.0745, 0.0941, 1.0)
    t.colors[36] = paint.rgba(0.0863, 0.0902, 0.1098, 1.0)
    t.colors[37] = paint.rgba(0.1176, 0.1216, 0.1412, 1.0)
    t.colors[38] = paint.rgba(0.149, 0.1569, 0.1765, 1.0)
    t.colors[39] = paint.rgba(1.0, 1.0, 1.0, 1.0)
    t.colors[40] = paint.rgba(0.8941, 0.9098, 0.9686, 1.0)
    t.colors[41] = paint.rgba(0.7647, 0.7765, 0.8353, 1.0)
    t.colors[42] = paint.rgba(0.5529, 0.5647, 0.6196, 1.0)
    t.colors[43] = paint.rgba(0.9373, 0.9412, 0.9686, 1.0)
    t.colors[44] = paint.rgba(0.0588, 0.0667, 0.0863, 1.0)
    t.colors[45] = paint.rgba(0.0, 0.2745, 0.5451, 1.0)
    t.colors[46] = paint.rgba(0.8549, 0.8863, 1.0, 1.0)
    t.colors[47] = paint.rgba(0.0, 0.0, 0.0, 1.0)
    t.colors[48] = paint.rgba(0.0, 0.0, 0.0, 1.0)
    t.colors[49] = paint.rgba(0.0, 0.1882, 0.3843, 1.0)
    t.colors[50] = paint.rgba(1.0, 0.8588, 0.7961, 1.0)
    t.colors[51] = paint.rgba(0.6392, 0.8157, 1.0, 1.0)
    t.colors[52] = paint.rgba(1.0, 0.7412, 0.6196, 1.0)
    t.colors[53] = paint.rgba(0.4314, 0.8824, 0.6745, 1.0)
    t.colors[54] = paint.rgba(0.8431, 0.7608, 1.0, 1.0)
    t.colors[55] = paint.rgba(0.9373, 0.7804, 0.4431, 1.0)
    t.colors[56] = paint.rgba(0.0, 0.8824, 0.9569, 1.0)
}

// The fifteen type styles, the seven roles of D805 mapped onto them.
fn fill_type_scale(t: *ThemeTokens) {
    t.text[0] = TextStyle { size: 14.0, line_height: 20.0, weight: 400u16, italic: false }
    t.text[1] = TextStyle { size: 12.0, line_height: 16.0, weight: 400u16, italic: false }
    t.text[2] = TextStyle { size: 22.0, line_height: 28.0, weight: 400u16, italic: false }
    t.text[3] = TextStyle { size: 24.0, line_height: 32.0, weight: 400u16, italic: false }
    t.text[4] = TextStyle { size: 14.0, line_height: 20.0, weight: 600u16, italic: false }
    t.text[5] = TextStyle { size: 11.0, line_height: 16.0, weight: 600u16, italic: false }
    t.text[6] = TextStyle { size: 13.0, line_height: 20.0, weight: 400u16, italic: false }
    t.text[7] = TextStyle { size: 57.0, line_height: 64.0, weight: 400u16, italic: false }
    t.text[8] = TextStyle { size: 45.0, line_height: 52.0, weight: 400u16, italic: false }
    t.text[9] = TextStyle { size: 36.0, line_height: 44.0, weight: 400u16, italic: false }
    t.text[10] = TextStyle { size: 32.0, line_height: 40.0, weight: 400u16, italic: false }
    t.text[11] = TextStyle { size: 28.0, line_height: 36.0, weight: 400u16, italic: false }
    t.text[12] = TextStyle { size: 24.0, line_height: 32.0, weight: 400u16, italic: false }
    t.text[13] = TextStyle { size: 22.0, line_height: 28.0, weight: 400u16, italic: false }
    t.text[14] = TextStyle { size: 16.0, line_height: 24.0, weight: 600u16, italic: false }
    t.text[15] = TextStyle { size: 14.0, line_height: 20.0, weight: 600u16, italic: false }
    t.text[16] = TextStyle { size: 16.0, line_height: 24.0, weight: 400u16, italic: false }
    t.text[17] = TextStyle { size: 14.0, line_height: 20.0, weight: 400u16, italic: false }
    t.text[18] = TextStyle { size: 14.0, line_height: 20.0, weight: 600u16, italic: false }
    t.text[19] = TextStyle { size: 12.0, line_height: 16.0, weight: 600u16, italic: false }
    t.text[20] = TextStyle { size: 11.0, line_height: 16.0, weight: 600u16, italic: false }
}

// ---- END GENERATED ----
type ControlState = struct { hovered: bool, pressed: bool, focused: bool, focus_visible: bool, selected: bool, disabled: bool, read_only: bool, invalid: bool }
// Plain is the v2 text button; Tonal, Elevated and Danger are the v2 additions (D942).
type ControlVariant = enum u8 { Filled, Outlined, Plain, Tonal, Elevated, Danger }
// `elevation` is the shadow level the control casts; `padding` and `padding_start`
// are its horizontal padding when the control sets them (zero: the pressable's own).
type ResolvedControl = struct { background: paint.Color, foreground: paint.Color, border: paint.Color, border_width: f32, focus_ring: f32, opacity: f32, radius: f32, elevation: u8, padding: f32, padding_start: f32 }
type SizeClass = enum u8 { Compact, Medium, Expanded }
type Capabilities = struct { hover: bool, fine_pointer: bool, keyboard: bool, touch: bool, pen: bool, resizable: bool, multi_window: bool, insets: geometry.Insets }
type Adaptation = struct { size: SizeClass, capabilities: Capabilities, profile: Profile }

fn color(t: *const ThemeTokens, role: ColorRole) -> paint.Color {
    ret t.colors[color_index(role)]
}

fn text_style(t: *const ThemeTokens, role: TextRole) -> TextStyle {
    ret t.text[text_index(role)]
}

// The reference theme: the Neper profile in one of the four built-in palettes.
// `Custom` starts from Light for a caller to overwrite.
fn reference(palette: Palette) -> ThemeTokens {
    var t: ThemeTokens = zero
    t.palette = palette
    t.profile = .Neper
    t.direction = .LeftToRight
    let contrast = palette == .HighContrast || palette == .HighContrastDark
    fill_palette(&t, palette)
    fill_type_scale(&t)
    t.spacing = Spacing { xs: 4.0, sm: 8.0, md: 12.0, lg: 16.0, xl: 24.0 }
    t.radii = Radii { xs: 4.0, sm: 8.0, md: 12.0, lg: 16.0, xl: 28.0, full: 9999.0 }
    var hairline: f32 = 1.0
    if contrast { hairline = 2.0 }
    t.borders = Borders { hairline: hairline, regular: hairline, thick: hairline + 1.0 }
    // A level's key-shadow strength; level 0 is flat.
    var e: [6]f32 = zero
    e[1] = 0.12
    e[2] = 0.12
    e[3] = 0.14
    e[4] = 0.14
    e[5] = 0.14
    t.elevation = e
    t.states = States { hover: 0.08, focus: 0.1, pressed: 0.1, dragged: 0.16, disabled_container: 0.12, disabled_content: 0.38, scrim: 0.32 }
    t.sizes = Sizes { control_xs: 24.0, control_sm: 32.0, control_md: 40.0, control_lg: 48.0, control_xl: 56.0, target_touch: 48.0, target_pointer: 32.0, icon_xs: 16.0, icon_sm: 18.0, icon_md: 24.0, icon_lg: 36.0, divider: 1.0, outline_focused: 2.0 }
    t.motion = Motion { fast_ms: 100u32, normal_ms: 200u32, slow_ms: 350u32, reduced: false }
    t.durations = Durations { short1: 50u32, short2: 100u32, short3: 150u32, short4: 200u32, medium1: 250u32, medium2: 300u32, medium3: 350u32, medium4: 400u32, long1: 450u32, long2: 500u32, stagger: 30u32 }
    // The Neper profile is a pointer host's: density -1, 32 tall, 32 targets.
    t.metrics = Metrics { hit_target: 32.0, control_height: 32.0, density: 1.0, focus_ring: 3.0, focus_offset: 2.0 }
    ret t
}

fn in_unit(v: f32) -> bool {
    ret finite(v) && v >= 0.0 && v <= 1.0
}

fn validate_theme(t: *const ThemeTokens) -> err {
    var i = 0usize
    while i < t.colors.len {
        if !paint.color_ok(t.colors[i]) { ret Invalid }
        i += 1usize
    }
    i = 0usize
    while i < t.text.len {
        let s = t.text[i]
        if !finite(s.size) || !(s.size > 0.0) || !finite(s.line_height) || s.line_height < s.size { ret Invalid }
        if s.weight < 100u16 || s.weight > 900u16 { ret Invalid }
        i += 1usize
    }
    if !(t.spacing.xs >= 0.0) || !(t.spacing.sm >= t.spacing.xs) || !(t.spacing.md >= t.spacing.sm) || !(t.spacing.lg >= t.spacing.md) || !(t.spacing.xl >= t.spacing.lg) { ret Invalid }
    if !(t.radii.xs >= 0.0) || !(t.radii.sm >= t.radii.xs) || !(t.radii.md >= t.radii.sm) || !(t.radii.lg >= t.radii.md) || !(t.radii.xl >= t.radii.lg) || !(t.radii.full >= t.radii.xl) { ret Invalid }
    if !(t.borders.hairline > 0.0) || !(t.borders.regular >= t.borders.hairline) || !(t.borders.thick >= t.borders.regular) { ret Invalid }
    i = 0usize
    while i < t.elevation.len {
        if !(t.elevation[i] >= 0.0) || t.elevation[i] > 1.0 { ret Invalid }
        i += 1usize
    }
    if t.motion.fast_ms > t.motion.normal_ms || t.motion.normal_ms > t.motion.slow_ms { ret Invalid }
    let d = t.durations
    if d.short1 > d.short2 || d.short2 > d.short3 || d.short3 > d.short4 || d.short4 > d.medium1 || d.medium1 > d.medium2 || d.medium2 > d.medium3 || d.medium3 > d.medium4 || d.medium4 > d.long1 || d.long1 > d.long2 { ret Invalid }
    let o = t.states
    if !in_unit(o.hover) || !in_unit(o.focus) || !in_unit(o.pressed) || !in_unit(o.dragged) || !in_unit(o.disabled_container) || !in_unit(o.disabled_content) || !in_unit(o.scrim) { ret Invalid }
    let z = t.sizes
    if !(z.control_xs > 0.0) || z.control_sm < z.control_xs || z.control_md < z.control_sm || z.control_lg < z.control_md || z.control_xl < z.control_lg || !(z.target_pointer > 0.0) || z.target_touch < z.target_pointer || !(z.icon_xs > 0.0) || z.icon_sm < z.icon_xs || z.icon_md < z.icon_sm || z.icon_lg < z.icon_md || !(z.divider > 0.0) || z.outline_focused < z.divider { ret Invalid }
    if !(t.metrics.hit_target > 0.0) || !(t.metrics.control_height > 0.0) || !(t.metrics.density > 0.0) || !(t.metrics.focus_ring >= 0.0) || !(t.metrics.focus_offset >= 0.0) { ret Invalid }
    ret ok
}

// A state layer (D940): `content` over `container` at `opacity`; over a transparent
// container the layer is the content colour itself at that opacity.
fn layer(container: paint.Color, content: paint.Color, opacity: f32) -> paint.Color {
    if !(container.alpha > 0.0) { ret paint.Color { red: content.red, green: content.green, blue: content.blue, alpha: opacity } }
    ret paint.Color { red: container.red + (content.red - container.red) * opacity, green: container.green + (content.green - container.green) * opacity, blue: container.blue + (content.blue - container.blue) * opacity, alpha: container.alpha }
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
    var elevation = 0u8
    if variant == .Outlined {
        // v2: an outlined control is its outline alone over what it sits on.
        background = paint.rgba(0.0, 0.0, 0.0, 0.0)
        foreground = color(t, .Primary)
        border = color(t, .Border)
        border_width = t.borders.regular
    }
    if variant == .Tonal {
        background = color(t, .SecondaryContainer)
        foreground = color(t, .OnSecondaryContainer)
        border = background
    }
    if variant == .Elevated {
        background = color(t, .SurfaceContainerLow)
        foreground = color(t, .Primary)
        border = background
        elevation = 1u8
    }
    if variant == .Danger {
        background = color(t, .Error)
        foreground = color(t, .OnError)
        border = background
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
    // The state layers: the content colour over the container at the theme's
    // opacities -- hovered, focused, pressed, the strongest one standing.
    if state.hovered && !state.pressed { background = layer(background, foreground, t.states.hover) }
    if state.focus_visible && !state.hovered && !state.pressed { background = layer(background, foreground, t.states.focus) }
    if state.pressed { background = layer(background, foreground, t.states.pressed) }
    if state.invalid {
        border = color(t, .Error)
        if border_width < t.borders.regular { border_width = t.borders.regular }
    }
    var focus_ring: f32 = 0.0
    if state.focused { focus_ring = t.metrics.focus_ring }
    var opacity: f32 = 1.0
    if state.disabled { opacity = 0.5 }
    if state.hovered && elevation != 0u8 { elevation = elevation + 1u8 }
    ret ResolvedControl { background: background, foreground: foreground, border: border, border_width: border_width, focus_ring: focus_ring, opacity: opacity, radius: t.radii.sm, elevation: elevation, padding: 0.0, padding_start: 0.0 }
}

// The v2 disabled look (D942): the container in the surface's content colour at
// the disabled-container opacity (none when it had no fill), the content at the
// disabled-content opacity, no shadow, full opacity.
fn disabled_look(t: *const ThemeTokens, look: ResolvedControl) -> ResolvedControl {
    var out = look
    let ink = color(t, .OnSurface)
    if look.background.alpha > 0.0 { out.background = paint.Color { red: ink.red, green: ink.green, blue: ink.blue, alpha: t.states.disabled_container } }
    if look.border_width > 0.0 { out.border = paint.Color { red: ink.red, green: ink.green, blue: ink.blue, alpha: t.states.disabled_container } }
    out.foreground = paint.Color { red: ink.red, green: ink.green, blue: ink.blue, alpha: t.states.disabled_content }
    out.elevation = 0u8
    out.opacity = 1.0
    ret out
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
        out.metrics.hit_target = t.sizes.target_touch
        out.metrics.control_height = t.sizes.control_md
        out.metrics.density = 1.25
        out.spacing = Spacing { xs: 6.0, sm: 10.0, md: 16.0, lg: 20.0, xl: 28.0 }
    }
    if a.profile == .DesktopDense {
        out.metrics.hit_target = t.sizes.control_xs
        out.metrics.control_height = t.sizes.control_xs
        out.metrics.density = 0.85
        out.spacing = Spacing { xs: 2.0, sm: 4.0, md: 8.0, lg: 12.0, xl: 16.0 }
    }
    if a.size == .Compact && !touch_first {
        out.spacing = Spacing { xs: t.spacing.xs, sm: t.spacing.sm, md: t.spacing.sm, lg: t.spacing.md, xl: t.spacing.lg }
    }
    ret out
}
