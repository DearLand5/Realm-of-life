class_name TutorialSteps
extends RefCounted
## Interactive tutorial content (data only). Each step completes when its
## `event` fires (TutorialManager listens to EventBus / scene hooks).
## scene: &"editor" | &"world"

const STEPS := [
	{"id": &"create", "scene": &"editor", "title": "1. Простой организм",
		"body": "Выберите пресет или начните с туловища. Перетаскивайте точки формы и меняйте длину, толщину и изгиб сегментов в панели параметров.",
		"event": &"editor_shape_changed"},
	{"id": &"limbs", "scene": &"editor", "title": "2. Конечности и органы чувств",
		"body": "В режиме «Конечности» добавьте ноги, плавники или крылья. В режиме «Чувства» — глаза, уши, усики. Симметрия включена по умолчанию.",
		"event": &"editor_part_added"},
	{"id": &"check", "scene": &"editor", "title": "3. Проверка выживания",
		"body": "Откройте «Диагностику»: она объясняет, сможет ли организм стоять, двигаться, дышать и питаться, и почему. Кнопка «Тест» запускает существо на полигоне.",
		"event": &"editor_diagnostics_opened"},
	{"id": &"metabolism", "scene": &"editor", "title": "4. Питание и обмен веществ",
		"body": "В режиме «Биология» выберите пищевую стратегию, теплокровность и скорость обмена. Крупное тело и теплокровность требуют больше пищи.",
		"event": &"editor_biology_changed"},
	{"id": &"save", "scene": &"editor", "title": "5. Сохранение вида",
		"body": "Нажмите «Сохранить»: вид попадёт в библиотеку и сможет переноситься между мирами.",
		"event": &"species_saved"},
	{"id": &"place", "scene": &"world", "title": "6. Заселение мира",
		"body": "Откройте инструменты песочницы и выберите «Заселить»: коснитесь участка мира, подходящего виду по климату.",
		"event": &"species_placed"},
	{"id": &"observe", "scene": &"world", "title": "7. Наблюдение",
		"body": "Коснитесь существа, чтобы увидеть его потребности, состояние и текущее поведение. Кнопки внизу карточки переключают вид от первого и третьего лица.",
		"event": &"creature_selected"},
	{"id": &"heredity", "scene": &"world", "title": "8. Размножение и наследование",
		"body": "Ускорьте время. В карточке особи откройте «Гены»: видно, какие аллели получены от родителей и какие признаки доминантны.",
		"event": &"creature_born"},
	{"id": &"evolution", "scene": &"world", "title": "9. Анализ эволюции",
		"body": "Откройте «Эволюцию»: графики численности и средних признаков, генеалогическое дерево и журнал мутаций показывают, как меняется вид поколение за поколением.",
		"event": &"evolution_opened"},
]


static func for_scene(scene: StringName) -> Array:
	var out := []
	for s in STEPS:
		if s["scene"] == scene:
			out.append(s)
	return out


static func index_of(id: StringName) -> int:
	for i in STEPS.size():
		if STEPS[i]["id"] == id:
			return i
	return -1
