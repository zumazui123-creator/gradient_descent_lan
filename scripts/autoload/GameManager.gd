extends Node

## Autoritativer, darstellungsfreier Spielzustand aus game.py.
## NetworkManager darf nur snapshot(), probe() und round_result() replizieren.

signal state_changed(snapshot: Dictionary)

const PHASE_LOBBY := "lobby"
const PHASE_PLAYING := "playing"
const PHASE_FINISHED := "finished"

var phase := PHASE_LOBBY
var round_number := 0
var winner_id: Variant = null
var players: Dictionary = {}
var seabed: Seabed = null


func reset() -> void:
	phase = PHASE_LOBBY
	round_number = 0
	winner_id = null
	players.clear()
	seabed = null
	state_changed.emit(snapshot())


func add_player(player_id: int, player_name: String) -> PlayerState:
	if player_id <= 0 or players.has(player_id):
		return null
	if phase != PHASE_LOBBY and phase != PHASE_FINISHED:
		return null
	if players.size() >= GameConstants.MAX_PLAYERS:
		return null

	var clean_name := player_name.strip_edges().substr(0, 18)
	if clean_name.is_empty():
		clean_name = "Spieler %d" % player_id

	var start_x := (GameConstants.WORLD_LEFT + GameConstants.WORLD_RIGHT) / 2.0
	var player := PlayerState.new(player_id, clean_name, _next_available_color(), start_x)
	players[player_id] = player
	state_changed.emit(snapshot())
	return player


func remove_player(player_id: int) -> void:
	if not players.erase(player_id):
		return

	if phase == PHASE_PLAYING and not players.is_empty() and _all_probes_used():
		phase = PHASE_FINISHED

	state_changed.emit(snapshot())


func start_round(seed_value: Variant = null) -> bool:
	if phase != PHASE_LOBBY and phase != PHASE_FINISHED:
		return false
	if players.size() < GameConstants.MIN_PLAYERS:
		return false

	var actual_seed := int(seed_value) if seed_value != null else randi()
	seabed = Seabed.new(actual_seed)
	round_number += 1
	winner_id = null
	phase = PHASE_PLAYING

	var ordered_ids: Array = players.keys()
	ordered_ids.sort()
	for index in range(ordered_ids.size()):
		var player: PlayerState = players[ordered_ids[index]]
		var start_x := GameConstants.WORLD_LEFT + (
			(GameConstants.WORLD_RIGHT - GameConstants.WORLD_LEFT)
			* (index + 1)
			/ float(ordered_ids.size() + 1)
		)
		player.reset_for_round(start_x)

	state_changed.emit(snapshot())
	return true


func set_axis(player_id: int, new_axis: int) -> void:
	if phase != PHASE_PLAYING or not players.has(player_id):
		return
	if new_axis != -1 and new_axis != 0 and new_axis != 1:
		return

	var player: PlayerState = players[player_id]
	player.axis = new_axis


func tick(delta: float) -> void:
	if phase != PHASE_PLAYING:
		return

	var safe_delta := minf(maxf(delta, 0.0), 0.12)
	for player: PlayerState in players.values():
		player.x = clampf(
			player.x + player.axis * GameConstants.SHIP_SPEED * safe_delta,
			GameConstants.WORLD_LEFT,
			GameConstants.WORLD_RIGHT
		)


func probe(player_id: int, now_seconds: float = -1.0) -> Dictionary:
	if phase != PHASE_PLAYING or seabed == null or not players.has(player_id):
		return {}

	var player: PlayerState = players[player_id]
	var timestamp := now_seconds
	if timestamp < 0.0:
		timestamp = Time.get_ticks_msec() / 1000.0

	if player.probes_left <= 0:
		return {}
	if timestamp - player.last_probe_time < GameConstants.PROBE_COOLDOWN_SECONDS:
		return {}

	player.last_probe_time = timestamp
	player.probes_left -= 1
	player.measurements += 1

	var depth := seabed.depth_at(player.x)
	var slope := seabed.slope_at(player.x)
	var found := absf(player.x - seabed.treasure_x) <= GameConstants.TREASURE_RADIUS

	if found:
		winner_id = player_id
		phase = PHASE_FINISHED
	elif _all_probes_used():
		phase = PHASE_FINISHED

	var result := {
		"type": "probe_result",
		"x": snappedf(player.x, 0.1),
		"y": snappedf(depth, 0.1),
		"slope": snappedf(slope, 0.001),
		"patch": seabed.patch_at(player.x),
		"probes_left": player.probes_left,
		"found": found,
	}
	state_changed.emit(snapshot())
	return result


func snapshot() -> Dictionary:
	var public_players: Array[Dictionary] = []
	var ordered_ids: Array = players.keys()
	ordered_ids.sort()

	for player_id in ordered_ids:
		var player: PlayerState = players[player_id]
		public_players.append(player.public_data())

	return {
		"type": "state",
		"phase": phase,
		"round": round_number,
		"winner": winner_id,
		"players": public_players,
	}


func apply_public_snapshot(public_snapshot: Dictionary) -> bool:
	## Baut auf Clients ausschließlich den freigegebenen Zustand nach.
	## Ein vorhandenes lokales Seabed wird dabei absichtlich verworfen.
	var incoming_phase := str(public_snapshot.get("phase", ""))
	if incoming_phase not in [PHASE_LOBBY, PHASE_PLAYING, PHASE_FINISHED]:
		return false

	var incoming_players: Variant = public_snapshot.get("players", [])
	if typeof(incoming_players) != TYPE_ARRAY:
		return false

	var rebuilt_players: Dictionary = {}
	for entry: Variant in incoming_players:
		if typeof(entry) != TYPE_DICTIONARY:
			return false

		var player_data: Dictionary = entry
		var player_id := int(player_data.get("id", 0))
		if player_id <= 0 or rebuilt_players.has(player_id):
			return false

		var player := PlayerState.new(
			player_id,
			str(player_data.get("name", "Spieler %d" % player_id)).substr(0, 18),
			str(player_data.get("color", "#ffffff")),
			clampf(
				float(player_data.get("x", GameConstants.WORLD_LEFT)),
				GameConstants.WORLD_LEFT,
				GameConstants.WORLD_RIGHT
			)
		)
		player.probes_left = clampi(
			int(player_data.get("probes_left", 0)),
			0,
			GameConstants.PROBES_PER_PLAYER
		)
		player.measurements = maxi(0, int(player_data.get("measurements", 0)))
		rebuilt_players[player_id] = player

	phase = incoming_phase
	round_number = maxi(0, int(public_snapshot.get("round", 0)))
	winner_id = public_snapshot.get("winner")
	players = rebuilt_players
	seabed = null
	state_changed.emit(snapshot())
	return true


func round_result() -> Dictionary:
	if phase != PHASE_FINISHED or seabed == null:
		return {}

	return {
		"type": "finished",
		"winner": winner_id,
		"terrain": seabed.public_profile(),
		"treasure_x": seabed.treasure_x,
	}


func _all_probes_used() -> bool:
	for player: PlayerState in players.values():
		if player.probes_left > 0:
			return false
	return true


func _next_available_color() -> String:
	var used_colors: Dictionary = {}
	for player: PlayerState in players.values():
		used_colors[player.color] = true

	for candidate: String in GameConstants.PLAYER_COLORS:
		if not used_colors.has(candidate):
			return candidate

	return GameConstants.PLAYER_COLORS[players.size() % GameConstants.PLAYER_COLORS.size()]
