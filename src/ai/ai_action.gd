class_name AiAction
extends RefCounted
## One behaviour of the utility AI, written as a small state machine
## (approach -> perform -> done). The Brain asks every action for a score
## (need urgency x feasibility x personality), runs the best one and lets it
## `update()` at the AI rate. Movement continues smoothly between AI ticks
## because actions only set goals on the agent's MoveIntent.

var a: CreatureAgent
var id: StringName = &"idle"
var label: String = "Отдыхает"          # Russian status text (shown through tr())
var min_commit: float = 2.0             # s before a lower-scored rival may take over
var emergency := false                  # may interrupt anything (flee)
var t_active: float = 0.0
var finished := false
var target_text: String = ""            # what the action is aimed at (HUD)
var needs: Needs                        # shared, owned by the brain


func attach(agent: CreatureAgent, shared_needs: Needs) -> void:
	a = agent
	needs = shared_needs


## 0 = not applicable; ~1 = as urgent as a basic need; >1.5 = emergency.
func score() -> float:
	return 0.0


func start() -> void:
	t_active = 0.0
	finished = false
	target_text = ""


## Called at the AI rate with the elapsed AI interval.
func update(_dt: float) -> void:
	pass


func stop() -> void:
	pass


## Metabolic activity level 0..1 passed to BiologySystem.tick.
func activity() -> float:
	return 0.3


## Hook for animation: eating, attacking, sleeping ... (read by the animator).
func pose() -> StringName:
	return &""
