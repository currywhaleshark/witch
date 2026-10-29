extends "res://tests/staff_visual.gd"
## Actual imported geometry / rigid pins and the actual damage frame, not a curve copy.
var hit_cases: Array = []

func find_part(staff: Node3D, name: String) -> Dictionary:
	for p in staff._parts:
		if p.spec.name==name:return p
	return {}

func aperture(staff: Node3D) -> float:
	var left:=find_part(staff,"cutter_jaw_l")
	var right:=find_part(staff,"cutter_jaw_r")
	var a:Vector3=left.node.transform * (Vector3(-.001,1.226,0)-left.rest.origin)
	var b:Vector3=right.node.transform * (Vector3(.001,1.226,0)-right.rest.origin)
	return a.distance_to(b)

func select_variant(kind: String) -> void:
	var rng:=RandomNumberGenerator.new()
	for seed_value in range(1,100):
		rng.seed=seed_value
		if ("attack" if rng.randf()<.5 else "attack_thrust")==kind:
			arena.player_visual._attack_rng.seed=seed_value
			return

func run() -> void:
	var staff:=Staff.new()
	root.add_child(staff)
	check(staff.initialize(),"v2 staff loads")
	staff.set_tool("bolt_cutter")
	staff.finish_assembly()
	var max_pin_error:=0.0
	var max_width:=0.0
	var min_width:=99.0
	for frame in range(101):
		staff.advance(.01,false,frame/100.0)
		max_width=maxf(max_width,aperture(staff))
		min_width=minf(min_width,aperture(staff))
		for side in [-1.0,1.0]:
			var tag:="l" if side<0 else "r"
			var jaw:=find_part(staff,"cutter_jaw_"+tag)
			var link:=find_part(staff,"cutter_link_"+tag)
			var slider:=find_part(staff,"cutter_lock")
			var upper:=Vector3(side*.115,.815,-.069)
			var lower:=Vector3(side*.030,.680,-.069)
			var link_top:Vector3=link.node.transform*(upper-link.rest.origin)
			var jaw_pin:Vector3=jaw.node.transform*(upper-jaw.rest.origin)
			var link_bottom:Vector3=link.node.transform*(lower-link.rest.origin)
			var slider_pin:Vector3=slider.node.transform*(lower-slider.rest.origin)
			max_pin_error=maxf(max_pin_error,maxf(link_top.distance_to(jaw_pin),link_bottom.distance_to(slider_pin)))
			check(link.node.basis.get_scale().is_equal_approx(Vector3.ONE),"link rigid scale frame %d side %.0f"%[frame,side])
	check(max_pin_error<.00001,"all link pins stay joined within 0.01 mm through full bite")
	check(max_width>.40 and max_width<.44,"tip aperture exceeds 40 cm at wide anticipation")
	check(absf(min_width-.002)<.00001,"closed straight edges meet at the 2 mm stop without crossing")
	staff.advance(0.0,false,.40)
	var before:=aperture(staff)
	staff.advance(0.0,false,.49)
	var near_hit:=aperture(staff)
	staff.advance(0.0,false,.50)
	check(before>.4 and near_hit>.07 and aperture(staff)<.00201,"snap retains visible aperture just before the real impact phase")
	staff.advance(0.0,false,.30)
	var frozen:=transforms(staff)
	staff.advance(1.0,true,.50)
	check(equal_poses(frozen,transforms(staff)),"paused open jaws and linkage stay fixed")
	staff.advance(.001,false,-1.0)
	check(aperture(staff)>.40,"interruption begins relaxing from the current open pose")
	for frame in 60:staff.advance(1.0/60.0,false,-1.0)
	check(absf(float(staff.debug_state().jaw_opening_degrees)-8.0)<.001,"interrupted jaws settle back to idle aperture")
	staff.free()
	arena=load("res://main.tscn").instantiate()
	root.add_child(arena)
	arena.set_physics_process(false)
	await process_frame
	for fps in [30,60]:
		for speed in [0.0,40.0,10000.0]:
			for kind in ["attack","attack_thrust"]:
				fresh()
				await process_frame
				arena.config.attack_speed_score=speed
				arena.request_slot("q",{})
				arena._physics_process(1.0/fps)
				select_variant(kind)
				arena.request_slot("lmb",{"enemy_id":"target"})
				check(arena.player_visual._attack_clip_kind==kind,"requested attack variant %s"%kind)
				var hp:float=arena.enemies.target.hp
				var hit:=false
				var peak:=0.0
				for frame in 100:
					arena._physics_process(1.0/fps)
					var tool:Node3D=arena.player_visual.staff_visual
					peak=maxf(peak,float(tool.debug_state().jaw_opening_degrees))
					if arena.enemies.target.hp<hp:
						hit=true
						var gap:=aperture(tool)
						check(absf(gap-.002)<.00002,"actual hit closes blades: %s IAS %.0f %dfps"%[kind,speed,fps])
						check(absf(arena.player_visual.clip_time/arena.player_visual.clip_length-.5)<.00001,"same-frame attack pose at impact")
						check(tool.debug_state().groups.bolt_cutter.min==1.0,"assembled cutter present at actual hit")
						hit_cases.append({"fps":fps,"ias":speed,"variant":kind,"frame":frame,"gap_m":gap,"peak_degrees":peak})
						break
				check(hit,"real damage occurs: %s IAS %.0f %dfps"%[kind,speed,fps])
				if speed<100.0:check(peak>30.0,"ordinary attack reaches the wide anticipation")
	var report={"passed":failures.is_empty(),"checks":checks,"failures":failures,
		"pin_error_max_m":max_pin_error,"max_tip_aperture_m":max_width,"closed_tip_gap_m":min_width,"hit_cases":hit_cases}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("CUTTER_VALIDATION_COMPLETE checks=",checks.size()," failures=",failures.size())
	arena.free()
	quit(0 if failures.is_empty() else 1)
