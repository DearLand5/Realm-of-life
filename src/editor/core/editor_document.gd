class_name EditorDocument
extends RefCounted
## The design being edited: genome + derived phenotype, selection, clipboard,
## dirty flag and undo history. Pure data/controller (no nodes), so the whole
## editing logic is unit-testable headless.
##
## Editing protocol (every change goes through one of these):
##   doc.modify(label, func(g: Genome): ..., tag)  # one-shot edit → history step
##   doc.live_edit(func(g): ...)                   # continuous (slider/drag): rebuilds
##   doc.commit(label, tag)                        #   ... then one history step
## After each edit the plan is repaired, the phenotype recompiled (fast, a few
## ms) and `changed(reason)` emitted:
##   &"live"      continuous edit in progress (UI keeps widgets, stage uses a low LOD)
##   &"commit"    values changed (widgets refresh values)
##   &"structure" parts added/removed/regrouped (panels rebuild)
##   &"history"   undo/redo restored another state (panels rebuild)
##   &"load"      a new design was loaded
## `edited(tag)` reports what kind of edit happened (&"shape", &"part_added",
## &"biology", &"genetics", ...) — the editor turns tags into tutorial events.

signal changed(reason: StringName)
signal selection_changed
signal edited(tag: StringName)

const DEFAULT_NAME := "Новый организм"

var genome: Genome
var phenotype: Phenotype
var diagnostics: Array[Dictionary] = []
var muscles: Array[MuscleGroup] = []
## Library uid of the design ("" = never saved).
var uid: String = ""
var dirty: bool = false
## Primary selected part (-1 = none) and the full selection (groups, multi-select).
var selected_id: int = -1
var selection: Array[int] = []
## New paired parts are bilateral when on (top-bar symmetry toggle).
var symmetry: bool = true
## Copied subtree (EditorCommands.subtree_dict format).
var clipboard: Dictionary = {}
var history := EditorHistory.new()
## True between live_edit() and commit().
var live: bool = false
## Last compile time (ms) — shown in debug overlays.
var build_ms: float = 0.0


func _init(g: Genome = null) -> void:
	load_genome(g if g != null else default_genome())


## A simple starting organism: a three-segment torso with a head, eyes and a mouth.
static func default_genome() -> Genome:
	var plan := BodyPlan.new()
	plan.name = DEFAULT_NAME
	plan.coverings = [CoveringDef.make(&"skin", Color(0.45, 0.62, 0.42), Color(0.86, 0.88, 0.7), &"countershade")]
	var torso := BodyPlanPresets.chain(&"torso", 0.1, [[0.14, 0.12, 0, 0, 1.0], [0.16, 0.12, 0, 0, 1.0], [0.14, 0.09, 0, 0, 1.0]])
	var t := plan.add_part(torso)
	var head := BodyPlanPresets.att(plan, BodyPlanPresets.chain(&"head", 0.085, [[0.1, 0.08, -4], [0.08, 0.045, -6]]), t, 1.0, 0.0, 0.0, 0, 0, 0, 0, "Голова")
	BodyPlanPresets.att(plan, BodyPlanPresets.point(&"eye", {"size": 0.3}), head, 0.55, 30.0, 0.9, 1, 0.0, 25.0, 0.0, "Глаз")
	BodyPlanPresets.att(plan, BodyPlanPresets.point(&"mouth", {"size": 0.6}), head, 1.0, 270.0, 0.4, 0, 0, 0, 0, "Рот")
	BodyPlanPresets.organ(plan, t, "stomach", 0.5, 0.12, 270.0, 0.25)
	BodyPlanPresets.organ(plan, t, "lungs", 0.75, 0.12)
	plan.repair()
	return Genome.new(plan)


# --- Loading ---------------------------------------------------------------------------

## Replaces the design. The plan is repaired (invalid saves never crash the editor).
func load_genome(g: Genome, species_uid: String = "") -> void:
	genome = g if g != null else default_genome()
	if genome.body_plan == null:
		genome.body_plan = BodyPlan.new()
	genome.body_plan.repair()
	# Complete partial biology/rules dictionaries so history snapshots are stable.
	for k in BodyPlan.BIOLOGY_DEFAULTS:
		if not genome.body_plan.biology.has(k):
			genome.body_plan.biology[k] = BodyPlan.BIOLOGY_DEFAULTS[k]
	for k in BodyPlan.CUSTOM_RULE_DEFAULTS:
		if not genome.body_plan.custom_rules.has(k):
			genome.body_plan.custom_rules[k] = BodyPlan.CUSTOM_RULE_DEFAULTS[k]
	genome.invalidate()
	uid = species_uid
	dirty = false
	live = false
	selected_id = -1
	selection.clear()
	rebuild()
	history.reset(snapshot("load"))
	changed.emit(&"load")
	selection_changed.emit()


func load_dict(d: Dictionary, species_uid: String = "") -> void:
	load_genome(Genome.from_dict(d), species_uid)


func plan() -> BodyPlan:
	return genome.body_plan


func design_name() -> String:
	return genome.body_plan.name


func set_design_name(n: String) -> void:
	var clean := n.strip_edges()
	if clean == "" or clean == genome.body_plan.name:
		return
	modify("Название", func(g: Genome) -> void: g.body_plan.name = clean, &"name")


# --- Derived data ----------------------------------------------------------------------

## Recompiles phenotype, diagnostics and muscle groups (synchronous, ~1–10 ms).
func rebuild() -> void:
	var t0 := Time.get_ticks_usec()
	genome.invalidate()
	phenotype = Phenotype.build(genome)
	diagnostics = AnatomyDiagnostics.run(phenotype)
	muscles = MuscleSystem.analyze(phenotype.anatomy, genome)
	build_ms = float(Time.get_ticks_usec() - t0) / 1000.0


func warning_count() -> int:
	var n := 0
	for d in diagnostics:
		if d["level"] == &"warning" or d["level"] == &"critical":
			n += 1
	return n


func critical_count() -> int:
	var n := 0
	for d in diagnostics:
		if d["level"] == &"critical":
			n += 1
	return n


# --- Selection -------------------------------------------------------------------------

func selected_part() -> BodyPart:
	return genome.body_plan.get_part(selected_id) if selected_id >= 0 else null


## Selects a part (-1 clears). Grouped parts select their whole group;
## `additive` toggles the part in a multi-selection.
func select(id: int, additive: bool = false) -> void:
	var plan_ := genome.body_plan
	var p := plan_.get_part(id)
	if p == null:
		if selected_id == -1 and selection.is_empty():
			return
		selected_id = -1
		selection.clear()
		selection_changed.emit()
		return
	if additive:
		if selection.has(id) and selection.size() > 1:
			selection.erase(id)
			selected_id = selection[selection.size() - 1]
		elif not selection.has(id):
			selection.append(id)
			selected_id = id
		selection_changed.emit()
		return
	var members: Array[int] = [id]
	if p.group >= 0:
		for q in plan_.parts:
			if q.group == p.group and q.id != id:
				members.append(q.id)
	if selected_id == id and selection == members:
		return
	selected_id = id
	selection = members
	selection_changed.emit()


func is_selected(id: int) -> bool:
	return selection.has(id)


func _validate_selection() -> void:
	var kept: Array[int] = []
	for id in selection:
		if genome.body_plan.get_part(id) != null:
			kept.append(id)
	selection = kept
	if genome.body_plan.get_part(selected_id) == null:
		selected_id = selection[0] if not selection.is_empty() else -1


# --- Editing -------------------------------------------------------------------------------

## One-shot edit: `fn(genome)` mutates the design; then repair, rebuild, record.
func modify(label: String, fn: Callable, tag: StringName = &"edit", reason: StringName = &"commit") -> void:
	fn.call(genome)
	_after_mutation()
	live = false
	_record(label)
	changed.emit(reason)
	edited.emit(tag)


## Continuous edit step (no history entry until commit()).
func live_edit(fn: Callable) -> void:
	fn.call(genome)
	_after_mutation()
	live = true
	changed.emit(&"live")


## Ends a continuous edit with one history step.
func commit(label: String, tag: StringName = &"edit") -> void:
	var was_live := live
	live = false
	if _record(label) or was_live:
		changed.emit(&"commit")
		edited.emit(tag)


func _after_mutation() -> void:
	var fixes := genome.body_plan.repair()
	if not fixes.is_empty():
		push_warning("EditorDocument: plan repaired: %s" % ", ".join(fixes))
	_validate_selection()
	rebuild()


func _record(label: String) -> bool:
	var pushed := history.push(snapshot(label))
	if pushed:
		dirty = true
	return pushed


func snapshot(label: String = "") -> Dictionary:
	return {"genome": genome.to_dict(), "selected": selected_id, "label": label}


func can_undo() -> bool:
	return history.can_undo()


func can_redo() -> bool:
	return history.can_redo()


## Restores the previous state. The selection stays on the edited part when it
## still exists (users expect to keep working on it).
func undo() -> bool:
	var s := history.undo()
	if s.is_empty():
		return false
	_restore(s, [selected_id, int(s.get("selected", -1))])
	edited.emit(&"undo")
	return true


func redo() -> bool:
	var s := history.redo()
	if s.is_empty():
		return false
	_restore(s, [int(s.get("selected", -1)), selected_id])
	edited.emit(&"redo")
	return true


func _restore(state: Dictionary, prefer: Array) -> void:
	var keep_uid := uid
	genome = Genome.from_dict(state.get("genome", {}))
	uid = keep_uid
	live = false
	dirty = true
	rebuild()
	selected_id = -1
	selection.clear()
	for cand in prefer:
		var sel := int(cand)
		if sel >= 0 and genome.body_plan.get_part(sel) != null:
			selected_id = sel
			selection.append(sel)
			break
	changed.emit(&"history")
	selection_changed.emit()


## Saves into the SpeciesLibrary. Without `save_as` an existing entry is
## overwritten (same uid). Returns the uid ("" on failure).
func save_to_library(name_override: String = "", save_as: bool = false) -> String:
	if name_override.strip_edges() != "" and name_override != genome.body_plan.name:
		genome.body_plan.name = name_override.strip_edges()
	var use_uid := "" if save_as else uid
	var saved := SpeciesLibrary.save_species(genome, genome.body_plan.name, use_uid)
	if saved != "":
		mark_saved(saved)
		if save_as:
			history.reset(snapshot("save"))
	return saved


## Marks the design as saved (after SpeciesLibrary.save_species).
func mark_saved(species_uid: String) -> void:
	uid = species_uid
	dirty = false
