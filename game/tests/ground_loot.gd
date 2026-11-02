extends SceneTree
## Crowded drops, label lifetime/Alt, shared hover/click targets and cosmetic drop motion.
var arena: Node3D
var checks: Array = []
var failures: Array = []
var rng := RandomNumberGenerator.new()
var output: String

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks.append(description)
	if not ok:
		failures.append(description)
		push_error(description)

func pile(at: Vector3, count: int) -> void:
	for i in count:
		var item: Dictionary = arena.items.generate(rng, 20, ["normal", "magic", "rare", "unique"][i % 4])
		# Identical names must still select different item instances.
		if i % 3 == 0:
			item.name = "겹친 이름의 반지"
		arena.drop_item(item, at)

func check_spacing(description: String) -> void:
	var separated := true
	var walkable := true
	for i in arena.ground_items.size():
		var a: Vector3 = arena.ground_items[i].node.position
		walkable = walkable and arena.map.walkable(a)
		for j in i:
			var b: Vector3 = arena.ground_items[j].node.position
			separated = separated and Vector2(a.x - b.x, a.z - b.z).length() >= 0.699
	check(separated and walkable, description)

func check_labels(description: String) -> void:
	var layout: Array = arena.loot_labels()
	var separated := true
	var selectable := true
	for i in layout.size():
		for j in i:
			separated = separated and not layout[i].rect.intersects(layout[j].rect)
		selectable = selectable and is_same(arena.loot_at(layout[i].rect.get_center()), layout[i].loot)
		selectable = selectable and is_same(arena.loot_at(layout[i].anchor), layout[i].loot)
	check(layout.size() == arena.ground_items.size() and separated and selectable, description)

func capture(name: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	arena.hud.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png(output.path_join(name + ".png"))
	check(result == OK, name + " GPU capture saved")

func alt(pressed: bool = true, echo: bool = false) -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_ALT
	key.pressed = pressed
	key.echo = echo
	root.push_input(key, true)

func point_at(screen: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	root.push_input(motion, true)
	arena.update_loot_hover(screen)

func timed_labels_and_motion() -> void:
	arena.reset_arena()
	arena.bag.clear()
	arena.show_all_loot_labels = false
	arena.place_camera(arena.player.position)
	pile(arena.player.position + Vector3(1, 0, 0), 2)
	var first: Dictionary = arena.ground_items[0]
	var second: Dictionary = arena.ground_items[1]
	var floor_position: Vector3 = first.node.position
	check(arena.loot_labels().size() == 2 and is_equal_approx(first.visual.global_position.y - floor_position.y, 0.95), "fresh drops start at waist height with labels visible")
	await capture("drop_start")
	await physics_frame
	arena._physics_process(1.0 / 60.0)
	check(first.age > 0 and first.visual.position.y > 0, "the actual arena frame advances the drop presentation")
	arena.tick_ground_loot(0.08)
	var early_height: float = first.visual.position.y
	var early_rotation: Vector3 = first.visual.rotation
	check(early_height > 0.8 and early_height < 0.95 and first.node.position == floor_position, "the mesh starts falling while its pickup destination stays on the floor")
	check(early_rotation.length() > 1.0, "the airborne item visibly tumbles rather than only spinning about its symmetry axis")
	await capture("drop_rotating")
	arena.tick_ground_loot(0.1)
	check(first.visual.position.y < early_height and first.visual.rotation.x > early_rotation.x, "the item continues falling and rotating toward the floor")
	check(is_same(arena.loot_at(arena.camera.unproject_position(first.visual.global_position)), first), "the airborne mesh remains selectable at its drawn position")
	await capture("drop_mid_fall")
	var age: float = first.age
	var height: float = first.visual.position.y
	var rotation: Vector3 = first.visual.rotation
	arena.paused = true
	arena.tick_ground_loot(10.0)
	check(first.age == age and first.visual.position.y == height and first.visual.rotation == rotation, "pause freezes label lifetime, fall and rotation")
	arena.paused = false
	arena.tick_ground_loot(0.1)
	check(first.visual.position.y < height and first.visual.position.y > 0, "the item keeps descending until impact")
	arena.tick_ground_loot(0.11)
	check(first.age < 0.42 and first.visual.position == Vector3.ZERO and first.visual.rotation == Vector3.ZERO and first.node.position == floor_position, "the faster drop lands flat in 0.4s without drift")
	await capture("drop_landed")
	arena.update_loot_hover(Vector2(3, 3))
	arena.tick_ground_loot(4.99 - first.age)
	var old_rect: Rect2 = arena.loot_labels()[0].rect
	check(arena.loot_labels().size() == 2, "uncollected labels remain visible just before five seconds")
	var hovered_rect: Rect2 = arena.loot_labels()[1].rect
	arena.update_loot_hover(hovered_rect.get_center())
	arena.tick_ground_loot(0.02)
	arena.update_loot_hover(hovered_rect.get_center())
	check(is_same(arena.hovered_loot, second) and arena.loot_labels().size() == 1 and arena.loot_labels()[0].rect == hovered_rect, "a label under the pointer stays in place when the other labels time out")
	arena.update_loot_hover(Vector2(3, 3))
	check(arena.loot_labels().is_empty() and arena.ground_items.size() == 2, "at five seconds only labels disappear; the items remain")
	check(arena.loot_at(old_rect.get_center()).is_empty(), "an invisible label has no stale clickable area")
	await capture("labels_hidden")
	arena.update_loot_hover(arena.camera.unproject_position(first.visual.global_position))
	var shown: Array = arena.loot_labels()
	check(shown.size() == 1 and is_same(shown[0].loot, first) and first.selection.visible, "hover reveals and highlights only that expired item's label")
	arena.update_loot_hover(shown[0].rect.get_center())
	check(is_same(arena.hovered_loot, first) and arena.loot_labels().size() == 1, "moving from the item onto its revealed label keeps it visible and selected")
	await capture("labels_hover_only")
	arena.update_loot_hover(arena.camera.unproject_position(second.visual.global_position))
	shown = arena.loot_labels()
	check(shown.size() == 1 and is_same(shown[0].loot, second) and not first.selection.visible, "switching between old items rebuilds the single label for the correct item")
	arena.update_loot_hover(Vector2(3, 3))
	check(arena.loot_labels().is_empty(), "leaving an old item hides its label again")
	point_at(Vector2(3, 3))
	alt()
	check(arena.show_all_loot_labels and arena.loot_labels().size() == 2, "holding Alt shows all old labels")
	alt(true, true)
	check(arena.show_all_loot_labels, "Alt key repeat does not change the held state")
	check_labels("all labels restored by Alt remain separated and clickable")
	await capture("labels_alt_all")
	alt(false)
	check(not arena.show_all_loot_labels and arena.loot_labels().is_empty() and first.age == 5.0, "releasing Alt immediately restores expired labels to hidden without resetting their age")
	alt()
	point_at(arena.loot_labels()[0].rect.get_center())
	check(not arena.hovered_loot.is_empty(), "a label temporarily revealed by Alt can be hovered")
	alt(false)
	check(arena.loot_labels().is_empty() and arena.hovered_loot.is_empty(), "an Alt-revealed label under the cursor cannot remain stuck visible after release")
	point_at(arena.camera.unproject_position(first.visual.global_position))
	alt()
	alt(false)
	check(arena.loot_labels().size() == 1 and is_same(arena.hovered_loot, first), "a cursor over the actual item still reveals only that label after Alt release")
	point_at(Vector2(3, 3))
	arena.inventory_window.show()
	await process_frame
	alt()
	check(arena.show_all_loot_labels, "Alt remains available while the inventory is open")
	point_at(arena.inventory_window.get_global_rect().get_center())
	alt(false)
	check(not arena.show_all_loot_labels and arena.loot_labels().is_empty(), "releasing Alt over the inventory hides expired labels immediately")
	arena.inventory_window.hide()
	point_at(Vector2(3, 3))
	alt()
	arena._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not arena.show_all_loot_labels and arena.loot_labels().is_empty(), "losing focus clears the held Alt display even without a key release")
	alt(false)
	pile(arena.player.position + Vector3(-1, 0, 0), 1)
	check(arena.loot_labels().size() == 1 and is_same(arena.loot_labels()[0].loot, arena.ground_items[-1]), "a later drop gets its own five-second label without revealing old loot")
	var airborne: Dictionary = arena.ground_items[-1]
	arena.tick_ground_loot(0.15)
	arena.player.position = airborne.node.position
	arena.pick_up(airborne)
	check(arena.bag.any(func(item): return is_same(item, airborne.item)) and arena.ground_items.size() == 2, "picking up during the spinning fall removes the item normally")
	await process_frame
	arena.tick_ground_loot(1.0)
	check(not is_instance_valid(airborne.node) and arena.loot_labels().is_empty(), "pickup leaves no airborne mesh or label timer behind")
	pile(arena.player.position + Vector3(-1, 0, 0), 1)
	var fresh_drop: Dictionary = arena.ground_items[-1]
	alt()
	arena.tick_ground_loot(1.0)
	alt(false)
	check(arena.loot_labels().size() == 1 and is_same(arena.loot_labels()[0].loot, fresh_drop), "releasing Alt preserves the remaining initial display time of a fresh drop")
	alt()
	arena.tick_ground_loot(4.1)
	check(arena.loot_labels().size() == 3, "all labels stay shown while Alt is held across a timeout")
	alt(false)
	check(arena.loot_labels().is_empty() and fresh_drop.age == 5.0, "a drop that expires during Alt is hidden immediately on release")
	arena.reset_arena()

func run() -> void:
	output = ProjectSettings.globalize_path("res://../reports/loot_selection")
	DirAccess.make_dir_recursive_absolute(output)
	rng.seed = 29
	arena = load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	arena.muted = true
	arena.help_visible = false
	await physics_frame
	await physics_frame
	var combat_state: int = arena.combat_rng.state
	var loot_state: int = arena.loot_rng.state
	pile(Vector3(1.8, 0, 0), 24)
	check(arena.ground_items.size() == 24, "all 24 drops at one point stay on the field")
	check_spacing("repeated drops have at least 0.7m separation on walkable ground")
	check(arena.combat_rng.state == combat_state and arena.loot_rng.state == loot_state, "spacing does not consume combat or loot RNG")
	check_labels("24 labels do not overlap; every label and disc selects its own item")
	var first: Dictionary = arena.loot_labels()[0]
	var second: Dictionary = arena.loot_labels()[1]
	arena.update_loot_hover(first.rect.get_center())
	check(is_same(arena.hovered_loot, first.loot) and first.loot.selection.visible and arena.GroundLootVisual.highlighted(first.loot.visual), "hovering a label highlights that item and its label")
	await capture("crowded_hover")
	arena.update_loot_hover(second.anchor)
	check(is_same(arena.hovered_loot, second.loot) and second.loot.selection.visible and not first.loot.selection.visible and not arena.GroundLootVisual.highlighted(first.loot.visual), "moving onto another disc transfers both highlights")
	arena.update_loot_hover(Vector2(3, 3))
	check(arena.hovered_loot.is_empty() and not second.loot.selection.visible, "leaving loot clears its highlight")
	arena.update_loot_hover(Vector2(640, 780))
	check(arena.hovered_loot.is_empty(), "the bottom HUD does not select ground loot")
	arena.paused = true
	arena.update_loot_hover(first.rect.get_center())
	check(arena.hovered_loot.is_empty(), "paused play does not offer an unavailable pickup")
	arena.paused = false
	arena.held_item = first.loot.item
	arena.update_loot_hover(first.rect.get_center())
	check(arena.hovered_loot.is_empty(), "carrying an inventory item suppresses ground pickup highlighting")
	arena.held_item = null
	for window in [arena.inventory_window, arena.character_window, arena.skill_window]:
		window.show()
		await process_frame
		window.position = first.rect.get_center() - Vector2(20, 20)
		arena.update_loot_hover(first.rect.get_center())
		check(arena.hovered_loot.is_empty() and arena.loot_at(first.rect.get_center()).is_empty(), "visible %s blocks loot under it" % window.name)
		window.hide()
	arena.place_camera(Vector3(0.6, 0, 0.3))
	check_labels("camera movement refreshes both the drawn labels and their click areas")
	var original_size: Vector2i = root.size
	root.size = Vector2i(1024, 720)
	await process_frame
	check_labels("labels remain separated and selectable at 1024x720")
	root.size = original_size
	await process_frame
	first = arena.loot_labels()[0]
	arena.player.position = first.loot.node.position
	arena.update_loot_hover(first.rect.get_center())
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = first.rect.get_center()
	root.push_input(click, true)
	click.pressed = false
	root.push_input(click, true)
	check(arena.bag.any(func(item): return is_same(item, first.loot.item)) and arena.ground_items.size() == 23 and arena.hovered_loot.is_empty(), "a real click picks up exactly the highlighted item and clears its hover")
	arena.reset_arena()
	check(arena.ground_items.is_empty() and arena.loot_labels().is_empty() and arena.hovered_loot.is_empty(), "restart removes loot, label cache and hover together")
	await timed_labels_and_motion()
	pile(Vector3(14.2, 0, 12.2), 32)
	check_spacing("32 repeated drops near a field corner stay separated and inside the map")
	arena.load_map("alley_v1")
	for i in 180:
		await physics_frame
		if arena.map.nav_ready():
			break
	check(arena.map.nav_ready(), "actual alley navigation is ready")
	var at: Vector3 = arena.map.start_point() + Vector3(0.8, 0, -0.6)
	pile(at, 16)
	arena.place_camera(arena.player.position)
	check_spacing("actual alley drops stay separated on walkable floor")
	check_labels("actual alley labels and discs share unambiguous click targets")
	first = arena.loot_labels()[0]
	arena.tick_ground_loot(5.1)
	arena.update_loot_hover(arena.camera.unproject_position(first.loot.visual.global_position))
	check(arena.loot_labels().size() == 1, "actual alley shows only the hovered old label")
	await capture("alley_hover")
	var report := {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  ") + "\n")
	print("GROUND_LOOT_RESULT " + JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
