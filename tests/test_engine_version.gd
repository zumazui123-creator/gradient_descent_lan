extends RefCounted

const REQUIRED_MAJOR := 4
const REQUIRED_MINOR := 8


static func run() -> Array[String]:
	var failures: Array[String] = []
	var version := Engine.get_version_info()
	var major := int(version.get("major", 0))
	var minor := int(version.get("minor", 0))
	var features: PackedStringArray = ProjectSettings.get_setting(
		"application/config/features",
		PackedStringArray()
	)

	if major != REQUIRED_MAJOR or minor < REQUIRED_MINOR:
		failures.append(
			"Godot 4.8+ erforderlich, ausgeführt wird %s."
			% str(version.get("string", "%d.%d" % [major, minor]))
		)
	if not features.has("4.8"):
		failures.append("project.godot deklariert Godot 4.8 nicht als Projekt-Feature.")
	return failures
