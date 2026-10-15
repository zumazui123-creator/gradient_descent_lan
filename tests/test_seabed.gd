extends RefCounted

const Constants = preload("res://scripts/model/GameConstants.gd")
const SeabedModel = preload("res://scripts/model/Seabed.gd")


static func run() -> Array[String]:
	var failures: Array[String] = []
	var seabed = SeabedModel.new(123456)
	var expected_point_count := int(
		(Constants.WORLD_RIGHT - Constants.WORLD_LEFT) / SeabedModel.STEP + 1
	)

	_expect(seabed.points.size() == expected_point_count, "Terrain hat falsche Punktzahl", failures)
	_expect(roundi(seabed.points.front().x) == Constants.WORLD_LEFT, "Terrain startet am falschen x", failures)
	_expect(roundi(seabed.points.back().x) == Constants.WORLD_RIGHT, "Terrain endet am falschen x", failures)

	for point: Vector2 in seabed.points:
		if point.y < 380.0 or point.y > 665.0:
			failures.append("Terrainhöhe liegt außerhalb 380…665")
			break

	var first_candidate_x := roundi(seabed.points[7].x)
	var last_candidate_x := roundi(seabed.points[seabed.points.size() - 8].x)
	_expect(
		seabed.treasure_x >= first_candidate_x and seabed.treasure_x <= last_candidate_x,
		"Schatz liegt außerhalb der erlaubten Kandidaten",
		failures
	)

	var sample_index := 100
	var sample: Vector2 = seabed.points[sample_index]
	_expect(is_equal_approx(seabed.depth_at(sample.x), sample.y), "Tiefe am Stützpunkt ist falsch", failures)

	var next_sample: Vector2 = seabed.points[sample_index + 1]
	var midpoint_x := (sample.x + next_sample.x) / 2.0
	var expected_midpoint_y := (sample.y + next_sample.y) / 2.0
	_expect(
		is_equal_approx(seabed.depth_at(midpoint_x), expected_midpoint_y),
		"Lineare Interpolation ist falsch",
		failures
	)

	_expect(
		is_equal_approx(seabed.depth_at(Constants.WORLD_LEFT - 500.0), seabed.points.front().y),
		"depth_at klemmt links nicht",
		failures
	)
	_expect(
		is_equal_approx(seabed.depth_at(Constants.WORLD_RIGHT + 500.0), seabed.points.back().y),
		"depth_at klemmt rechts nicht",
		failures
	)

	var slope := seabed.slope_at(sample.x)
	_expect(absf(slope) < 100.0, "Gefälle ist nicht plausibel", failures)

	var patch := seabed.patch_at(sample.x)
	var half_curve := int(Constants.MEASUREMENT_CURVE_LENGTH / 2.0)
	_expect(not patch.is_empty(), "Mess-Patch ist leer", failures)
	_expect(roundi(patch.front().x) == int(sample.x) - half_curve, "Mess-Patch startet falsch", failures)
	_expect(roundi(patch.back().x) == int(sample.x) + half_curve, "Mess-Patch endet falsch", failures)

	var profile := seabed.public_profile()
	_expect(profile.size() == seabed.points.size(), "Öffentliches Profil ist unvollständig", failures)
	return failures


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
