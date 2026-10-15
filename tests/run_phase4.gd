extends Node

const EngineVersionTests = preload("res://tests/test_engine_version.gd")
const SeabedTests = preload("res://tests/test_seabed.gd")
const GameManagerTests = preload("res://tests/test_game_manager.gd")
const NetworkContractTests = preload("res://tests/test_network_contract.gd")
const UIContractTests = preload("res://tests/test_ui_contract.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	failures.append_array(EngineVersionTests.run())
	failures.append_array(SeabedTests.run())
	failures.append_array(GameManagerTests.run())
	failures.append_array(NetworkContractTests.run())
	failures.append_array(UIContractTests.run())

	if failures.is_empty():
		print("Phase 4: alle Logik-, Netzwerk- und Szenenvertragstests bestanden.")
		get_tree().quit(0)
		return

	for failure in failures:
		push_error("Phase 4: " + failure)
	get_tree().quit(1)
