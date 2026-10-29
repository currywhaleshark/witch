extends SceneTree
## GPU review captures for combat VFX v1: real arena code paths on the flat field,
## stepped at 60fps, saved as close-up contact sheets plus one native-scale frame each.
const Shape = preload("res://scripts/shapes.gd")
const CombatVfx = preload("res://scripts/combat_vfx.gd")
var arena: Node3D
var output := ""
var only := ""
var records: Array = []
var saved := 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		if arg.begins_with("--only="): only = arg.trim_prefix("--only=")
	call_deferred("run")

func grab() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func clear_actors() -> void:
	for e in arena.enemies.values(): e.body.free()
	arena.enemies.clear()
	for fx in arena.effects: fx.node.free()
	arena.effects.clear()
	for bolt in arena.bolts: bolt.node.free()
	arena.bolts.clear()
	for wall in get_nodes_in_group("vfx_review_wall"): wall.free()

func suppress_hud() -> void:
	arena.hud.visible = false; arena.hover_ring.visible = false; arena.move_marker.visible = false
	for ring in arena.tool_rings.values(): ring.visible = false

func prepare(tool_slot: String = "") -> void:
	arena.reset_arena()
	clear_actors()
	arena.player.position = Vector3.ZERO
	arena.config.mana_regen = 0.0
	arena.force_rolls = {"hit": true, "crit": false}
	arena.muted = true; arena.help_visible = false
	if tool_slot != "":
		arena.state = arena.rules.bind(arena.state, "r", tool_slot)

func target(id: String, pos: Vector3, kind: String, quiet: bool = true) -> Dictionary:
	arena.spawn_enemy(id, pos, false, "normal", kind)
	var enemy: Dictionary = arena.enemies[id]
	enemy.hp = 5000.0; enemy.max_hp = 5000.0
	if quiet: enemy.cooldown = 999.0
	return enemy

func wall(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new(); body.collision_layer = arena.map.WORLD_LAYER
	var shape := BoxShape3D.new(); shape.size = size
	var col := CollisionShape3D.new(); col.shape = shape; body.add_child(col)
	arena.world.add_child(body); body.position = pos; body.add_to_group("vfx_review_wall")
	Shape.box(body, Vector3.ZERO, size, Color("657578"))

func vfx_ids() -> Array:
	return arena.effects.filter(func(fx): return fx.node is CombatVfx).map(func(fx): return fx.node.get_instance_id())

func wait_until(condition: Callable, limit: int) -> void:
	# Runs the arena without capturing until just before the event under review.
	for f in limit:
		if condition.call(): return
		await physics_frame
		arena._physics_process(1.0 / 60.0)

func film(id: String, label: String, frames: int, every: int, focus: Vector3, zoom: float, before: Callable = Callable()) -> void:
	# Steps the real arena update; keeps a contact sheet of close-ups, plus one native-scale
	# frame a few ticks after the first new effect appears.
	var shots: Array[Image] = []
	# Effects alive before filming (and the staff trail, which is not an effect record) don't count.
	var baseline := vfx_ids()
	var native_in := -1
	var native_frame := -1
	for f in frames:
		if before.is_valid(): before.call(f)
		await physics_frame
		arena._physics_process(1.0 / 60.0)
		suppress_hud()
		if native_frame < 0 and native_in < 0 and vfx_ids().any(func(id): return id not in baseline):
			native_in = 4
		if native_in >= 0:
			native_in -= 1
			if native_in < 0:
				native_frame = f
				arena.camera.size = 20.0 / 1.75 * arena.player_visual.MODEL_SCALE
				arena.place_camera(focus)
				assert((await grab()).save_png(output.path_join(id + "_native.png")) == OK)
				saved += 1
		if f % every == 0:
			arena.camera.size = zoom
			arena.place_camera(focus)
			var img := await grab()
			shots.append(img.get_region(Rect2i(290, 50, 700, 700)))
	var cols := 4
	var cell := 320
	var rows := int(ceil(shots.size() / float(cols)))
	var sheet := Image.create(cols * cell, rows * cell, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.05, 0.05, 0.06))
	for i in shots.size():
		var small := shots[i]
		small.convert(Image.FORMAT_RGBA8)
		small.resize(cell - 4, cell - 4, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(small, Rect2i(0, 0, cell - 4, cell - 4), Vector2i((i % cols) * cell + 2, int(i / cols) * cell + 2))
	assert(sheet.save_png(output.path_join(id + "_sheet.png")) == OK)
	saved += 1
	records.append({"id": id, "label": label, "frames": frames, "every": every, "sheet": id + "_sheet.png", "busiest_frame": native_frame})


func run() -> void:
	root.size = Vector2i(1280, 800)
	arena = load("res://main.tscn").instantiate(); root.add_child(arena)
	arena.set_physics_process(false); arena.set_process_input(false); arena.set_process_unhandled_input(false)
	await process_frame
	DirAccess.make_dir_recursive_absolute(output)
	if only in ["", "combat"]: await combat_scenes()
	if only in ["", "summons"]: await summon_scenes()
	var file := FileAccess.open(output.path_join("captures%s.json" % ("" if only == "" else "_" + only)), FileAccess.WRITE)
	file.store_string(JSON.stringify({"saved": saved, "records": records}, "  ") + "\n")
	print("REVIEW_COMBAT_VFX_DONE saved=%d" % saved)
	quit(0)

func combat_scenes() -> void:
	# Player basic attacks with each tool, then a forced crit.
	for plan in [
			{"id": "staff", "label": "지팡이 기본 공격", "tool": "", "key": ""},
			{"id": "bolt_cutter", "label": "볼트 커터", "tool": "", "key": "q"},
			{"id": "grinder", "label": "그라인더", "tool": "grinder", "key": "r"},
			{"id": "chainsaw", "label": "전기톱", "tool": "chainsaw", "key": "r"},
			{"id": "crit", "label": "치명타 (지팡이)", "tool": "", "key": "", "crit": true}]:
		prepare(plan.tool)
		target("dummy", Vector3(1.5, 0, 0), "rag")
		if plan.key != "": arena.request_slot(plan.key, {})
		if plan.get("crit", false): arena.force_rolls = {"hit": true, "crit": true}
		arena.request_slot("lmb", {"enemy_id": "dummy"})
		await film(plan.id, plan.label, 48, 2, Vector3(0.8, 0.6, 0), 4.2)

	# Shotgun: two targets in the cone and a wall that stops the side traces.
	prepare()
	target("dummy", Vector3(3.4, 0, 0), "rag")
	target("dummy2", Vector3(4.0, 0, 1.0), "rag")
	wall(Vector3(2.6, 0.825, -1.6), Vector3(0.2, 1.65, 1.6))
	await physics_frame
	arena.request_slot("rmb", {"enemy_id": "dummy"})
	await film("shotgun", "산탄 · 탄선/총구 연기/벽 착탄", 40, 2, Vector3(1.8, 0.6, 0), 6.0)

	# Enemy attacks against the witch: rag claw, crow bolt, brute charge.
	prepare()
	arena.hp = 100000.0
	var rag := target("rag", Vector3(1.0, 0, 0), "rag", false)
	rag.cooldown = 0.0
	await film("rag_claw", "넝마귀 할퀴기 → 피격", 48, 2, Vector3(0.5, 0.6, 0), 4.2)
	prepare()
	arena.hp = 100000.0
	var crow := target("crow", Vector3(6.0, 0, 0), "crow", false)
	crow.cooldown = 0.0
	await film("crow_bolt", "까마귀 전기탄", 96, 4, Vector3(3.0, 0.6, 0), 8.0)
	prepare()
	arena.hp = 100000.0
	var brute := target("brute", Vector3(5.0, 0, 0), "brute", false)
	brute.cooldown = 0.0; brute.charge_cooldown = 0.0
	await film("brute_charge", "철문 아귀 돌진 경고 → 먼지", 108, 6, Vector3(2.5, 0.6, 0), 8.0)

	# Boss: warnings during the sweep wind-up, the sweep release, the chained slam, then the shockwave.
	prepare()
	arena.hp = 100000.0
	arena.config.enemy_speed = 0.0
	arena.player.position = Vector3(0, 0, 2.7)
	arena.spawn_enemy("boss", Vector3.ZERO, true, "boss", "latch")
	var boss: Dictionary = arena.enemies.boss
	await film("boss_warning", "보스 휩쓸기 경고 채움", 84, 7, Vector3(0, 0.6, 2.0), 10.0)
	await wait_until(func(): return boss.attack == "sweep" and boss.windup < 0.12, 120)
	await film("boss_sweep", "보스 휩쓸기 발동", 32, 2, Vector3(0, 0.6, 2.0), 10.0)
	await wait_until(func(): return boss.attack == "slam" and boss.windup < 0.12, 200)
	await film("boss_slam", "보스 내려찍기 발동", 64, 4, Vector3(0, 0.6, 2.5), 11.0)
	prepare()
	arena.hp = 100000.0
	arena.config.enemy_speed = 0.0
	arena.player.position = Vector3(0, 0, 4.5)
	arena.spawn_enemy("boss", Vector3.ZERO, true, "boss", "latch")
	boss = arena.enemies.boss
	boss.pattern_dir = Vector3.BACK
	var wave: Dictionary = arena.config.enemy_types.latch.boss.shockwave
	arena.begin_boss(boss, "shockwave", wave.windup)
	arena.disc_warning(boss.body.position, wave.radius, wave.windup)
	await wait_until(func(): return boss.windup < 0.12, 200)
	await film("boss_shockwave", "보스 충격파 발동", 64, 4, Vector3(0, 0.6, 0.5), 14.0)

func summon_prepare(node_kind: String) -> void:
	prepare()
	arena.hp = 100000.0
	arena.config.enemy_speed = 0.0
	arena.config.automaton_node = node_kind

func summon_scenes() -> void:
	# Turret: arrival settle, brass slugs and their hits.
	summon_prepare("base")
	target("dummy", Vector3(4.0, 0, 0), "brute")
	arena.spawn_ally(Vector3(1.2, 0, 0.8), false, "")
	await film("turret_fire", "포탑 착지 → 사격 · 착탄", 96, 4, Vector3(2.4, 0.6, 0.4), 6.5)
	# Base automaton pulse shots, then its end-of-life self-destruct.
	summon_prepare("base")
	target("dummy", Vector3(3.2, 0, 0), "brute")
	arena.spawn_ally(Vector3(1.0, 0, 0.8), true, "dummy")
	await film("automaton_fire", "태엽인형(기본) 사격", 72, 3, Vector3(2.0, 0.6, 0.4), 6.0)
	arena.allies[0].life = 0.02
	await film("automaton_blast", "태엽인형 수명 종료 자폭", 60, 3, Vector3(2.0, 0.6, 0.4), 7.0)
	# A node runs in and detonates with the bigger blast.
	summon_prepare("A")
	target("dummy", Vector3(4.5, 0, 0), "brute")
	arena.spawn_ally(Vector3(0.8, 0, 0.8), true, "dummy")
	await film("automaton_a_blast", "A 자폭 노드 돌진 → 대형 폭발", 120, 5, Vector3(2.6, 0.6, 0.4), 7.5)
	# B node saw cutting sprays sparks instead of firing.
	summon_prepare("B")
	target("dummy", Vector3(2.6, 0, 0), "brute")
	arena.spawn_ally(Vector3(1.0, 0, 0.6), true, "dummy")
	await film("automaton_b_saw", "B 절삭 노드 톱 절삭", 96, 4, Vector3(1.9, 0.6, 0.3), 5.5)
	# Summon taking hits, then destroyed (no blast); turret lifetime shutdown.
	summon_prepare("base")
	arena.spawn_ally(Vector3(1.4, 0, 0.6), false, "")
	for i in 12:
		await physics_frame; arena._physics_process(1.0 / 60.0)
	var turret: Dictionary = arena.allies[0]
	var hits := func(f: int) -> void:
		if f == 4 or f == 22: arena.damage_ally(turret, 3.0, "normal")
		if f == 40: arena.damage_ally(turret, 9999.0, "normal")
	await film("summon_hit_break", "소환체 피격 → 파괴", 72, 3, Vector3(1.4, 0.6, 0.6), 4.5, hits)
	summon_prepare("base")
	# A distant enemy keeps the field uncleared, so the turret clock still runs.
	target("far", Vector3(-9.0, 0, -9.0), "rag")
	arena.spawn_ally(Vector3(1.4, 0, 0.6), false, "")
	for i in 12:
		await physics_frame; arena._physics_process(1.0 / 60.0)
	arena.allies[0].life = 0.02
	await film("turret_shutdown", "포탑 수명 종료", 60, 3, Vector3(1.4, 0.6, 0.6), 4.5)
	# Target relay links every eligible summon to the marked enemy.
	summon_prepare("base")
	arena.state = arena.rules.bind(arena.state, "r", "relay")
	target("dummy", Vector3(2.8, 0, -0.6), "brute")
	target("other", Vector3(-2.4, 0, 1.2), "rag")
	arena.spawn_ally(Vector3(-0.9, 0, 1.0), false, "")
	arena.spawn_ally(Vector3(0.6, 0, 1.3), true, "other")
	for i in 30:
		await physics_frame; arena._physics_process(1.0 / 60.0)
	arena.request_slot("r", {"enemy_id": "dummy"})
	await film("relay", "표적 중계 연결", 48, 2, Vector3(0.5, 0.6, 0.3), 8.0)
