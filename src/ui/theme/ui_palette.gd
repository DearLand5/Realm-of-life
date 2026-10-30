class_name UIPalette
extends RefCounted
## Colour tokens of the Realm of Life UI and data-visualisation palettes.
##
##   * `tokens(high_contrast)` — semantic UI colours. UITheme exports them into
##     the theme as type `UITheme.TYPE` ("Realm"), so custom-drawn widgets read
##     them with `get_theme_color(&"accent", UITheme.TYPE)` and follow live
##     theme changes automatically;
##   * `series(mode)` — categorical chart colours (colour-blind safe variants);
##   * `status(mode)` — good / warn / bad / info / neutral indicator colours.
##
## Colour is never the only carrier of meaning: toasts pair it with an icon,
## charts with a legend and the scrub read-out.

const MODES: Array[StringName] = [&"none", &"deuteranopia", &"protanopia", &"tritanopia"]
const MODE_LABELS := {
	&"none": "Обычное зрение",
	&"deuteranopia": "Дейтеранопия",
	&"protanopia": "Протанопия",
	&"tritanopia": "Тританопия",
}

# Nature-inspired categorical set: leaf, sky, sun, coral, lilac, moss, sand, ice.
const _SERIES_NONE := ["#5ed6a8", "#58b7f0", "#f2c063", "#f07a64", "#b48cf0", "#9ccc5a", "#e6a37a", "#7fd9e6"]
# Okabe & Ito (2008): distinguishable for deutan and protan vision. For
# protanopia, vermillion (seen dark) is moved back and sky blue leads.
const _SERIES_DEUTER := ["#56b4e9", "#e69f00", "#f0e442", "#009e73", "#cc79a7", "#0072b2", "#d55e00", "#bbbbbb"]
const _SERIES_PROTAN := ["#56b4e9", "#f0e442", "#e69f00", "#cc79a7", "#009e73", "#0072b2", "#bbbbbb", "#d55e00"]
# Paul Tol "vibrant": avoids the blue/green and yellow/pink pairs tritans confuse.
const _SERIES_TRITAN := ["#ee7733", "#33bbee", "#ee3377", "#009988", "#bbbbbb", "#cc3311", "#0077bb", "#f2c1d1"]

const _STATUS := {
	&"none": {"good": "#6fd68f", "warn": "#f2c063", "bad": "#f0705a", "info": "#58b7f0", "neutral": "#9db5af"},
	&"deuteranopia": {"good": "#56b4e9", "warn": "#f0e442", "bad": "#d55e00", "info": "#cc79a7", "neutral": "#bbbbbb"},
	&"protanopia": {"good": "#56b4e9", "warn": "#f0e442", "bad": "#e69f00", "info": "#cc79a7", "neutral": "#bbbbbb"},
	&"tritanopia": {"good": "#009988", "warn": "#ee7733", "bad": "#ee3377", "info": "#33bbee", "neutral": "#bbbbbb"},
}


## Semantic UI colours. Keys are stable API (widgets rely on them).
static func tokens(high_contrast: bool = false) -> Dictionary:
	if high_contrast:
		return {
			"bg": Color("#000000"), "bg_deep": Color("#000000"),
			"panel": Color("#050a0a"), "panel_strong": Color("#000000"), "card": Color("#0b1414"),
			"surface": Color("#122020"), "surface_hover": Color("#1d3434"), "surface_pressed": Color("#000000"),
			"inset": Color("#000000"), "border": Color("#cfe9e1"), "border_strong": Color("#ffffff"),
			"accent": Color("#ffe066"), "accent_hover": Color("#fff0a8"), "accent_pressed": Color("#e0bf3a"),
			"accent_text": Color("#000000"), "accent_soft": Color(1.0, 0.88, 0.4, 0.28),
			"highlight": Color("#ffe066"), "text": Color("#ffffff"), "text_dim": Color("#e6f2ee"),
			"text_faint": Color("#c4d6d1"), "text_disabled": Color("#8a9a96"),
			"danger": Color("#ff6b57"), "danger_hover": Color("#ff8f7f"), "danger_text": Color("#000000"),
			"shadow": Color(0, 0, 0, 0.0), "scrim": Color(0, 0, 0, 0.82), "focus": Color("#ffffff"),
			"track": Color("#3a4c4a"), "grid": Color(1, 1, 1, 0.28),
		}
	return {
		"bg": Color("#0d1c1e"), "bg_deep": Color("#071113"),
		"panel": Color(0.055, 0.105, 0.112, 0.90), "panel_strong": Color(0.045, 0.09, 0.095, 0.97),
		"card": Color(0.095, 0.165, 0.172, 0.92),
		"surface": Color(0.135, 0.215, 0.222, 0.96), "surface_hover": Color(0.17, 0.27, 0.275, 0.98),
		"surface_pressed": Color(0.085, 0.15, 0.158, 1.0),
		"inset": Color(0.03, 0.07, 0.075, 0.75),
		"border": Color(0.48, 0.70, 0.65, 0.20), "border_strong": Color(0.52, 0.78, 0.70, 0.45),
		"accent": Color("#5ed6a8"), "accent_hover": Color("#7fe4bc"), "accent_pressed": Color("#43b98d"),
		"accent_text": Color("#062019"), "accent_soft": Color(0.37, 0.84, 0.66, 0.18),
		"highlight": Color("#f2c063"), "text": Color("#e8f3ef"), "text_dim": Color("#a3bbb5"),
		"text_faint": Color("#728d87"), "text_disabled": Color("#566b67"),
		"danger": Color("#e8705c"), "danger_hover": Color("#f08a78"), "danger_text": Color("#2a0a05"),
		"shadow": Color(0.0, 0.02, 0.02, 0.45), "scrim": Color(0.01, 0.04, 0.045, 0.62),
		"focus": Color(0.55, 0.92, 0.78, 0.75),
		"track": Color(0.20, 0.30, 0.30, 0.9), "grid": Color(0.6, 0.8, 0.75, 0.10),
	}


static func normalize_mode(mode) -> StringName:
	var m := StringName(str(mode)) if mode != null else &"none"
	return m if MODES.has(m) else &"none"


## Categorical chart colours for a colour-vision mode (8 entries, cycle with `series_color`).
static func series(mode = &"none") -> PackedColorArray:
	var src: Array = _SERIES_NONE
	match normalize_mode(mode):
		&"deuteranopia": src = _SERIES_DEUTER
		&"protanopia": src = _SERIES_PROTAN
		&"tritanopia": src = _SERIES_TRITAN
	var out := PackedColorArray()
	for h in src:
		out.append(Color(str(h)))
	return out


static func series_color(index: int, mode = &"none") -> Color:
	var s := series(mode)
	return s[posmod(index, s.size())]


## {good, warn, bad, info, neutral} → Color.
static func status(mode = &"none") -> Dictionary:
	var src: Dictionary = _STATUS[normalize_mode(mode)]
	var out := {}
	for k in src:
		out[k] = Color(str(src[k]))
	return out
