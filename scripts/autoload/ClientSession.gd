extends Node

## Rein lokaler Darstellungszustand. Enthält keine geheimen Serverdaten.

signal round_data_reset

var local_player_id := 0
var measurements: Array[Dictionary] = []
var last_measurement: Dictionary = {}
var released_terrain: Array = []
var released_treasure_x: Variant = null


func reset_round() -> void:
	measurements.clear()
	last_measurement.clear()
	released_terrain.clear()
	released_treasure_x = null
	round_data_reset.emit()


func reset_all() -> void:
	local_player_id = 0
	reset_round()
