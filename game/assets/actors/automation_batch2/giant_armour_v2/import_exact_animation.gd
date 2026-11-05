@tool
extends EditorScenePostImport
## Keep the authored 24 Hz samples plus exact contact/event subframes.
## The standard GLTF import resamples these at integer frames before optimization.
## This hook touches only this asset's AnimationLibrary, during import only.

func read_floats(document: Dictionary, binary: PackedByteArray, index: int, components: int) -> Array:
	var a: Dictionary=document.accessors[index]
	assert(int(a.componentType)==5126 and not a.has("sparse"))
	var view: Dictionary=document.bufferViews[int(a.bufferView)]
	var offset:int=int(view.get("byteOffset",0))+int(a.get("byteOffset",0))
	var stride:int=int(view.get("byteStride",components*4))
	var rows:Array=[]
	for i in int(a.count):
		var values:Array=[]
		for j in components:values.append(binary.decode_float(offset+i*stride+j*4))
		rows.append(values)
	return rows

func _post_import(scene: Node) -> Object:
	var file:=FileAccess.get_file_as_bytes(get_source_file())
	assert(file.decode_u32(0)==0x46546c67)
	var json_bytes:int=file.decode_u32(12)
	var document:Dictionary=JSON.parse_string(file.slice(20,20+json_bytes).get_string_from_utf8())
	var binary:PackedByteArray=file.slice(28+json_bytes)
	var player:AnimationPlayer=scene.find_children("*","AnimationPlayer",true,false)[0]
	var skeleton:Skeleton3D=scene.find_children("*","Skeleton3D",true,false)[0]
	var track_root:Node=player.get_node(player.root_node)
	var path:=String(track_root.get_path_to(skeleton))
	for name in player.get_animation_library_list():player.remove_animation_library(name)
	var library:=AnimationLibrary.new();player.add_animation_library("",library)
	for source in document.animations:
		var animation:=Animation.new();animation.length=float(source.extras.duration_seconds);animation.step=1.0/24.0
		animation.loop_mode=Animation.LOOP_LINEAR if source.extras.loop else Animation.LOOP_NONE
		for channel in source.channels:
			var bone_name:String=document.nodes[int(channel.target.node)].name
			assert(skeleton.find_bone(bone_name)>=0)
			var sampler:Dictionary=source.samplers[int(channel.sampler)]
			assert(sampler.interpolation=="LINEAR")
			var times:=read_floats(document,binary,int(sampler.input),1)
			var component_count:int=4 if channel.target.path=="rotation" else 3
			var values:=read_floats(document,binary,int(sampler.output),component_count)
			var track_type:int={"translation":Animation.TYPE_POSITION_3D,"rotation":Animation.TYPE_ROTATION_3D,"scale":Animation.TYPE_SCALE_3D}[channel.target.path]
			var track:int=animation.add_track(track_type);animation.track_set_path(track,NodePath(path+":"+bone_name))
			animation.track_set_interpolation_type(track,Animation.INTERPOLATION_LINEAR)
			for i in times.size():
				var t:float=times[i][0];var v:Array=values[i]
				match channel.target.path:
					"translation":animation.position_track_insert_key(track,t,Vector3(v[0],v[1],v[2]))
					"rotation":animation.rotation_track_insert_key(track,t,Quaternion(v[0],v[1],v[2],v[3]).normalized())
					"scale":animation.scale_track_insert_key(track,t,Vector3(v[0],v[1],v[2]))
		animation.set_meta("exact_source_sample_times",true)
		library.add_animation(source.name,animation)
	scene.set_meta("hound_import_exact_times_v2",true)
	return scene
