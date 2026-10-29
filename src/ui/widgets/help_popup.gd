class_name HelpPopup
extends RefCounted
## Explains a term in a small dialog (text from `Glossary`), with tappable
## related terms. Any UI can use it; HelpButton is the usual (?) trigger.
##
##   HelpPopup.show_term("аллель")
##   HelpPopup.show_text(tr("Скорость времени"), tr("×1 — сутки длятся 24 минуты..."))


## Opens the glossary entry for `term` (or a fallback text if unknown).
static func show_term(term: String, host: Node = null) -> ModalDialog:
	var e := Glossary.lookup(term)
	if e.is_empty():
		return show_text(Glossary.display(term), TranslationServer.translate("Описание пока не добавлено."), host)
	var d := ModalDialog.create(str(e["title"]), str(e["text"]), &"help", ModalDialog.SizeClass.SMALL)
	var see: Array = e["see"]
	if not see.is_empty():
		var cap := Label.new()
		cap.theme_type_variation = &"CaptionLabel"
		cap.text = TranslationServer.translate("См. также")
		d.content.add_child(cap)
		var flow := HFlowContainer.new()
		for s in see:
			var term_s := str(s)
			if not Glossary.has(term_s):
				continue
			var chip := IconButton.make(&"", Glossary.display(term_s), "", &"ChipButton")
			chip.pressed.connect(func() -> void:
				var h := d.get_parent()
				d.close(&"link")
				show_term(term_s, h))
			flow.add_child(chip)
		d.content.add_child(flow)
	d.add_button(&"ok", TranslationServer.translate("Понятно"), &"AccentButton")
	return d.open(host)


static func show_text(title: String, text: String, host: Node = null) -> ModalDialog:
	var d := ModalDialog.create(title, text, &"info", ModalDialog.SizeClass.SMALL)
	d.add_button(&"ok", TranslationServer.translate("Понятно"), &"AccentButton")
	return d.open(host)
