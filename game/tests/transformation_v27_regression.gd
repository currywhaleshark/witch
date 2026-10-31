extends "res://tests/transformation_v26.gd"
func run() -> void:
	ProjectSettings.set_setting("debug/entry_polish_v27",true)
	await super.run()
