extends SceneTree
var output := ""
var checks: Array = []
var failures: Array = []
var arena: Node3D
var max_anchor_error := 0.0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	call_deferred("run")

func check(ok: bool,label: String) -> void:
	checks.append(label)
	if not ok:failures.append(label)

func run() -> void:
	arena=load("res://main.tscn").instantiate()
	arena.field_entry_mode=1
	root.add_child(arena)
	arena.set_physics_process(false)
	await process_frame
	check(arena.player_visual.use_entry_polish_v27,"v27 enabled by default without a debug override")
	check(arena.player_visual.loaded_ok,"player loads the auxiliary hair rig")
	if not arena.player_visual.loaded_ok:
		finish();return
	for rate in [30,60,120]:
		arena.reset_arena();arena.muted=true
		await process_frame
		var v=arena.player_visual
		var body:Skeleton3D=v.runtime.skeleton
		var rig:Skeleton3D=v._hair_motion._rig
		check(body.get_bone_count()==107 and rig.get_bone_count()==8,"107 body bones and independent 8-bone hair %d"%rate)
		var reveals:=0
		var previous:float=0.0
		var body_id:int=body.get_instance_id()
		for frame in rate*3:
			arena._physics_process(1.0/rate)
			for anchor in ["DEF-head","DEF-chest"]:
				var a:Transform3D=rig.global_transform*rig.get_bone_global_pose(rig.find_bone(anchor))
				var b:Transform3D=body.global_transform*body.get_bone_global_pose(body.find_bone(anchor))
				max_anchor_error=maxf(max_anchor_error,a.origin.distance_to(b.origin))
				check(a.basis.is_equal_approx(b.basis),"hair anchor orientation %s %d/%d"%[anchor,rate,frame])
			var reveal=v._entry._reveal
			if reveal.active:
				reveals+=1
				check(reveal.previews.size()==2 and reveal.progress>=previous,"complementary clothed reveal advances %d/%d"%[rate,frame])
				previous=reveal.progress
				for mesh in v.runtime.slots.outfit.find_children("*","MeshInstance3D",true,false):
					check(not mesh.visible,"logical outfit hidden only while clothed previews render %d/%d"%[rate,frame])
		check(reveals>10,"progressive reveal spans multiple frames %d"%rate)
		check(v.form=="transformed" and not v.field_entry_active(),"same three-second entry endpoint %d"%rate)
		check(v.runtime.skeleton.get_instance_id()==body_id,"body skeleton retained %d"%rate)
		check(v._entry._reveal.previews.is_empty() and v._entry._reveal.hidden_meshes.is_empty(),"no transient reveal remains %d"%rate)
		for mesh in v.runtime.slots.outfit.find_children("*","MeshInstance3D",true,false):
			check(mesh.visible,"finished outfit visible %d"%rate)
	check(max_anchor_error<.0001,"head and chest hair anchors within 0.1mm")
	for t in [2.2,2.5]:
		arena.reset_arena();arena.muted=true
		await process_frame
		var v=arena.player_visual
		for frame in int(t*60):arena._physics_process(1.0/60.0)
		var before:Dictionary=v.debug_snapshot()
		var hair_pose:Transform3D=v._hair_motion._rig.get_bone_global_pose(v._hair_motion._rig.find_bone("DEF-hair.02.L"))
		arena.paused=true
		for i in 30:arena._physics_process(1.0/60.0)
		check(v._entry.elapsed==before.field_entry.elapsed and v._entry._reveal.progress==before.field_entry.reveal.progress,"pause holds reveal %.1f"%t)
		check(v._hair_motion._rig.get_bone_global_pose(v._hair_motion._rig.find_bone("DEF-hair.02.L")).is_equal_approx(hair_pose),"pause holds hair %.1f"%t)
		arena.paused=false
		v.freeze_for_death()
		check(v._entry._reveal.previews.is_empty(),"death clears reveal before/after logical swap %.1f"%t)
		for mesh in v.runtime.slots.outfit.find_children("*","MeshInstance3D",true,false):check(mesh.visible,"cancel restores complete garment %.1f"%t)
	arena.reset_arena();await process_frame
	var v=arena.player_visual
	var old_id:int=v.runtime.slots.hair.get_instance_id()
	check(not v.replace_parts({"hair":{"asset":v.PARTS.eyes.asset,"auxiliary_hair":true}}),"invalid auxiliary rig is rejected")
	check(v.runtime.slots.hair.get_instance_id()==old_id,"failed hair replacement preserves existing hair")
	check(v.replace_parts({"hair":{"asset":v.ASSET_DIR+"hair_semilong_v21.glb","hide_body_regions":[]}}),"old compatible hair can still be equipped")
	check(v.replace_parts({"hair":v.HAIR_V27}),"bone-driven hair can be re-equipped")
	check(v.runtime.skeleton.get_bone_count()==107,"hair changes never add bones to shared body")
	finish()

func finish() -> void:
	var result:Dictionary={"passed":failures.is_empty(),"checks":checks.size(),"failures":failures,"max_anchor_error_m":max_anchor_error}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("TRANSFORMATION_V27_CHECKS ",JSON.stringify(result))
	arena.free();quit(0 if failures.is_empty() else 1)
