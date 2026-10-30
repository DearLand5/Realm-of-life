class_name Gait
extends RefCounted
## Gait patterns by support-leg count and speed: duty factor (fraction of the
## cycle a foot is on the ground), stride multiplier and per-leg phase offsets.
##   biped        alternate legs; walk / run (flight phase)
##   quadruped    lateral-sequence walk -> diagonal trot -> bounding gallop
##   hexapod      alternating tripods
##   many legs    metachronal wave travelling along the body
## Legs are described by (side: -1 left / +1 right, rank: 0 front .. 1 rear).

const WALK := 0
const TROT := 1
const GALLOP := 2

var name: StringName = &"walk"
var duty: float = 0.7
var stride_mult: float = 1.0
var bob: float = 0.03           # body bob amplitude (fraction of leg length)
var bound: float = 0.0          # pitch rocking of the body (rad) for bounding gaits


## Picks the gait for a stance at speed ratio r = v / top land speed.
static func pick(stance: StringName, leg_count: int, r: float) -> Gait:
	var g := Gait.new()
	match stance:
		&"biped", &"monopod":
			if r < 0.4:
				g.name = &"walk"
				g.duty = 0.64
				g.stride_mult = 1.0
				g.bob = 0.04
			else:
				g.name = &"run"
				g.duty = clampf(0.55 - 0.3 * (r - 0.4), 0.3, 0.55)
				g.stride_mult = 1.9
				g.bob = 0.07
		&"quadruped":
			if r < 0.3:
				g.name = &"walk"
				g.duty = 0.72
				g.stride_mult = 1.0
				g.bob = 0.02
			elif r < 0.62:
				g.name = &"trot"
				g.duty = 0.52
				g.stride_mult = 1.5
				g.bob = 0.035
			else:
				g.name = &"gallop"
				g.duty = 0.36
				g.stride_mult = 2.4
				g.bob = 0.04
				g.bound = 0.09
		&"hexapod":
			g.name = &"tripod"
			g.duty = 0.62 if r < 0.5 else 0.5
			g.stride_mult = 1.0 if r < 0.5 else 1.5
			g.bob = 0.02
		_:
			g.name = &"wave"
			g.duty = 0.7
			g.stride_mult = 0.8
			g.bob = 0.01
	return g


## Phase offset (0..1) of a leg for this gait.
func offset(stance: StringName, side: int, rank: float, index: int, leg_count: int) -> float:
	var right := 0.0 if side >= 0 else 0.5
	match stance:
		&"biped", &"monopod":
			return right
		&"quadruped":
			var front := rank < 0.5
			match name:
				&"walk":
					# Lateral sequence: LH 0, LF .25, RH .5, RF .75
					if side < 0:
						return 0.25 if front else 0.0
					return 0.75 if front else 0.5
				&"trot":
					# Diagonal pairs move together.
					var diag := (side >= 0) == front
					return 0.0 if diag else 0.5
				_:
					# Bounding: hind pair then front pair, small left/right lag.
					var lag := 0.06 if side < 0 else 0.0
					return (0.5 if front else 0.0) + lag
		&"hexapod":
			# Tripods: (L front, R middle, L rear) vs (R front, L middle, R rear).
			var k := int(round(rank * 2.0))
			var left := side < 0
			var group_a := (left and k != 1) or (not left and k == 1)
			return 0.0 if group_a else 0.5
	# Metachronal wave: rank along the body, mirrored legs half a cycle apart.
	return fposmod(rank * 0.75 + right, 1.0)
