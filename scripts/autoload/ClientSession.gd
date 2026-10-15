extends Node

## Rein lokaler Darstellungszustand. Enthält keine geheimen Serverdaten.

signal round_data_reset
signal public_state_changed(snapshot: Dictionary)
signal measurement_received(result: Dictionary)
signal round_result_received(winner_id: Variant, terrain: Array, treasure_x: int)

var local_player_id := 0
var public_state: Dictionary = {}
var measurements: Array[Dictionary] = []
var last_measurement: Dictionary = {}
var released_terrain: Array = []
var released_treasure_x: Variant = null
var released_winner_id: Variant = null


func apply_public_state(snapshot: Dictionary) -> void:
	public_state = snapshot.duplicate(true)
	public_state_changed.emit(public_state)


func store_measurement(result: Dictionary) -> void:
	var safe_result: Dictionary = result.duplicate(true)
	measurements.append(safe_result)
	if int(safe_result.get("player_id", local_player_id)) == local_player_id:
		last_measurement = safe_result
	measurement_received.emit(safe_result)


func release_round_result(winner_id: Variant, terrain: Array, treasure_x: int) -> void:
	released_winner_id = winner_id
	released_terrain = terrain.duplicate(true)
	released_treasure_x = treasure_x
	round_result_received.emit(winner_id, released_terrain, treasure_x)


func reset_round() -> void:
	measurements.clear()
	last_measurement.clear()
	released_terrain.clear()
	released_treasure_x = null
	released_winner_id = null
	round_data_reset.emit()


func reset_all() -> void:
	local_player_id = 0
	public_state.clear()
	reset_round()
