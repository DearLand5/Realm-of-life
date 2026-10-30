class_name MoveIntent
extends RefCounted
## What a creature WANTS to do this frame; the CreatureMover decides what its
## body can actually do (LocomotionProfile limits, terrain, medium).
## Written by the Brain's actions (AI rate) or by the CreatureController
## (player input, every frame); read by the mover every frame.
##
## Steering is "goal based" so that actions only need to run at the AI rate:
## the mover re-aims at `goal_node` (a moving target) every frame.

enum Mode { NONE, SEEK, FLEE, DIRECT }

var mode: int = Mode.NONE
var goal := Vector3.ZERO            # SEEK: where to go; FLEE: what to run from
var goal_node: Node3D = null        # SEEK/FLEE: live target (overrides `goal` while valid)
var dir := Vector3.ZERO             # DIRECT: desired travel direction (world, y used when swimming/flying)
var speed: float = 0.0              # desired speed in m/s (the mover clamps to the body's limits)
var arrive_radius: float = 0.4      # SEEK: slow down and stop inside this distance
var face := Vector3.ZERO            # optional gaze/body direction while standing still (xz)
var jump := false
var fly := false                    # wants to be airborne (fliers) — false lands
var altitude: float = 4.0           # flying: metres above ground; swimming: metres below the surface
var surface := true                 # swimming: stay at the surface (lung breathers), false = use `altitude` depth
var sprint := false                 # allows speeds above the sustainable pace (fatigue builds faster)
var avoid_water := true             # land walkers: treat deep water as an obstacle
var group_pull := Vector3.ZERO      # boid-like blend (cohesion + alignment) added to the heading, magnitude 0..1
var urgency: float = 0.0            # 0..1 for animation (alert posture) and steering sharpness


func clear() -> void:
	mode = Mode.NONE
	goal_node = null
	speed = 0.0
	jump = false
	sprint = false
	group_pull = Vector3.ZERO
	face = Vector3.ZERO
	urgency = 0.0


func seek(target: Vector3, v: float, arrive: float = 0.4) -> void:
	mode = Mode.SEEK
	goal = target
	goal_node = null
	speed = v
	arrive_radius = arrive


func seek_node(target: Node3D, v: float, arrive: float = 0.4) -> void:
	mode = Mode.SEEK
	goal_node = target
	goal = target.position if target != null else goal
	speed = v
	arrive_radius = arrive


func flee_from(threat: Vector3, v: float) -> void:
	mode = Mode.FLEE
	goal = threat
	goal_node = null
	speed = v


func direct(d: Vector3, v: float) -> void:
	mode = Mode.DIRECT
	dir = d
	speed = v


func stop() -> void:
	mode = Mode.NONE
	speed = 0.0


func is_moving() -> bool:
	return mode != Mode.NONE and speed > 0.01
