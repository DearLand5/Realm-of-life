# Realm of Life — архитектура и контракты подсистем

## 1. Выбор технологий

| Требование | Решение |
|---|---|
| Мобильные Android/iOS + перенос на ПК | **Godot 4.4+**, экспорт на все платформы из одного проекта |
| Производительность на телефоне | рендерер `mobile` (Vulkan) с откатом на OpenGL ES 3 (`gl_compatibility`); многоуровневая симуляция A–D |
| Процедурная геометрия | `ArrayMesh`/`SurfaceTool`, SDF + Surface Nets, GPU-скиннинг `Skeleton3D` |
| Язык | **GDScript** (без зависимости от Mono на мобильных); горячие места можно вынести в GDExtension, не меняя интерфейсов |
| Сохранения | JSON-конверты с версией формата, контрольной суммой, бэкапом и ZSTD-сжатием |

## 2. Слои

```
          ┌─────────────── Сцены / UI ────────────────┐
          │ MainMenu   CreatureEditor   World(HUD)    │
          └───────┬──────────────┬──────────┬────────┘
                  │              │          │
  ┌───────────────▼──┐   ┌───────▼───────┐  │   Ввод/камера:
  │ ProceduralAnatomy│   │ CreatureAgent │  │   MobileInputSystem,
  │ (меши, скиннинг) │◄──┤ (узел особи)  │  │   FreeCameraSystem,
  └───────▲──────────┘   └──┬────┬────┬──┘  │   CreatureController
          │                 │    │    │     │
  ┌───────┴────────┐  ┌─────▼┐ ┌─▼──┐ ┌▼────▼──────────┐
  │ AnatomyCompiler│  │  AI  │ │Phys│ │ Biology/Genetics│
  │ (морфогенез)   │  │      │ │    │ │ Evolution       │
  └───────▲────────┘  └──────┘ └────┘ └──────▲─────────┘
          │      Phenotype = f(Genome)        │
  ┌───────┴──────────────────────────────────┴─────────┐
  │ Данные: BodyPlan, Genome, TraitCatalog, SpeciesDef, │
  │ Individual, WorldData, ClimateState, PlantSpecies   │
  └─────────────────────────────────────────────────────┘
  Мир: WorldGenerator → WorldData;  Time/Weather → ClimateState;
       EcosystemSimulation (EcoGrid + популяции C/D) ;  PerformanceManager
```

Причинная цепочка (главный принцип): **Genome → AnatomyModel → (Locomotion, Senses,
Physiology) → поведение и выживание → отбор → частоты аллелей**. Никакие способности не
задаются отдельно от анатомии.

## 3. Данные анатомии

### 3.1 BodyPlan (`src/anatomy/plan/`)
Граф `BodyPart`. Единственное требование — один корень. Виды частей и параметры — в
`PartSchema` (data-driven: редактор строит панели из схемы).

- **Spine-части** (`torso, cell, neck, head, tail, limb, fin, wing, tentacle, antenna, flagellum`) —
  цепочка `BodySegment` (длина, радиус конца, pitch/yaw/roll, flatten, пределы сустава, жёсткость, soft).
- **Point-части** (`eye, ear, nose, mouth, horn, spike, claw, whisker, gill, sensor, gland,
  light_organ, shell, organ`) — только `params`. Размеры point-частей **относительны локальному
  радиусу родителя** (масштабирование тела сохраняет пропорции).
- Крепление: `attach_t` (0..1 вдоль родителя), `attach_angle` (0 право, 90 спина, 180 лево,
  270 брюхо), `attach_depth` (0 ось, 1 поверхность, <1 внутри).
- Размножение копий (только при компиляции): `symmetry` 1 = зеркально, N≥3 = радиально;
  `repeat_count/span/yaw` = метамерия (сегментированные тела, ноги многоножки).
- `CoveringDef` ×≤4 слота: тип покрова (кожа, чешуя, пластины, панцирь, хитин, шерсть, перья,
  щетина, слизь, мембрана) с биологическими свойствами (теплоизоляция, броня, удержание воды,
  гибкость, масса на м²) + окраска и узор.
- `biology`: habitat, reproduction_mode/method, diet, metamorphosis, molting, colonial.
- `custom_rules`: fantasy, ignore_oxygen, ignore_support, free_energy — пользовательские правила
  для вымышленных видов (явно помечаются в диагностике).

### 3.2 Кадры (frames)
- Корень horizontal: X — вправо, Y — вперёд (−Z мира), Z — вверх. Vertical (радиальные): X, Y=вверх, Z.
- Кость: локальная +Y вдоль кости. Сегмент гнётся `pitch` (вокруг X), `yaw` (вокруг Z), `roll` (вокруг Y).
- Кадр крепления «в середине»: Y = наружу (нормаль эллипса сечения), X = назад вдоль родителя,
  Z = по окружности. ⇒ для правой ноги `pitch < 0` — вниз, `yaw > 0` — вперёд.
- Кадр крепления «на торце» (t≈0/1, depth≈0): продолжение цепочки, `pitch > 0` — вверх.
- Зеркальная копия = геометрическое отражение x → −x (`MathUtil.mirror_basis_x`: M·B·M —
  остаётся поворотом). Дети зеркальной части наследуют зеркальность.

### 3.3 AnatomyModel (`src/anatomy/compiler/anatomy_model.gd`)
Выход `AnatomyCompiler.compile(genome)`:
- `bones: Array[Bone]` — индекс 0 = root; родитель всегда раньше ребёнка; поля: start/end/basis
  (rest, геом. пространство), r0/r1/flatten, лимиты сустава, side, mass/muscle_mass (реальные кг),
  function, is_tip, thin (тонкая цепь → рисуется трубкой).
- `primitives: Array[Primitive]` — SDF тела: round cone (kind 0) на каждую не-thin кость +
  эллипсоиды панцирей (kind 1); `blend` — радиус гладкого объединения; `aabb`.
- `accessories: Array[Accessory]` — eye, ear, nose, mouth, horn, spike, claw, whisker, gill,
  sensor, gland, light, organ (внутренний), membrane (крыло/плавник: `params.bones`, `chord`,
  `trail`, `normal`, `fan`, `subtype`, `area`), fluke, foot, tube (`params.bones`), cell_organelle, shell.
- `instances` — развёрнутые копии частей (part_id, mirrored, radial/repeat index, bones, anchor).
- `coverings` — экспрессированные покровы (цвет/толщина с учётом генов).
- `stats` (реальные единицы): mass, tissue/muscle/fat/covering/hard mass, volume, surface_area,
  length/width/height, streamline, com, cavity_volume, organ_volume{type: m³}, support_count,
  support_tips, leg_length, leg_radius, bone_stress, wing_area, fin_area, armor, insulation,
  water_retention, flexibility, needs_moisture, mouth{type,size,teeth,bite_force,venom,count},
  weapons{bite,horn,claw,spike,venom}, brain, kind_count, function_count, ground_clearance.
- `AnatomySdf.distance/raycast/gradient` — эталонная SDF (пикинг в редакторе, проверка органов).

### 3.4 Профили
- `LocomotionProfile.build(model, genome)` — ходьба/бег (Фруд, мощность/вес, напряжение кости),
  ползание (сегменты, гибкость, чешуя), плавание (мощность vs сопротивление), полёт (подъёмная
  сила, нагрузка на крыло, мощность), прыжок, лазание, рытьё; стоимость передвижения (Дж/м);
  `notes` — объяснения ограничений.
- `SenseProfile.build(model, genome)` — зрение (дальность от размера глаза и типа, поле зрения
  из направлений глаз, бинокулярность, ночное/цветное), обоняние, слух, осязание, вибрация,
  электро-, термо-, магниторецепция; `head_bone`, `eye_point`, `eye_forward` (для 1-го лица).
- `PhysiologyProfile.build(phenotype)` — BMR (Клайбер × теплокровность × метаболизм), запас
  энергии, тип дыхания, пригодные среды, эффективность диет, продолжительность жизни.

## 4. Генетика (`src/genetics/`)
- `TraitCatalog.DEFS` — ~55 признаков (анатомия, окраска, физиология, жизненный цикл, поведение,
  чувства), у каждого 1–3 локуса, доминантность `h`, хромосома, шаг мутации.
- Экспрессия локуса: `h·max(a,b) + (1−h)·min(a,b)`; признак = среднее локусов.
- `Genetics.sexual()` — мейоз со сцеплением (кроссинговер между соседними локусами), план тела —
  «супер-ген» от одного родителя + покомпонентный кроссинговер частей с общим id.
- `Genetics.mutate()` — Пуассоновское число мутаций, крупные эффекты, категории можно
  блокировать, структурные мутации `BodyPlanMutator` (сегменты, повторы, удвоение/утрата частей,
  покровы, узоры, цвет).
- `Genetics.distance()` — количественная + структурная дистанция (видообразование, совместимость).

## 5. Время (`Units`)
Физическое время — движение/анимация; биологическое = физическое × 60 (сутки ≈ 24 мин на ×1).
`TimeController` выдаёт за кадр `phys_dt` и `bio_dt` (с учётом паузы/ускорения). Год = 4 сезона ×
10 суток.

## 6. Контракты подсистем (интерфейсы, которые используют другие)

### 6.1 ProceduralAnatomy — `src/anatomy/mesh/`, `src/skeleton/`, `shaders/creature*.gdshader`
```
CreatureMeshCache (static/autoload-free singleton через static var)
  request(model: AnatomyModel, lod: int, callback: Callable(meshes: CreatureMeshSet)) -> void
  get_cached(morph_key: String, lod: int) -> CreatureMeshSet or null
  build_now(model, lod) -> CreatureMeshSet        # синхронно (редактор/тесты)
CreatureMeshSet: body: ArrayMesh (скиннинг на кости AnatomyModel), accessories: Array[{mesh, bone, transform, material_kind}], skin: Skin
SkeletonBuilder.build(model) -> Skeleton3D        # имена и индексы костей = AnatomyModel.bones
CreatureVisual (Node3D)
  setup(model: AnatomyModel, individual_seed: int, lod := 0) ; set_lod(lod)
  get_skeleton() -> Skeleton3D ; set_highlight(part_id, on) ; set_xray(on)
  set_condition(wetness, damage, fatigue)         # шейдерные параметры состояния
  set_muscle_bulge(bone, amount)                  # деформация мышц через масштаб кости
```
Вершинные атрибуты тела: `CUSTOM0` = позиция в rest-пространстве (xyz) + слот покрова (w),
`COLOR` = веса слотов покровов 0..3, `BONES/WEIGHTS` (4 кости).

### 6.2 World — `src/world/`, `src/weather/`, `src/time/`
```
WorldGenerator.generate(config: Dictionary) -> WorldData   # детерминированно по config.seed
WorldConfig.defaults() -> Dictionary  {seed, size, resolution, sea_level, relief, vegetation, biome_diversity, temperature_offset, moisture_offset, rivers}
TerrainRenderer (Node3D).setup(world: WorldData) ; update_focus(pos)  # чанки + LOD
WaterRenderer (Node3D).setup(world)
FloraSystem.generate_species(world, rng) -> Array[PlantSpecies]
FloraRenderer (Node3D).setup(world, species, biomass_provider: Callable(cx:int, cz:int, plant:int)->float, cell_size)
TimeController (Node): time_scale, paused, step_once(), climate: ClimateState; сигналы → EventBus
DayNightCycle (Node3D): sun/moon/sky/ambient по ClimateState
WeatherSystem (Node): обновляет ClimateState (weather, clouds, rain, wind, fog, drought), визуальные эффекты
```

### 6.3 Biosim — `src/biology/`, `src/ecosystem/`, `src/evolution/`
```
Individual (RefCounted): id, species_id, genome, phenotype (не сохраняется), sex, age, energy, hydration,
  body_temp, fatigue, health, stage, growth, pregnancy, position, heading, alive...; to_dict/from_dict
BiologySystem.tick(ind, env: Dictionary, bio_dt, activity: float) -> Array[event]
  env = {temperature, humidity, oxygen, in_water, light, water_nearby}
BiologySystem.feed(ind, food_kind, kg, quality) -> float (усвоено Дж)
Reproduction.can_mate(a, b) ; Reproduction.conceive(mother, father, rng) ; Reproduction.offspring(...)
EcoGrid: cell_size, dim, plant_species; biomass(cx,cz,p); consume_plants(pos, kg, prefs) -> {kg, energy, toxicity};
  add_carcass(pos, kg, species_id); nearest_carcass(pos, r); detritus; step(bio_dt)
PopulationManager: пулы уровня C/D по секторам; fold(individuals, sector) ; unfold(sector, max) -> Array[Individual]; step(bio_dt)
SpeciesRegistry: register(def), get(id), all(), sample_history(day), mark_extinct()
EvolutionSystem: settings (мутации), check_speciation(), phylogeny(), log
FaunaGenerator.generate(world, plants, rng, count) -> Array[SpeciesDef]  # функционально жизнеспособные
```

### 6.4 Creature runtime — `src/ai/`, `src/physics/`, `src/muscle/`, `src/control/`
```
CreatureAgent (Node3D): individual, phenotype, visual(CreatureVisual), brain, mover, animator
  sim_tier: 0=A полная, 1=B упрощённая ; set_tier(t)
  possess(controller) / release()
Perception.update(agent, world_ctx) ; Memory ; Brain (utility AI: потребности → действия)
Mover: движение по способностям LocomotionProfile, среда (суша/вода/воздух), высота рельефа
ProceduralAnimator: походка по числу ног, IK стоп без скольжения, волна тела, взмахи крыльев, мягкие ткани
CreatureController: схемы управления (ground, flyer, swimmer, tentacle, crawler), 1-е/3-е лицо
```

### 6.5 Input/UI — `src/input/`, `src/ui/`, `src/camera/`
```
UITheme.build(scale) -> Theme ; Icons (векторные) ; виджеты: IconButton, ParamSlider(+/−, поле), ...
GestureRecognizer (Node): сигналы tap/double_tap/long_press/drag/pinch/two_finger_drag/rotate
VirtualJoystick (Control), TouchButton (Control), ControlLayout (профили раскладок по режимам)
FreeCamera (Node3D/Camera3D): orbit/pan/zoom, follow(target), focus(pos), height_provider: Callable
SafeArea (Control-контейнер)
```

### 6.6 Редактор существ — `src/editor/`, `scenes/creature_editor.tscn`
```
Payload сцены (Game.take_pending): {"species_uid"} | {"preset"} | {"genome": dict} | {} (стартовый выбор)
Кнопка «Тест»: res://scenes/test_arena.tscn с {"genome", "return_to": "editor"}; без арены — тест-карусель в редакторе
CreatureEditor (Control, signal tutorial_event) — оболочка: верхняя панель, рейка режимов, контекстный лист
  (боковой в ландшафте / нижний в портрете), полоса статистики; строится кодом
EditorContext   — общее состояние сессии (doc, режим, активный сегмент, режим жестов, флаги вида); связь через сигналы
EditorDocument  — Genome + Phenotype + выделение + история (EditorHistory, снимки, ≥ 100 шагов);
                  modify() / live_edit()+commit(); после каждой правки repair() и синхронная перекомпиляция (3–7 мс)
EditorCommands, AttachMapper, PartPicker, SurfaceRay — чистая логика правок и геометрии (без узлов, тестируется headless)
PartCatalog     — каталог частей и быстрые пресеты («Лапа бегуна», «Перьевое крыло», «Клюв»…)
PanelSpec → SpecPanel → PartPanel — контекстные панели генерируются из PartSchema (только параметры выбранного вида)
EditorStage     — 3D-сцена: свет, пол с тенью, FreeCamera, CreatureVisual; меш — асинхронно через CreatureMeshCache.request
                  (LOD2 при перетаскивании, LOD0 в покое; один запрос в полёте, побеждает новейшая модель)
EditorGestures / HandleOverlay / PartDragger — выбор касанием, перетаскивание крепления по поверхности родителя,
                  экранные манипуляторы (длина, толщина, перемещение, поворот); два пальца — всегда камера
modes/Mode*     — страницы вкладок: Форма, Скелет, Конечности, Покровы, Чувства, Органы, Биология, Гены, Проверка
```
События для обучения: `editor_shape_changed`, `editor_part_added`, `editor_diagnostics_opened`, `editor_biology_changed`, `species_saved`.

## 7. Многоуровневая симуляция
| Уровень | Кто | Что считается | Частота |
|---|---|---|---|
| A | особи рядом с камерой (< ~40 м) | полная анимация/IK, восприятие, AI, биология | каждый кадр / AI 4–8 Гц |
| B | в зоне наблюдения (< ~100 м) | упрощённая анимация, AI 1–2 Гц | реже |
| C | удалённые сектора | популяционные пулы: питание, смертность, рождаемость, миграция, отбор на выборке геномов | ~1 Гц |
| D | далёкие/незначимые | агрегированный пул с большим шагом | ~0.2 Гц |

Переходы сохраняют численность: особи «сворачиваются» в пул сектора (count, энергия, возрастная
структура, выборка геномов) и «разворачиваются» обратно, сэмплируя геномы из выборки. При
ускорении ≥ ×256 вся симуляция переходит в популяционный режим.

## 8. Сохранения
Конверт `{format, kind, app_version, saved_at, checksum, data}`; запись атомарная (`.tmp` → rename,
предыдущий файл → `.bak`), чтение с откатом на `.bak`, `Migrations.upgrade()` по версиям, все
`from_dict` терпимы к отсутствующим/неизвестным ключам. Мир хранит конфиг генерации (геометрия
пересоздаётся детерминированно) + динамическое состояние (климат, EcoGrid, популяции, особи,
виды, история). Автосохранение с ротацией (3 слота), ручные контрольные точки.

## 9. Добавление нового вида части тела
1. Запись в `PartSchema` (`SPINE_KINDS`/`POINT_KINDS`, `PARAMS`, `KIND_LABELS`, режим в `MODE_KINDS`).
2. Компилятор: размер/аксессуар в `_point_raw` или `_spine_accessories`.
3. Если влияет на способности — учесть в `LocomotionProfile`/`SenseProfile`/`PhysiologyProfile`.
4. Меш аксессуара — в `src/anatomy/mesh/` по типу аксессуара.
5. Тест в `tests/`.
