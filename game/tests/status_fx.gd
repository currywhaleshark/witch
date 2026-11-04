extends SceneTree
## Enemy debuff markers (presentation only): slow at the feet, bound round the waist, shred on
## the chest, bleed out of the sides, stun over the head. Each has its own place so several read
## at once, fades in and out, freezes on pause and leaves combat RNG alone. Writes no report.
var arena: Node3D
var failures: Array = []
var checks: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, name: String) -> void:
	checks.append(name)
	if not condition:
		failures.append(name)
		push_error(name)

func step(count: int = 1) -> void:
	for i in count:
		await physics_frame
		arena._physics_process(1.0 / 60.0)

func enemy(id: String, at: Vector3, kind: String = "light") -> Dictionary:
	arena.spawn_enemy(id, at, false, "normal", kind)
	var spawned: Dictionary = arena.enemies[id]
	spawned.cooldown = 999
	spawned.max_hp = 99999.0
	spawned.hp = 99999.0
	return spawned

func fresh() -> void:
	arena.reset_arena()
	arena.player.position = Vector3.ZERO
	arena.config.enemy_speed = 0
	arena.muted = true
	for id in arena.enemies.keys():
		arena.enemies[id].body.free()
	arena.enemies.clear()
	enemy("anchor", Vector3(-11, 0, -9))
	await step(2)

func surfaces(fx: Node3D) -> int:
	return fx.get_node("Markers").mesh.get_surface_count() + fx.get_node("Overlay").mesh.get_surface_count()

func run() -> void:
	arena = load("res://main.tscn").instantiate()
	get_root().add_child(arena)
	await step(5)
	await fresh()
	var foe: Dictionary = enemy("a", Vector3(2, 0, 2))
	await step(10)
	check(arena.status_fx(foe) == null, "no marker node before any debuff")

	# Real paths: a stun and a bind from the device helper, a bleed from the chainsaw rule.
	foe.slow = 2.0
	await step(12)
	var fx: Node3D = arena.status_fx(foe)
	check(fx != null and fx.showing() == ["slow"], "slow alone shows only the foot ripple")
	check(fx != null and surfaces(fx) == 1, "the markers draw a mesh")
	check(fx != null and fx.get_node("Overlay").mesh.get_surface_count() == 0, "only the shield draws over the body")
	arena.restrain("a", "stun", 2.0)
	arena.add_bleed("a")
	arena.add_bleed("a")
	foe.shred = 2.0
	await step(30)
	check(fx.showing() == ["slow", "shred", "bleed", "stun"], "slow, shred, bleed and stun show together")
	check(not fx.drops.is_empty(), "bleeding spurts drops")
	foe.bound = 2.0
	await step(20)
	check(fx.showing().size() == 5, "a bind adds the waist cables: all five at once")

	# Each marker has its own place: ground < waist < chest < head, bleed out at the sides.
	var waist: float = lerpf(fx.bottom, fx.top, 0.4) + (fx.top - fx.bottom) * 0.09
	var chest: float = lerpf(fx.bottom, fx.top, 0.66) - 0.15 * fx.scale_factor
	check(waist < chest, "the top cable stays under the shield's lower edge")
	check(fx.stun_height > fx.top, "stars circle above the head")
	check(fx.stun_height < 0.35 + 1.55 * foe.size, "stars stay under the HP bar")
	var view: Camera3D = arena.camera
	var right := Vector3(view.global_basis.x.x, 0, view.global_basis.x.z).normalized()
	var lateral: Array = fx.drops.map(func(drop): return absf(drop.p.dot(right)))
	check(lateral.min() >= fx.radius * 0.9, "blood leaves from the sides, clear of the chest shield")
	check(fx.drops.all(func(drop): return drop.p.y < fx.stun_height - 0.1), "blood never reaches the stars")

	# More stacks spurt more often.
	var few: Array = []
	var many: Array = []
	for count in [1, 5]:
		await fresh()
		var target: Dictionary = enemy("b", Vector3(2, 0, 2))
		for i in count:
			arena.add_bleed("b")
		var spurts := 0
		var before := 0
		for i in 120:
			await step()
			var now: int = arena.status_fx(target).drops.filter(func(drop): return drop.age <= 1.0 / 60.0 + 0.0001).size()
			if now > 0 and before == 0:
				spurts += 1
			before = now
		(few if count == 1 else many).append(spurts)
	check(many[0] > few[0], "five bleed stacks spurt more often than one (%d > %d)" % [many[0], few[0]])

	# Pause freezes the markers; combat RNG is untouched by them.
	await fresh()
	foe = enemy("c", Vector3(2, 0, 2))
	foe.slow = 3.0
	foe.stun = 3.0
	arena.add_bleed("c")
	await step(10)
	fx = arena.status_fx(foe)
	var state: int = arena.rng.state
	await step(30)
	check(arena.rng.state == state, "markers never draw from the combat RNG")
	arena.paused = true
	var frozen: float = fx.time
	await step(20)
	check(fx.time == frozen, "pause freezes the markers")
	arena.paused = false

	# Ending debuffs fade out and leave nothing drawn.
	foe.slow = 0.0
	foe.stun = 0.0
	foe.bleeds.clear()
	await step(4)
	check(fx.presence.slow > 0 and fx.presence.slow < 1, "an ended slow fades rather than vanishing")
	await step(50)
	check(fx.showing().is_empty() and surfaces(fx) == 0, "everything fades out once the debuffs end")

	# Bigger enemies get larger, higher markers; the boss's stars stay over its head.
	await fresh()
	var small: Dictionary = enemy("rag", Vector3(2, 0, 2), "rag")
	var big: Dictionary = enemy("brute", Vector3(-2, 0, 2), "brute")
	small.stun = 2.0
	big.stun = 2.0
	await step(5)
	check(arena.status_fx(big).stun_height > arena.status_fx(small).stun_height, "a brute's stars sit higher than a rag-ghoul's")
	check(arena.status_fx(big).scale_factor > arena.status_fx(small).scale_factor, "a brute's markers are larger")

	# A dying enemy takes its markers with it.
	var marker: Node3D = arena.status_fx(small)
	arena.damage_enemy("rag", 999999.0, true)
	await step(3)
	check(not is_instance_valid(marker), "markers go with a dead enemy")

	print("STATUS_FX ", checks.size() - failures.size(), "/", checks.size())
	for failure in failures:
		print("FAIL ", failure)
	quit(1 if not failures.is_empty() else 0)
