extends SceneTree
const Staff = preload("res://scripts/staff_visual.gd")
var failures: Array = []
var checks: Array = []
var output := ""
var arena: Node3D

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks.append(label)
	if not ok:
		failures.append(label)
		push_error(label)

func transforms(staff: Node3D) -> Array:
	return staff._parts.map(func(p): return p.node.transform)

func equal_poses(a: Array,b: Array) -> bool:
	if a.size()!=b.size():return false
	for i in a.size():
		if not a[i].is_equal_approx(b[i]):return false
	return true

func fresh() -> void:
	arena.reset_arena()
	for enemy in arena.enemies.values():enemy.body.free()
	arena.enemies.clear()
	arena.spawn_enemy("sentinel",Vector3(18,0,18),false,"normal","brute")
	arena.spawn_enemy("target",Vector3(1.6,0,0),false,"normal","rag")
	arena.enemies.target.hp=10000.0
	arena.enemies.target.max_hp=10000.0
	for enemy in arena.enemies.values():enemy.cooldown=999.0
	arena.player.position=Vector3.ZERO
	arena.config.enemy_speed=0.0
	arena.config.mana_regen=0.0
	arena.config.attack_speed_score=0.0
	arena.state.mana=500.0
	arena.state=arena.rules.bind(arena.state,"r","grinder")
	arena.state=arena.rules.bind(arena.state,"e","chainsaw")
	arena.muted=true
	arena.force_rolls={"hit":true,"crit":false}
	arena._physics_process(0.0)

func run() -> void:
	var staff=Staff.new()
	root.add_child(staff)
	check(staff.initialize(),"modular GLB and metadata load")
	check(staff.common_root.get_child_count()==9,"nine persistent common rigid meshes")
	check(staff._parts.size()==41,"41 independently assembled tool parts")
	var common_poses: Array=staff.common_root.get_children().map(func(n):return n.transform)
	check(staff.set_appearance("seal"),"equipment seal can be fitted")
	var seal:Node3D=staff._ornaments.ornament_seal
	var seal_id:=seal.get_instance_id()
	var seal_pose:=seal.transform
	check(not staff.set_appearance("unknown") and staff.appearance=="seal","invalid equipment appearance rolls back")
	for fps in [30,60]:
		for tool in Staff.TOOLS:
			staff.set_tool(tool)
			for frame in int(.5*fps):staff.advance(1.0/fps,false)
			var snap:Dictionary=staff.debug_state()
			check(snap.groups[tool].min>=.99999,"%d fps %s finishes assembly"%[fps,tool])
			for other in Staff.TOOLS:
				if other!=tool:check(snap.groups[other].max==0.0,"%d fps %s removes %s"%[fps,tool,other])
			check(common_poses==staff.common_root.get_children().map(func(n):return n.transform),"%s preserves shaft/core"%tool)
			check(seal.visible and seal_id==seal.get_instance_id() and seal_pose==seal.transform,"%s retains equipment ornament"%tool)
			var before:=transforms(staff)
			var clock:float=staff._mechanism_time
			staff.advance(.5,true)
			check(equal_poses(before,transforms(staff)) and staff._mechanism_time==clock,"%s mechanism pauses"%tool)
			staff.advance(.04,false)
			if tool!="bolt_cutter":check(not equal_poses(before,transforms(staff)),"%s mechanism actually moves"%tool)
		staff.set_tool(null)
		for frame in int(.2*fps):staff.advance(1.0/fps,false)
		check(staff._parts.all(func(p):return p.weight==0.0 and not p.node.visible),"%d fps unequip removes all module pieces"%fps)
	# Repeated reversals preserve the already assembled pose at the instant of each request.
	for i in 18:
		var before:=transforms(staff)
		staff.set_tool(Staff.TOOLS[i%3] if i%4 else null)
		check(equal_poses(before,transforms(staff)),"rapid switch %d does not teleport pieces"%i)
		staff.advance(.025,false)
	staff.set_tool("chainsaw")
	staff.finish_assembly()
	check(staff.debug_state().groups.chainsaw.min==1.0,"release hook completes the active head")
	check(staff._parts.filter(func(p):return p.spec.group!="chainsaw").all(func(p):return p.weight==0.0),"release hook clears departing heads")
	staff.advance(.01,false)
	for part in staff._parts:
		if part.spec.driver=="chain":
			var point:Vector3=part.node.position
			check(point.y>=.70 and point.y<=1.11 and absf(point.x)<=.070,"chain tooth follows guide: "+part.spec.name)
	# The reserved sliding grip is checked on actual imported vertex positions.
	var grip_max:=0.0
	for mesh in staff.common_root.get_children():
		for surface in mesh.mesh.get_surface_count():
			var vertices:PackedVector3Array=mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var p:Vector3=mesh.transform*vertex
				if p.y>-.42 and p.y<.35:grip_max=maxf(grip_max,Vector2(p.x,p.z).length())
	check(grip_max<=.0111,"imported sliding grip radius stays within 11.1 mm")
	staff.free()
	arena=load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	await process_frame
	for score in [0.0,40.0,10000.0]:
		for item in [{"slot":"q","tool":"bolt_cutter"},{"slot":"r","tool":"grinder"},{"slot":"e","tool":"chainsaw"}]:
			fresh()
			arena.config.attack_speed_score=score
			var mp:float=arena.state.mana
			arena.request_slot(item.slot,{})
			check(arena.state.active_tool==item.tool and arena.action_time==0.0,"%s IAS %.0f immediate toggle remains mobile"%[item.tool,score])
			check(arena.state.mana==mp,"%s toggle adds no resource cost"%item.tool)
			arena._physics_process(1.0/60.0)
			arena.request_slot("lmb",{"enemy_id":"target"})
			var expected:float=arena.attack_seconds(item.tool)
			check(is_equal_approx(arena.action_time,expected),"%s retains attack duration"%item.tool)
			var start_hp:float=arena.enemies.target.hp
			var released:=false
			for frame in 100:
				await physics_frame
				arena._physics_process(1.0/60.0)
				if arena.enemies.target.hp<start_hp:
					released=true
					check(arena.player_visual.staff_visual.debug_state().groups[item.tool].min>=.99999,"%s IAS %.0f head complete at actual damage"%[item.tool,score])
					check(is_equal_approx(arena.player_visual.clip_time/arena.player_visual.clip_length,.5),"%s IAS %.0f keeps release pose"%[item.tool,score])
					break
			check(released,"%s IAS %.0f actual hit occurs"%[item.tool,score])
	fresh()
	arena.request_slot("r",{})
	arena._physics_process(.05)
	var visual:Node3D=arena.player_visual.staff_visual
	var pose_before:=transforms(visual)
	arena.paused=true
	arena._physics_process(.4)
	check(equal_poses(pose_before,transforms(visual)),"arena pause freezes in-progress assembly")
	arena.paused=false
	arena.damage_player(20.0)
	arena._physics_process(.05)
	check(arena.state.active_tool=="grinder","hit reaction preserves instant tool state")
	visual.set_appearance("seal")
	arena.state.mana=0.0
	arena._physics_process(.05)
	for frame in 20:arena._physics_process(1.0/60.0)
	check(arena.state.active_tool==null and visual._parts.all(func(p):return p.weight==0.0),"mana exhaustion restores bare staff")
	check(visual._ornaments.ornament_seal.visible,"mana exhaustion preserves equipment seal")
	var old_ref:WeakRef=weakref(visual)
	arena.reset_arena()
	await process_frame
	check(old_ref.get_ref()==null,"reset frees old staff and all transient pieces")
	check(arena.player_visual.staff_visual.loaded_ok,"reset loads one fresh staff")
	var report={"passed":failures.is_empty(),"checks":checks,"failures":failures,"grip_radius_max":grip_max,"engine":Engine.get_version_info().string}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("STAFF_VALIDATION_COMPLETE checks=",checks.size()," failures=",failures.size())
	arena.free()
	quit(0 if failures.is_empty() else 1)
