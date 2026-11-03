extends Node3D
## An offscreen shell for the artillery barrage or the naval gun: it drops in nose first along a
## steep line from beyond the screen and is gone the moment it lands. Arena owns its timing and
## what the impact does; this only draws the shell.
const MODELS = {
	"artillery": preload("res://assets/weapons/firearm_material_v4/artillery_shell.glb"),
	"naval": preload("res://assets/weapons/firearm_material_v4/naval_shell.glb"),
}
# The authored shells are 0.33m / 0.51m long; at the field camera they read only somewhat larger.
const SCALES = {"artillery": 2.2, "naval": 2.6}
var start: Vector3
var end: Vector3

func initialize(kind: String, from: Vector3, to: Vector3) -> void:
	name = "IncomingShell"
	# Reset clears it together with the casts' leftovers.
	add_to_group("cast_assemblies")
	add_child(MODELS[kind].instantiate())
	start = from
	end = to
	scale = Vector3.ONE * float(SCALES[kind])
	visible = false

func place(progress: float) -> void:
	# The nose (local -Z at the origin) leads along the line toward the impact.
	visible = true
	var at: Vector3 = start.lerp(end, clampf(progress, 0.0, 1.0))
	global_transform = Transform3D(Basis.looking_at((end - start).normalized(), Vector3.UP).scaled(scale), at)
