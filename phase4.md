# Phase 4: Benutzeroberfläche und Grafik implementieren (`gui.py` \$\\rightarrow\$ Godot Szenen & Nodes)

In dieser Phase bauen wir die visuellen Elemente und Szenen in Godot nach, die zuvor in Python mit Pygame (`gui.py`) gerendert wurden. Godot nutzt hierfür das hierarchische Szenensystem aus `Control`\-Nodes (für UI) und `Node2D`/`Line2D` (für die Spielwelt).

---

## 1\. Schritt 4.1: Hauptmenü-Szene (`Menu.tscn`)

Die Hauptmenü-Szene ermöglicht dem Spieler die Eingabe seines Namens, der Server-IP und die Auswahl zwischen "Spiel hosten" und "Beitreten".

### Szenenstruktur (`Menu.tscn`):

* `Control` (Root, Layout: Full Rect)  
  * `ColorRect` (Hintergrundfarbe, z. B. dunkles Blau/Navy)  
  * `PanelContainer` (Zentraler Kasten für das Menü)  
    * `VBoxContainer` oder `GridContainer` (Inhalt)  
      * `Label` ("Gemeinsam auf Schatzsuche")  
      * `Label` ("Dein Name:")  
      * `LineEdit` (NameLineEdit)  
      * `Label` ("Host-IP (zum Beitreten):")  
      * `LineEdit` (AddressLineEdit)  
      * `HBoxContainer` (Buttons)  
        * `Button` (HostButton \- Text: "Spiel hosten")  
        * `Button` (JoinButton \- Text: "Beitreten")  
      * `Label` (InfoLabel \- Port & Hinweise)

### GDScript-Skript für das Hauptmenü (`Menu.gd`):

extends Control

@onready var name\_input: LineEdit \= \$PanelContainer/VBoxContainer/NameLineEdit

@onready var address\_input: LineEdit \= \$PanelContainer/VBoxContainer/AddressLineEdit

@onready var info\_label: Label \= \$PanelContainer/VBoxContainer/InfoLabel

func \_ready() \-\> void:

    info\_label.text \= "Port: %d · Gleiche LAN-Verbindung nötig" % NetworkManager.DEFAULT\_PORT

func \_on\_host\_button\_pressed() \-\> void:

    NetworkManager.player\_name \= name\_input.text if name\_input.text \!= "" else "Spieler"

    var err \= NetworkManager.host\_game()

    if err \== OK:

        get\_tree().change\_scene\_to\_file("res://scenes/Lobby.tscn")

    else:

        info\_label.text \= "Host konnte nicht starten: Fehler %d" % err

func \_on\_join\_button\_pressed() \-\> void:

    NetworkManager.player\_name \= name\_input.text if name\_input.text \!= "" else "Spieler"

    var ip \= address\_input.text.strip\_edges()

    if ip \== "":

        ip \= "127.0.0.1"

    var err \= NetworkManager.join\_game(ip)

    if err \== OK:

        get\_tree().change\_scene\_to\_file("res://scenes/Lobby.tscn")

    else:

        info\_label.text \= "Verbindung fehlgeschlagen."

---

## 2\. Schritt 4.2: Lobby-Szene (`Lobby.tscn`)

In der Lobby sehen alle verbundenen Spieler ihre Namen und Farben. Der Host kann ab 2 Spielern die Runde starten.

### Szenenstruktur (`Lobby.tscn`):

* `Control` (Root)  
  * `Panel` (Hintergrund-Container)  
    * `VBoxContainer`  
      * `Label` ("Lobby")  
      * `Label` (StatusLabel \- IP-Adresse oder Wartestatus)  
      * `ItemList` oder `VBoxContainer` (PlayerListContainer \- Zeigt verbundene Spieler)  
      * `Button` (StartButton \- "Runde starten ↵", anfangs deaktiviert)

### GDScript-Skript für die Lobby (`Lobby.gd`):

extends Control

@onready var status\_label: Label \= \$Panel/VBoxContainer/StatusLabel

@onready var player\_list\_container: VBoxContainer \= \$Panel/VBoxContainer/PlayerListContainer

@onready var start\_button: Button \= \$Panel/VBoxContainer/StartButton

func \_ready() \-\> void:

    if NetworkManager.is\_host:

        status\_label.text \= "Mitspieler verbinden sich mit %s:%d" % \[NetworkManager.local\_ip(), NetworkManager.DEFAULT\_PORT\]

        start\_button.visible \= true

    else:

        status\_label.text \= "Warte, bis der Host die Runde startet..."

        start\_button.visible \= false

func \_process(\_delta: float) \-\> void:

    \# Spielerliste dynamisch aus GameState aktualisieren

    update\_player\_list()

    

    \# Host darf starten, wenn mind. 2 Spieler da sind

    if NetworkManager.is\_host:

        start\_button.disabled \= GameState.players.size() \< 2

func update\_player\_list() \-\> void:

    \# Vorherige Einträge löschen

    for child in player\_list\_container.get\_children():

        child.queue\_free()

        

    for p in GameState.players.values():

        var lbl \= Label.new()

        lbl.text \= p.name \+ (" (Host)" if p.id \== 1 else "")

        lbl.add\_theme\_color\_override("font\_color", Color(p.color))

        player\_list\_container.add\_child(lbl)

func \_on\_start\_button\_pressed() \-\> void:

    if NetworkManager.is\_host:

        \# RPC an alle Clients, um das Spiel zu starten

        NetworkManager.request\_start\_round.rpc()

---

## 3\. Schritt 4.3: Spielfeld-Szene (`Game.tscn`)

Die Spielszene ist das Herzstück. Hier wird der Meeresboden performant gezeichnet, die Schiffe bewegt und die Kamera nachgeführt.

### Szenenstruktur (`Game.tscn`):

* `Node2D` (Root)  
  * `CanvasLayer` (Für UI-Elemente wie Sonden-Zähler und HUD)  
    * `Control` (HUD)  
      * `Label` (InfoLabel \- Gefälle, Tiefe, Sonden)  
      * `Button` (HelpButton \- "Hilfe H")  
  * `Node2D` (WorldContainer)  
    * `Line2D` (SeabedLine \- Zeichnet den Meeresboden fließend)  
    * `Node2D` (ShipsContainer \- Enthält die Schiffe der Spieler)  
    * `Camera2D` (GameCamera \- Mit sanftem Smoothing `position_smoothing_enabled = true`)

### GDScript-Skript für das Spielfeld (`Game.gd`):

extends Node2D

@onready var seabed\_line: Line2D \= \$WorldContainer/SeabedLine

@onready var game\_camera: Camera2D \= \$WorldContainer/GameCamera

@onready var info\_label: Label \= \$CanvasLayer/HUD/InfoLabel

var local\_player\_id: int \= 1 \# Eigene Peer ID ermitteln

func \_ready() \-\> void:

    local\_player\_id \= multiplayer.get\_unique\_id()

    draw\_seabed()

func draw\_seabed() \-\> void:

    if GameState.seabed:

        var points \= PackedVector2Array()

        for pt in GameState.seabed.public\_profile():

            points.append(Vector2(pt\[0\], pt\[1\]))

        seabed\_line.points \= points

func \_process(dt: float) \-\> void:

    \# 1\. Eingabe erfassen (Pfeiltasten / A / D)

    var axis \= 0

    if Input.is\_action\_pressed("ui\_right") or Input.is\_action\_pressed("move\_right"):

        axis \= 1

    elif Input.is\_action\_pressed("ui\_left") or Input.is\_action\_pressed("move\_left"):

        axis \= \-1

        

    \# An Server senden

    if NetworkManager.peer:

        NetworkManager.send\_axis.rpc\_id(1, axis)

        

    \# Sonden auslösen per Leertaste oder Sonden-Taste

    if Input.is\_action\_just\_pressed("probe") or Input.is\_action\_just\_pressed("ui\_down"):

        NetworkManager.request\_probe.rpc\_id(1)

    \# 2\. Kamera folgt dem eigenen Schiff

    if GameState.players.has(local\_player\_id):

        var p \= GameState.players\[local\_player\_id\]

        var target\_x \= clamp(p.x, 72.0 \+ 600.0, 2184.0 \- 600.0) \# Zentriert im Viewport

        game\_camera.global\_position \= lerp(game\_camera.global\_position, Vector2(target\_x, 380.0), dt \* 10.0)

---

## 4\. Schritt 4.4: Overlay & Hilfe (`HelpDialog.tscn`)

Ein modales Popup-Fenster, das per Tastendruck (`H` oder `Escape`) ein- und ausgeblendet werden kann.

### Szenenstruktur (`HelpDialog.tscn`):

* `Control` (Root, Layout: Full Rect, visibel false bei Start)  
  * `ColorRect` (Dunkles, halbtransparentes Overlay)  
  * `PanelContainer` (Zentrierter Kasten)  
    * `VBoxContainer`  
      * `Label` ("So funktioniert die Schatzsuche")  
      * `Label` (Regeln und Hinweise...)  
      * `Button` (CloseButton \- "Schließen")

### GDScript-Skript für die Hilfe (`HelpDialog.gd`):

extends Control

func \_input(event: InputEvent) \-\> void:

    if event.is\_action\_pressed("toggle\_help") or (event is InputEventKey and event.pressed and event.keycode \== KEY\_H):

        visible \= not visible

    elif event.is\_action\_pressed("ui\_cancel") and visible:

        visible \= false

func \_on\_close\_button\_pressed() \-\> void:

    visible \= false

---

## Fazit & Nächste Schritte:

Mit dieser Godot-Struktur hast du die komplette Benutzeroberfläche, das performante `Line2D`\-Terrain-Rendering und die Multiplayer-Synchronisation erfolgreich in Godot übertragen. Du kannst das Projekt jetzt direkt in Godot testen (`F5` drücken) und mit dem Ausbau deiner neuronalen Netzwerke als Schiffssteuerung beginnen\!