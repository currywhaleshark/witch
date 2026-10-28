extends "res://scripts/actor_visual.gd"
## Arena events drive this rig. There are no damage, targeting or cooldown rules here.
var _pattern := "idle"
var _released := ""
var _recover_pattern := "idle"
var _queued: Dictionary = {}
var release_events: Array[Dictionary] = []

func begin_attack(attack: String, windup: float) -> void:
	# A sweep resolves and starts its chained slam in the same arena update.
	# Keep that sweep's contact pose visible for this update before starting the slam.
	if not _released.is_empty():
		_queued = {"pattern": attack, "windup": windup}
		return
	_pattern = attack
	_attack_total = maxf(windup, 0.0001)
	_pending_release = true
	_recovery = -1.0

func release_attack(attack: String) -> void:
	_released = attack
	_pending_release = false
	_recover_pattern = attack
	_recovery = 0.0

func sync_enemy(enemy: Dictionary, dt: float) -> void:
	var distance: float = enemy.body.global_position.distance_to(_last_position)
	_last_position = enemy.body.global_position
	_clock += dt
	_move_clock += minf(distance / maxf(0.01, 0.8 * float(enemy.size)), dt * 3.5)
	_reaction = maxf(0.0, _reaction - dt)
	if float(enemy.flash) > _last_flash + 0.02:
		_reaction = 0.26
	_last_flash = enemy.flash
	if not _released.is_empty():
		sample(_released, 0.5)
		release_samples.append(fraction)
		release_events.append({"pattern": _released, "fraction": fraction})
		if release_samples.size() > 16: release_samples.pop_front()
		if release_events.size() > 16: release_events.pop_front()
		_released = ""
		return
	if not _queued.is_empty():
		var next := _queued.duplicate()
		_queued.clear()
		begin_attack(next.pattern, next.windup)
	if _pending_release and enemy.windup > 0:
		sample(_pattern, 0.5 * (1.0 - float(enemy.windup) / _attack_total))
		return
	_pending_release = false
	if _recovery >= 0.0:
		_recovery += dt
		if _recovery < 0.3:
			sample(_recover_pattern, 0.5 + 0.5 * _recovery / 0.3)
			return
		_recovery = -1.0
	if _reaction > 0:
		sample("hit", 1.0 - _reaction / 0.26)
	elif distance > 0.0001:
		sample("move", fposmod(_move_clock, 1.0))
	else:
		sample("idle", fposmod(_clock / 2.0, 1.0))

func debug_state() -> Dictionary:
	var result := super.debug_state()
	result.release_events = release_events.duplicate(true)
	return result
