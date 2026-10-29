class_name HelpButton
extends IconButton
## Small (?) button that opens the glossary explanation of `term`.
##
##   row.add_child(HelpButton.for_term("число фруда"))

@export var term: String = ""


static func for_term(term_text: String) -> HelpButton:
	var b := HelpButton.new()
	b.term = term_text
	b.icon_name = &"help"
	b.theme_type_variation = &"FlatButton"
	b.tooltip_text = TranslationServer.translate("Что это?")
	return b


func _ready() -> void:
	super()
	pressed.connect(func() -> void:
		if term != "":
			HelpPopup.show_term(term))


func _update_layout() -> void:
	super()
	var t := UITheme.k(self, &"touch")
	custom_minimum_size = Vector2(t, t)
	icon_scale = 0.9
