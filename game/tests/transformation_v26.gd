extends SceneTree
var arena: Node3D
var output := ""
var checks: Array = []
var failures: Array = []
var bone_error := 0.0
var grip_error := 0.0
var attachment_jump := 0.0
var cases: Array = []

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks.append(label)
	if not ok: failures.append(label)

func advance(count: int, dt: float = 1.0/60.0) -> void:
	for i in count:
		await physics_frame
		arena._physics_process(dt)

func fresh() -> void:
	arena.reset_arena()
	arena.muted = true
	arena.config.enemy_speed = 0.0
	arena.config.mana_regen = 0.0
	arena.force_rolls={"hit":true,"crit":false}
	for enemy in arena.enemies.values(): enemy.cooldown=999.0

func run() -> void:
	arena=load("res://main.tscn").instantiate()
	arena.field_entry_mode=1
	root.add_child(arena)
	arena.set_physics_process(false)
	arena.set_process_input(false)
	arena.set_process_unhandled_input(false)
	await process_frame
	arena.load_map("flat")
	fresh()
	var v=arena.player_visual
	check(v.loaded_ok and v.field_entry_active(),"explicit field entry starts on the actual game scene")
	check(v.form=="civilian" and not v.staff_root.visible,"first frame is clothed civilian with no staff")
	check((-v.global_basis.z).dot(Vector3(arena.camera.basis.z.x,0,arena.camera.basis.z.z).normalized())>.99,"standalone entry presents the gesture toward the game camera")
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../reports/transformation_v26/pose_fixture.json").simplify_path()))
	for sample in fixture.samples:
		v._sample("entry",float(sample.seconds))
		var bones:Skeleton3D=v.runtime.skeleton
		for name in sample.bones:
			var p:Array=sample.bones[name]
			var actual:Vector3=v.asset_wrapper.global_transform.affine_inverse()*bones.global_transform*bones.get_bone_global_pose(bones.find_bone(name)).origin
			bone_error=maxf(bone_error,actual.distance_to(Vector3(p[0],p[1],p[2])))
	check(bone_error<.0003,"imported entry poses match reopened Blender within 0.3mm")
	for rate in [30,60,120]:
		fresh();v=arena.player_visual
		var body_id:int=v.runtime.body.get_instance_id()
		var skeleton_id:int=v.runtime.skeleton.get_instance_id()
		var hair_id:int=v.runtime.slots.hair.get_instance_id()
		var eyes_id:int=v.runtime.slots.eyes.get_instance_id()
		var old_outfit:int=v.runtime.slots.outfit.get_instance_id()
		var start:Vector3=arena.player.position
		var mana:float=arena.state.mana
		var hp:float=arena.hp
		var rng_state:int=arena.combat_rng.state
		var enemy_positions:Dictionary={}
		for id in arena.enemies: enemy_positions[id]=arena.enemies[id].body.position
		var no_empty_outfit:=true
		var no_early_change:=true
		var assembled_before_grasp:=true
		var origin_before:=Vector3.ZERO
		var prior_grasp:=false
		var phases:Array=[]
		var count:=0
		while v.field_entry_active() and count<rate*4:
			arena.request_slot("rmb",{"ground":[4,0,0]})
			if count in [0,rate,2*rate]: check(arena.windup.is_empty() and arena.queued_input.is_empty(),"entry rejects combat input %d/%d"%[rate,count])
			await advance(1,1.0/rate)
			var entry=v._entry
			no_empty_outfit=no_empty_outfit and is_instance_valid(v.runtime.slots.outfit) and v.runtime.slots.outfit.visible
			no_early_change=no_early_change and (v.form=="civilian" or entry.elapsed>=2.3999)
			if entry.grasped:
				for part in v.staff_visual._entry_parts:
					assembled_before_grasp=assembled_before_grasp and part.node.transform.is_equal_approx(part.rest)
				var bones:Skeleton3D=v.runtime.skeleton
				var right:Vector3=bones.global_transform*bones.get_bone_global_pose(bones.find_bone("DEF-hand.R"))*v.STAFF_GRIP_OFFSET
				grip_error=maxf(grip_error,right.distance_to(v.staff_root.to_global(Vector3(0,.26,0))))
				if not prior_grasp: attachment_jump=maxf(attachment_jump,origin_before.distance_to(v.staff_root.global_position))
			prior_grasp=entry.grasped
			origin_before=v.staff_root.global_position
			if phases.is_empty() or phases.back()!=entry.phase: phases.append(entry.phase)
			count+=1
		check(count==rate*3,"entry completes in 3 seconds at %d fps"%rate)
		check(phases==["civilian","assembly","grasp","outfit","ready"],"phase order is assembly then held staff then outfit at %d fps"%rate)
		check(no_empty_outfit and no_early_change,"covered outfit remains present through the complete transition at %d fps"%rate)
		check(assembled_before_grasp,"all common parts reach rest before grasp at %d fps"%rate)
		check(v.form=="transformed" and v.staff_root.visible,"entry ends with transformed outfit and visible staff")
		check(v.runtime.slots.outfit.get_instance_id()!=old_outfit and v.runtime.slots.outfit.find_children("TF_*","MeshInstance3D",true,false).size()==13,"the actual v4 outfit replaces the civilian slot")
		check(v.runtime.body.get_instance_id()==body_id and v.runtime.skeleton.get_instance_id()==skeleton_id and v.runtime.slots.hair.get_instance_id()==hair_id and v.runtime.slots.eyes.get_instance_id()==eyes_id,"body rig hair and eyes remain the same instances")
		check(arena.elapsed==0.0 and arena.player.position==start and arena.state.mana==mana and arena.hp==hp and arena.combat_rng.state==rng_state,"entry does not advance combat clocks movement costs HP or combat RNG")
		var unmoved:=true
		for id in arena.enemies:unmoved=unmoved and arena.enemies[id].body.position==enemy_positions[id]
		check(unmoved,"enemies wait until entry is finished")
		check(v._entry._overlays.is_empty() and not v._entry.visible and v._entry._light.light_energy==0.0,"entry clears overlays lights and particles")
		check(v._state=="idle" and v.staff_root.basis.is_equal_approx(v.STAFF_GRIP_BASIS),"held attachment and accepted idle are restored")
		arena.request_slot("rmb",{"ground":[4,0,0]})
		check(not arena.windup.is_empty(),"combat input starts normally after entry")
		cases.append({"fps":rate,"frames":count,"phases":phases})
	fresh();await advance(48);v=arena.player_visual
	var time:float=v._entry.elapsed
	var frame:Transform3D=v.staff_root.global_transform
	arena.paused=true;await advance(20)
	check(v._entry.elapsed==time and v.staff_root.global_transform==frame and arena.elapsed==0.0,"pause freezes entry pose parts and combat")
	arena.paused=false;await advance(132)
	check(not v.field_entry_active() and v.form=="transformed","pause resumes the same timeline to completion")
	for at in [30,150]:
		fresh();await advance(at)
		arena.reset_arena();v=arena.player_visual
		check(v._entry.elapsed==0.0 and v.form=="civilian" and not v.staff_root.visible,"reset during assembly or costume change restarts unarmed civilian")
		check(v.asset_wrapper.find_children("FieldEntryTransformation","Node3D",true,false).size()==1,"reset leaves one entry controller")
	fresh();await advance(55);arena.load_map("alley_v2");v=arena.player_visual
	check(v.field_entry_active() and v._entry.elapsed==0.0 and arena.player.position==arena.map.start_point(),"map entry restarts at the new field spawn")
	await advance(180)
	check(v.form=="transformed" and not v.field_entry_active(),"alley entry completes with the selected outfit")
	fresh();await advance(30);v=arena.player_visual
	arena.hp=0.0;await advance(2)
	check(not v.field_entry_active() and v.is_dead and not v._entry.visible,"forced death cancels entry and clears its effects")
	fresh();arena.muted=false
	var sound_start:int=arena.sound_index
	await advance(180)
	check(arena.sound_index-sound_start==3,"assembly grasp and outfit each trigger one existing audio cue")
	fresh();arena.muted=true;sound_start=arena.sound_index;await advance(180)
	check(arena.sound_index==sound_start,"mute suppresses all entry cues")
	v=arena.player_visual
	var slot=v.runtime.slots.outfit
	check(not v.set_form("invalid") and v.runtime.slots.outfit==slot and v.form=="transformed","invalid form preserves the selected outfit")
	check(v.set_form("civilian") and v.set_form("transformed"),"both forms remain replaceable on the shared rig")
	check(grip_error<.003 and attachment_jump<.003,"floating-to-hand attachment and held grip stay within 3mm")
	var result:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"cases":cases,"bone_error_m":bone_error,"grip_error_m":grip_error,"attachment_jump_m":attachment_jump}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("TRANSFORMATION_TEST_COMPLETE ",checks.size()," failures=",failures)
	arena.free();quit(0 if failures.is_empty() else 1)
