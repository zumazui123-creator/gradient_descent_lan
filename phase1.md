# Phase 1: Architektur und Migrationsvertrag (Python → Godot 4)

## Ziel dieser Phase

Phase 1 legt die verbindliche Architektur für die Portierung fest. Sie enthält
noch keine vollständige GDScript-Implementierung der Spielregeln. Am Ende der
Phase ist eindeutig definiert:

- welche Eigenschaften des Python-Spiels erhalten bleiben,
- welcher Godot-Baustein welches Python-Modul ersetzt,
- welche Daten ausschließlich der Host kennen darf,
- wie Szenen, Autoloads, Signale und RPCs zusammenspielen,
- und anhand welcher Kriterien die späteren Phasen geprüft werden.

Zielplattform ist **Godot 4.2 oder neuer mit GDScript**. Die bestehende Python-Version
bleibt während der Migration die Referenzimplementierung.

---

## 1. Ist-Zustand der Python-Version

### `main.py` – Programmeinstieg

- verarbeitet `--host`, `--join`, `--name` und `--port`,
- prüft den Portbereich,
- erzeugt `GameUI` und startet die Pygame-Schleife.

### `game.py` – autoritative, darstellungsfreie Spiellogik

- definiert alle Spielkonstanten,
- generiert mit `Seabed` aus einem Seed sechs Täler,
- interpoliert Tiefe und berechnet das lokale Gefälle,
- verwaltet Spieler, Bewegung, Sonden und Rundenstatus,
- entscheidet serverseitig, ob eine Sonde den Schatz findet.

Wichtige unveränderte Regeln:

| Regel | Referenzwert |
|---|---:|
| Fenster / Referenz-Viewport | `1200 × 760` |
| befahrbare Welt | `x = 72 … 2184` |
| Meeresoberfläche | `y = 247` |
| Spieler | `2 … 4` |
| Sonden je Spieler | `40` |
| Schiffsgeschwindigkeit | `280 px/s` |
| Schatzradius | `22 px` |
| Sonden-Cooldown | `0,40 s` |
| Terrain-Abtastung | alle `4 px` |
| sichtbarer Mess-Patch | ungefähr `±55 px` |
| Tangentenbreite | `48 px` |
| Netzwerkport | `50415` |

### `network.py` – Host-Autorität und LAN-Protokoll

- der Host besitzt den einzigen autoritativen `GameState`,
- Clients senden nur Eingaben (`axis`, `probe`, `start`, `restart`),
- der Host sendet Zustands-Snapshots ungefähr alle `0,08 s`,
- ein Sondenergebnis geht nur an den Spieler, der gemessen hat,
- das vollständige Terrain und `treasure_x` werden erst nach Rundenende
  veröffentlicht.

### `gui.py` – lokaler Clientzustand und Darstellung

- enthält Menü, Verbindungsstatus, Lobby, Spielansicht und Hilfe,
- verarbeitet Tastatur, Maus, Kamera und Sondenanimation,
- speichert ausschließlich die eigenen Messungen eines Clients,
- folgt während des Spiels dem eigenen Schiff,
- erlaubt nach Rundenende das freie Verschieben der Kamera.

---

## 2. Unverhandelbare Verhaltensregeln des Ports

1. **Server-Autorität:** Nur der Host verändert Positionen, Sondenzahlen,
   Gewinner und Rundenphase.
2. **Verdeckte Karte:** Vor Rundenende darf kein Client das komplette Terrain,
   den Seed oder `treasure_x` erhalten. Das gilt auch für Daten in replizierten
   Nodes und Properties.
3. **Private Messungen:** Ein `probe_result` wird nur an den anfragenden Peer
   gesendet. Andere Spieler sehen weder Patch noch Tiefe oder Gefälle.
4. **Identische Host-Sicht:** Auch der Host zeichnet während der Runde nur seine
   eigenen Messungen. Die Host-UI darf deshalb nicht direkt aus dem
   autoritativen `Seabed` rendern.
5. **Validierung auf dem Server:** Peer-ID, Phase, Achsenwert, Host-Rechte,
   Cooldown und Sondenvorrat werden serverseitig geprüft.
6. **Deterministische Tests:** Die Kernlogik muss weiterhin einen expliziten
   Seed annehmen können. Python- und Godot-Zufallsfolgen müssen nicht
   bitidentisch sein; Regeln und Wertebereiche müssen übereinstimmen.
7. **LAN ohne externen Dienst:** Hosting und Beitritt funktionieren direkt über
   IP und Port im lokalen Netz.

---

## 3. Zielarchitektur

### 3.1 Autoloads

#### `GameManager.gd`

Autoritativer Spielzustand und reine Spielregeln:

- Spieler anlegen und entfernen,
- Runde starten und zurücksetzen,
- serverseitige Bewegung ticken,
- Sonden prüfen,
- öffentliche Snapshots erzeugen,
- Terrain nach Rundenende freigeben.

`GameManager` enthält keine UI-Aufrufe und öffnet keine Netzwerkverbindung.
Auf Clients hält er nur den empfangenen öffentlichen Zustand; `Seabed` wird
dort während einer laufenden Runde nicht erzeugt.

#### `NetworkManager.gd`

Verbindungs- und Transportebene:

- `ENetMultiplayerPeer.create_server()` / `create_client()`,
- Peer-Verbindungen und Abbrüche,
- Zuordnung von Godot-Peer-ID zu Spieler,
- validierte Client-Anfragen an den Server,
- öffentliche Snapshots an alle Peers,
- private Sondenergebnisse an genau einen Peer,
- Rundenergebnis an alle Peers.

Godot reserviert Peer-ID `1` für den Server. Diese ID wird direkt als
Spieler-ID verwendet. Dadurch ist keine zweite, fehleranfällige ID-Tabelle
nötig. Der Host ist Spieler `1`.

#### `ClientSession.gd`

Lokaler, nicht autoritativer Darstellungszustand:

- eigene Peer-/Spieler-ID,
- eigene Messungen und letzte Messung,
- freigegebenes Terrain nach Rundenende,
- lokaler Hinweistext und Verbindungsstatus,
- Reset beim Beginn einer neuen Runde oder bei Trennung.

Diese Trennung verhindert, dass die Host-Ansicht versehentlich auf geheime
Serverdaten zugreift.

### 3.2 Szenen

```text
Main.tscn (Node)
├── SceneContainer (Node)
└── OverlayLayer (CanvasLayer)
    └── NoticeLabel (Label)

MainMenu.tscn (Control)
└── Menü mit Name, Host-IP, Port, Hosten und Beitreten

Lobby.tscn (Control)
└── Spielerliste, Host-Adresse und Start-Button

GameView.tscn (Node2D)
├── World (Node2D)
│   ├── SeabedRenderer (Node2D)
│   ├── ProbeRenderer (Node2D)
│   ├── Ships (Node2D)
│   └── Camera2D
└── HUD (CanvasLayer)
    ├── PlayerStrip (Control)
    ├── MeasurementPanel (Control)
    ├── RoundFinishedPanel (Control)
    └── HelpDialog (Control)
```

`Main.tscn` bleibt während der Sitzung bestehen und wechselt nur seine
Inhaltsszene. Damit bleiben Netzwerk und lokale Sitzung bei einem Wechsel von
Lobby zu Spielansicht erhalten.

### 3.3 Fachklassen

- `Seabed.gd` (`RefCounted`): Terrain, Interpolation, Gefälle, Patch und Profil.
- `PlayerState.gd` (`RefCounted`): serverseitige Spielerdaten und öffentliches
  Dictionary.
- `SeabedRenderer.gd` (`Node2D`): zeichnet bekannte Patches beziehungsweise
  nach Rundenende das vollständige Profil. Ein eigenes `_draw()` ist geeigneter
  als ein einzelnes `Line2D`, weil Fläche, Teilstücke, Messpunkte, Tangente und
  Schatz gemeinsam gerendert werden.
- `ShipView.gd` (`Node2D`): rein visuelle Darstellung eines Schiffs.

---

## 4. Zustandsbesitz

| Daten | Host autoritativ | alle Clients | nur lokaler Client |
|---|:---:|:---:|:---:|
| Phase, Runde, Gewinner | ✓ | Snapshot | – |
| Spielername, Farbe, Position, Sondenanzahl | ✓ | Snapshot | – |
| Eingabeachse und Sonden-Cooldown | ✓ | – | Eingabeabsicht |
| Seed, `Seabed`, `treasure_x` während der Runde | ✓ | **niemals** | **niemals** |
| eigenes Sondenergebnis | erzeugt | – | ✓ |
| fremde Sondenergebnisse | verarbeitet | **niemals** | **niemals** |
| Gesamtprofil nach Rundenende | ✓ | ✓ | ✓ |
| Kamera, Hilfe, Animationen | – | – | ✓ |

---

## 5. Signal- und Szenenfluss

```text
MainMenu
  ├─ host_requested ─┐
  └─ join_requested ─┴─> NetworkManager
                            │ connected / failed
                            v
                          Lobby
                            │ state_received(playing)
                            v
                         GameView
                            │ state_received(finished)
                            v
                    Ergebnis-Overlay in GameView
```

Szenen sprechen nicht direkt miteinander. `NetworkManager` und
`ClientSession` veröffentlichen Signale wie:

- `connection_succeeded(is_host)`
- `connection_failed(message)`
- `state_updated(snapshot)`
- `private_probe_received(result)`
- `round_started(round_number)`
- `round_finished(winner_id, terrain, treasure_x)`
- `server_disconnected()`

Die zentrale `Main.gd` reagiert auf Phasenwechsel und wechselt die
Inhaltsszene. RPC-Methoden wechseln niemals selbst die Szene.

---

## 6. RPC-Vertrag

| RPC | Richtung | Transfermodus | Empfänger / Wirkung |
|---|---|---|---|
| `register_player(name)` | Client → Server | zuverlässig | Name bereinigen, Spieler anlegen |
| `submit_axis(axis)` | Client → Server | unzuverlässig, geordnet | Achse `-1/0/1` validieren |
| `request_probe()` | Client → Server | zuverlässig | Cooldown/Sonden prüfen |
| `request_start_round()` | Host → Server | zuverlässig | nur Peer `1`, mindestens 2 Spieler |
| `request_restart_round()` | Host → Server | zuverlässig | nur Peer `1`, Phase `finished` |
| `receive_state(snapshot)` | Server → alle | unzuverlässig, geordnet | öffentliche Daten aktualisieren |
| `receive_probe_result(result)` | Server → einzelner Peer | zuverlässig | private Messung speichern |
| `receive_round_started(number)` | Server → alle | zuverlässig | ClientSession zurücksetzen |
| `receive_round_finished(...)` | Server → alle | zuverlässig | Terrain freigeben |
| `receive_notice(message)` | Server → einzelner Peer | zuverlässig | Fehler/Hinweis anzeigen |

Für den Host werden dieselben öffentlichen Wrapper verwendet wie für Clients.
Ein Wrapper ruft auf Peer `1` den Server-Handler direkt auf; andere Peers
senden den entsprechenden RPC an ID `1`. So hängt korrektes Host-Verhalten
nicht von `call_local`-Seiteneffekten ab.

Snapshots enthalten ausschließlich:

```gdscript
{
    "phase": "lobby" | "playing" | "finished",
    "round": int,
    "winner": int oder null,
    "players": [
        {
            "id": int,
            "name": String,
            "color": String,
            "x": float,
            "probes_left": int,
            "measurements": int
        }
    ]
}
```

`seed`, Terrainpunkte, `treasure_x`, `axis` und `last_probe` gehören nicht in
laufende Snapshots.

---

## 7. Szenen- und Rundenstatus

```text
menu
  └─ Verbindung erfolgreich → lobby

lobby
  └─ Host startet bei ≥ 2 Spielern → playing

playing
  ├─ Schatz gefunden → finished
  └─ alle Sonden verbraucht → finished

finished
  └─ Host startet neue Runde bei ≥ 2 Spielern → playing

jeder Netzwerkstatus
  └─ Server getrennt / Verlassen → menu
```

Ein später beitretender Client wird während `playing` abgewiesen. Ein Beitritt
in `finished` bleibt wie in Python erlaubt und erhält sofort den öffentlichen
Snapshot sowie das bereits freigegebene Rundenergebnis.

---

## 8. Projektstruktur

```text
res://
├── project.godot
├── scenes/
│   ├── Main.tscn
│   ├── MainMenu.tscn
│   ├── Lobby.tscn
│   ├── GameView.tscn
│   └── components/
│       ├── HelpDialog.tscn
│       └── ShipView.tscn
├── scripts/
│   ├── autoload/
│   │   ├── GameManager.gd
│   │   ├── NetworkManager.gd
│   │   └── ClientSession.gd
│   ├── model/
│   │   ├── GameConstants.gd
│   │   ├── PlayerState.gd
│   │   └── Seabed.gd
│   ├── scenes/
│   │   ├── Main.gd
│   │   ├── MainMenu.gd
│   │   ├── Lobby.gd
│   │   └── GameView.gd
│   └── view/
│       ├── SeabedRenderer.gd
│       └── ShipView.gd
├── assets/
│   ├── themes/
│   └── textures/
└── tests/
    ├── test_seabed.gd
    ├── test_game_manager.gd
    └── fixtures/
```

Die Python-Dateien bleiben zunächst im Repository. Erst wenn der Godot-Port
alle Abnahmetests erfüllt, können sie archiviert oder entfernt werden.

---

## 9. Reihenfolge der weiteren Umsetzung

1. **Phase 2 – Kernlogik:** Konstanten, `PlayerState`, `Seabed` und
   `GameManager`; deterministische Unit-Tests mit festen Seeds.
2. **Phase 3 – Netzwerk:** ENet-Verbindung, Registrierung, RPCs,
   serverseitige Validierung und Datenschutztests mit zwei Instanzen.
3. **Phase 4 – UI und Grafik:** Menü, Lobby, Spielansicht, Kamera, bekannte
   Terrain-Patches, Tangente, Hilfe und Ergebnisansicht.

Die vorhandenen Dokumente `phase2.md` bis `phase4.md` sind Entwürfe und müssen
bei der Umsetzung an die hier festgelegten Namen, Zuständigkeiten und
Sicherheitsregeln angepasst werden.

---

## 10. Abnahmekriterien für Phase 1

- [x] Alle vier Python-Module und ihre Verantwortlichkeiten sind erfasst.
- [x] Konstanten und sichtbares Referenzverhalten sind dokumentiert.
- [x] Autoritative, replizierte und lokale Daten sind getrennt.
- [x] Die Geheimhaltung von Terrain, Seed und fremden Messungen ist festgelegt.
- [x] Szenen, Autoloads, Fachklassen und Signale sind benannt.
- [x] Der RPC-Vertrag einschließlich Richtung und Zuverlässigkeit ist definiert.
- [x] Statusübergänge und Verhalten bei Verbindungsabbruch sind beschrieben.
- [x] Eine konsistente Godot-Projektstruktur ist festgelegt.
- [x] Godot-Projektgerüst (`project.godot`, Ordner und Startszene) anlegen.
- [ ] Projekt in einer installierten Godot-4-Version ohne Parserfehler öffnen.

Das Projektgerüst ist angelegt. Die abschließende Prüfung im Godot-Editor ist
noch offen, weil in dieser Umgebung kein Godot-Befehl im `PATH` gefunden wurde.
