// Style values for the UI tree: plain immutable structs a caller builds from
// `defaults()` and hands to layout and paint. `validate` is the single guard --
// every length finite and, for padding and the size bounds, non-negative; a
// margin may be negative; a `Px` minimum never above a `Px` maximum; opacity in
// `[0, 1]`; the background brush as `paint.validate` sees it. There is no
// cascade, selector or inheritance: a style is what its fields say.

use e.gfx.geometry
use e.math
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
// Per-corner radii (D945): all four zero means every corner takes `radius`.
type Corners = struct { top_left: f32, top_right: f32, bottom_right: f32, bottom_left: f32 }
type Style = struct { display: Display, position: Position, width: Length, height: Length, min_width: Length, min_height: Length, max_width: Length, max_height: Length, margin: EdgeLengths, padding: EdgeLengths, background: paint.Brush, opacity: f32, overflow: Overflow, border: Border, radius: f32, shadow: Shadow, corners: Corners, shade: u8 }
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
        corners: Corners { top_left: 0.0, top_right: 0.0, bottom_right: 0.0, bottom_left: 0.0 },
        shade: 0u8,
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
    let c = value.corners
    if !finite(c.top_left) || !finite(c.top_right) || !finite(c.bottom_right) || !finite(c.bottom_left) || c.top_left < 0.0 || c.top_right < 0.0 || c.bottom_right < 0.0 || c.bottom_left < 0.0 { ret Invalid }
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
// `Linux` is the GNOME / libadwaita look (`adwaita`). `Windows` is the MTG Studio v3 look (`windows`): the native-style Windows face of the
// DevExpress controls; a control branches on it only where its shape differs.
type Profile = enum u8 { Neper, DesktopDense, Touch, MaterialLike, CupertinoLike, Windows, Linux }
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
// `Container` is the FAB's primary container (D944).
// `Default` is the button the Enter key presses: Filled everywhere, except that the Windows
// look draws it as a plain face button with an accent border.
type ControlVariant = enum u8 { Filled, Outlined, Plain, Tonal, Elevated, Danger, Container, Default }
// `elevation` is the shadow level the control casts; `padding` and `padding_start`
// are its horizontal padding when the control sets them (zero: the pressable's own);
// with `custom_padding` they and `padding_y` are taken exactly, zero included; a
// nonzero `min_width` or `min_height` raises the pressable's own minimum (D944).
type ResolvedControl = struct { background: paint.Color, foreground: paint.Color, border: paint.Color, border_width: f32, focus_ring: f32, opacity: f32, radius: f32, elevation: u8, padding: f32, padding_start: f32, padding_y: f32, custom_padding: bool, min_width: f32, min_height: f32, corners: Corners }
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

// A colour from 0xRRGGBB.
fn hex_raw(value: u32) -> paint.Color {
    ret paint.rgba(f32((value >> 16u32) & 255u32) / 255.0, f32((value >> 8u32) & 255u32) / 255.0, f32(value & 255u32) / 255.0, 1.0)
}

fn put(t: *ThemeTokens, role: ColorRole, value: u32) {
    t.colors[color_index(role)] = hex_raw(value)
}

// ---- the Windows dark look's colour map ----------------------------------------------------------------------
// The Windows light look paints its tiles and tables from measured light colours (`hex` literals in the painters).
// While `set_windark(true)` is on (the harness and the app turn it on for the Windows Dark palette), `hex` and `hexa`
// map such a light literal to its dark counterpart instead of every painter carrying a second table: a neutral grey
// follows the tone curve below (face #FDFDFD to #2B2B2B, dialog #F0F0F0 to #202020, border #D2D2D2 to #5A5A5A, text
// black to white), a light tint (selection, hover) becomes a dark tint of its hue, a mid accent (#0078D7) is lifted
// (to about #4CC2FF). The tokens (`put`, `hex_raw`) and every resolver in this file are written in dark values already
// and never pass through the map; a painter that wants an exact dark value calls `hex_raw`.
var windark_on: bool = false

fn set_windark(on: bool) {
    windark_on = on
}

fn windark_active() -> bool {
    ret windark_on
}

// A segment of the grey tone curve: input v between v0 and v1 gives o0 to o1.
fn wd_seg(v: f32, v0: f32, v1: f32, o0: f32, o1: f32) -> f32 {
    ret o0 + (o1 - o0) * (v - v0) / (v1 - v0)
}

// The dark grey (0..255) of a light grey (0..255). Folded at #F0F0F0: the light face and the dark face are both
// the "lowest" grey of their theme, and the lighter hover and border greys of the light theme are darker, so
// in dark they are the lighter ones.
fn windark_gray(v: f32) -> f32 {
    if v >= 253.0 { ret 43.0 }
    if v >= 240.0 { ret wd_seg(v, 240.0, 253.0, 32.0, 43.0) }
    if v >= 232.0 { ret wd_seg(v, 232.0, 240.0, 46.0, 32.0) }
    if v >= 229.0 { ret wd_seg(v, 229.0, 232.0, 60.0, 46.0) }
    if v >= 222.0 { ret wd_seg(v, 222.0, 229.0, 69.0, 60.0) }
    if v >= 210.0 { ret wd_seg(v, 210.0, 222.0, 90.0, 69.0) }
    if v >= 192.0 { ret wd_seg(v, 192.0, 210.0, 105.0, 90.0) }
    if v >= 160.0 { ret wd_seg(v, 160.0, 192.0, 130.0, 105.0) }
    if v >= 128.0 { ret wd_seg(v, 128.0, 160.0, 145.0, 130.0) }
    if v >= 109.0 { ret wd_seg(v, 109.0, 128.0, 157.0, 145.0) }
    if v >= 80.0 { ret wd_seg(v, 80.0, 109.0, 190.0, 157.0) }
    if v >= 40.0 { ret wd_seg(v, 40.0, 80.0, 230.0, 190.0) }
    ret wd_seg(v, 0.0, 40.0, 255.0, 230.0)
}

fn wd_hue(p: f32, q: f32, h0: f32) -> f32 {
    var h = h0
    if h < 0.0 { h += 1.0 }
    if h > 1.0 { h -= 1.0 }
    if h < 1.0 / 6.0 { ret p + (q - p) * 6.0 * h }
    if h < 0.5 { ret q }
    if h < 2.0 / 3.0 { ret p + (q - p) * (2.0 / 3.0 - h) * 6.0 }
    ret p
}

// The dark colour (0..1 channels in, out) of a light one.
fn windark_rgb(red: f32, green: f32, blue: f32) -> paint.Color {
    var hi = red
    if green > hi { hi = green }
    if blue > hi { hi = blue }
    var lo = red
    if green < lo { lo = green }
    if blue < lo { lo = blue }
    if hi - lo <= 0.04 {
        let g = windark_gray((red + green + blue) / 3.0 * 255.0) / 255.0
        ret paint.rgba(g, g, g, 1.0)
    }
    let light = (hi + lo) / 2.0
    var span = 2.0 * light
    if light > 0.5 { span = 2.0 - 2.0 * light }
    var sat = (hi - lo) / span
    var hue: f32 = 0.0
    let d = hi - lo
    if hi == red {
        hue = (green - blue) / d
        if green < blue { hue += 6.0 }
    } else if hi == green {
        hue = (blue - red) / d + 2.0
    } else {
        hue = (red - green) / d + 4.0
    }
    hue = hue / 6.0
    var nl = light
    if light >= 0.8 {
        nl = 0.38 - (light - 0.8) * 0.9
        if sat > 0.9 { sat = 0.9 }
    } else if light < 0.5 {
        // a mid accent is lifted a little only: #0078D7 stays a row colour white text reads on (the focus line and rims that want #4CC2FF say so)
        nl = light + 0.07
    }
    var q = nl + sat - nl * sat
    if nl < 0.5 { q = nl * (1.0 + sat) }
    let p = 2.0 * nl - q
    ret paint.rgba(wd_hue(p, q, hue + 1.0 / 3.0), wd_hue(p, q, hue), wd_hue(p, q, hue - 1.0 / 3.0), 1.0)
}

// A colour from 0xRRGGBB; under `set_windark` the dark counterpart of a light colour.
fn hex(value: u32) -> paint.Color {
    let c = hex_raw(value)
    if !windark_on { ret c }
    ret windark_rgb(c.red, c.green, c.blue)
}

// A colour from 0xRRGGBB at `alpha`; mapped like `hex`.
fn hexa(value: u32, alpha: f32) -> paint.Color {
    let c = hex_raw(value)
    if !windark_on { ret hexa_raw(value, alpha) }
    let d = windark_rgb(c.red, c.green, c.blue)
    ret paint.rgba(d.red, d.green, d.blue, alpha)
}

// The Windows look: MTG Studio v3's DevExpress controls as the program draws them, measured
// from docs/grid-parity (tcxgrid/00-options-*-v3.png at 150 % DPI, tokens.json). Only the Light
// palette is measured; the others take the Neper colours with the Windows metrics. Controls
// read the face of a button or field from `SurfaceContainerLowest` (#FDFDFD), the frame of a
// group box from `OutlineVariant`, and the dialog face from `Background` (#F0F0F0).
// Unmeasured: the disabled and hover/pressed colours (see docs/ui/looks/status.json gaps).
fn windows(palette: Palette) -> ThemeTokens {
    var t = reference(palette)
    t.profile = .Windows
    if palette == .Light {
        put(&t, .Background, 15790320u32)
        put(&t, .Surface, 16777215u32)
        put(&t, .SurfaceVariant, 15790320u32)
        put(&t, .Primary, 24504u32)
        put(&t, .FocusRing, 24504u32)
        put(&t, .Text, 0u32)
        put(&t, .OnSurface, 0u32)
        put(&t, .TextMuted, 7171437u32)
        put(&t, .OnSurfaceVariant, 7171437u32)
        put(&t, .Border, 13816530u32)
        put(&t, .Outline, 13816530u32)
        put(&t, .OutlineVariant, 14474460u32)
        put(&t, .SurfaceContainerLowest, 16645629u32)
        put(&t, .Selection, 10932991u32)
    }
    // looks-polish: the Windows Dark and High-Contrast palettes (see windows_fill_dark, windows_fill_contrast).
    if palette == .Dark { windows_fill_dark(&t) }
    if palette == .HighContrast { windows_fill_contrast(&t, false) }
    if palette == .HighContrastDark { windows_fill_contrast(&t, true) }
    // Flat square-ish corners: v3's buttons and fields are 3 px.
    t.radii = Radii { xs: 2.0, sm: 4.0, md: 4.0, lg: 4.0, xl: 4.0, full: 9999.0 }
    t.borders = Borders { hairline: 1.0, regular: 1.0, thick: 2.0 }
    var e: [6]f32 = zero
    t.elevation = e
    // 8.4 pt (11.2 px, fitted by ink width of "Cancel") body text; v3 labels are regular weight, not the Neper semibold.
    let body = TextStyle { size: 11.2, line_height: 15.0, weight: 400u16, italic: false }
    t.text[0] = body
    t.text[1] = body
    t.text[4] = body
    t.text[17] = body
    t.text[18] = body
    t.text[19] = body
    t.sizes.control_xs = 18.0
    t.sizes.control_sm = 22.0
    t.sizes.outline_focused = 1.0
    // Buttons, combo boxes and text fields are 22 layout units high.
    t.metrics = Metrics { hit_target: 22.0, control_height: 22.0, density: 1.0, focus_ring: 0.0, focus_offset: 0.0 }
    ret t
}

// ---- looks-polish: Windows Dark and High-Contrast palettes ------------------------------------
// Dark is the Windows 11 dark theme: dialog face #202020, control face and field #2B2B2B, border
// #5A5A5A, accent #4CC2FF, text white (values from the task brief and the WinUI dark ramp; no v3
// capture exists in dark, so every Dark value is unmeasured). The contrast palettes are the Windows
// system colours: `black` is "High contrast black" (window #000000, text #FFFFFF, GrayText
// #3FF23F, Highlight #1AEBFF), the other "High contrast white" (window #FFFFFF, text #000000,
// GrayText #600000, Highlight #37006E). Neper's HighContrast is white, HighContrastDark black.
fn windows_fill_dark(t: *ThemeTokens) {
    put(t, .Background, 0x202020u32)
    put(t, .Surface, 0x2B2B2Bu32)
    put(t, .SurfaceVariant, 0x202020u32)
    put(t, .Primary, 0x4CC2FFu32)
    put(t, .OnPrimary, 0x000000u32)
    put(t, .FocusRing, 0x4CC2FFu32)
    put(t, .Text, 0xFFFFFFu32)
    put(t, .OnSurface, 0xFFFFFFu32)
    put(t, .TextMuted, 0x9D9D9Du32)
    put(t, .OnSurfaceVariant, 0x9D9D9Du32)
    put(t, .Border, 0x5A5A5Au32)
    put(t, .Outline, 0x5A5A5Au32)
    put(t, .OutlineVariant, 0x454545u32)
    put(t, .SurfaceContainerLowest, 0x2B2B2Bu32)
    put(t, .SurfaceContainerLow, 0x272727u32)
    put(t, .SurfaceContainer, 0x2B2B2Bu32)
    put(t, .SurfaceContainerHigh, 0x323232u32)
    put(t, .SurfaceContainerHighest, 0x3A3A3Au32)
    put(t, .SurfaceDim, 0x1C1C1Cu32)
    put(t, .SurfaceBright, 0x383838u32)
    put(t, .Selection, 0x264F78u32)
}

fn windows_fill_contrast(t: *ThemeTokens, black: bool) {
    var window = 0xFFFFFFu32
    var ink = 0x000000u32
    var gray = 0x600000u32
    var highlight = 0x37006Eu32
    var on_highlight = 0xFFFFFFu32
    if black {
        window = 0x000000u32
        ink = 0xFFFFFFu32
        gray = 0x3FF23Fu32
        highlight = 0x1AEBFFu32
        on_highlight = 0x000000u32
    }
    put(t, .Background, window)
    put(t, .Surface, window)
    put(t, .SurfaceVariant, window)
    put(t, .Primary, highlight)
    put(t, .OnPrimary, on_highlight)
    put(t, .FocusRing, highlight)
    put(t, .Text, ink)
    put(t, .OnSurface, ink)
    put(t, .TextMuted, gray)
    put(t, .OnSurfaceVariant, gray)
    put(t, .Border, ink)
    put(t, .Outline, ink)
    put(t, .OutlineVariant, ink)
    put(t, .SurfaceContainerLowest, window)
    put(t, .SurfaceContainerLow, window)
    put(t, .SurfaceContainer, window)
    put(t, .SurfaceContainerHigh, window)
    put(t, .SurfaceContainerHighest, window)
    put(t, .SurfaceDim, window)
    put(t, .SurfaceBright, window)
    put(t, .Selection, highlight)
}

// Whether a Windows token set is one of the two high-contrast palettes.
fn windows_contrast(t: *const ThemeTokens) -> bool {
    ret t.palette == .HighContrast || t.palette == .HighContrastDark
}

// The accent a Windows control draws its default, focused and checked border in: Light #298DD9
// (measured on v3's default button, docs/ui/looks/windows-measurements.md), Dark #4CC2FF, and the
// contrast palettes' Highlight.
fn windows_accent(t: *const ThemeTokens) -> paint.Color {
    if t.palette == .Dark { ret hex_raw(0x4CC2FFu32) }
    if windows_contrast(t) { ret color(t, .Primary) }
    ret hex_raw(0x298DD9u32)
}
// ---- round 7: the dark flag of the Windows bars and grids ------------------------------------------------------
// `windows_dark_enter` sets the colour map (`set_windark`) from a theme at the entry of a control; the maps are above.
fn windows_dark_enter(t: *const ThemeTokens) {
    windark_on = t.profile == .Windows && t.palette == .Dark
}

fn windows_dark_on() -> bool { ret windark_on }
// ---- end looks-polish palettes -----------------------------------------------------------------

// ---- the Cupertino look (profile CupertinoLike, docs/ui/looks/cupertino) -----------------------
// Apple's system colours, Light and Dark, from the Human Interface Guidelines / UIKit: label and
// secondaryLabel, systemBlue #007AFF (#0A84FF dark), the grouped backgrounds, the separators, the
// four fills. No Apple platform was available as a live reference, so every value is the published
// system value (confident) or an approximation (marked in docs/ui/looks/cupertino notes). SF Pro is
// not installed on the Windows host: the type scale uses Segoe UI at SF Pro's sizes.

// A colour from 0xRRGGBB at `alpha`.
fn hexa_raw(value: u32, alpha: f32) -> paint.Color {
    ret paint.rgba(f32((value >> 16u32) & 255u32) / 255.0, f32((value >> 8u32) & 255u32) / 255.0, f32(value & 255u32) / 255.0, alpha)
}

fn puta(t: *ThemeTokens, role: ColorRole, value: u32, alpha: f32) {
    t.colors[color_index(role)] = hexa_raw(value, alpha)
}

fn cupertino(palette: Palette) -> ThemeTokens {
    var t = reference(palette)
    t.profile = .CupertinoLike
    let dark = palette == .Dark || palette == .HighContrastDark
    // systemBlue, systemRed, systemGreen, systemOrange.
    var blue = 0x007AFFu32
    var red = 0xFF3B30u32
    var green = 0x34C759u32
    var orange = 0xFF9500u32
    if dark {
        blue = 0x0A84FFu32
        red = 0xFF453Au32
        green = 0x30D158u32
        orange = 0xFF9F0Au32
    }
    // Grouped backgrounds: Light #F2F2F7 / white cells; Dark #1C1C1E / #2C2C2E cells (the elevated grouped level).
    if !dark {
        puta(&t, .Background, 0xF2F2F7u32, 1.0)
        puta(&t, .Surface, 0xFFFFFFu32, 1.0)
        puta(&t, .SurfaceVariant, 0xE5E5EAu32, 1.0)
        puta(&t, .Text, 0x000000u32, 1.0)
        puta(&t, .OnSurface, 0x000000u32, 1.0)
        // secondaryLabel rgba(60,60,67,0.6) flattened on white.
        puta(&t, .TextMuted, 0x8A8A8Eu32, 1.0)
        puta(&t, .OnSurfaceVariant, 0x8A8A8Eu32, 1.0)
        // opaqueSeparator #C6C6C8; Outline is the unchecked-box edge (rgba(0,0,0,0.25) flattened).
        puta(&t, .Border, 0xC6C6C8u32, 1.0)
        puta(&t, .Outline, 0xBFBFBFu32, 1.0)
        puta(&t, .OutlineVariant, 0xD1D1D6u32, 1.0)
        puta(&t, .SecondaryContainer, 0xE9E9EBu32, 1.0)
        puta(&t, .OnSecondaryContainer, 0x000000u32, 1.0)
        puta(&t, .PrimaryContainer, 0xD9EBFFu32, 1.0)
        puta(&t, .SurfaceDim, 0xD1D1D6u32, 1.0)
        puta(&t, .SurfaceBright, 0xFFFFFFu32, 1.0)
        puta(&t, .SurfaceContainerLowest, 0xFFFFFFu32, 1.0)
        puta(&t, .SurfaceContainerLow, 0xF9F9FBu32, 1.0)
        puta(&t, .SurfaceContainer, 0xF2F2F7u32, 1.0)
        puta(&t, .SurfaceContainerHigh, 0xE9E9EBu32, 1.0)
        puta(&t, .SurfaceContainerHighest, 0xE5E5EAu32, 1.0)
        puta(&t, .InverseSurface, 0x2C2C2Eu32, 1.0)
        puta(&t, .InverseOnSurface, 0xFFFFFFu32, 1.0)
        puta(&t, .Selection, 0xB3D7FFu32, 1.0)
        puta(&t, .TextSelection, 0xB3D7FFu32, 1.0)
        puta(&t, .ErrorContainer, 0xFFE0DEu32, 1.0)
    }
    if dark {
        puta(&t, .Background, 0x1C1C1Eu32, 1.0)
        puta(&t, .Surface, 0x2C2C2Eu32, 1.0)
        puta(&t, .SurfaceVariant, 0x3A3A3Cu32, 1.0)
        puta(&t, .Text, 0xFFFFFFu32, 1.0)
        puta(&t, .OnSurface, 0xFFFFFFu32, 1.0)
        // secondaryLabel rgba(235,235,245,0.6) flattened on #2C2C2E.
        puta(&t, .TextMuted, 0x9E9EA6u32, 1.0)
        puta(&t, .OnSurfaceVariant, 0x9E9EA6u32, 1.0)
        puta(&t, .Border, 0x38383Au32, 1.0)
        puta(&t, .Outline, 0x6B6B6Eu32, 1.0)
        puta(&t, .OutlineVariant, 0x48484Au32, 1.0)
        puta(&t, .SecondaryContainer, 0x48484Au32, 1.0)
        puta(&t, .OnSecondaryContainer, 0xFFFFFFu32, 1.0)
        puta(&t, .PrimaryContainer, 0x0F3A66u32, 1.0)
        puta(&t, .SurfaceDim, 0x000000u32, 1.0)
        puta(&t, .SurfaceBright, 0x3A3A3Cu32, 1.0)
        puta(&t, .SurfaceContainerLowest, 0x1C1C1Eu32, 1.0)
        puta(&t, .SurfaceContainerLow, 0x242426u32, 1.0)
        puta(&t, .SurfaceContainer, 0x2C2C2Eu32, 1.0)
        puta(&t, .SurfaceContainerHigh, 0x3A3A3Cu32, 1.0)
        puta(&t, .SurfaceContainerHighest, 0x48484Au32, 1.0)
        puta(&t, .InverseSurface, 0xE5E5EAu32, 1.0)
        puta(&t, .InverseOnSurface, 0x000000u32, 1.0)
        puta(&t, .Selection, 0x1E4F8Au32, 1.0)
        puta(&t, .TextSelection, 0x1E4F8Au32, 1.0)
        puta(&t, .ErrorContainer, 0x5A1A16u32, 1.0)
    }
    puta(&t, .Primary, blue, 1.0)
    puta(&t, .OnPrimary, 0xFFFFFFu32, 1.0)
    puta(&t, .OnPrimaryContainer, blue, 1.0)
    puta(&t, .Secondary, 0x8E8E93u32, 1.0)
    puta(&t, .OnSecondary, 0xFFFFFFu32, 1.0)
    puta(&t, .Focus, blue, 1.0)
    // The keyboard focus ring: the accent at about half strength.
    puta(&t, .FocusRing, blue, 0.55)
    puta(&t, .Error, red, 1.0)
    puta(&t, .OnError, 0xFFFFFFu32, 1.0)
    puta(&t, .OnErrorContainer, red, 1.0)
    puta(&t, .Success, green, 1.0)
    puta(&t, .OnSuccess, 0xFFFFFFu32, 1.0)
    puta(&t, .Warning, orange, 1.0)
    puta(&t, .OnWarning, 0xFFFFFFu32, 1.0)
    puta(&t, .Tertiary, orange, 1.0)
    puta(&t, .Scrim, 0x000000u32, 1.0)
    puta(&t, .Shadow, 0x000000u32, 1.0)
    puta(&t, .Data1, blue, 1.0)
    puta(&t, .Data2, green, 1.0)
    puta(&t, .Data3, orange, 1.0)
    puta(&t, .Data4, 0xAF52DEu32, 1.0)
    puta(&t, .Data5, 0xFF2D55u32, 1.0)
    puta(&t, .Data6, 0x5AC8FAu32, 1.0)
    // SF Pro's text styles (iOS defaults), set in Segoe UI: body 17, subhead 15, caption 12 / 11, title 22 / 28 / 34.
    t.text[0] = TextStyle { size: 17.0, line_height: 22.0, weight: 400u16, italic: false }
    t.text[1] = TextStyle { size: 15.0, line_height: 20.0, weight: 400u16, italic: false }
    t.text[2] = TextStyle { size: 22.0, line_height: 28.0, weight: 400u16, italic: false }
    t.text[3] = TextStyle { size: 17.0, line_height: 22.0, weight: 600u16, italic: false }
    t.text[4] = TextStyle { size: 15.0, line_height: 20.0, weight: 600u16, italic: false }
    t.text[5] = TextStyle { size: 12.0, line_height: 16.0, weight: 400u16, italic: false }
    t.text[6] = TextStyle { size: 13.0, line_height: 18.0, weight: 400u16, italic: false }
    t.text[7] = TextStyle { size: 34.0, line_height: 41.0, weight: 400u16, italic: false }
    t.text[8] = TextStyle { size: 28.0, line_height: 34.0, weight: 400u16, italic: false }
    t.text[9] = TextStyle { size: 22.0, line_height: 28.0, weight: 400u16, italic: false }
    t.text[10] = TextStyle { size: 34.0, line_height: 41.0, weight: 700u16, italic: false }
    t.text[11] = TextStyle { size: 28.0, line_height: 34.0, weight: 700u16, italic: false }
    t.text[12] = TextStyle { size: 20.0, line_height: 25.0, weight: 400u16, italic: false }
    t.text[13] = TextStyle { size: 22.0, line_height: 28.0, weight: 400u16, italic: false }
    t.text[14] = TextStyle { size: 17.0, line_height: 22.0, weight: 600u16, italic: false }
    t.text[15] = TextStyle { size: 15.0, line_height: 20.0, weight: 600u16, italic: false }
    t.text[16] = TextStyle { size: 17.0, line_height: 22.0, weight: 400u16, italic: false }
    t.text[17] = TextStyle { size: 15.0, line_height: 20.0, weight: 400u16, italic: false }
    t.text[18] = TextStyle { size: 17.0, line_height: 22.0, weight: 600u16, italic: false }
    t.text[19] = TextStyle { size: 13.0, line_height: 18.0, weight: 400u16, italic: false }
    t.text[20] = TextStyle { size: 11.0, line_height: 13.0, weight: 400u16, italic: false }
    // Corner radii 5 (macOS controls), 8, 10, 12 (iOS grouped list), 14 (sheets); circular arcs stand in for Apple's continuous curve.
    t.radii = Radii { xs: 5.0, sm: 8.0, md: 10.0, lg: 12.0, xl: 14.0, full: 9999.0 }
    t.spacing = Spacing { xs: 4.0, sm: 8.0, md: 12.0, lg: 16.0, xl: 20.0 }
    t.borders = Borders { hairline: 0.5, regular: 1.0, thick: 2.0 }
    var e: [6]f32 = zero
    e[1] = 0.10
    e[2] = 0.12
    e[3] = 0.14
    e[4] = 0.16
    e[5] = 0.18
    t.elevation = e
    t.states = States { hover: 0.06, focus: 0.0, pressed: 0.14, dragged: 0.16, disabled_container: 0.12, disabled_content: 0.3, scrim: 0.4 }
    // Control heights: macOS regular 22 / large 28 / x-large 32, iOS medium 34 / large 44 (the hit-target minimum) / 50.
    t.sizes = Sizes { control_xs: 22.0, control_sm: 28.0, control_md: 34.0, control_lg: 44.0, control_xl: 50.0, target_touch: 44.0, target_pointer: 28.0, icon_xs: 12.0, icon_sm: 17.0, icon_md: 22.0, icon_lg: 28.0, divider: 0.5, outline_focused: 3.0 }
    t.motion = Motion { fast_ms: 100u32, normal_ms: 250u32, slow_ms: 350u32, reduced: false }
    t.metrics = Metrics { hit_target: 44.0, control_height: 34.0, density: 1.0, focus_ring: 3.0, focus_offset: 0.0 }
    ret t
}
// The hairline between list rows and under bars: iOS's separator colour.
fn cupertino_separator(t: *const ThemeTokens) -> paint.Color {
    if t.palette == .Dark { ret hexa_raw(0x545458u32, 0.6) }
    ret hexa_raw(0x3C3C43u32, 0.29)
}

// A colour at another alpha.
fn cup_alpha(c: paint.Color, alpha: f32) -> paint.Color {
    ret paint.Color { red: c.red, green: c.green, blue: c.blue, alpha: alpha }
}

// The tertiary fill (rgba(118,118,128,.12) Light, .24 Dark) that gray and bezel-less controls rest on,
// at `strength` times its resting alpha.
fn cup_fill(t: *const ThemeTokens, strength: f32) -> paint.Color {
    if t.palette == .Dark { ret hexa_raw(0x767680u32, 0.24 * strength) }
    ret hexa_raw(0x767680u32, 0.12 * strength)
}

// A button's look in the Cupertino idiom. `variant`: Filled / Default / Container the prominent accent fill,
// Tonal the tinted button (accent at 15 %), Elevated the gray one (tertiary fill, accent label), Plain the
// label alone, Outlined the macOS bezel (white face, hairline, 1 px shadow below), Danger the red fill.
// `height` picks the size: 28 small, 34 medium, 44 large (iOS configuration sizes; 22 / 28 / 32 for the macOS
// bezel). Hover is an approximation (Apple's buttons have none on touch; the iPad pointer lifts them).
fn cupertino_resolve(t: *const ThemeTokens, variant: ControlVariant, state: ControlState, height: f32) -> ResolvedControl {
    let dark = t.palette == .Dark
    let accent = color(t, .Primary)
    let ink = color(t, .Text)
    let clear = paint.rgba(0.0, 0.0, 0.0, 0.0)
    var face = accent
    var label = hex_raw(0xFFFFFFu32)
    var edge = clear
    var edge_w: f32 = 0.0
    var lift = 0u8
    var pad_x: f32 = 16.0
    var radius: f32 = 10.0
    var weight_pad: f32 = 0.0
    if height <= 28.5 {
        pad_x = 12.0
        radius = 8.0
    }
    if height >= 40.0 {
        pad_x = 20.0
        radius = 12.0
    }
    // The macOS regular push button (22 tall) is 5 px round with 14 px sides and a 64 px least width.
    var least = height
    if height <= 24.0 {
        radius = 5.0
        pad_x = 12.0
        least = 64.0
    }
    let prominent = variant == .Filled || variant == .Default || variant == .Container
    if variant == .Danger { face = color(t, .Error) }
    if variant == .Tonal {
        face = cup_alpha(accent, 0.15)
        if dark { face = cup_alpha(accent, 0.22) }
        label = accent
    }
    if variant == .Elevated {
        face = cup_fill(t, 1.0)
        label = accent
    }
    if variant == .Plain {
        face = clear
        label = accent
    }
    if variant == .Outlined {
        // The macOS push button (bordered): radius about a quarter of the height, a hairline and a shadow edge.
        radius = height * 0.23
        pad_x = 12.0
        if height > 25.0 { pad_x = 14.0 }
        lift = 1u8
        label = cup_alpha(ink, 0.85)
        if dark {
            face = hexa_raw(0xFFFFFFu32, 0.22)
            edge = hexa_raw(0xFFFFFFu32, 0.08)
        }
        if !dark {
            face = hex_raw(0xFFFFFFu32)
            edge = hexa_raw(0x000000u32, 0.10)
        }
        edge_w = 0.5
    }
    // The states: pressed darkens a fill (the accent toward black), a tint or gray fill deepens, plain dims its label.
    if state.hovered && !state.pressed {
        if prominent || variant == .Danger { face = mix(face, hex_raw(0xFFFFFFu32), 0.10) }
        if variant == .Tonal { face = cup_alpha(accent, 0.20) }
        if variant == .Elevated { face = cup_fill(t, 1.5) }
        if variant == .Plain { face = cup_fill(t, 0.6) }
        if variant == .Outlined && !dark { face = hex_raw(0xFAFAFAu32) }
        if variant == .Outlined && dark { face = hexa_raw(0xFFFFFFu32, 0.27) }
    }
    if state.pressed {
        if prominent || variant == .Danger { face = mix(face, hex_raw(0x000000u32), 0.22) }
        if variant == .Tonal { face = cup_alpha(accent, 0.28) }
        if variant == .Elevated { face = cup_fill(t, 2.0) }
        if variant == .Plain { label = cup_alpha(label, 0.35) }
        if variant == .Outlined && !dark { face = hex_raw(0xE3E3E3u32) }
        if variant == .Outlined && dark { face = hexa_raw(0xFFFFFFu32, 0.34) }
        if variant == .Outlined { lift = 0u8 }
    }
    if state.disabled {
        if prominent || variant == .Danger {
            face = cup_fill(t, 1.5)
            label = cup_alpha(color(t, .OnSurface), 0.3)
        }
        if variant == .Tonal || variant == .Elevated {
            face = cup_fill(t, 0.8)
            label = cup_alpha(color(t, .OnSurface), 0.3)
        }
        if variant == .Plain { label = cup_alpha(color(t, .OnSurface), 0.3) }
        if variant == .Outlined {
            label = cup_alpha(ink, 0.25)
            if !dark { face = hexa_raw(0xFFFFFFu32, 0.6) }
            if dark { face = hexa_raw(0xFFFFFFu32, 0.10) }
            lift = 0u8
        }
    }
    ret ResolvedControl { background: face, foreground: label, border: edge, border_width: edge_w, focus_ring: 0.0, opacity: 1.0, radius: radius, elevation: lift, padding: pad_x, padding_start: 0.0, padding_y: weight_pad, custom_padding: true, min_width: least, min_height: height, corners: zero }
}
// ---- end the Cupertino look --------------------------------------------------------------------

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

// ---- Neper dark: ink an application chose for a light page (a card colour, a link blue, a rule's colour) --------
// The sRGB relative luminance of a colour (WCAG 2).
fn rel_channel(c: f32) -> f32 {
    if c <= 0.03928 { ret c / 12.92 }
    ret math.pow[f32]((c + 0.055) / 1.055, 2.4)
}

fn rel_luminance(c: paint.Color) -> f32 {
    ret 0.2126 * rel_channel(c.red) + 0.7152 * rel_channel(c.green) + 0.0722 * rel_channel(c.blue)
}

// The WCAG contrast ratio of two colours.
fn contrast_ratio(a: paint.Color, b: paint.Color) -> f32 {
    let la = rel_luminance(a)
    let lb = rel_luminance(b)
    if la > lb { ret (la + 0.05) / (lb + 0.05) }
    ret (lb + 0.05) / (la + 0.05)
}

// Under the Neper look in its Dark palette an ink that reads below 4.5:1 on the lightest dark surface (the page,
// a selected row) is lifted toward white until it does (5.0 in the code: the measured fill of a selected row is a little lighter than the token), keeping its hue; every other look and palette gets the ink
// back unchanged, so the light pictures do not move.
fn same_color(a: paint.Color, b: paint.Color) -> bool {
    ret a.red == b.red && a.green == b.green && a.blue == b.blue
}

fn lift_ink(t: *const ThemeTokens, ink: paint.Color) -> paint.Color {
    if t.palette != .Dark || t.profile != .Neper { ret ink }
    var ground = color(t, .SurfaceVariant)
    let selection = color(t, .Selection)
    if rel_luminance(selection) > rel_luminance(ground) { ground = selection }
    // the palette's own inks for a light fill (on-primary on the accent) stay as they are: lifting them would erase them
    if same_color(ink, color(t, .OnPrimary)) || same_color(ink, color(t, .OnSecondary)) || same_color(ink, color(t, .OnTertiary)) { ret ink }
    if same_color(ink, color(t, .OnError)) || same_color(ink, color(t, .OnSuccess)) || same_color(ink, color(t, .OnWarning)) || same_color(ink, color(t, .InverseOnSurface)) { ret ink }
    var share: f32 = 0.0
    var out = ink
    while contrast_ratio(out, ground) < 5.0 && share < 1.0 {
        share += 0.05
        out = mix(ink, paint.Color { red: 1.0, green: 1.0, blue: 1.0, alpha: ink.alpha }, share)
    }
    ret out
}

// The edge of an interactive frame (list, read-only field): OutlineVariant, which is a divider's ink, reads 2.0:1 on the Neper
// dark page, so that look takes a fixed ink at 3.9:1 on the page and 3.5:1 on a container; everything else is unchanged.
fn frame_ink(t: *const ThemeTokens) -> paint.Color {
    if t.palette == .Dark && t.profile == .Neper { ret hex_raw(0x707380u32) }
    ret color(t, .OutlineVariant)
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
    if variant == .Container {
        background = color(t, .PrimaryContainer)
        foreground = color(t, .OnPrimaryContainer)
        border = background
        elevation = 3u8
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
    // M3: a focused outlined control's outline turns `primary` (md.comp.outlined-button.focus.outline.color).
    if t.profile == .MaterialLike && variant == .Outlined && state.focus_visible && !state.invalid { border = color(t, .Primary) }
    var focus_ring: f32 = 0.0
    if state.focused { focus_ring = t.metrics.focus_ring }
    var opacity: f32 = 1.0
    if state.disabled { opacity = 0.5 }
    if state.hovered && elevation != 0u8 { elevation = elevation + 1u8 }
    // M3: a filled or tonal button lifts to level 1 when hovered, an elevated one sits at 1 and goes to 2 only while hovered (not pressed).
    if t.profile == .MaterialLike {
        if variant == .Elevated && !state.disabled { elevation = 1u8 }
        if state.hovered && !state.pressed && !state.disabled {
            if variant == .Elevated { elevation = 2u8 }
            if variant == .Filled || variant == .Tonal { elevation = 1u8 }
        }
    }
    ret ResolvedControl { background: background, foreground: foreground, border: border, border_width: border_width, focus_ring: focus_ring, opacity: opacity, radius: t.radii.sm, elevation: elevation, padding: 0.0, padding_start: 0.0, padding_y: 0.0, custom_padding: false, min_width: 0.0, min_height: 0.0, corners: zero }
}

// The Windows look's button (docs/ui/looks): a #FDFDFD face with a 1 px border, 74 x 22 visible
// (v3's 75 x 23 DFM box, the native theme draws it ~1.3 px inside), black label; `Default` (and a
// focused or toggled-on button) takes the accent border, as the native theme draws a defaulted
// button; `Plain` is the label alone. Measured (v3 at 150 %, docs/ui/looks/windows-measurements.md):
// the rest face, border, accent, size, and the disabled face, border and label. Unmeasured, so a
// guess: the hover and pressed faces and every Dark and contrast colour. High contrast draws the
// button as the system does: button face and text, Highlight under the pointer.
fn windows_resolve(t: *const ThemeTokens, variant: ControlVariant, state: ControlState) -> ResolvedControl {
    var face = color(t, .SurfaceContainerLowest)
    var ink = color(t, .Text)
    var edge = color(t, .Border)
    // Windows 11 dark: the button face is #333333 (the field's #2B2B2B stays the edit's).
    if t.palette == .Dark { face = hex_raw(0x333333u32) }
    let contrast = windows_contrast(t)
    let accent = windows_accent(t)
    let plain = variant == .Plain
    if plain {
        face = paint.rgba(0.0, 0.0, 0.0, 0.0)
        edge = face
    }
    if state.selected {
        if contrast {
            face = color(t, .Primary)
            ink = color(t, .OnPrimary)
        }
        if !contrast { face = mix(color(t, .SurfaceContainerLowest), accent, 0.2) }
    }
    // looks5: the hover face measured on v3's hovered Options buttons (states/hover-button-options-*): #E0EEF9 inside the accent ring.
    var hover = hex_raw(0xE0EEF9u32)
    // looks4: the pressed face measured on v3's pressed buttons (docs/ui/looks/ref/windows/states/button-pressed-*): #CCE4F7.
    var press = hex_raw(0xCCE4F7u32)
    if t.palette == .Dark {
        hover = hex_raw(0x3C3C3Cu32)
        // round 10: the native dark pressed face (docs/ui/looks/ref/windows-native/dark/button-pressed): #666666
        press = hex_raw(0x666666u32)
    }
    if state.hovered && !state.pressed {
        if contrast {
            face = color(t, .Primary)
            ink = color(t, .OnPrimary)
        }
        if !contrast && !plain && !state.selected {
            face = hover
            if t.palette == .Light { edge = accent }
        }
        if !contrast && (plain || state.selected) { face = layer(face, ink, 0.04) }
    }
    if state.pressed {
        if contrast {
            face = color(t, .Primary)
            ink = color(t, .OnPrimary)
        }
        if !contrast && !plain && !state.selected { face = press }
        if !contrast && (plain || state.selected) { face = layer(face, ink, 0.08) }
    }
    if variant == .Default || state.focused || state.selected { edge = accent }
    if state.disabled {
        // Measured on v3's disabled Apply: face #F9F9F9, border #EAEAEA, label #878787 (Light).
        face = hex_raw(0xF9F9F9u32)
        edge = hex_raw(0xEAEAEAu32)
        ink = hex_raw(0x878787u32)
        if t.palette == .Dark {
            // round 10: the native dark disabled button: face #333333, ring #404040, label #CCCCCC (button-disabled)
            face = hex_raw(0x333333u32)
            edge = hex_raw(0x404040u32)
            ink = hex_raw(0xCCCCCCu32)
        }
        if contrast {
            face = color(t, .SurfaceContainerLowest)
            edge = color(t, .TextMuted)
            ink = color(t, .TextMuted)
        }
        if plain { face = paint.rgba(0.0, 0.0, 0.0, 0.0) }
        if plain { edge = face }
    }
    var stroke = t.borders.regular
    if (variant == .Default || state.focused || state.selected) && contrast {
        stroke = 2.0
    }
    // 3 px sides and 2 px above and below the label leave the room v3's dotted focus rectangle sits in.
    ret ResolvedControl { background: face, foreground: ink, border: edge, border_width: stroke, focus_ring: 0.0, opacity: 1.0, radius: t.radii.sm, elevation: 0u8, padding: 3.0, padding_start: 0.0, padding_y: 2.0, custom_padding: true, min_width: 73.33, min_height: 21.33, corners: zero }
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

// ---- Windows look, group `choices` (docs/ui/looks): check box and radio mark -----------------
// The native Windows 11 mark TcxCheckBox / TcxRadioButton draw with NativeStyle: a 13 unit box
// (round for a radio) with a 1 unit #636363 edge on a #F3F3F3 face, or filled with the system
// accent (`Primary`, #005FB8) with a white tick, dash or dot when chosen. Measured at rest from
// docs/grid-parity/tcxgrid/00-options-interface-controls-v3.png and 00b-...; hover, pressed and
// disabled are the Windows 11 conventions, not captured (see docs/ui/looks/status.d/choices.json).
// `background` is the face, `foreground` the tick or dot, `border` the edge.
fn windows_choice_resolve(t: *const ThemeTokens, chosen: bool, state: ControlState) -> ResolvedControl {
    let ground = color(t, .Background)
    var face = hex_raw(15987699u32)
    var edge = hex_raw(7895160u32)
    var ink = hex_raw(16777215u32)
    if chosen {
        face = color(t, .Primary)
        edge = face
        if state.hovered && !state.pressed { face = mix(face, ground, 0.1) }
        if state.pressed { face = mix(face, ground, 0.2) }
        edge = face
    } else {
        if state.hovered && !state.pressed { face = layer(face, hex_raw(0u32), 0.04) }
        if state.pressed {
            face = layer(face, hex_raw(0u32), 0.09)
            edge = mix(edge, ground, 0.25)
        }
    }
    if state.disabled {
        if chosen {
            face = layer(ground, hex_raw(0u32), 0.22)
            edge = face
        } else {
            face = paint.rgba(0.0, 0.0, 0.0, 0.0)
            edge = mix(edge, ground, 0.6)
        }
    }
    ret ResolvedControl { background: face, foreground: ink, border: edge, border_width: 1.2, focus_ring: 0.0, opacity: 1.0, radius: 4.0, elevation: 0u8, padding: 0.0, padding_start: 0.0, padding_y: 0.0, custom_padding: false, min_width: 13.0, min_height: 13.0, corners: zero }
}

// ---- Windows look, caption and dialog window (docs/ui/looks, group feedback) ----
// v3's windows wear the Windows 11 dark caption: #1F2022 with white text, measured from
// docs/grid-parity/tcxgrid/00-options-interface-controls-v3.png (150 % DPI; 30 tall, the close
// glyph 10 wide). Unmeasured guesses: the inactive caption and every hover and pressed colour.
fn windows_caption_face(active: bool) -> paint.Color {
    if active { ret hex_raw(2039842u32) }
    // looks3: measured on the live captures (the inactive Options and About captions are #202020).
    ret hex_raw(2105376u32)
}

fn windows_caption_ink(active: bool) -> paint.Color {
    if active { ret hex_raw(16777215u32) }
    ret hex_raw(7895160u32)
}

// The close button's hover (#C42B1C) and pressed (#B22A1B) faces; its glyph turns white.
fn windows_caption_close(pressed: bool) -> paint.Color {
    if pressed { ret hex_raw(11676187u32) }
    ret hex_raw(12856092u32)
}

// looks3: the live 96 DPI captures put the dark caption at 31 rows (y 0 to 30).
fn windows_caption_height() -> f32 { ret 31.0 }

// looks5: the light caption of v3's DevExpress dialogs (Advanced Filter, Conditional Formatting Rules Manager, the Customization
// tool window): #F0F4F8 with black text and glyphs, as the live captures show (the capture varies by one level, a Mica wash).
fn windows_caption_light_face() -> paint.Color {
    // Windows 11 dark: the DevExpress dialogs' caption is the #2B2B2B control grey with white text.
    if windark_on { ret hex_raw(0x2B2B2Bu32) }
    ret hex_raw(0xF0F4F8u32)
}
fn windows_caption_light_ink() -> paint.Color {
    if windark_on { ret hex_raw(0xFFFFFFu32) }
    ret hex_raw(0u32)
}

// ---- Android look (docs/ui/looks, profile MaterialLike) ---------------------------------------
// Material Design 3 as Android ships it. The Neper default already is M3 in structure (shape
// scale 4/8/12/16/28, state layers 8/10/10/16 %, the fifteen type styles, elevation 0 to 5), so
// the Android look is: the M3 baseline tonal palette (seed #6750A4), the phone metrics (40 high
// controls, 48 targets, density 1, no focus ring: Android shows focus as the 10 % state layer),
// and Roboto Medium (500) where the M3 type scale says Medium. Colours are the published M3
// baseline values (exact); the control geometry is in `control.material_*`.
fn material_fill_light(t: *ThemeTokens) {
    put(t, .Background, 0xFEF7FFu32)
    put(t, .Surface, 0xFEF7FFu32)
    put(t, .SurfaceVariant, 0xE7E0ECu32)
    put(t, .Primary, 0x6750A4u32)
    put(t, .OnPrimary, 0xFFFFFFu32)
    put(t, .PrimaryContainer, 0xEADDFFu32)
    put(t, .OnPrimaryContainer, 0x21005Du32)
    put(t, .Secondary, 0x625B71u32)
    put(t, .OnSecondary, 0xFFFFFFu32)
    put(t, .SecondaryContainer, 0xE8DEF8u32)
    put(t, .OnSecondaryContainer, 0x1D192Bu32)
    put(t, .Tertiary, 0x7D5260u32)
    put(t, .OnTertiary, 0xFFFFFFu32)
    put(t, .TertiaryContainer, 0xFFD8E4u32)
    put(t, .OnTertiaryContainer, 0x31111Du32)
    put(t, .Error, 0xB3261Eu32)
    put(t, .OnError, 0xFFFFFFu32)
    put(t, .ErrorContainer, 0xF9DEDCu32)
    put(t, .OnErrorContainer, 0x410E0Bu32)
    put(t, .Text, 0x1D1B20u32)
    put(t, .OnSurface, 0x1D1B20u32)
    put(t, .TextMuted, 0x49454Fu32)
    put(t, .OnSurfaceVariant, 0x49454Fu32)
    put(t, .Border, 0x79747Eu32)
    put(t, .Outline, 0x79747Eu32)
    put(t, .OutlineVariant, 0xCAC4D0u32)
    put(t, .Focus, 0x6750A4u32)
    put(t, .FocusRing, 0x6750A4u32)
    put(t, .Selection, 0xD0BCFFu32)
    put(t, .TextSelection, 0xD0BCFFu32)
    put(t, .SurfaceDim, 0xDED8E1u32)
    put(t, .SurfaceBright, 0xFEF7FFu32)
    put(t, .SurfaceContainerLowest, 0xFFFFFFu32)
    put(t, .SurfaceContainerLow, 0xF7F2FAu32)
    put(t, .SurfaceContainer, 0xF3EDF7u32)
    put(t, .SurfaceContainerHigh, 0xECE6F0u32)
    put(t, .SurfaceContainerHighest, 0xE6E0E9u32)
    put(t, .InverseSurface, 0x322F35u32)
    put(t, .InverseOnSurface, 0xF5EFF7u32)
    put(t, .InversePrimary, 0xD0BCFFu32)
}

fn material_fill_dark(t: *ThemeTokens) {
    put(t, .Background, 0x141218u32)
    put(t, .Surface, 0x141218u32)
    put(t, .SurfaceVariant, 0x49454Fu32)
    put(t, .Primary, 0xD0BCFFu32)
    put(t, .OnPrimary, 0x381E72u32)
    put(t, .PrimaryContainer, 0x4F378Bu32)
    put(t, .OnPrimaryContainer, 0xEADDFFu32)
    put(t, .Secondary, 0xCCC2DCu32)
    put(t, .OnSecondary, 0x332D41u32)
    put(t, .SecondaryContainer, 0x4A4458u32)
    put(t, .OnSecondaryContainer, 0xE8DEF8u32)
    put(t, .Tertiary, 0xEFB8C8u32)
    put(t, .OnTertiary, 0x492532u32)
    put(t, .TertiaryContainer, 0x633B48u32)
    put(t, .OnTertiaryContainer, 0xFFD8E4u32)
    put(t, .Error, 0xF2B8B5u32)
    put(t, .OnError, 0x601410u32)
    put(t, .ErrorContainer, 0x8C1D18u32)
    put(t, .OnErrorContainer, 0xF9DEDCu32)
    put(t, .Text, 0xE6E0E9u32)
    put(t, .OnSurface, 0xE6E0E9u32)
    put(t, .TextMuted, 0xCAC4D0u32)
    put(t, .OnSurfaceVariant, 0xCAC4D0u32)
    put(t, .Border, 0x938F99u32)
    put(t, .Outline, 0x938F99u32)
    put(t, .OutlineVariant, 0x49454Fu32)
    put(t, .Focus, 0xD0BCFFu32)
    put(t, .FocusRing, 0xD0BCFFu32)
    put(t, .Selection, 0x4F378Bu32)
    put(t, .TextSelection, 0x4F378Bu32)
    put(t, .SurfaceDim, 0x141218u32)
    put(t, .SurfaceBright, 0x3B383Eu32)
    put(t, .SurfaceContainerLowest, 0x0F0D13u32)
    put(t, .SurfaceContainerLow, 0x1D1B20u32)
    put(t, .SurfaceContainer, 0x211F26u32)
    put(t, .SurfaceContainerHigh, 0x2B2930u32)
    put(t, .SurfaceContainerHighest, 0x36343Bu32)
    put(t, .InverseSurface, 0xE6E0E9u32)
    put(t, .InverseOnSurface, 0x322F35u32)
    put(t, .InversePrimary, 0x6750A4u32)
}

fn material(palette: Palette) -> ThemeTokens {
    var t = reference(palette)
    t.profile = .MaterialLike
    if palette == .Light { material_fill_light(&t) }
    if palette == .Dark { material_fill_dark(&t) }
    // The M3 type scale's Medium (500) styles; Neper draws them at 600.
    var i = 0usize
    while i < 21usize {
        if t.text[i].weight == 600u16 { t.text[i].weight = 500u16 }
        i += 1usize
    }
    // Phone metrics: 40 dp controls, 48 dp targets, a 4 dp grid, no focus ring.
    t.metrics = Metrics { hit_target: 48.0, control_height: 40.0, density: 1.0, focus_ring: 0.0, focus_offset: 0.0 }
    ret t
}
// ---- end Android look ---------------------------------------------------------------------------

// ---- Linux look (docs/ui/looks, profile Linux) ---------------------------------------------------
// GNOME as libadwaita 1.5 / GTK 4.14 draws it, measured by rendering the real library headlessly
// (docs/ui/looks/ref/linux/adwaita-tokens.md, scripts/linux). Colours are the named libadwaita
// colours: window #fafafa / #242424, view #ffffff / #1e1e1e, header bar #ffffff / #303030, card
// #ffffff / white 8 %, accent_bg #3584e4 (accent_color #1c71d8 / #78aeed for text and rings),
// destructive_bg #e01b24 / #c01c28, text black 80 % / white. Metrics: 34 high controls, radius 6,
// focus ring 2 px, drawn by each control inside its own edge (GTK's offset -2), so the runtime's
// ring is off. Font: Cantarell 11 pt (14.67 px), regular and bold (looks.e registers them from
// docs/ui/looks/ref/linux/fonts). Only Light and Dark exist; the contrast palettes keep the
// Neper colours with these metrics.
fn adwaita_fill_light(t: *ThemeTokens) {
    put(t, .Background, 0xFAFAFAu32)
    put(t, .Surface, 0xFFFFFFu32)
    put(t, .SurfaceVariant, 0xEBEBEBu32)
    put(t, .Primary, 0x3584E4u32)
    put(t, .OnPrimary, 0xFFFFFFu32)
    put(t, .Secondary, 0x1C71D8u32)
    put(t, .OnSecondary, 0xFFFFFFu32)
    puta(t, .Text, 0x000000u32, 0.8)
    puta(t, .OnSurface, 0x000000u32, 0.8)
    puta(t, .TextMuted, 0x000000u32, 0.55)
    puta(t, .OnSurfaceVariant, 0x000000u32, 0.55)
    puta(t, .Border, 0x000000u32, 0.12)
    puta(t, .Outline, 0x000000u32, 0.12)
    puta(t, .OutlineVariant, 0x000000u32, 0.07)
    put(t, .Focus, 0x1C71D8u32)
    puta(t, .FocusRing, 0x1C71D8u32, 0.5)
    put(t, .Error, 0xC01C28u32)
    put(t, .OnError, 0xFFFFFFu32)
    put(t, .ErrorContainer, 0xE01B24u32)
    put(t, .OnErrorContainer, 0xFFFFFFu32)
    put(t, .Success, 0x1B8553u32)
    put(t, .OnSuccess, 0xFFFFFFu32)
    put(t, .SuccessContainer, 0x2EC27Eu32)
    put(t, .OnSuccessContainer, 0xFFFFFFu32)
    put(t, .Warning, 0x9C6E03u32)
    put(t, .OnWarning, 0xFFFFFFu32)
    put(t, .WarningContainer, 0xE5A50Au32)
    put(t, .OnWarningContainer, 0x000000u32)
    put(t, .Selection, 0xC2DAF7u32)
    put(t, .TextSelection, 0xC2DAF7u32)
    put(t, .SurfaceDim, 0xEBEBEBu32)
    put(t, .SurfaceBright, 0xFFFFFFu32)
    put(t, .SurfaceContainerLowest, 0xFFFFFFu32)
    put(t, .SurfaceContainerLow, 0xFAFAFAu32)
    put(t, .SurfaceContainer, 0xFFFFFFu32)
    put(t, .SurfaceContainerHigh, 0xFFFFFFu32)
    put(t, .SurfaceContainerHighest, 0xFAFAFAu32)
}

fn adwaita_fill_dark(t: *ThemeTokens) {
    put(t, .Background, 0x242424u32)
    put(t, .Surface, 0x1E1E1Eu32)
    put(t, .SurfaceVariant, 0x303030u32)
    put(t, .Primary, 0x3584E4u32)
    put(t, .OnPrimary, 0xFFFFFFu32)
    put(t, .Secondary, 0x78AEEDu32)
    put(t, .OnSecondary, 0x000000u32)
    put(t, .Text, 0xFFFFFFu32)
    put(t, .OnSurface, 0xFFFFFFu32)
    puta(t, .TextMuted, 0xFFFFFFu32, 0.55)
    puta(t, .OnSurfaceVariant, 0xFFFFFFu32, 0.55)
    puta(t, .Border, 0xFFFFFFu32, 0.15)
    puta(t, .Outline, 0xFFFFFFu32, 0.15)
    puta(t, .OutlineVariant, 0xFFFFFFu32, 0.08)
    put(t, .Focus, 0x78AEEDu32)
    puta(t, .FocusRing, 0x78AEEDu32, 0.5)
    put(t, .Error, 0xFF7B63u32)
    put(t, .OnError, 0x000000u32)
    put(t, .ErrorContainer, 0xC01C28u32)
    put(t, .OnErrorContainer, 0xFFFFFFu32)
    put(t, .Success, 0x8FF0A4u32)
    put(t, .OnSuccess, 0x000000u32)
    put(t, .SuccessContainer, 0x26A269u32)
    put(t, .OnSuccessContainer, 0xFFFFFFu32)
    put(t, .Warning, 0xF8E45Cu32)
    put(t, .OnWarning, 0x000000u32)
    put(t, .WarningContainer, 0xCD9309u32)
    put(t, .OnWarningContainer, 0x000000u32)
    put(t, .Selection, 0x253D59u32)
    put(t, .TextSelection, 0x253D59u32)
    put(t, .SurfaceDim, 0x303030u32)
    put(t, .SurfaceBright, 0x383838u32)
    put(t, .SurfaceContainerLowest, 0x1E1E1Eu32)
    put(t, .SurfaceContainerLow, 0x242424u32)
    put(t, .SurfaceContainer, 0x353535u32)
    put(t, .SurfaceContainerHigh, 0x303030u32)
    put(t, .SurfaceContainerHighest, 0x383838u32)
}

fn adwaita(palette: Palette) -> ThemeTokens {
    var t = reference(palette)
    t.profile = .Linux
    if palette == .Light { adwaita_fill_light(&t) }
    if palette == .Dark { adwaita_fill_dark(&t) }
    // Radii: check 4, button / entry 6 (GTK's 6 px), popover 12, dialog 18.
    t.radii = Radii { xs: 4.0, sm: 6.0, md: 6.0, lg: 12.0, xl: 18.0, full: 9999.0 }
    t.borders = Borders { hairline: 1.0, regular: 1.0, thick: 2.0 }
    // Text: Cantarell 11 pt = 14.67 px at weight 400 (buttons, labels, body), headings bold; .caption is 82 %.
    var i = 0usize
    while i < 21usize {
        if t.text[i].weight == 600u16 { t.text[i].weight = 400u16 }
        i += 1usize
    }
    let body = TextStyle { size: 14.667, line_height: 19.0, weight: 400u16, italic: false }
    let label_style = TextStyle { size: 14.667, line_height: 19.0, weight: 700u16, italic: false }
    t.text[0] = body
    t.text[4] = label_style
    t.text[17] = body
    t.text[18] = body
    t.text[19] = body
    t.text[1] = TextStyle { size: 12.0, line_height: 16.0, weight: 400u16, italic: false }
    t.text[5] = t.text[1]
    t.text[3] = TextStyle { size: 14.667, line_height: 19.0, weight: 700u16, italic: false }
    t.states = States { hover: 0.08, focus: 0.0, pressed: 0.16, dragged: 0.16, disabled_container: 0.12, disabled_content: 0.5, scrim: 0.5 }
    t.sizes = Sizes { control_xs: 24.0, control_sm: 28.0, control_md: 34.0, control_lg: 40.0, control_xl: 50.0, target_touch: 44.0, target_pointer: 34.0, icon_xs: 12.0, icon_sm: 16.0, icon_md: 16.0, icon_lg: 32.0, divider: 1.0, outline_focused: 2.0 }
    // 34 high controls; the focus ring is drawn by the control inside its edge (offset -2), not by the runtime.
    t.metrics = Metrics { hit_target: 34.0, control_height: 34.0, density: 1.0, focus_ring: 0.0, focus_offset: 0.0 }
    ret t
}

// The accent colour for text and rings (libadwaita's accent_color), which differs from the accent_bg a
// suggested button fills with (`Primary`): #1c71d8 Light, #78aeed Dark.
fn adwaita_accent(t: *const ThemeTokens) -> paint.Color {
    if t.palette == .Dark { ret hex_raw(0x78AEEDu32) }
    ret hex_raw(0x1C71D8u32)
}

// The Linux button (libadwaita 1.5), measured on the live library: Tonal (and Outlined, Elevated, Container) is
// the default button, black 8 % over what it sits on (white 10 % Dark), 11.6 % hovered, 23.6 % pressed; Filled
// and Default are `suggested-action` (accent_bg #3584e4, white label, hover white 10 %, pressed black 19 %),
// Danger is `destructive-action` (#e01b24 Light, #c01c28 Dark); Plain is `flat`: no face until hovered
// (black 5.6 %, pressed 12.4 %). A disabled button is the whole thing at 50 % opacity. A keyboard-focused button
// wears a 2 px ring of the accent at 50 % inside its edge (the face's own colour on a coloured button, so none
// shows): `border` is that ring, 1.86 px wide (the measured coverage of the second pixel); the border is inside the
// padding box here, so the box does not grow. Corners 6, padding 5 10 (17 for a caption alone, set by the control),
// 34 high. The caption is 14.67 px Cantarell Bold: libadwaita draws button labels bold.
fn adwaita_resolve(t: *const ThemeTokens, variant: ControlVariant, state: ControlState) -> ResolvedControl {
    let dark = t.palette == .Dark
    let suggested = variant == .Filled || variant == .Default
    let destructive = variant == .Danger
    let flat = variant == .Plain
    var ink = color(t, .Text)
    var tint = paint.rgba(0.0, 0.0, 0.0, 1.0)
    var rest: f32 = 0.08
    var hover: f32 = 0.116
    var press: f32 = 0.236
    if dark {
        tint = paint.rgba(1.0, 1.0, 1.0, 1.0)
        rest = 0.096
        hover = 0.146
        press = 0.292
    }
    if flat {
        rest = 0.0
        hover = 0.056
        press = 0.124
        if dark {
            hover = 0.068
            press = 0.151
        }
    }
    var alpha = rest
    if state.hovered && !state.pressed { alpha = hover }
    if state.pressed || state.selected { alpha = press }
    var face = paint.Color { red: tint.red, green: tint.green, blue: tint.blue, alpha: alpha }
    if suggested || destructive {
        ink = hex_raw(0xFFFFFFu32)
        var base = 0x3584E4u32
        var up = 0x4990E7u32
        var down = 0x2B6AB7u32
        if destructive {
            base = 0xE01B24u32
            up = 0xE33039u32
            down = 0xB5161Du32
            if dark {
                base = 0xC01C28u32
                up = 0xC6313Cu32
                down = 0x9B1720u32
            }
        } else if dark {
            up = 0x4890E7u32
            down = 0x2B6BB8u32
        }
        face = hex_raw(base)
        if state.hovered && !state.pressed { face = hex_raw(up) }
        if state.pressed || state.selected { face = hex_raw(down) }
    }
    var ring = paint.rgba(0.0, 0.0, 0.0, 0.0)
    var stroke: f32 = 0.0
    if state.focus_visible && !state.disabled {
        // On a coloured button the ring is the face's own colour, so nothing shows: none is drawn.
        if !suggested && !destructive {
            ring = color(t, .FocusRing)
            stroke = 2.0
        }
    }
    var opacity: f32 = 1.0
    // `button.flat:disabled:not(:checked)` is `filter: opacity(0.3)`, every other button 0.5
    if state.disabled {
        opacity = 0.5
        if flat && !state.selected { opacity = 0.3 }
    }
    ret ResolvedControl { background: face, foreground: ink, border: ring, border_width: stroke, focus_ring: 0.0, opacity: opacity, radius: t.radii.sm, elevation: 0u8, padding: 10.0, padding_start: 0.0, padding_y: 7.5, custom_padding: true, min_width: 0.0, min_height: 34.0, corners: zero }
}
// A coloured Linux button (suggested-action, destructive-action) is two layers in GTK: its background colour, then a
// `background-image` wash (white 10 % hovered, black 20 % pressed), each antialiased on its own at the corners, so a corner pixel is
// not the pre-mixed face's. Answers whether the variant is coloured, the base colour and the wash (clear at rest).
fn adwaita_layers(t: *const ThemeTokens, variant: ControlVariant, state: ControlState) -> (bool, paint.Color, paint.Color) {
    let suggested = variant == .Filled || variant == .Default
    let destructive = variant == .Danger
    var base = hex_raw(0x3584E4u32)
    if destructive {
        base = hex_raw(0xE01B24u32)
        if t.palette == .Dark { base = hex_raw(0xC01C28u32) }
    }
    var wash = paint.rgba(0.0, 0.0, 0.0, 0.0)
    if state.hovered && !state.pressed { wash = paint.rgba(1.0, 1.0, 1.0, 0.1) }
    if state.pressed || state.selected { wash = paint.rgba(0.0, 0.0, 0.0, 0.2) }
    ret (suggested || destructive, base, wash)
}
// ---- end Linux look -----------------------------------------------------------------------------
// looks5: the hovered minimise or maximise button's wash over the dark caption (states/hover-caption-minimize-main, -maximize-main).
fn windows_caption_hot() -> paint.Color {
    if windark_on { ret hex_raw(0x3C3C3Cu32) }
    ret hex_raw(0x2C2D2Fu32)
}

// ---- round 10 (group d): the light caption of an inactive window, from the native Windows 11 capture
// (ref/windows-native/light/window-inactive: face #F3F3F3, title and glyphs about #939393; derived from the darkest ink pixels). v3
// showed no inactive light caption.
fn windows_caption_light_face_inactive() -> paint.Color {
    if windark_on { ret hex_raw(0x202020u32) }
    ret hex_raw(0xF3F3F3u32)
}
fn windows_caption_light_ink_inactive() -> paint.Color {
    if windark_on { ret hex_raw(0x787878u32) }
    ret hex_raw(0x939393u32)
}
