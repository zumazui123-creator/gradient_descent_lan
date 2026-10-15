extends Node

## Autoritativer Spielzustand. Die Spiellogik wird in Phase 2 portiert.

signal state_changed(snapshot: Dictionary)

const PHASE_LOBBY := "lobby"
const PHASE_PLAYING := "playing"
const PHASE_FINISHED := "finished"

var phase: String = PHASE_LOBBY
var round_number: int = 0
var winner_id: Variant = null
var players: Dictionary = {}


func reset() -> void:
	phase = PHASE_LOBBY
	round_number = 0
	winner_id = null
	players.clear()
