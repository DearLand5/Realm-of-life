class_name ModeLimbs
extends EditorMode
## «Конечности»: legs, arms, fins, wings, tentacles, antennae, flagella from
## quick presets; segments, mobility, function, foot, symmetry and repeats.


func build() -> void:
	add_quick_add(["leg_run", "leg_paw", "arm_hand", "fin_pectoral", "wing_feather", "tentacle_suckers", "antenna", "flagellum", "leg_insect"])
	add_part_chips(PartSchema.MODE_KINDS[&"limbs"], tr("Конечности"))
	add_selected_panel()
