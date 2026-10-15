# Phase 4: Benutzeroberfläche, Kamera und Grafik

## Ergebnis

Die Pygame-Oberfläche aus `gui.py` ist als Godot-Szenenstruktur umgesetzt.
Menü, Lobby, Spielansicht, Kamera, Schiffe, Terrain-Patches, Tangente,
Sondenanimation, Hilfe und Rundenende verwenden die in den Phasen 1 bis 3
festgelegten Zustands- und Netzwerkgrenzen.

Neue beziehungsweise erweiterte Dateien:

```text
scenes/Main.tscn
scenes/MainMenu.tscn
scenes/Lobby.tscn
scenes/GameView.tscn
scenes/components/HelpDialog.tscn
scenes/components/ShipView.tscn
scripts/scenes/Main.gd
scripts/scenes/MainMenu.gd
scripts/scenes/Lobby.gd
scripts/scenes/GameView.gd
scripts/scenes/HelpDialog.gd
scripts/view/SeabedRenderer.gd
scripts/view/ShipView.gd
scripts/view/OverviewBar.gd
tests/test_engine_version.gd
tests/test_ui_contract.gd
tests/run_phase4.gd
```

Alle Grafikelemente werden mit Godot-Nodes und `_draw()` erzeugt. Der Port
benötigt daher keine externen Bilder oder Schriftdateien.

---

## 1. Szenenfluss

`Main.tscn` bleibt während der gesamten Sitzung aktiv. `Main.gd` tauscht nur
den Inhalt von `SceneContainer` aus:

```text
MainMenu
   │ Verbindung bestätigt
   v
 Lobby
   │ Runde gestartet
   v
GameView ── Rundenende ──> Ergebnisdialog in GameView
   │ Esc / Menü
   v
MainMenu
```

Der Szenenwechsel reagiert auf Signale von `NetworkManager`. RPC-Methoden
wechseln keine Szene. Verbindungsfehler, Serverabbruch und Hinweise erscheinen
im globalen `NoticeLabel`.

Ein Beitritt nach Rundenende öffnet direkt `GameView`, weil der Client den
finalen Snapshot und das freigegebene Terrain erhält.

---

## 2. Hauptmenü

`MainMenu.tscn` enthält:

- Spielername mit maximal 18 Zeichen,
- Host-IP,
- UDP-Port,
- „Spiel hosten“ und „Beitreten“,
- Verbindungs- und Validierungsmeldungen.

Der Port wird vor dem Netzwerkaufruf auf `1 … 65535` geprüft. Während eines
Verbindungsversuchs werden alle Eingabefelder und Buttons deaktiviert.

---

## 3. Lobby

`Lobby.tscn` zeigt:

- die lokale Host-IP und den Port beim Host,
- einen Wartetext auf Clients,
- alle Spielernamen mit ihrer Farbe,
- eine Host-Markierung,
- die wichtigsten Spielregeln,
- einen Start-Button nur für den Host.

Der Start-Button ist erst ab zwei Spielern aktiv. `Enter` startet ebenfalls
die Runde; `Escape` oder „Verlassen“ beendet die Sitzung sauber.

---

## 4. Spielansicht

### 4.1 Welt und Kamera

`GameView.tscn` trennt Welt und HUD:

```text
GameView
├── World
│   ├── SeabedRenderer
│   ├── Ships
│   └── Camera2D
└── HUD (CanvasLayer)
    └── Root
        ├── PlayerStrip
        ├── OverviewBar
        ├── MeasurementPanel
        ├── FinishedPanel
        └── HelpDialog
```

Die Welt verwendet dieselben Pixelkoordinaten wie Python. Die Kamera liegt bei
`x = 600 + camera_x`, wodurch die Umrechnung weiterhin
`screen_x = world_x - camera_x` entspricht.

Während `playing` folgt die Kamera weich dem eigenen Schiff. Nach Rundenende
wird sie auf den Schatz zentriert und kann mit Pfeiltasten oder A/D über die
gesamte Karte verschoben werden.

### 4.2 Schiffe

`ShipView.gd` zeichnet pro Spieler:

- farbigen Rumpf,
- Mast und Segel,
- Spielernamen,
- Markierung des lokalen Spielers.

Positionen werden zwischen den Netzwerksnapshots geglättet, ohne den
autoritativen Zustand zu verändern.

### 4.3 Übersichtsbalken

`OverviewBar.gd` zeigt:

- die aktuelle Kameraposition,
- den sichtbaren Kartenausschnitt,
- farbige Positionen aller Spieler,
- eine größere Markierung für den lokalen Spieler.

---

## 5. Meeresboden und Messungen

`SeabedRenderer.gd` ist ein eigener `Node2D` mit `_draw()`.

### Während der Runde

Der Renderer liest ausschließlich:

```text
ClientSession.measurements
ClientSession.last_measurement
```

Er zeichnet:

- nur die bekannten lokalen Terrain-Patches,
- weiße Messpunkte,
- die letzte Tangente mit exakt 48 Pixel Gesamtbreite,
- die animierte Sondenleine und Sonde.

Das autoritative `GameManager.seabed` wird nie gelesen. Diese Regel gilt auch
für die Host-Ansicht.

### Nach Rundenende

Erst wenn `ClientSession.released_terrain` gefüllt ist, zeichnet der Renderer:

- das komplette gefüllte Terrain,
- die grüne Profilkante,
- die freigegebene Schatzposition.

Zustandsänderungen rufen `queue_redraw()` auf. Dadurch wird das gecachte
Godot-Zeichenergebnis nur bei Bedarf neu aufgebaut.

---

## 6. HUD und Bedienung

Das HUD enthält:

- Rundennummer und UDP-Port,
- Spielerfarben und verbleibende Sonden,
- Tiefe, Gefälle und Richtungshinweis der letzten Messung,
- kontextabhängige Steuerungshinweise,
- Hilfe-Button,
- Ergebnisdialog und Host-Neustart.

Steuerung:

| Eingabe | Wirkung |
|---|---|
| `←` / `→` oder physisch `A` / `D` | Schiff beziehungsweise Ergebniskarte bewegen |
| `Leertaste`, `↓` oder `S` | Sonde absenken |
| `H` | Hilfe öffnen oder schließen |
| `Enter` | Runde in der Lobby starten (Host) |
| `R` | neue Runde nach Rundenende (Host) |
| `Escape` | Hilfe schließen oder Sitzung verlassen |

Während die Hilfe geöffnet ist, wird keine Bewegungs- oder Sondenanfrage
gesendet.

---

## 7. Ergebnis und Neustart

`FinishedPanel` unterscheidet:

- Gewinner mit Name,
- Ende durch verbrauchte Sonden,
- Host mit aktivem Neustart-Button,
- Clients mit Wartetext.

Beim Neustart löscht `ClientSession.reset_round()` alte Messungen und das
freigegebene Terrain. `GameView` bleibt bestehen und aktualisiert Schiffe, HUD
und Renderer über den zuverlässigen Start-Snapshot.

---

## 8. Auflösung und Layout

`project.godot` verwendet den Referenz-Viewport `1200 × 760`,
`canvas_items`-Stretching und ausdrücklich `keep` als Seitenverhältnis.
Damit übernimmt Godot 4.7 nicht den neuen `expand`-Standard.
Vollbild-Hintergründe und Dialoge nutzen Full-Rect-Anker; die eigentliche
Spielansicht behält die Koordinaten der Python-Referenz bei.

Container verwalten Menü-, Lobby- und Dialoginhalte. Feste Offsets werden nur
für das pixelgenaue Spiel-HUD verwendet.

---

## 9. Tests

### Gesamter Vertragslauf

Mit Godot 4.7+:

```powershell
godot --headless --path C:\Users\zorn_a\Code\gradient_descent_lan `
  --script res://tests/run_phase4.gd
```

Der Lauf enthält alle Tests aus Phase 2 und 3 sowie Szenenprüfungen für:

- Mindestversion Godot 4.7 und Projekt-Feature `4.7`,
- Main-Szenencontainer und globalen Hinweis,
- Menü-Eingaben und Buttons,
- Lobby-Spielerliste und Start-Button,
- Renderer, Schiffscontainer und Kamera,
- HUD, Ergebnisdialog und Hilfe,
- öffentliche Methoden von Hilfe und Schiffsdarstellung.

### LAN-Smoke-Test

Der Zwei-Prozess-Test aus Phase 3 prüft weiterhin die echte ENet-Verbindung:

```powershell
# Terminal 1
godot --headless --path C:\Users\zorn_a\Code\gradient_descent_lan `
  --script res://tests/network_smoke_peer.gd -- --role=host --port=50416

# Terminal 2
godot --headless --path C:\Users\zorn_a\Code\gradient_descent_lan `
  --script res://tests/network_smoke_peer.gd -- --role=client --port=50416
```

Für die visuelle Abnahme wird das Projekt anschließend einmal normal im
Godot-Editor gestartet und mit zwei lokalen Fenstern gespielt.

---

## 10. Abnahmekriterien für Phase 4

- [x] `project.godot` verlangt Godot 4.7 und bewahrt das bisherige Seitenverhältnis.
- [x] Hauptmenü mit Name, IP, Port, Hosten und Beitreten ist implementiert.
- [x] Lobby mit Spielern, Host-Adresse und Startberechtigung ist implementiert.
- [x] Szenenwechsel reagieren auf Netzwerk- und Rundenstatus.
- [x] Öffentliche Spielerzustände erzeugen und aktualisieren Schiffe und HUD.
- [x] Kamera folgt dem eigenen Schiff und ist nach Rundenende steuerbar.
- [x] Übersichtsbalken zeigt Kamera und Spielerpositionen.
- [x] Eigene Mess-Patches, Messpunkte und 48-Pixel-Tangente werden gezeichnet.
- [x] Sondenanimation ist implementiert.
- [x] Gesamtterrain und Schatz erscheinen erst nach Rundenende.
- [x] Hilfe, Ergebnisdialog und Neustart sind implementiert.
- [x] UI greift nicht auf das autoritative Terrain zu.
- [x] Szenenvertragstests sind vorhanden.
- [x] Alle `res://`-Ressourcenpfade existieren.
- [x] `git diff --check` meldet keine Formatfehler.
- [ ] Godot-Headless-Tests laufen ohne Parser- oder Laufzeitfehler.
- [ ] Visueller Test mit Host und Client ist bestanden.

Die letzten beiden Punkte bleiben offen, weil in dieser Umgebung kein
Godot-Befehl im `PATH` verfügbar ist.
