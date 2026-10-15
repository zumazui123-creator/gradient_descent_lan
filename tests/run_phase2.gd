extends SceneTree

const SeabedTests = preload("res://tests/test_seabed.gd")
const GameManagerTests = preload("res://tests/test_game_manager.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	failures.append_array(SeabedTests.run())
	failures.append_array(GameManagerTests.run())

	if failures.is_empty():
		print("Phase 2: alle Kernlogik-Tests bestanden.")
		quit(0)
		return

	for failure in failures:
		push_error("Phase 2: " + failure)
	quit(1)
