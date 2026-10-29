class_name Collapsible
extends VBoxContainer
## Section with a tappable header that shows/hides its content.
##
##   var sec := Collapsible.make(tr("Климат"), &"thermometer")
##   sec.content.add_child(ParamSlider.make(tr("Температура"), -10, 10, 0.5, 0, "°C"))
##   sec.expanded = false
##
## Signals: toggled(expanded: bool) — user taps only.

signal toggled(expanded: bool)

var title: String = "":
	set(v):
		title = v
		if _header != null:
			_header.text = v
var icon_name: StringName = &""
var expanded: bool = true:
	set(v):
		expanded = v
		_apply()

## Put section widgets here.
var content: VBoxContainer
var _header: IconButton
var _chevron: IconView


static func make(title_text: String, icon_id: StringName = &"", open: bool = true) -> Collapsible:
	var c := Collapsible.new()
	c.title = title_text
	c.icon_name = icon_id
	c.expanded = open
	return c


func _init() -> void:
	_header = IconButton.make(&"", "", "", &"FlatButton")
	_header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_header.pressed.connect(func() -> void:
		expanded = not expanded
		toggled.emit(expanded))
	add_child(_header)
	_chevron = IconView.make(&"chevron_down", 22.0, &"text_dim")
	_header.add_child(_chevron)
	content = VBoxContainer.new()
	add_child(content)


func _ready() -> void:
	_header.text = title
	_header.icon_name = icon_name
	_apply()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _header != null:
		var gap := UITheme.k(self, &"gap")
		content.add_theme_constant_override("separation", UITheme.k(self, &"gap_large"))
		add_theme_constant_override("separation", gap)
		_header.add_theme_font_override("font", UITheme.bold_font(self))
		_place_chevron.call_deferred()
	elif what == NOTIFICATION_RESIZED:
		_place_chevron.call_deferred()


func _place_chevron() -> void:
	if _chevron == null:
		return
	var sz := float(UITheme.k(self, &"icon"))
	_chevron.size = Vector2(sz, sz)
	_chevron.position = Vector2(_header.size.x - sz - UITheme.k(self, &"pad_small"), (_header.size.y - sz) * 0.5)


func _apply() -> void:
	if content == null:
		return
	content.visible = expanded
	_chevron.icon = &"chevron_up" if expanded else &"chevron_down"
