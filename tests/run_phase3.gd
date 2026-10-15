extends SceneTree

const EngineVersionTests = preload("res://tests/test_engine_version.gd")
const SeabedTests = preload("res://tests/test_seabed.gd")
const GameManagerTests = preload("res://tests/test_game_manager.gd")
const NetworkContractTests = preload("res://tests/test_network_contract.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	failures.append_array(EngineVersionTests.run())
	failures.append_array(SeabedTests.run())
	failures.append_array(GameManagerTests.run())
	failures.append_array(NetworkContractTests.run())

	if failures.is_empty():
		print("Phase 3: alle Kernlogik- und Netzwerkvertragstests bestanden.")
		quit(0)
		return

	for failure in failures:
		push_error("Phase 3: " + failure)
	quit(1)
