class_name Seabed
extends RefCounted

## Geglättete 1D-Landschaft mit sechs Tälern und einem tiefsten Punkt.

const STEP := 4
const VALLEY_COUNT := 6

var points: Array[Vector2] = []
var treasure_x := GameConstants.WORLD_LEFT


func _init(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var world_width := float(GameConstants.WORLD_RIGHT - GameConstants.WORLD_LEFT)
	var centers: Array[float] = []
	var amplitudes: Array[float] = []

	for index in range(VALLEY_COUNT):
		centers.append((index + 0.5) / float(VALLEY_COUNT) + rng.randf_range(-0.016, 0.016))
		amplitudes.append(rng.randf_range(77.0, 107.0))

	amplitudes[rng.randi_range(0, amplitudes.size() - 1)] += 31.0
	var phase := rng.randf_range(-PI, PI)

	for world_x in range(GameConstants.WORLD_LEFT, GameConstants.WORLD_RIGHT + 1, STEP):
		var normalized_x := (world_x - GameConstants.WORLD_LEFT) / world_width
		var y := 426.0 + 15.0 * sin(2.0 * PI * 1.1 * normalized_x + phase)

		for index in range(centers.size()):
			var distance := (normalized_x - centers[index]) / 0.039
			y += amplitudes[index] * exp(-0.5 * distance * distance)

		y += 7.0 * sin(2.0 * PI * 9.2 * normalized_x + phase * 0.57)
		points.append(Vector2(world_x, clampf(y, 380.0, 665.0)))

	var deepest_point := points[7]
	for index in range(8, points.size() - 7):
		if points[index].y > deepest_point.y:
			deepest_point = points[index]
	treasure_x = roundi(deepest_point.x)


func depth_at(world_x: float) -> float:
	var clamped_x := clampf(world_x, GameConstants.WORLD_LEFT, GameConstants.WORLD_RIGHT)
	var index := int(floor((clamped_x - GameConstants.WORLD_LEFT) / STEP))
	index = mini(index, points.size() - 2)

	var left_point := points[index]
	var right_point := points[index + 1]
	var fraction := (clamped_x - left_point.x) / STEP
	return lerpf(left_point.y, right_point.y, fraction)


func slope_at(world_x: float) -> float:
	var left_x := maxf(GameConstants.WORLD_LEFT, world_x - 12.0)
	var right_x := minf(GameConstants.WORLD_RIGHT, world_x + 12.0)
	return (depth_at(right_x) - depth_at(left_x)) / (right_x - left_x)


func patch_at(world_x: float) -> Array[Vector2]:
	var left_x := maxi(GameConstants.WORLD_LEFT, int(world_x) - 55)
	var right_x := mini(GameConstants.WORLD_RIGHT, int(world_x) + 55)
	var patch: Array[Vector2] = []

	for sample_x in range(left_x, right_x + 1, 5):
		patch.append(Vector2(sample_x, roundf(depth_at(sample_x))))

	if patch.is_empty() or roundi(patch.back().x) != right_x:
		patch.append(Vector2(right_x, roundf(depth_at(right_x))))

	return patch


func public_profile() -> Array[Vector2]:
	var profile: Array[Vector2] = []
	profile.resize(points.size())

	for index in range(points.size()):
		profile[index] = Vector2(points[index].x, roundf(points[index].y))

	return profile
