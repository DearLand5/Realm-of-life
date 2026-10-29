class_name ThemeBinder
extends Node
## Keeps its parent (Control or Window) themed with `UITheme.current()` and
## re-applies it when ui_scale / text_scale / colorblind_mode / high_contrast
## change — whether they changed through `Game.set_setting` or anything else
## (cheap poll, 4×/s; there is no settings-changed signal in EventBus yet).
## Create with `UITheme.attach(node)`.

## Emitted after a (re)theme was applied.
signal theme_applied(theme: Theme)

const POLL_INTERVAL := 0.25

var _key := ""
var _t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	refresh(true)


func _process(delta: float) -> void:
	_t += delta
	if _t < POLL_INTERVAL:
		return
	_t = 0.0
	refresh()


## Re-applies the theme if settings changed (or always with `force`).
func refresh(force: bool = false) -> void:
	var key := UITheme.settings_key()
	if not force and key == _key:
		return
	_key = key
	var theme := UITheme.current()
	var p := get_parent()
	if p is Control:
		(p as Control).theme = theme
	elif p is Window:
		(p as Window).theme = theme
	theme_applied.emit(theme)
