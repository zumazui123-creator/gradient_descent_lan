class_name PlayerState
extends RefCounted

## Serverseitige Spielerdaten. Nur public_data() darf repliziert werden.

var id: int
var display_name: String
var color: String
var x: float
var probes_left := GameConstants.PROBES_PER_PLAYER
var axis := 0
var last_probe_time := -10.0
var measurements := 0


func _init(player_id: int, player_name: String, player_color: String, start_x: float) -> void:
	id = player_id
	display_name = player_name
	color = player_color
	x = start_x


func reset_for_round(start_x: float) -> void:
	x = start_x
	probes_left = GameConstants.PROBES_PER_PLAYER
	axis = 0
	last_probe_time = -10.0
	measurements = 0


func public_data() -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"color": color,
		"x": snappedf(x, 0.1),
		"probes_left": probes_left,
		"measurements": measurements,
	}
