class_name UITheme
extends RefCounted
## App-wide touch-first theme: dark translucent teal/green-charcoal panels,
## soft rounded corners, subtle borders, mint accent. Finger-sized by default
## (52 px touch targets at scale 1), with a high-contrast variant and
## colour-blind safe data palettes.
##
## Usage
##   UITheme.attach(my_root_control)      # applies now + re-applies on settings change
##   var t := UITheme.build(1.25, 1.0)    # explicit build (tests, previews)
##   UITheme.current()                    # cached theme for current Game settings
##
## Theme variations (set `theme_type_variation`):
##   Buttons:  AccentButton (primary), DangerButton, FlatButton, TabButton, ChipButton, HudButton
##   Labels:   TitleLabel, HeaderLabel, SubheaderLabel, DimLabel, CaptionLabel, AccentLabel, ValueLabel
##   Panels:   CardPanel, DialogPanel, ToastPanel, InsetPanel, SheetPanel, HudPanel, BadgePanel, ClearPanel
## Design tokens live in theme type `UITheme.TYPE` ("Realm"):
##   colours  = UIPalette.tokens() keys + good/warn/bad/info/neutral + series_0..7
##   constants: touch, gap, gap_large, pad, pad_small, radius, radius_large, icon, icon_large,
##              scale_pct, text_scale_pct, high_contrast
##   font sizes: tiny, small, normal, large, title, huge;  fonts: bold, regular
## Custom-drawn widgets read tokens with `UITheme.color(self, &"accent")` etc. and
## redraw on NOTIFICATION_THEME_CHANGED, so live re-theming needs no extra code.
##
## Settings used: Game.setting("ui_scale"), "text_scale", "colorblind_mode",
## "high_contrast" (bool; not in Game.DEFAULT_SETTINGS yet → false).

const TYPE := &"Realm"
const BASE_TOUCH := 52.0
## Physical size a touch target should reach on phones (Android/iOS guidance ≈ 7–9 mm).
const TARGET_TOUCH_MM := 7.5
const FONT_SIZES := {"tiny": 13, "small": 15, "normal": 18, "large": 23, "title": 30, "huge": 44}

static var _cache: Theme
static var _cache_key := ""


## Builds a fresh Theme. `ui_scale` scales sizes; fonts scale by ui_scale × text_scale.
static func build(ui_scale: float = 1.0, text_scale: float = 1.0, high_contrast: bool = false,
		colorblind: StringName = &"none") -> Theme:
	return UIThemeBuilder.new(ui_scale, text_scale, high_contrast, colorblind).build()


## Theme for the current settings (rebuilt only when they change).
static func current() -> Theme:
	var key := settings_key()
	if _cache == null or key != _cache_key:
		_cache_key = key
		_cache = build(ui_scale(), text_scale(), high_contrast(), colorblind_mode())
	return _cache


## Identifies the visual configuration; changes whenever a re-theme is needed.
static func settings_key() -> String:
	return "%.2f|%.2f|%s|%s" % [ui_scale(), text_scale(), high_contrast(), colorblind_mode()]


## Applies the current theme to `target` (Control or Window) and keeps it
## updated live. Returns the binder (child node of target).
static func attach(target: Node) -> ThemeBinder:
	for ch in target.get_children():
		if ch is ThemeBinder:
			(ch as ThemeBinder).refresh(true)
			return ch
	var b := ThemeBinder.new()
	b.name = "ThemeBinder"
	target.add_child(b, false, Node.INTERNAL_MODE_FRONT)
	b.refresh(true)
	return b


# --- Settings -------------------------------------------------------------------

static func setting(key: String, fallback: Variant) -> Variant:
	return UIApp.setting(key, fallback)


## Effective size scale: user setting × device factor (bigger on small phones).
static func ui_scale() -> float:
	return clampf(float(setting("ui_scale", 1.0)), 0.5, 2.5) * device_factor()


static func text_scale() -> float:
	return clampf(float(setting("text_scale", 1.0)), 0.6, 2.5)


static func high_contrast() -> bool:
	return bool(setting("high_contrast", false))


static func colorblind_mode() -> StringName:
	return UIPalette.normalize_mode(setting("colorblind_mode", "none"))


## On phones/tablets, enlarges the UI so a 52 px target is ≥ TARGET_TOUCH_MM
## physically. 1.0 on desktop and in headless runs.
static func device_factor() -> float:
	if not OS.has_feature("mobile"):
		return 1.0
	var dpi := DisplayServer.screen_get_dpi()
	var tree := Engine.get_main_loop() as SceneTree
	if dpi <= 0 or tree == null or tree.root == null:
		return 1.0
	var phys_per_px := absf(tree.root.get_final_transform().get_scale().x)
	var mm := BASE_TOUCH * phys_per_px / float(dpi) * 25.4
	return snappedf(clampf(TARGET_TOUCH_MM / maxf(mm, 0.1), 1.0, 1.8), 0.05)


# --- Data palettes ------------------------------------------------------------------

## Chart series colours for `mode` (null = current colour-blind setting).
static func palette(mode: Variant = null) -> PackedColorArray:
	return UIPalette.series(colorblind_mode() if mode == null else mode)


## {good, warn, bad, info, neutral} for `mode` (null = current setting).
static func status_colors(mode: Variant = null) -> Dictionary:
	return UIPalette.status(colorblind_mode() if mode == null else mode)


# --- Token access for custom widgets -------------------------------------------------

## Size scale baked into the control's theme (1.0 without our theme).
static func scale_of(c: Control) -> float:
	var v := c.get_theme_constant(&"scale_pct", TYPE)
	return float(v) / 100.0 if v > 0 else 1.0


## Design constant (touch, gap, pad, radius, icon...) with an unscaled fallback.
static func k(c: Control, name: StringName) -> int:
	if c.has_theme_constant(name, TYPE):
		return c.get_theme_constant(name, TYPE)
	var defaults := {&"touch": 52, &"gap": 8, &"gap_large": 14, &"pad": 16, &"pad_small": 10, &"radius": 14,
		&"radius_large": 22, &"icon": 24, &"icon_large": 32}
	return int(defaults.get(name, 0))


static func color(c: Control, name: StringName) -> Color:
	if c.has_theme_color(name, TYPE):
		return c.get_theme_color(name, TYPE)
	var tok := UIPalette.tokens(false)
	if tok.has(String(name)):
		return tok[String(name)]
	var st := UIPalette.status(&"none")
	return st.get(String(name), Color.WHITE)


static func font_size(c: Control, name: StringName) -> int:
	if c.has_theme_font_size(name, TYPE):
		return c.get_theme_font_size(name, TYPE)
	return int(FONT_SIZES.get(String(name), 18))


static func bold_font(c: Control) -> Font:
	if c.has_theme_font(&"bold", TYPE):
		return c.get_theme_font(&"bold", TYPE)
	return c.get_theme_default_font()


## Series colour i from the control's theme (follows colour-blind mode).
static func series(c: Control, i: int) -> Color:
	var key := StringName("series_%d" % posmod(i, 8))
	if c.has_theme_color(key, TYPE):
		return c.get_theme_color(key, TYPE)
	return UIPalette.series_color(i, colorblind_mode())


## Sets a theme constant override only when it changes. Overriding re-sends
## NOTIFICATION_THEME_CHANGED synchronously, so widgets that restyle themselves
## in that notification must use this to avoid infinite recursion.
static func override_const(c: Control, name: StringName, v: int) -> void:
	if not c.has_theme_constant_override(name) or c.get_theme_constant(name) != v:
		c.add_theme_constant_override(name, v)
