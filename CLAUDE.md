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
- В контейнере нет Vulkan — рендер проверяется только через OpenGL Compatibility.

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
