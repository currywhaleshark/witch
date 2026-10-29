extends RefCounted
## One muzzle frame drives the airborne gun, cone and traces. Range remains player-relative.
const CONE_DOT := 0.86
const AIM_HEIGHT := 1.2
const FORWARD_OFFSET := 0.62
const SIDE_OFFSET := 0.52
const MUZZLE_HEIGHT := 1.12

static func frame(arena: Node3D, target: Vector3, at_enemy: bool = false) -> Transform3D:
	var direction: Vector3=target-arena.player.position
	direction.y=0.0
	if direction.length()<0.05:
		direction=-arena.player_model.global_basis.z; direction.y=0.0
		if direction.length()<0.01: direction=Vector3.FORWARD
		direction=direction.normalized()
		target=arena.player.position+direction*float(arena.rules.skills.shotgun.range)
	direction=direction.normalized()
	var near: float=Vector2(target.x-arena.player.position.x,target.z-arena.player.position.z).length()
	# Pull back beside a close enemy as well as a close cursor, so the muzzle cannot skip it.
	for enemy in arena.enemies.values():
		var relative: Vector3=enemy.body.position-arena.player.position; relative.y=0.0
		if relative.length()>0.001 and relative.normalized().dot(direction)>CONE_DOT:
			near=minf(near,relative.length())
	var room:=clampf(near/1.8,0.0,1.0)
	var right:=direction.cross(Vector3.UP).normalized()
	var height:=MUZZLE_HEIGHT+(1.0-room)*0.68
	var aim:=target+Vector3.UP*AIM_HEIGHT
	var fallback: Vector3=arena.player.position+Vector3.UP*height
	# Prefer the right shoulder; use the left or overhead position if a wall blocks it.
	for side in [1.0,-1.0,0.0]:
		var origin: Vector3=fallback+direction*FORWARD_OFFSET*room+right*SIDE_OFFSET*room*side
		if side==0.0: origin=arena.player.position+Vector3.UP*1.85
		# An enemy is aimed at chest height; a floor click fires level from the muzzle instead
		# of pitching the barrel down into the ground.
		if not at_enemy: aim=Vector3(target.x,origin.y,target.z)
		var axis: Vector3=(aim-origin).normalized()
		if axis.length()<0.01: axis=direction
		var basis:=Basis.looking_at(axis,Vector3.UP)
		var rear:=origin-axis*0.84
		var clear: bool=arena.map.clear(fallback,origin) and arena.map.clear(origin,rear)
		for edge in [-0.15,0.15]:
			clear=clear and arena.map.clear(origin+basis.x*edge,rear+basis.x*edge)
		if clear: return Transform3D(basis,origin)
	if not at_enemy: aim=Vector3(target.x,fallback.y,target.z)
	return Transform3D(Basis.looking_at((aim-fallback).normalized(),Vector3.UP),fallback)

static func contains(arena: Node3D, shot: Transform3D, enemy: Node3D) -> bool:
	if enemy.position.distance_to(arena.player.position)>float(arena.rules.skills.shotgun.range): return false
	var delta:=enemy.global_position-shot.origin; delta.y=0.0
	var direction: Vector3=-shot.basis.z; direction.y=0.0
	if delta.length()>0.001 and delta.normalized().dot(direction.normalized())<=CONE_DOT: return false
	return arena.map.clear(shot.origin,enemy.global_position+Vector3.UP*AIM_HEIGHT)

static func traces(arena: Node3D, shot: Transform3D) -> Array[Vector3]:
	var result: Array[Vector3]=[]
	var spread:=acos(CONE_DOT)
	var offset: Vector3=shot.origin-arena.player.global_position; offset.y=0.0
	var radius: float=arena.rules.skills.shotgun.range
	for step in range(-3,4):
		var direction:=(-shot.basis.z).rotated(Vector3.UP,spread*step/3.0).normalized()
		var flat:=Vector3(direction.x,0,direction.z).normalized()
		var along:=offset.dot(flat)
		var planar_length: float=maxf(0.0,-along+sqrt(maxf(0.0,along*along+radius*radius-offset.length_squared())))
		var length: float=planar_length/maxf(0.01,Vector2(direction.x,direction.z).length())
		# Flat test arenas have no floor collider; do not draw downward rays through their floor.
		if direction.y< -0.001:
			length=minf(length,maxf(0.0,(shot.origin.y-arena.map.ground_y(shot.origin))/-direction.y))
		var end:=shot.origin+direction*length
		var query:=PhysicsRayQueryParameters3D.create(shot.origin,end,arena.map.WORLD_LAYER|arena.map.FLOOR_LAYER)
		var hit: Dictionary=arena.get_world_3d().direct_space_state.intersect_ray(query)
		result.append(hit.position if not hit.is_empty() else end)
	return result
