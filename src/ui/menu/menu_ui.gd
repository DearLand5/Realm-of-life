class_name MenuUI
extends RefCounted
## Small builders shared by the menu dialogs (section headers, labelled fields).


## Section header: accent icon + bold title (with breathing room above).
static func section(title: String, icon_id: StringName = &"") -> HBoxContainer:
	var h := HBoxContainer.new()
	h.custom_minimum_size.y = 40
	UITheme.override_const(h, "separation", 10)
	if icon_id != &"":
		var iv := IconView.make(icon_id, 24.0, &"accent")
		iv.size_flags_vertical = Control.SIZE_SHRINK_END
		h.add_child(iv)
	var l := Label.new()
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	l.theme_type_variation = &"SubheaderLabel"
	l.text = title
	h.add_child(l)
	return h


## Caption above a control.
static func field(caption: String, control: Control) -> VBoxContainer:
	var v := VBoxContainer.new()
	UITheme.override_const(v, "separation", 4)
	var l := Label.new()
	l.text = caption
	v.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(control)
	return v


static func column() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.override_const(v, "separation", 14)
	return v


static func dim_label(text: String) -> Label:
	var l := Label.new()
	l.theme_type_variation = &"DimLabel"
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l
