# Phase 1: Architektur-Mapping (Python zu Godot)

Dieses Dokument beschreibt die detaillierte architektonische Planung für den Übergang von deiner bestehenden Python-Implementierung (Pygame, manuelle TCP-Sockets, prozedurale Skripte) zu einer modernen, szenen- und komponenten-basierten Softwarearchitektur in **Godot Engine (GDScript)**.

---

## 1. Architektonisches Grundprinzip: Von Monolith zu Node-Tree & Singletons

In Python hattest du eine lose Kopplung über ein eigenes TCP-Protokoll und globale Module (`main.py`, `game.py`, `network.py`, `gui.py`). Godot verfolgt ein objektorientiertes **Szenen- und Knotensystem (Scene Tree)** kombiniert mit **Singletons (Autoloads)** für globale Zustände.

### Architektur-Ziele:
* **Separation of Concerns (SoC):** Trennung von Spiel-Logik (Game State), Netzwerk (Multiplayer RPCs) und Darstellung (UI/2D Rendering).
* **Signal-Driven Architecture:** Kommunikation zwischen UI und Logik über Godots native `Signal`-Mechanismus statt direkter Funktionsaufrufe.

---

## 2. Modul-für-Modul Übersetzungsplan

### Schritt 2.1: `main.py` $\rightarrow$ Godot Project Settings & Hauptszene (`Main.tscn`)
* **Python-Verhalten:** Nimmt Startparameter über Argumente entgegen (`--host`, `--join`), initialisiert Pygame und startet die UI-Schleife.
* **Godot-Entsprechung:** 
  * Godot nutzt das **Project Setting** (`application/run/main_scene`), um die Startszene (z. B. `MainMenu.tscn`) zu definieren.
  * Kommandozeilenargumente können in Godot über `OS.get_cmdline_args()` ausgelesen werden, für ein klassisches Spiel ist ein grafisches Hauptmenü jedoch eleganter.
* **Untersteps:**
  1. Erstelle eine `Main.tscn` als Hauptmenü-Szene mit Eingabefeldern (`LineEdit`) für Spielername und Host-IP sowie Buttons für "Hosten" und "Beitreten".
  2. Implementiere ein Szenenwechselsystem (`get_tree().change_scene_to_file()`), um dynamisch zwischen Menü, Lobby und Spielfeld zu wechseln.

### Schritt 2.2: `game.py` $\rightarrow$ Godot Autoload (Singleton) & Datenklassen
* **Python-Verhalten:** Enthält die mathematische Spielwelt (`Seabed`), Spieler-Ressourcen, Kollisionen und den Rundenstatus (`GameState`).
* **Godot-Entsprechung:**
  * Ein globaler Autoload (z.B. benannt `GameManager.gd`) verwaltet den Server-Zustand, die Spielerliste und den Phasenübergang (`lobby`, `playing`, `finished`).
  * Die Seekarte (`Seabed`) wird als eigenständige Klasse oder als Logik-Komponente innerhalb der Spielszene implementiert.
* **Untersteps:**
  1. **Singleton einrichten:** Registriere `GameManager.gd` in den Projekteinstellungen unter *Autoload*.
  2. **Seabed-Portierung:** Übersetze die mathematische Kurvengenerierung (Sinuswellen und Gauß-Glockenkurven für die Täler, $y = f(x)$) nach GDScript.
  3. **Spieler-Datenstruktur:** Erstelle eine innere Klasse `PlayerInfo` zur Speicherung von ID, Name, Farbe, Position $x$ und verbleibenden Sonden.

### Schritt 2.3: `network.py` $\rightarrow$ Godot ENetMultiplayerPeer & RPCs
* **Python-Verhalten:** Manueller TCP-Server, Threading für eingehende Verbindungen, Byte-Parsing von JSON-Zeilen (`_encode`, `_decode`).
* **Godot-Entsprechung:**
  * Godots integriertes Multiplayer-Framework (`ENetMultiplayerPeer`) übernimmt die gesamte Socket-Verwaltung, Paket-Serialisierung und den Verbindungsaufbau im LAN.
  * Manuelles JSON-Parsen entfällt; stattdessen werden **RPCs (Remote Procedure Calls)** verwendet.
* **Untersteps:**
  1. **Multiplayer API initialisieren:** Erstelle eine Netzwerk-Manager-Klasse, die `ENetMultiplayerPeer.create_server()` oder `create_client()` aufruft.
  2. **Server-Authority etablieren:** Der Host agiert als Server (`multiplayer.is_server()`), verwaltet die offizielle Spiel-Logik und synchronisiert Zustände.
  3. **RPC-Annotationen nutzen:** 
     * `@rpc("any_peer", "call_local", "reliable")` für Client-Aktionen (z.B. Achsenänderung oder Sonden-Anforderung).
     * `@rpc("authority", "call_local", "reliable")` für State-Updates vom Server an die Clients.

### Schritt 2.4: `gui.py` $\rightarrow$ Godot Control-Nodes & 2D-Nodes
* **Python-Verhalten:** Manuelles Zeichnen mit `pygame.draw` auf einer Surface, eigene Rect-Kollisionen für Buttons, Event-Polling.
* **Godot-Entsprechung:**
  * **UI-Elemente:** Nutze native Godot-Nodes wie `Control`, `PanelContainer`, `Label`, `Button` und `LineEdit` mit eingebautem Layout- und Theme-System (Anchors).
  * **2D-Rendering:** 
    * Der Meeresboden wird über einen `Line2D`-Knoten gerendert (automatische Linien-Glättung und Farbverläufe).
    * Die Kamera folgt dem Spieler über einen `Camera2D`-Knoten mit aktiviertem Smoothing.
* **Untersteps:**
  2. **Spielansicht (Game.tscn):** Platziere einen `Line2D` für den Meeresboden, Sprite-Knoten für die Schiffe und einen `Camera2D`.
  3. **UI-Overlay:** Erstelle ein HUD als `Control`-Node für verbleibende Sonden, Rundenanzeige und den Hilfe-Dialog.

---

## 3. Empfohlene Ordnerstruktur im Godot-Projekt

Um die Architektur sauber zu halten, empfiehlt sich folgende Ordnerstruktur:

```text
res://
├── scenes/
│   ├── MainMenu.tscn
│   ├── Lobby.tscn
│   ├── GameView.tscn
│   └── HelpDialog.tscn
├── scripts/
│   ├── GameManager.gd       # Autoload: Spielzustand & Logik
│   ├── NetworkManager.gd    # Autoload: ENet Multiplayerverwaltung
│   ├── Seabed.gd            # Mathematische Generierung der Seekarte
│   └── Player.gd            # Spieler-Daten und Steuerung
├── assets/
│   ├── themes/              # UI-Design (Schriftarten, Farben)
│   └── textures/            # Sprites / Grafiken
└── project.godot
```

---

## 4. Nächste Schritte (Übergang zu Phase 2)
Nachdem diese Architektur verstanden und in Godot eingerichtet ist, folgt in **Phase 2** die konkrete Implementierung der mathematischen Spielregeln (`Seabed` und `GameState`) in GDScript.