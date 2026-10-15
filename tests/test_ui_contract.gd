extends RefCounted

const MainScene = preload("res://scenes/Main.tscn")
const MenuScene = preload("res://scenes/MainMenu.tscn")
const LobbyScene = preload("res://scenes/Lobby.tscn")
const GameScene = preload("res://scenes/GameView.tscn")
const HelpScene = preload("res://scenes/components/HelpDialog.tscn")
const ShipScene = preload("res://scenes/components/ShipView.tscn")


static func run() -> Array[String]:
	var failures: Array[String] = []
	_check_scene(MainScene, "Main", ["SceneContainer", "OverlayLayer/NoticeLabel"], failures)
	_check_scene(
		MenuScene,
		"MainMenu",
		[
			"Center/Panel/Margin/Content/NameInput",
			"Center/Panel/Margin/Content/AddressInput",
			"Center/Panel/Margin/Content/PortInput",
			"Center/Panel/Margin/Content/Buttons/HostButton",
			"Center/Panel/Margin/Content/Buttons/JoinButton",
		],
		failures
	)
	_check_scene(
		LobbyScene,
		"Lobby",
		[
			"Center/Panel/Margin/Content/StatusLabel",
			"Center/Panel/Margin/Content/Body/PlayerSection/PlayerList",
			"Center/Panel/Margin/Content/Actions/StartButton",
		],
		failures
	)
	_check_scene(
		GameScene,
		"GameView",
		[
			"World/SeabedRenderer",
			"World/Ships",
			"World/Camera2D",
			"HUD/Root/PlayerStrip",
			"HUD/Root/OverviewBar",
			"HUD/Root/MeasurementPanel/Content/MeasurementLabel",
			"HUD/Root/FinishedPanel",
			"HUD/Root/HelpDialog",
		],
		failures
	)

	var help = HelpScene.instantiate()
	_expect(not help.visible, "Hilfe ist beim Start sichtbar", failures)
	_expect(help.has_method("open") and help.has_method("close"), "Hilfe-API fehlt", failures)
	help.free()

	var ship = ShipScene.instantiate()
	_expect(ship.has_method("set_state"), "ShipView.set_state fehlt", failures)
	ship.free()
	return failures


static func _check_scene(
	scene: PackedScene,
	scene_name: String,
	required_paths: Array,
	failures: Array[String]
) -> void:
	var instance := scene.instantiate()
	for path: String in required_paths:
		if instance.get_node_or_null(NodePath(path)) == null:
			failures.append("%s: Node-Pfad fehlt: %s" % [scene_name, path])
	instance.free()


static func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
