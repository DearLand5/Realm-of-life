# CLAUDE.md — Realm of Life

3D-песочница жизни и эволюции (Godot 4, GDScript). Мобильные устройства (Android/iOS) — основная
платформа, ПК — вторичная. Подробная архитектура и контракты подсистем: `docs/ARCHITECTURE.md`.
Статус реализации: `docs/STATUS.md`.

## Движок и запуск

- Godot **4.4+** (проверено на 4.7.2). Рендерер `mobile` с откатом на `gl_compatibility`
  (`rendering_device/fallback_to_opengl3`). Все шейдеры обязаны работать в обоих рендерерах
  (никаких compute-шейдеров, `hint_screen_texture` только с проверкой).
- Бинарник в контейнере: `godot` (`/usr/local/bin/godot`).
- **После добавления/переименования `class_name`** обязательно: `tools/reimport.sh`
  (пересобирает `.godot/global_script_class_cache.cfg`, иначе классы «не найдены»).
- Тесты (headless): `tools/test.sh` или `tools/test.sh anatomy` (фильтр по имени файла).
  Тест = файл `tests/**/test_*.gd`, `extends TestCase`, методы `test_*`, проверки `check()/near()`.
- Скриншоты (программный рендер под Xvfb): `tools/shot.sh tools/<script>.gd -- <args>`;
  сохраняй в `res://screenshots/tmp/` (в .gitignore). Скрипт-инструмент `extends SceneTree`,
  ждёт `await process_frame`, затем `ShotUtil.save_viewport(get_root(), path)`.
  Камеру ставь ПОСЛЕ первого `await process_frame` через `look_at_from_position`.
- Vulkan в контейнере — только программный (lavapipe, пакет `mesa-vulkan-drivers`):
  `godot --rendering-driver vulkan --rendering-method mobile ...`; по умолчанию проверяй через OpenGL.
- Телефон в скриншотах: `SHOT_RES=1600x720 RL_DEVICE_FACTOR=1.1 tools/shot.sh ...` (20:9 и
  авто-увеличение UI, как на устройстве). UI обязан помещаться в 1280×720 и 1600×720 без наложений.
- Тела существ: `creature.gdshader` (детальный) и `creature_lite.gdshader` (облегчённый, по умолчанию
  на телефонах; настройка `creature_shading`). Новые эффекты покровов добавляй в оба.
- Иконки UI рисуются из растрового атласа (`IconAtlas`, строится один раз при старте); векторная
  отрисовка — только для атласа и `stroke != 1`. Не рисуй в `_draw()` каждый кадр сотни линий/дуг:
  на телефоне каждый вызов отрисовки дорог.
- Профиль нагрузки мира: `tools/shot.sh tools/profile_world.gd` (или `godot --headless ... -s`
  для чистого CPU). Экосистема/популяции шагают «по мере накопления времени» (`row_period`,
  `sector_period`), а не каждый кадр.
- Шум в шейдерах мира (`terrain_noise.gdshaderinc`) — выборки из бесшовных текстур `RlNoise`
  (а не хэши): новый материал с этим include обязан вызвать `RlNoise.bind(mat)`.
- Мобильные правила рендера: 3D ниже нативного разрешения + FSR, MSAA выкл./FXAA, один каскад
  теней, рельеф тени не отбрасывает, особи вне кадра не анимируются. Замер на устройстве:
  меню мира → «Тест производительности»; настройки → «Показывать FPS».
- На устройстве лог пишется в `user://logs/godot.log` (настройки → «Журнал», копирование); сбой при открытии редактора ловит
  `EditorCrashGuard` (следующее открытие — в облегчённом режиме). Сборку можно открыть сразу в
  редакторе: `game -- --rl-open=editor`.
- APK: `tools/export_android.sh` (шаблоны экспорта, Android SDK, ключ через
  `GODOT_ANDROID_KEYSTORE_RELEASE_*`) → `dist/RealmOfLife-<версия>.apk`. Ориентация — только альбомная.
- Скрипты, запускаемые через `godot -s`, компилируются ДО появления автозагрузок (`EventBus`, `Game`):
  делай их «тонкими запускателями», которые после первого кадра `load()`-ят настоящий код
  (пример: `tools/preview_world_hud.gd` → `tools/preview_world_hud_impl.gd`). В модельном коде
  вместо `EventBus` используй `Bus.emit()` (`src/core/bus.gd`), в UI-ките — `UIApp`.
- Сцены: `main_menu` → `creature_editor` / `world` / `test_arena` (переходы через `Game.goto_scene` с payload).
- Порядок интеграции мира: `src/sim/sim_world.gd` (+ `world_builder.gd`, `agent_manager.gd`, `hud/`).

## Структура

```
src/core/        EventBus (autoload), Game (autoload), Units, Rng, MathUtil, Serial, SpatialHash
src/anatomy/     plan/ (BodyPlan, BodyPart, BodySegment, CoveringDef, PartSchema, Presets)
                 compiler/ (AnatomyCompiler → AnatomyModel, AnatomySdf), mesh/ (меши), Phenotype, Diagnostics
src/genetics/    TraitCatalog, Genome, Genetics, BodyPlanMutator
src/biology/     PhysiologyProfile, Individual, BiologySystem, Reproduction
src/physics/     LocomotionProfile, движение, процедурная анимация/IK
src/skeleton/    построение Skeleton3D из AnatomyModel
src/muscle/      мышечные группы, усталость, «вздутие» мышц
src/ai/          SenseProfile, восприятие, память, utility-AI, социальность
src/evolution/   SpeciesDef, SpeciesRegistry, видообразование, филогения, FaunaGenerator
src/ecosystem/   EcoGrid (растения/детрит/нутриенты), популяции уровня C/D, падаль
src/world/       WorldData, Biomes, PlantSpecies, генератор, ландшафт, вода, флора
src/weather/     ClimateState, WeatherSystem
src/time/        TimeController, смена суток
src/control/     CreatureController (1-е/3-е лицо, схемы по типу тела)
src/camera/      FreeCameraSystem
src/input/       жесты, виртуальный стик, раскладки управления
src/ui/          тема, иконки, виджеты, HUD, главное меню
src/editor/      редактор существ
src/save/        SaveSystem, Migrations, SpeciesLibrary
src/performance/ PerformanceManager (уровни A–D, адаптивное качество)
src/experiment/  контролируемые эксперименты песочницы
src/sim/         SimWorld (сцена мира), SimState, WorldBuilder, AgentManager, HUD, EventLog, WorldContext
src/creature/    CreatureAgent (живая особь: восприятие → ИИ → движение → анимация → биология)
src/arena/       тестовый полигон редактора
src/audio/       процедурная звуковая атмосфера
src/tutorial/    шаги и оверлей обучения
scenes/          .tscn (минимальные: корневой узел + скрипт, UI строится кодом)
shaders/         .gdshader
tests/           headless-тесты;  tools/ — скрипты превью/скриншотов/утилиты
docs/            ARCHITECTURE.md, STATUS.md
```

## Соглашения по коду

- GDScript со статической типизацией (`var x: float`, `:=`), табы, `snake_case`, классы `PascalCase`.
  `:=` нельзя с Variant-выражениями (`dict.get()`, `arr[i]` нетипизированного массива) — пиши тип явно.
- Типизированным массивам (`Array[T]`) не присваивай литералы-нетипизированные массивы из других
  массивов; используй `.append()`/`.assign()`.
- Комментарии и идентификаторы — на английском; **весь текст интерфейса — на русском**.
- Один класс — одна ответственность; файлы < ~600 строк; без дублирования логики.
- Данные отделены от узлов: модели (`RefCounted`) сериализуются `to_dict()/from_dict()`
  и терпимы к отсутствующим/лишним ключам (обратная и прямая совместимость сохранений).
- Системы общаются через: явные ссылки, переданные в `setup(...)`, сервисы `Game.service(&"id")`
  и сигналы `EventBus`. Никаких `get_node("/root/...")` к чужим внутренностям.
- Параметры, которые игрок может менять, не хардкодятся в логике: схемы (`PartSchema`,
  `TraitCatalog`), настройки мира, `Genetics.DEFAULT_SETTINGS`.
- Время: физическое (движение, анимация) и биологическое (×`Units.BIO_TIME_RATIO` = 60).
  Все биологические скорости — «в биологическую секунду». Не путать.
- Единицы СИ: метры, кг, секунды, ватты, джоули, °C.
- Детерминизм: случайность только через `Rng`, засеянный от сида мира/системы.
- UI строится кодом, крупные элементы (≥ 48 px при ui_scale = 1), учитывай safe area.
- Ввод в 3D-видах: `InputEventScreenTouch/Drag` (мышь эмулирует касания);
  `InputEventMouseButton` ЛКМ не обрабатывать (двойная обработка на устройствах),
  колесо/ПКМ/СКМ — только для ПК.

## Ключевые контракты (кратко; полностью — docs/ARCHITECTURE.md)

- `Genome` = `BodyPlan` (структурные гены) + диплоидные аллели `TraitCatalog`.
- `Phenotype.build(genome)` → `anatomy: AnatomyModel`, `locomotion: LocomotionProfile`,
  `senses: SenseProfile`, `physiology: PhysiologyProfile`. Дёшево (~1–5 мс), меши не строит.
- Геометрия `AnatomyModel` — в «геометрическом пространстве» (size_scale = 1), существо смотрит в −Z,
  нижняя опора на y = 0; реальный размер = узел × `size_scale` × рост особи.
- Меши кэшируются по `genome.morph_key()` (размер в ключ не входит — это масштаб узла).
- Диагностика: `AnatomyDiagnostics.run(phenotype)` → `[{level, system, text}]`, `viability()`.

## Рабочий процесс

- Проверяй изменения: `tools/test.sh` (должно быть 0 failures) и, для визуала, скриншот.
- Не редактируй чужие подсистемы, если задача это не требует; общие файлы
  (`project.godot`, `src/core/*`, модели данных) меняй осторожно и описывай изменения.
- Коммиты — осмысленными порциями, сообщение на английском.
