extends "res://tests/review_automation_actor_v1.gd"
## Actual-size lineup and shared-mesh node variants, isolated from arena rules.
var entries: Array[Dictionary] = []
var holders: Array[Node3D] = []
var hud: CanvasLayer
var player: Node3D

func add_actor(kind: String, size: float, at: Vector3, armour: bool = false) -> Dictionary:
	var holder := Node3D.new(); world.add_child(holder); holders.append(holder)
	holder.scale = Vector3.ONE * size; holder.position = at
	var version := "v2" if kind == "hound" else "v1"
	var path := "res://assets/actors/automation_batch2/%s_%s/%s_%s.glb" % [kind, version, kind, version]
	var base: Node3D = load(path).instantiate(); holder.add_child(base)
	var ap: AnimationPlayer = base.find_children("*", "AnimationPlayer", true, false)[0]
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var entry := {"holder": holder, "base": base, "ap": ap, "kind": kind, "armour": null, "armour_ap": null}
	if armour:
		var extra: Node3D = load("res://assets/actors/automation_batch2/%s_armour_v1/%s_armour_v1.glb" % [kind, kind]).instantiate()
		holder.add_child(extra); entry.armour = extra
		var aa: AnimationPlayer = extra.find_children("*", "AnimationPlayer", true, false)[0]
		aa.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL; entry.armour_ap = aa
	entries.append(entry); return entry

func pose_entry(entry: Dictionary, clip: String, t: float) -> void:
	for ap in [entry.ap, entry.armour_ap]:
		if ap == null: continue
		ap.play(clip); ap.seek(t, true); ap.advance(0)
	for target in [entry.base, entry.armour]:
		if target == null: continue
		for sk in target.find_children("*", "Skeleton3D", true, false): sk.force_update_all_bone_transforms()
	Presentation.sample(entry.base, entry.kind, clip, t)

func floor_at(x: float, depth: float = 0.0) -> Vector3:
	return Vector3(.70710678,0,-.70710678)*x + Vector3(.70710678,0,.70710678)*depth

func label(text: String, at: Vector3, width: float = 140.0) -> void:
	var item := Label.new(); hud.add_child(item); item.text = text
	item.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; item.size.x = width
	item.add_theme_font_size_override("font_size", 16)
	item.position = camera.unproject_position(at) + Vector2(-width/2, 14)

func clear_actors() -> void:
	for holder in holders: holder.free()
	holders.clear(); entries.clear()
	for item in hud.get_children(): item.free()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output); make_world(); root.size = Vector2i(1280,800)
	hud = CanvasLayer.new(); root.add_child(hud)
	player = PlayerVisual.new(); world.add_child(player); check(player.initialize(), "current witch loads")
	player.set_process(false); player._sample("idle", .5)
	camera.rotation_degrees = Vector3(-30,45,0)
	camera.size = 20.0 / 1.75 * player.MODEL_SCALE
	camera.position = Vector3(0,.7,0) + camera.basis.z * 30
	metrics["native_camera"] = {"size":camera.size, "pitch":-30,"yaw":45,"resolution":[1280,800],"model_height_m":1.5,"studio_lighting_only":true}
	player.position = floor_at(-7.0); label("Witch", player.position)
	for row in [["hound",-5.7],["beacon",-4.3],["giant",-1.9]]:
		var entry := add_actor(row[0],1.0,floor_at(row[1])); pose_entry(entry,"pulse" if row[0]=="beacon" else "idle",.2)
		label(row[0], entry.holder.position)
	for row in [["automaton",.65],["turret",2.0],["rag",3.4],["crow",4.9],["brute",6.5]]:
		var holder := Node3D.new(); world.add_child(holder); holders.append(holder); holder.position=floor_at(row[1])
		var visual: Node3D = Actors.create(holder,row[0]); check(visual!=null and visual.loaded_ok,"existing actor "+row[0]); visual.sample("idle",.2)
		label(row[0],holder.position)
	await capture("native_lineup.jpg")
	for holder in holders: holder.rotation.y=PI
	player.rotation.y=PI
	await capture("native_lineup_front.jpg")
	player.rotation.y=0
	clear_actors()
	player.position = floor_at(-7.0); label("Witch",player.position)
	for row in [["hound",1.0,-5.6,false,"Hound 1.0"],["hound",1.2,-3.8,true,"Heavy 1.2"],["giant",1.0,-.5,false,"Giant 1.0"],["giant",1.1,3.6,true,"Enhanced 1.1"]]:
		var entry := add_actor(row[0],row[1],floor_at(row[2]),row[3]); pose_entry(entry,"idle",.2); label(row[4],entry.holder.position)
	await capture("enhanced_lineup.jpg")
	for holder in holders: holder.rotation.y=PI
	player.rotation.y=PI
	await capture("enhanced_lineup_front.jpg")
	player.rotation.y=0
	clear_actors(); player.position=floor_at(-7.0); label("Witch",player.position)
	var hounds: Array[Dictionary] = []; var giants: Array[Dictionary] = []
	for i in 3:
		hounds.append(add_actor("hound",.8,floor_at(-5.6+i*1.2,-.2 if i==1 else .2)))
		giants.append(add_actor("giant",.75,floor_at(-.7+i*2.7,-.2 if i==1 else .2)))
	for holder in holders: holder.rotation.y=PI
	player.rotation.y=PI
	var hound_mesh: Mesh = hounds[0].base.find_children("*","MeshInstance3D",true,false)[0].mesh
	var giant_mesh: Mesh = giants[0].base.find_children("*","MeshInstance3D",true,false)[0].mesh
	for i in 3:
		check(hounds[i].base.find_children("*","MeshInstance3D",true,false)[0].mesh==hound_mesh,"hound pack shares unchanged base mesh")
		check(giants[i].base.find_children("*","MeshInstance3D",true,false)[0].mesh==giant_mesh,"giant pack shares unchanged base mesh")
		label("Hound %d / 0.8"%(i+1),hounds[i].holder.position)
		label("Giant %d / 0.75"%(i+1),giants[i].holder.position)
	for frame in 144:
		for i in 3:
			pose_entry(hounds[i],"run",fmod(frame/24.0+i*.08,.5))
			pose_entry(giants[i],"walk",fmod(frame/24.0+i*.17,1.2))
		await capture("multiple/%03d.jpg"%frame)
	clear_actors(); player.hide()
	var giant := add_actor("giant",1.0,Vector3.ZERO)
	pose_entry(giant,"slam",.55)
	art_height=2.8; place("side"); await capture("slam_contact_side.jpg")
	place("front"); await capture("slam_contact_front.jpg")
	clear_actors()
	var result := {"passed":failures.is_empty(),"checks":checks,"failures":failures,"captures":captures,"metrics":metrics,"scope":"prepared art at actual game camera; no gameplay integration"}
	FileAccess.open(output.path_join("runtime_validation.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("AUTOMATION_BATCH2_REVIEW ",JSON.stringify(result));quit(0 if failures.is_empty() else 1)
