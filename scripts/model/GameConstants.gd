class_name GameConstants
extends RefCounted

## Gemeinsame Spielparameter aus game.py.

const VIEWPORT_WIDTH := 1200
const VIEWPORT_HEIGHT := 760
const WORLD_LEFT := 72
const WORLD_RIGHT := 2184
const SEA_Y := 247

const MIN_PLAYERS := 1
const MAX_PLAYERS := 6
const MAX_TEAMS := 3
const PROBES_PER_PLAYER := 40
const SHIP_SPEED := 280.0
const TREASURE_RADIUS := 22.0
const PROBE_COOLDOWN_SECONDS := 1.5
const MEASUREMENT_CURVE_LENGTH := 50
const MEASUREMENT_TANGENT_LENGTH := 70.0

const PLAYER_COLORS := [
	"#40e6ff",
	"#ffbd56",
	"#c295ff",
	"#74f49d",
	"#ff7aa8",
	"#ff8f5a",
]
