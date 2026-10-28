extends RefCounted
## Presentation-only decoration planes. No colliders, navigation geometry or combat RNG.
const ROOT = "res://assets/textures/decals_v1/"
const Shape = preload("res://scripts/shapes.gd")
const SIGN_IDS = {"세탁소":"laundry", "철물점":"hardware", "슈퍼":"super", "미용실":"salon", "복덕방":"realty", "분식":"snack", "약국":"pharmacy", "만화방":"comics", "문방구":"stationery"}
const YAW = {"-z":0.0, "-x":90.0, "+z":180.0, "+x":-90.0}
const MASK_COLORS = {"grime_streak_coping":"4d493d", "grime_streak_window":"49483f", "grime_rust_run":"6d4933", "grime_base_dirt":"4e553e", "grime_soot":"30353e", "floor_patch":"303739", "floor_oil":"202326", "floor_cracks":"24272a", "floor_puddle_stain":"797b77", "floor_arrow":"b2afa4", "floor_text_slow":"b2afa4"}
const POSTERS = ["poster_redevelop_notice", "poster_tutoring", "poster_moving", "poster_lost_cat", "poster_volunteer", "poster_circus", "poster_torn_layers"]
const PLATES = ["plate_dog", "plate_lot_number", "plate_no_flyers", "box_milk"]
const VERTICAL_FOR = {"복덕방":"sign_v_realty", "약국":"sign_v_pharmacy"}
const AFRAME_FOR = {"복덕방":"aframe_realty", "분식":"aframe_snack"}
const GAS = Color("d6ac36")
var textures: Dictionary = {}
var assets: Dictionary = {}
var layout: Dictionary = {}
var nodes: Array[MeshInstance3D] = []
var enabled := true

func state(key: String, faded: bool = false) -> String:
	if layout.is_empty(): return "original"
	if faded: return "vacant"
	var rng := RandomNumberGenerator.new()
	rng.seed=hash("occupancy:"+key)
	return layout.get("lot_states",{}).get(key,["open","closed","vacant"][rng.randi()%3])

func configure(map_id: String) -> void:
	nodes.clear()
	layout = {}
	if not enabled or map_id != "alley_v2": return
	var path := "res://data/maps/alley_decals_v1.json"
	if not FileAccess.file_exists(path): return
	layout = JSON.parse_string(FileAccess.get_file_as_string(path))
	if assets.is_empty():
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "manifest.json"))
		for item in manifest.assets: assets[item.id] = item

func _texture(id: String) -> Texture2D:
	if not textures.has(id):
		var suffix := "_rgba.png" if MASK_COLORS.has(id) else ".png"
		var path := ROOT + id + suffix
		if not ResourceLoader.exists(path): return null
		textures[id] = load(path)
	return textures[id]

func add_plane(parent: Node3D, id: String, size: Vector2, pos: Vector3, rotation: Vector3, opacity: float = 1.0) -> MeshInstance3D:
	var texture := _texture(id)
	if texture == null: return null
	var mesh := MeshInstance3D.new()
	mesh.name = "Decoration_" + id
	var quad := QuadMesh.new()
	quad.size = size
	mesh.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = texture
	mat.albedo_color = Color(Color(MASK_COLORS.get(id, "ffffff")), opacity)
	mat.roughness = 1.0
	mat.metallic_specular = 0.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.set_meta("decoration_id", id)
	mesh.set_meta("decal_base_alpha", opacity)
	parent.add_child(mesh)
	mesh.position = pos
	mesh.rotation_degrees = rotation
	nodes.append(mesh)
	return mesh

func _at(f: Dictionary, u: float, v: float, y: float) -> Vector3:
	var w: float = f.face + f.sign * v
	return Vector3(u,y,w) if f.along_x else Vector3(w,y,u)

func wall(parent: Node3D, f: Dictionary, id: String, u: float, y: float, opacity: float = 1.0, v: float = -0.008) -> MeshInstance3D:
	if not assets.has(id): return null
	var s: Array = assets[id].world_size
	return add_plane(parent,id,Vector2(s[0],s[1]),_at(f,u,v,y),Vector3(0,YAW[f.out],0),opacity)

func sign(parent: Node3D, f: Dictionary, text: String, faded: bool, center: float, y: float, width: float) -> bool:
	if layout.is_empty() or not SIGN_IDS.has(text): return false
	var id: String = "sign_" + SIGN_IDS[text] + ("_faded" if text == "문방구" and faded else "")
	var node := add_plane(parent,id,Vector2(width,0.6),_at(f,center,-0.168,y),Vector3(0,YAW[f.out],0))
	if node == null: return false
	# Keep the central 70% of a nominal 4.8m board fixed; only plain end caps stretch.
	var xs := [-width/2.0,-1.68,1.68,width/2.0]
	var us := [0.0,0.15,0.85,1.0]
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in 3:
		var n := verts.size()
		verts.append_array(PackedVector3Array([Vector3(xs[i],0.3,0),Vector3(xs[i+1],0.3,0),Vector3(xs[i+1],-0.3,0),Vector3(xs[i],-0.3,0)]))
		uv.append_array(PackedVector2Array([Vector2(us[i],0),Vector2(us[i+1],0),Vector2(us[i+1],1),Vector2(us[i],1)]))
		for j in 4: normals.append(Vector3.FORWARD * -1.0)
		indices.append_array(PackedInt32Array([n,n+1,n+2,n,n+2,n+3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=verts; arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_TEX_UV]=uv; arrays[Mesh.ARRAY_INDEX]=indices
	var shape := ArrayMesh.new()
	shape.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	node.mesh=shape
	node.set_meta("sign_text",text)
	if parent.get_meta("alley_state","closed") == "open":
		var mat: StandardMaterial3D = node.material_override
		mat.emission_enabled = true
		mat.emission_texture = mat.albedo_texture
		mat.emission = Color("b6aaa0")
		mat.emission_energy_multiplier = 0.28
	return true

func decorate_run(parent: Node3D, f: Dictionary, a: float, b: float, ground: float, kind: String, key: String) -> void:
	if layout.is_empty() or b-a < 1.5: return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("decals:%s:%s" % [layout.seed,key])
	var center := (a+b)/2.0
	var demo: bool = key in layout.demolition_lots
	wall(parent,f,"grime_base_dirt",center,ground+0.2,0.42,-0.017)
	wall(parent,f,"grime_streak_coping",center,ground+1.13,0.38)
	if demo:
		wall(parent,f,"spray_demolish",center,ground+0.88,0.8,-0.013)
		if b-a > 2.0: wall(parent,f,"poster_demolition",b-0.35,ground+0.9,1.0,-0.015)
		if b-a > 3.0: wall(parent,f,"spray_x" if hash(key)%2 == 0 else "spray_vacant",a+0.7,ground+0.85,0.72,-0.016)
	else:
		var poster: String = POSTERS[rng.randi()%POSTERS.size()]
		wall(parent,f,poster,center,ground+0.9,1.0,-0.015)
	if kind == "house" and b-a > 2.2:
		wall(parent,f,PLATES[rng.randi()%PLATES.size()],a+0.35,ground+1.02,1.0,-0.02)
	if b-a > 3.4:
		wall(parent,f,"grime_rust_run",a+0.55,ground+0.55,0.32,-0.01)

func shop(parent: Node3D, f: Dictionary, u0: float, u1: float, ground: float, lot: Dictionary, key: String) -> void:
	if layout.is_empty(): return
	var center := (u0+u1)/2.0
	wall(parent,f,"poster_torn_layers" if lot.get("faded",false) else "poster_moving",u0+0.65,ground+1.0,1.0,-0.075)
	if lot.get("faded",false):
		wall(parent,f,"spray_no_entry",center,ground+1.1,0.82,-0.078)
		wall(parent,f,"spray_number",u1-0.65,ground+0.6,0.72,-0.08)
	elif hash(key)%3 == 0:
		wall(parent,f,"stencil_no_parking",center,ground+0.65,0.7,-0.075)
	var occupancy: String = parent.get_meta("alley_state","closed")
	wall(parent,f,"glass_open" if occupancy == "open" else ("glass_closing_sale" if occupancy == "closed" else "glass_for_rent"),center,ground+1.3,0.85,-0.14)
	if occupancy == "vacant":
		wall(parent,f,"boarded_door",u1-0.95,ground+1.0,1.0,-0.145)

func lot(parent: Node3D, f: Dictionary, u0: float, u1: float, ground: float, key: String, building: bool) -> void:
	if layout.is_empty(): return
	var center: float = (u0+u1)/2.0
	if f.sign < 0 and layout.get("banners",{}).has(key) and u1-u0 >= 5.0:
		var banner_y: float = 2.05 if building else 1.65
		var post_h: float = 2.85 if building else 2.12
		wall(parent,f,layout.banners[key],center,ground+banner_y,1.0,-0.055)
		for offset in [-2.4,2.4]:
			Shape.box(parent,_at(f,center+offset,0.01,ground+post_h/2),Vector3(0.035,post_h,0.035),Color("55534b"))
	# One building, one trade: a shop's projecting sign and A-frame repeat its own sign; a house only
	# carries a trade run from home (fortune teller, old inn), listed per lot in the layout.
	var business: String = parent.get_meta("business","")
	var vertical: String = VERTICAL_FOR.get(business,"") if business != "" else layout.get("home_signs",{}).get(key,"")
	var facade: float = float(parent.get_meta("facade",0.0))
	if vertical != "" and building:
		var inset: float = 0.3 if business != "" else 0.9
		projecting(parent,f,vertical,u1-inset,ground,facade,parent.get_meta("alley_state") == "open")
	var board: String = AFRAME_FOR.get(business,"")
	if board != "" and f.sign < 0 and parent.get_meta("alley_state") == "open": aframe(parent,f,board,u0+0.55,ground)

func projecting(parent: Node3D, f: Dictionary, id: String, u: float, ground: float, facade: float, lit: bool) -> void:
	if not assets.has(id): return
	var s: Array = assets[id].world_size
	var center := _at(f,u,facade-0.36,ground+2.35+float(s[1])/2.0)
	var yaw: float = YAW[f.out] + 90.0
	var normal := Basis(Vector3.UP,deg_to_rad(yaw))*Vector3.BACK
	for side in [-1,1]:
		var panel := add_plane(parent,id,Vector2(s[0],s[1]),center+normal*side*0.012,Vector3(0,yaw+(180 if side < 0 else 0),0))
		if lit:
			var mat: StandardMaterial3D = panel.material_override
			mat.emission_enabled=true;mat.emission_texture=mat.albedo_texture
			mat.emission=Color("a09990");mat.emission_energy_multiplier=0.25
	for y in [ground+2.5,ground+2.2+float(s[1])]:
		var size := Vector3(0.04,0.045,0.66) if f.along_x else Vector3(0.66,0.045,0.04)
		Shape.box(parent,_at(f,u,facade-0.3,y),size,Color("5a5751"))

func aframe(parent: Node3D, f: Dictionary, id: String, u: float, ground: float) -> void:
	var frame := Node3D.new()
	parent.add_child(frame);frame.position=_at(f,u,-0.05,ground);frame.rotation_degrees.y=YAW[f.out]
	for side in [-1,1]:
		var panel := add_plane(frame,id,Vector2(0.5,1),Vector3(0,0.62,side*0.15),Vector3(-side*13,180 if side<0 else 0,0))
		for x in [-0.25,0.25]:
			var leg := Shape.box(frame,Vector3(x,0.55,side*0.15),Vector3(0.035,1.13,0.035),Color("534b41"))
			leg.rotation_degrees.x = -side*13
		panel.set_meta("presentation_prop",true)

func window(house: Node3D, face: String, cx: float, cz: float, size: Vector3, y: float, t: float) -> void:
	if layout.is_empty(): return
	var key: String = house.get_meta("lot_key","")
	var occupancy: String = house.get_meta("alley_state","open")
	var pos := Vector3(cx+t,y,cz+size.z/2+0.095) if face == "z" else Vector3(cx+size.x/2+0.095,y,cz+t)
	var rot := Vector3(0,0 if face == "z" else 90,0)
	var index: int = hash("window:%s:%s:%s:%s"%[key,face,y,t])
	var texture: String = "grille_window" if index%2 == 0 else "grille_window_green"
	if occupancy == "vacant": texture = "boarded_window" if index%2 == 0 else "glass_broken"
	add_plane(house,texture,Vector2(1.14,1.19),pos,rot)
	if index%3 == 0:
		add_plane(house,"grime_streak_window",Vector2(1.2,1.4),pos-Vector3(0,0.8,0),rot,0.25)

func fixtures(house: Node3D, rect: Array, base: float, storeys: int, face: String) -> Vector3:
	# Modelled fittings on a seen face (+z or +x), in the window-free strips at its two corners: a
	# yellow gas riser with its meter at the back corner, the electric meter box and the service
	# cable rising to the drop point at the front corner. Returns the drop point for the pole wire.
	if layout.is_empty(): return Vector3.INF
	var along_x: bool = face == "z"
	var wall: float = rect[3] if along_x else rect[2]
	var lo: float = rect[0] if along_x else rect[1]
	var hi: float = rect[2] if along_x else rect[3]
	var at := func(a: float, y: float, off: float) -> Vector3:
		return Vector3(a, y, wall + off) if along_x else Vector3(wall + off, y, a)
	var flat := func(a: float, d: float) -> Vector3:
		return Vector3(a, 0, d) if along_x else Vector3(d, 0, a)
	# Windows sit evenly along the face; skip fittings where the corner strip is too narrow.
	var span: float = hi - lo
	var corner: float = span / (2.0 * maxi(1, int(span / 2.3))) - 0.575
	var top: float = base + storeys * 2.8 - 0.35
	var drop: float = base + mini(storeys, 2) * 2.8 - 0.55
	if corner < 0.45:
		return Vector3.INF
	var g: float = lo + 0.28
	Shape.cylinder(house, at.call(g, (base + 0.05 + top) / 2.0, 0.07), 0.028, top - base - 0.05, GAS)
	for level in storeys:
		# Each floor's branch runs a short way along the wall before entering it.
		Shape.box(house, at.call(g + 0.27, base + level * 2.8 + 2.3, 0.07), flat.call(0.54, 0.05) + Vector3(0, 0.05, 0), GAS)
	var clip: float = base + 0.6
	while clip < top:
		Shape.box(house, at.call(g, clip, 0.035), flat.call(0.09, 0.07) + Vector3(0, 0.03, 0), Color("5c5a55"))
		clip += 1.1
	Shape.box(house, at.call(g, base + 1.3, 0.1), flat.call(0.26, 0.17) + Vector3(0, 0.3, 0), Color("b9b6ad"))
	Shape.box(house, at.call(g, base + 1.36, 0.19), flat.call(0.12, 0.01) + Vector3(0, 0.08, 0), Color("2b3236"))
	var e: float = hi - 0.3
	Shape.box(house, at.call(e, base + 1.55, 0.07), flat.call(0.32, 0.14) + Vector3(0, 0.44, 0), Color("8e918f"))
	add_plane(house, "box_meter", Vector2(0.3, 0.42), at.call(e, base + 1.55, 0.142), Vector3(0, 0 if along_x else 90, 0))
	for side in [-0.035, 0.035]:
		Shape.box(house, at.call(e + side, (base + 1.77 + drop) / 2.0, 0.035), flat.call(0.022, 0.022) + Vector3(0, drop - base - 1.77, 0), Color("1e1f22"))
	Shape.box(house, at.call(e, drop, 0.06), flat.call(0.12, 0.1) + Vector3(0, 0.07, 0), Color("d8d4c8"))
	return at.call(e, drop, 0.1)

func pole(parent: Node3D, f: Dictionary, u: float, ground: float, v: float) -> void:
	# Paper strips and the pole plate sit on the pole's alley side.
	if layout.is_empty(): return
	wall(parent,f,"pole_ad_strip",u,ground+1.85,1.0,v)
	wall(parent,f,"pole_number_plate",u,ground+2.6,1.0,v-0.004)

func prop(body: Node3D, rect: Array, bottom: float, top: float) -> void:
	if layout.is_empty() or top-bottom > 1.0: return
	# Add dressing inside an existing prop's collision footprint, with no new walkable obstruction.
	var w: float = rect[2]-rect[0]
	var d: float = rect[3]-rect[1]
	var cx: float = (rect[0]+rect[2])/2
	var cz: float = (rect[1]+rect[3])/2
	# The body is centered in world space; kit coordinates below are local.
	var h: float = top-bottom
	body.get_child(0).hide()
	for i in 3:
		var x: float = -w*0.32+i*w*0.32
		var crate := Shape.box(body,Vector3(x,-h*0.08,0),Vector3(w*0.25,h*0.82,d*0.65),Color("85745b") if i != 1 else Color("3d574f"))
		for band in [-0.2,0.2]:
			Shape.box(body,Vector3(x,h*0.16,band*d),Vector3(w*0.26,h*0.06,0.025),Color("514b3f"))
		crate.set_meta("presentation_prop",true)
	for i in 3:
		var plank := Shape.box(body,Vector3(0,h*0.46+i*0.012,-d*0.35+i*0.07),Vector3(w*0.9,0.024,0.08),Color("71614b"))
		plank.rotation_degrees.y = i*4-4
	var sack := Shape.sphere(body,Vector3(w*0.25,-h*0.1,d*0.32),minf(h*0.4,0.28),Color("8e8979"))
	sack.scale=Vector3(1.15,0.9,0.75)

func floors(map: Node3D) -> void:
	if layout.is_empty(): return
	for item in layout.floor_decals:
		var at := Vector3(item.pos[0],0,item.pos[1])
		var h: float = map._floor_top(at.x,at.z)
		if h < 0: continue
		var s: Array = assets[item.id].world_size
		var node := add_plane(map,item.id,Vector2(s[0],s[1]),Vector3(at.x,h+float(item.get("lift",0.009)),at.z),Vector3(-90,item.get("yaw",0),0),item.get("opacity",1.0))
		if item.id == "erosion_gear_reveal":
			var mat := ShaderMaterial.new()
			mat.shader=preload("res://shaders/alley_gear_reveal.gdshader")
			mat.set_shader_parameter("slab_texture",_texture("erosion_crack_slab"))
			mat.set_shader_parameter("gear_texture",_texture("erosion_gear_reveal"))
			mat.set_shader_parameter("opacity",item.get("opacity",1.0))
			node.material_override=mat
			node.mesh.size=Vector2(3.0,2.0)
