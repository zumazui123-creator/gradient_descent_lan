extends Node

## ENet-Transport und RPC-Grenze. Die Implementierung folgt in Phase 3.

signal connection_succeeded(is_host: bool)
signal connection_failed(message: String)
signal server_disconnected
signal state_received(snapshot: Dictionary)
signal private_probe_received(result: Dictionary)
signal round_started(round_number: int)
signal round_finished(winner_id: Variant, terrain: Array, treasure_x: int)

const DEFAULT_PORT := 50415
const SERVER_PEER_ID := 1

var peer: ENetMultiplayerPeer
var is_host := false


func reset() -> void:
	peer = null
	is_host = false
