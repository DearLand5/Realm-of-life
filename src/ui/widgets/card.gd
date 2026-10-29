class_name Card
extends PanelContainer
## Rounded panel with an optional header (icon, title, subtitle, actions) and a
## content column.
##
##   var c := Card.make(tr("Популяция"), &"chart", tr("последние 30 дней"))
##   c.content.add_child(chart)
##   c.add_action(IconButton.make(&"settings", "", tr("Настроить"), &"FlatButton"))

var title: String = ""
var subtitle: String = ""
var icon_name: StringName = &""
## Card body (VBox).
var content: VBoxContainer
## Header row (hidden when there is no title/icon/action).
var header: HBoxContainer

var _title: Label
var _subtitle: Label
var _actions: HBoxContainer


static func make(title_text: String = "", icon_id: StringName = &"", subtitle_text: String = "", variation: StringName = &"CardPanel") -> Card:
	var c := Card.new()
	c.title = title_text
	c.icon_name = icon_id
	c.subtitle = subtitle_text
	c.theme_type_variation = variation
	return c


func _init() -> void:
	theme_type_variation = &"CardPanel"
	var v := VBoxContainer.new()
	add_child(v)
	header = HBoxContainer.new()
	v.add_child(header)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	titles.add_theme_constant_override("separation", 0)
	header.add_child(titles)
	_title = Label.new()
	_title.theme_type_variation = &"SubheaderLabel"
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle = Label.new()
	_subtitle.theme_type_variation = &"DimLabel"
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(_title)
	titles.add_child(_subtitle)
	_actions = HBoxContainer.new()
	header.add_child(_actions)
	content = VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(content)


func _ready() -> void:
	_title.text = title
	_subtitle.text = subtitle
	_subtitle.visible = subtitle != ""
	if icon_name != &"":
		var iv := IconView.make(icon_name, UITheme.k(self, &"icon_large"), &"accent")
		iv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		header.add_child(iv)
		header.move_child(iv, 0)
	_update_header()


func add_action(b: Control) -> void:
	_actions.add_child(b)
	_update_header()


func _update_header() -> void:
	header.visible = title != "" or icon_name != &"" or _actions.get_child_count() > 0
	_title.visible = title != ""


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and content != null:
		var gap := UITheme.k(self, &"gap_large")
		(get_child(0) as VBoxContainer).add_theme_constant_override("separation", gap)
		content.add_theme_constant_override("separation", UITheme.k(self, &"gap"))
		header.add_theme_constant_override("separation", UITheme.k(self, &"gap_large"))
