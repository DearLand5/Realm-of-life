class_name UIThemeBuilder
extends RefCounted
## Internal: assembles the Theme for `UITheme.build()`. Use UITheme instead.
##
## Every interactive control reaches the touch-target height (52 px × scale)
## through its StyleBox content margins, so even plain Buttons/LineEdits made
## by other code are finger-sized without custom_minimum_size.

var s: float = 1.0
var ts: float = 1.0
var hc: bool = false
var cb: StringName = &"none"
var c: Dictionary = {}
var t: Theme
var font: Font
var bold: Font
var fs: Dictionary = {}
var touch: int = 52
var radius: float = 14.0
var line_h: float = 26.0
var pad_v: float = 13.0


func _init(ui_scale: float, text_scale: float, high_contrast: bool, colorblind: StringName) -> void:
	s = clampf(ui_scale, 0.5, 3.0)
	ts = clampf(text_scale, 0.6, 2.5)
	hc = high_contrast
	cb = UIPalette.normalize_mode(colorblind)
	c = UIPalette.tokens(hc)


func build() -> Theme:
	t = Theme.new()
	font = ThemeDB.fallback_font
	var fv := FontVariation.new()
	fv.base_font = font
	fv.variation_embolden = 0.6
	bold = fv
	var k := s * ts
	for key in UITheme.FONT_SIZES:
		fs[key] = maxi(9, int(round(float(UITheme.FONT_SIZES[key]) * k)))
	touch = px(UITheme.BASE_TOUCH)
	radius = 14.0 * s
	t.default_font = font
	t.default_font_size = fs["normal"]
	line_h = font.get_height(fs["normal"])
	pad_v = maxf(px(6), (touch - line_h) * 0.5)
	_tokens()
	_labels()
	_buttons()
	_inputs()
	_ranges()
	_toggles()
	_popups()
	_panels()
	_tabs()
	_lists()
	_scroll()
	return t


func px(v: float) -> int:
	return int(round(v * s))


func flat(bg: Color, rad: float = -1.0, border: Color = Color.TRANSPARENT, bw: float = 0.0) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.set_corner_radius_all(int(round(radius if rad < 0.0 else rad)))
	b.corner_detail = 8
	b.anti_aliasing = true
	var w := bw * (2.0 if hc else 1.0)
	if w > 0.0 and border.a > 0.0:
		b.border_color = border
		b.set_border_width_all(maxi(1, int(round(w * s))))
	return b


func padded(b: StyleBox, h: float, v: float) -> StyleBox:
	b.content_margin_left = h
	b.content_margin_right = h
	b.content_margin_top = v
	b.content_margin_bottom = v
	return b


func _focus(rad: float = -1.0) -> StyleBoxFlat:
	var f := flat(Color.TRANSPARENT, rad, c["focus"], 2.0)
	f.draw_center = false
	f.set_expand_margin_all(px(2))
	return f


func _tokens() -> void:
	var T := UITheme.TYPE
	for key in c:
		t.set_color(key, T, c[key])
	var st := UIPalette.status(cb)
	for key in st:
		t.set_color(key, T, st[key])
	var series := UIPalette.series(cb)
	for i in series.size():
		t.set_color("series_%d" % i, T, series[i])
	t.set_constant("touch", T, touch)
	t.set_constant("gap", T, px(8))
	t.set_constant("gap_large", T, px(14))
	t.set_constant("pad", T, px(16))
	t.set_constant("pad_small", T, px(10))
	t.set_constant("radius", T, px(14))
	t.set_constant("radius_large", T, px(22))
	t.set_constant("icon", T, px(24))
	t.set_constant("icon_large", T, px(32))
	t.set_constant("scale_pct", T, int(round(s * 100.0)))
	t.set_constant("text_scale_pct", T, int(round(ts * 100.0)))
	t.set_constant("high_contrast", T, 1 if hc else 0)
	for key in fs:
		t.set_font_size(key, T, fs[key])
	t.set_font("bold", T, bold)
	t.set_font("regular", T, font)


func _label_variant(name: StringName, size_key: String, col: Color, use_bold: bool = false) -> void:
	t.set_type_variation(name, &"Label")
	t.set_font_size("font_size", name, fs[size_key])
	t.set_color("font_color", name, col)
	if use_bold:
		t.set_font("font", name, bold)


func _labels() -> void:
	t.set_color("font_color", "Label", c["text"])
	t.set_constant("line_spacing", "Label", px(2))
	_label_variant(&"TitleLabel", "huge", c["text"], true)
	_label_variant(&"HeaderLabel", "large", c["text"], true)
	_label_variant(&"SubheaderLabel", "normal", c["text"], true)
	_label_variant(&"DimLabel", "small", c["text_dim"])
	_label_variant(&"CaptionLabel", "tiny", c["text_faint"])
	_label_variant(&"AccentLabel", "normal", c["accent"], true)
	_label_variant(&"ValueLabel", "normal", c["text"], true)
	t.set_color("default_color", "RichTextLabel", c["text"])
	t.set_font("bold_font", "RichTextLabel", bold)
	for key in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]:
		t.set_font_size(key, "RichTextLabel", fs["normal"])
	var sep := StyleBoxLine.new()
	sep.color = c["border"]
	sep.thickness = maxi(1, px(1))
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", px(12))
	var vsep := StyleBoxLine.new()
	vsep.color = c["border"]
	vsep.thickness = maxi(1, px(1))
	vsep.vertical = true
	t.set_stylebox("separator", "VSeparator", vsep)
	t.set_constant("separation", "VSeparator", px(12))


## Sets the five Button styleboxes + text/icon colours for `type`.
func _button_type(type: StringName, bg: Color, bg_hover: Color, bg_pressed: Color, fg: Color, fg_pressed: Color,
		border: Color, pressed_border: Color, rad: float = -1.0, h_pad: float = 18.0) -> void:
	var hp := px(h_pad)
	t.set_stylebox("normal", type, padded(flat(bg, rad, border, 1.0), hp, pad_v))
	t.set_stylebox("hover", type, padded(flat(bg_hover, rad, c["border_strong"] if border.a > 0.0 else border, 1.0), hp, pad_v))
	t.set_stylebox("pressed", type, padded(flat(bg_pressed, rad, pressed_border, 1.5), hp, pad_v))
	t.set_stylebox("hover_pressed", type, padded(flat(bg_pressed.lightened(0.06), rad, pressed_border, 1.5), hp, pad_v))
	var dis_bg := bg
	dis_bg.a *= 0.45
	t.set_stylebox("disabled", type, padded(flat(dis_bg, rad), hp, pad_v))
	t.set_stylebox("focus", type, _focus(rad))
	for pair in [["font_color", fg], ["font_hover_color", fg], ["font_focus_color", fg], ["font_pressed_color", fg_pressed],
			["font_hover_pressed_color", fg_pressed], ["font_disabled_color", c["text_disabled"]],
			["icon_normal_color", fg], ["icon_hover_color", fg], ["icon_focus_color", fg], ["icon_pressed_color", fg_pressed],
			["icon_hover_pressed_color", fg_pressed], ["icon_disabled_color", c["text_disabled"]]]:
		t.set_color(pair[0], type, pair[1])
	t.set_constant("h_separation", type, px(10))


func _buttons() -> void:
	var sel: Color = c["surface"].lerp(c["accent"], 0.24)
	sel.a = 1.0
	_button_type(&"Button", c["surface"], c["surface_hover"], sel, c["text"], c["text"], c["border"], c["accent"])
	t.set_type_variation(&"AccentButton", &"Button")
	_button_type(&"AccentButton", c["accent"], c["accent_hover"], c["accent_pressed"], c["accent_text"], c["accent_text"],
		Color.TRANSPARENT, c["accent_pressed"])
	t.set_font("font", &"AccentButton", bold)
	t.set_type_variation(&"DangerButton", &"Button")
	_button_type(&"DangerButton", c["danger"], c["danger_hover"], c["danger"].darkened(0.15), c["danger_text"], c["danger_text"],
		Color.TRANSPARENT, c["danger"])
	var clear := Color(c["surface"], 0.0)
	var hover_soft := Color(c["surface_hover"], 0.7)
	t.set_type_variation(&"FlatButton", &"Button")
	_button_type(&"FlatButton", clear, hover_soft, c["accent_soft"], c["text"], c["accent"], Color.TRANSPARENT, Color.TRANSPARENT)
	t.set_type_variation(&"TabButton", &"Button")
	_button_type(&"TabButton", clear, hover_soft, c["accent_soft"], c["text_dim"], c["accent"], Color.TRANSPARENT,
		Color.TRANSPARENT, 12.0 * s, 10.0)
	t.set_type_variation(&"ChipButton", &"Button")
	_button_type(&"ChipButton", c["inset"], c["surface_hover"], c["accent_soft"], c["text_dim"], c["accent"], c["border"],
		c["accent"], touch * 0.5, 16.0)
	var hud := Color(c["panel"], minf(c["panel"].a, 0.72))
	t.set_type_variation(&"HudButton", &"Button")
	_button_type(&"HudButton", hud, c["surface_hover"], sel, c["text"], c["accent"], c["border"], c["accent"], touch * 0.5, 14.0)


func _inputs() -> void:
	var hp := px(14)
	t.set_stylebox("normal", "LineEdit", padded(flat(c["inset"], 12.0 * s, c["border"], 1.0), hp, pad_v))
	t.set_stylebox("focus", "LineEdit", padded(flat(Color.TRANSPARENT, 12.0 * s, c["accent"], 2.0), hp, pad_v))
	(t.get_stylebox("focus", "LineEdit") as StyleBoxFlat).draw_center = false
	t.set_stylebox("read_only", "LineEdit", padded(flat(Color(c["inset"], 0.35), 12.0 * s), hp, pad_v))
	var sel: Color = c["accent"]
	sel.a = 0.35
	for pair in [["font_color", c["text"]], ["font_selected_color", c["text"]], ["font_uneditable_color", c["text_dim"]],
			["font_placeholder_color", c["text_faint"]], ["caret_color", c["accent"]], ["selection_color", sel],
			["clear_button_color", c["text_dim"]], ["clear_button_color_pressed", c["accent"]]]:
		t.set_color(pair[0], "LineEdit", pair[1])
	t.set_constant("caret_width", "LineEdit", maxi(2, px(2)))
	t.set_constant("minimum_character_width", "LineEdit", 3)
	t.set_icon("clear", "LineEdit", ShapeTexture.make(ShapeTexture.Kind.CLOSE, Vector2i(px(22), px(22)), Color.WHITE))
	t.set_stylebox("normal", "TextEdit", t.get_stylebox("normal", "LineEdit"))
	t.set_stylebox("focus", "TextEdit", t.get_stylebox("focus", "LineEdit"))
	t.set_color("font_color", "TextEdit", c["text"])
	t.set_color("caret_color", "TextEdit", c["accent"])
	t.set_color("selection_color", "TextEdit", sel)


func _ranges() -> void:
	var full := 100.0 * s
	var track := flat(c["track"], full)
	padded(track, 0, px(3))
	var area := flat(c["accent"], full)
	padded(area, 0, px(3))
	var area_hi := flat(c["accent_hover"], full)
	padded(area_hi, 0, px(3))
	var gs := Vector2i(px(30), px(30))
	var knob := Color("#f4fbf8") if not hc else Color.WHITE
	for type in ["HSlider", "VSlider"]:
		t.set_stylebox("slider", type, track)
		t.set_stylebox("grabber_area", type, area)
		t.set_stylebox("grabber_area_highlight", type, area_hi)
		t.set_icon("grabber", type, ShapeTexture.make(ShapeTexture.Kind.GRABBER, gs, knob, c["accent"], c["accent"], 2.0))
		t.set_icon("grabber_highlight", type, ShapeTexture.make(ShapeTexture.Kind.GRABBER, gs, knob, c["accent_pressed"], c["accent_hover"], 3.0))
		t.set_icon("grabber_disabled", type, ShapeTexture.make(ShapeTexture.Kind.GRABBER, gs, c["track"], c["text_disabled"]))
		t.set_icon("tick", type, ShapeTexture.make(ShapeTexture.Kind.RADIO_ON, Vector2i(px(6), px(6)), c["text_faint"], c["text_faint"]))
	var bg := padded(flat(c["inset"], full, c["border"], 1.0), 0, px(5))
	var fill := padded(flat(c["accent"], full), 0, px(5))
	t.set_stylebox("background", "ProgressBar", bg)
	t.set_stylebox("fill", "ProgressBar", fill)
	t.set_color("font_color", "ProgressBar", c["text"])
	t.set_font_size("font_size", "ProgressBar", fs["small"])


func _toggles() -> void:
	var empty := padded(flat(Color.TRANSPARENT), px(4), pad_v)
	var hover := padded(flat(Color(c["surface_hover"], 0.35), 12.0 * s), px(4), pad_v)
	var sw := Vector2i(px(54), px(32))
	var cbx := Vector2i(px(28), px(28))
	var on := ShapeTexture.make(ShapeTexture.Kind.SWITCH_ON, sw, c["accent"], c["accent_text"] if hc else Color("#f4fbf8"))
	var off := ShapeTexture.make(ShapeTexture.Kind.SWITCH_OFF, sw, c["track"], c["text_dim"], c["border"], 1.0)
	var on_d := ShapeTexture.make(ShapeTexture.Kind.SWITCH_ON, sw, Color(c["accent"], 0.35), Color(1, 1, 1, 0.5))
	var off_d := ShapeTexture.make(ShapeTexture.Kind.SWITCH_OFF, sw, Color(c["track"], 0.4), Color(c["text_dim"], 0.4))
	var chk := ShapeTexture.make(ShapeTexture.Kind.CHECK_ON, cbx, c["accent"], c["accent_text"])
	var unchk := ShapeTexture.make(ShapeTexture.Kind.CHECK_OFF, cbx, c["inset"], c["text"], c["border_strong"], 1.5)
	var rad_on := ShapeTexture.make(ShapeTexture.Kind.RADIO_ON, cbx, c["inset"], c["accent"], c["accent"], 2.0)
	var rad_off := ShapeTexture.make(ShapeTexture.Kind.RADIO_OFF, cbx, c["inset"], c["text"], c["border_strong"], 1.5)
	for type in ["CheckButton", "CheckBox"]:
		for st in ["normal", "pressed", "disabled"]:
			t.set_stylebox(st, type, empty)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("hover_pressed", type, hover)
		t.set_stylebox("focus", type, _focus(12.0 * s))
		for pair in [["font_color", c["text"]], ["font_pressed_color", c["text"]], ["font_hover_color", c["text"]],
				["font_hover_pressed_color", c["text"]], ["font_focus_color", c["text"]], ["font_disabled_color", c["text_disabled"]]]:
			t.set_color(pair[0], type, pair[1])
		t.set_constant("h_separation", type, px(12))
	for suffix in ["", "_mirrored"]:
		t.set_icon("checked" + suffix, "CheckButton", on)
		t.set_icon("unchecked" + suffix, "CheckButton", off)
		t.set_icon("checked_disabled" + suffix, "CheckButton", on_d)
		t.set_icon("unchecked_disabled" + suffix, "CheckButton", off_d)
	for pair in [["checked", chk], ["unchecked", unchk], ["checked_disabled", chk], ["unchecked_disabled", unchk],
			["radio_checked", rad_on], ["radio_unchecked", rad_off], ["radio_checked_disabled", rad_on], ["radio_unchecked_disabled", rad_off]]:
		t.set_icon(pair[0], "CheckBox", pair[1])


func _popups() -> void:
	# OptionButton = Button look + arrow.
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		var b: StyleBox = t.get_stylebox(st, "Button").duplicate()
		if b is StyleBoxFlat and st != "focus":
			(b as StyleBoxFlat).content_margin_right = px(40)
		t.set_stylebox(st, "OptionButton", b)
		if st != "focus":
			t.set_stylebox(st + "_mirrored", "OptionButton", b)
	for pair in [["font_color", c["text"]], ["font_hover_color", c["text"]], ["font_pressed_color", c["accent"]],
			["font_hover_pressed_color", c["accent"]], ["font_focus_color", c["text"]], ["font_disabled_color", c["text_disabled"]]]:
		t.set_color(pair[0], "OptionButton", pair[1])
	t.set_icon("arrow", "OptionButton", ShapeTexture.make(ShapeTexture.Kind.ARROW_DOWN, Vector2i(px(22), px(22)), c["text_dim"]))
	t.set_constant("arrow_margin", "OptionButton", px(14))
	t.set_constant("h_separation", "OptionButton", px(10))
	# PopupMenu: finger-sized rows.
	var panel := padded(flat(c["panel_strong"], 16.0 * s, c["border_strong"], 1.0), px(8), px(8))
	_shadow(panel, 18.0)
	t.set_stylebox("panel", "PopupMenu", panel)
	t.set_stylebox("hover", "PopupMenu", flat(c["accent_soft"], 10.0 * s))
	var sep := StyleBoxLine.new()
	sep.color = c["border"]
	sep.thickness = maxi(1, px(1))
	t.set_stylebox("separator", "PopupMenu", sep)
	t.set_stylebox("labeled_separator_left", "PopupMenu", sep)
	t.set_stylebox("labeled_separator_right", "PopupMenu", sep)
	for pair in [["font_color", c["text"]], ["font_hover_color", c["text"]], ["font_disabled_color", c["text_disabled"]],
			["font_accelerator_color", c["text_faint"]], ["font_separator_color", c["text_dim"]]]:
		t.set_color(pair[0], "PopupMenu", pair[1])
	t.set_constant("v_separation", "PopupMenu", maxi(px(12), int(touch - line_h)))
	t.set_constant("h_separation", "PopupMenu", px(12))
	t.set_constant("item_start_padding", "PopupMenu", px(14))
	t.set_constant("item_end_padding", "PopupMenu", px(14))
	var ic := Vector2i(px(24), px(24))
	t.set_icon("checked", "PopupMenu", ShapeTexture.make(ShapeTexture.Kind.CHECK_ON, ic, c["accent"], c["accent_text"]))
	t.set_icon("unchecked", "PopupMenu", ShapeTexture.make(ShapeTexture.Kind.CHECK_OFF, ic, c["inset"], c["text"], c["border_strong"], 1.5))
	t.set_icon("radio_checked", "PopupMenu", ShapeTexture.make(ShapeTexture.Kind.RADIO_ON, ic, c["inset"], c["accent"], c["accent"], 2.0))
	t.set_icon("radio_unchecked", "PopupMenu", ShapeTexture.make(ShapeTexture.Kind.RADIO_OFF, ic, c["inset"], c["text"], c["border_strong"], 1.5))
	t.set_icon("submenu", "PopupMenu", ShapeTexture.make(ShapeTexture.Kind.ARROW_RIGHT, ic, c["text_dim"]))
	t.set_icon("submenu_mirrored", "PopupMenu", ShapeTexture.make(ShapeTexture.Kind.ARROW_RIGHT, ic, c["text_dim"]))
	# Tooltips.
	var tip := padded(flat(c["panel_strong"], 10.0 * s, c["border_strong"], 1.0), px(12), px(8))
	_shadow(tip, 10.0)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", c["text"])
	t.set_font_size("font_size", "TooltipLabel", fs["small"])
	t.set_stylebox("panel", "PopupPanel", panel)


func _shadow(b: StyleBoxFlat, size: float) -> void:
	if c["shadow"].a > 0.0:
		b.shadow_color = c["shadow"]
		b.shadow_size = px(size)
		b.shadow_offset = Vector2(0, px(size * 0.25))


func _panel_variant(name: StringName, base: StringName, box: StyleBox) -> void:
	t.set_type_variation(name, base)
	t.set_stylebox("panel", name, box)


func _panels() -> void:
	var p := px(16)
	t.set_stylebox("panel", "Panel", flat(c["panel"], 18.0 * s, c["border"], 1.0))
	t.set_stylebox("panel", "PanelContainer", padded(flat(c["panel"], 18.0 * s, c["border"], 1.0), p, p))
	_panel_variant(&"CardPanel", &"PanelContainer", padded(flat(c["card"], 16.0 * s, c["border"], 1.0), p, p))
	var dialog := padded(flat(c["panel_strong"], 22.0 * s, c["border_strong"], 1.0), px(20), px(18))
	_shadow(dialog, 28.0)
	_panel_variant(&"DialogPanel", &"PanelContainer", dialog)
	var toast := padded(flat(c["panel_strong"], 16.0 * s, c["border_strong"], 1.0), px(14), px(10))
	_shadow(toast, 16.0)
	_panel_variant(&"ToastPanel", &"PanelContainer", toast)
	_panel_variant(&"InsetPanel", &"PanelContainer", padded(flat(c["inset"], 12.0 * s), px(10), px(10)))
	var sheet := padded(flat(c["panel_strong"], 22.0 * s, c["border_strong"], 1.0), px(18), px(16))
	sheet.corner_radius_bottom_left = 0
	sheet.corner_radius_bottom_right = 0
	_shadow(sheet, 24.0)
	_panel_variant(&"SheetPanel", &"PanelContainer", sheet)
	_panel_variant(&"HudPanel", &"PanelContainer", padded(flat(Color(c["panel"], minf(c["panel"].a, 0.78)), 16.0 * s, c["border"], 1.0), px(10), px(8)))
	_panel_variant(&"BadgePanel", &"PanelContainer", padded(flat(c["accent"], 100.0 * s), px(7), px(1)))
	_panel_variant(&"ClearPanel", &"PanelContainer", StyleBoxEmpty.new())
	var win := flat(c["panel_strong"], 18.0 * s, c["border_strong"], 1.0)
	t.set_stylebox("panel", "AcceptDialog", padded(win, p, p))
	t.set_stylebox("embedded_border", "Window", win)
	t.set_stylebox("embedded_unfocused_border", "Window", win)
	t.set_color("title_color", "Window", c["text"])


func _tabs() -> void:
	var hp := px(18)
	var sel := padded(flat(c["accent_soft"], 12.0 * s), hp, pad_v)
	sel.border_color = c["accent"]
	sel.border_width_bottom = maxi(2, px(3))
	var unsel := padded(flat(Color.TRANSPARENT, 12.0 * s), hp, pad_v)
	var hov := padded(flat(Color(c["surface_hover"], 0.6), 12.0 * s), hp, pad_v)
	for type in ["TabBar", "TabContainer"]:
		t.set_stylebox("tab_selected", type, sel)
		t.set_stylebox("tab_unselected", type, unsel)
		t.set_stylebox("tab_hovered", type, hov)
		t.set_stylebox("tab_disabled", type, unsel)
		t.set_stylebox("tab_focus", type, _focus(12.0 * s))
		for pair in [["font_selected_color", c["text"]], ["font_unselected_color", c["text_dim"]],
				["font_hovered_color", c["text"]], ["font_disabled_color", c["text_disabled"]],
				["icon_selected_color", c["accent"]], ["icon_unselected_color", c["text_dim"]],
				["icon_hovered_color", c["text"]], ["icon_disabled_color", c["text_disabled"]], ["drop_mark_color", c["accent"]]]:
			t.set_color(pair[0], type, pair[1])
	t.set_constant("h_separation", "TabBar", px(10))
	t.set_stylebox("panel", "TabContainer", padded(flat(c["panel"], 16.0 * s, c["border"], 1.0), px(14), px(14)))
	t.set_stylebox("tabbar_background", "TabContainer", StyleBoxEmpty.new())
	t.set_constant("icon_separation", "TabContainer", px(10))


func _lists() -> void:
	var rad := 10.0 * s
	t.set_stylebox("panel", "ItemList", padded(flat(c["inset"], 12.0 * s), px(8), px(8)))
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	var sel := flat(c["accent_soft"], rad)
	var hov := flat(Color(c["surface_hover"], 0.6), rad)
	for st in ["selected", "selected_focus", "hovered_selected", "hovered_selected_focus"]:
		t.set_stylebox(st, "ItemList", sel)
	t.set_stylebox("hovered", "ItemList", hov)
	t.set_stylebox("cursor", "ItemList", _focus(rad))
	t.set_stylebox("cursor_unfocused", "ItemList", StyleBoxEmpty.new())
	for pair in [["font_color", c["text"]], ["font_hovered_color", c["text"]], ["font_selected_color", c["text"]],
			["font_hovered_selected_color", c["text"]], ["guide_color", c["border"]]]:
		t.set_color(pair[0], "ItemList", pair[1])
	t.set_constant("v_separation", "ItemList", maxi(px(10), int(touch - line_h)))
	t.set_constant("h_separation", "ItemList", px(12))
	t.set_constant("icon_margin", "ItemList", px(10))
	t.set_stylebox("panel", "Tree", t.get_stylebox("panel", "ItemList"))
	t.set_stylebox("selected", "Tree", sel)
	t.set_stylebox("selected_focus", "Tree", sel)
	t.set_color("font_color", "Tree", c["text"])
	t.set_constant("v_separation", "Tree", px(12))


func _scroll() -> void:
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	t.set_stylebox("focus", "ScrollContainer", StyleBoxEmpty.new())
	var full := 100.0 * s
	var m := px(3)
	for type in ["VScrollBar", "HScrollBar"]:
		var track := flat(Color(c["inset"], 0.35), full)
		var grab := flat(Color(c["text_faint"], 0.55), full)
		var grab_hi := flat(c["text_dim"], full)
		var grab_pr := flat(c["accent"], full)
		for b in [track, grab, grab_hi, grab_pr]:
			if type == "VScrollBar":
				padded(b, m, m)
			else:
				padded(b, m, m)
		t.set_stylebox("scroll", type, track)
		t.set_stylebox("scroll_focus", type, track)
		t.set_stylebox("grabber", type, grab)
		t.set_stylebox("grabber_highlight", type, grab_hi)
		t.set_stylebox("grabber_pressed", type, grab_pr)
		for ic in ["increment", "increment_highlight", "increment_pressed", "decrement", "decrement_highlight", "decrement_pressed"]:
			t.set_icon(ic, type, ShapeTexture.make(ShapeTexture.Kind.BLANK, Vector2i(1, 1), Color.TRANSPARENT))
