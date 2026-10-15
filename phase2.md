# Phase 2: Kernlogik von Python nach GDScript portieren

## Ergebnis

Die darstellungsfreie Logik aus `game.py` ist nach Godot 4.7+ portiert. Phase 2
umfasst Konstanten, Spielerdaten, prozedurales Terrain, Bewegung, Sonden,
Rundenstatus und öffentliche Zustandsdaten. Netzwerk und Benutzeroberfläche
bleiben bewusst Aufgabe der Phasen 3 und 4.

Implementierte Dateien:

```text
scripts/model/GameConstants.gd
scripts/model/PlayerState.gd
scripts/model/Seabed.gd
scripts/autoload/GameManager.gd
tests/test_engine_version.gd
tests/test_seabed.gd
tests/test_game_manager.gd
tests/run_phase2.gd
```

---

## 1. Portierte Konstanten

`GameConstants.gd` ist die gemeinsame Quelle für Spielparameter:

| Konstante | Wert |
|---|---:|
| Referenz-Viewport | `1200 × 760` |
| Weltgrenzen | `72 … 2184` |
| Meeresoberfläche | `247` |
| Spielerzahl | `2 … 4` |
| Sonden je Spieler | `40` |
| Schiffsgeschwindigkeit | `280 px/s` |
| Schatzradius | `22 px` |
| Sonden-Cooldown | `0,40 s` |

Die vier Spielerfarben wurden unverändert übernommen.

---

## 2. `PlayerState.gd`

`PlayerState` ersetzt die Python-Dataclass `Player` und speichert:

- Peer-/Spieler-ID,
- Anzeigename und Farbe,
- autoritative x-Position,
- verbleibende Sonden,
- aktuelle Bewegungsachse,
- Zeitpunkt der letzten Sonde,
- Anzahl der Messungen.

`reset_for_round()` setzt alle rundenbezogenen Werte zurück. `public_data()`
liefert ausschließlich Daten, die an alle Clients übertragen werden dürfen.
`axis` und `last_probe_time` sind absichtlich nicht enthalten.

---

## 3. `Seabed.gd`

Der Generator bewahrt die Regeln aus `game.py`:

1. Ein lokaler `RandomNumberGenerator` wird mit dem Runden-Seed initialisiert.
2. Sechs leicht versetzte Gauß-Täler werden erzeugt.
3. Eines der Täler erhält einen zusätzlichen Tiefenbonus.
4. Zwei Sinusanteile sorgen für groß- und kleinskalige Variation.
5. Die Höhe wird auf `380 … 665` begrenzt.
6. Terrainpunkte liegen im Abstand von vier Pixeln.
7. Der tiefste zulässige Punkt wird zu `treasure_x`.

Öffentliche Methoden:

| Methode | Zweck |
|---|---|
| `depth_at(x)` | geklemmte lineare Interpolation zwischen Stützpunkten |
| `slope_at(x)` | zentrierte Differenz über maximal 24 Pixel |
| `patch_at(x)` | sichtbarer Messbereich von ungefähr `x ± 55` |
| `public_profile()` | gerundetes Gesamtprofil nach Rundenende |

Godots und Pythons Zufallszahlengenerator erzeugen für denselben Seed nicht
dieselbe Punktfolge. Die Godot-Version ist innerhalb derselben Engine-Version
deterministisch; Formel, Grenzen und Spielregeln bleiben identisch.

---

## 4. `GameManager.gd`

Der Autoload ersetzt `GameState` und besitzt den autoritativen Zustand:

```text
lobby → playing → finished
          ↑           │
          └─ Neustart ┘
```

### Spieler

`add_player(peer_id, name)` verwendet die Godot-Peer-ID direkt als Spieler-ID.
Das vermeidet eine zweite ID-Zuordnung im Netzwerkcode. Farben werden aus den
noch unbenutzten Farben gewählt, damit auch nach einem Verbindungsabbruch keine
doppelten Farben entstehen.

Beitritte sind wie in Python nur in `lobby` oder `finished` möglich. Eine Runde
benötigt mindestens zwei und erlaubt höchstens vier Spieler.

### Rundenstart

`start_round(seed)`:

- erzeugt ein neues `Seabed`,
- erhöht die Rundennummer,
- löscht den Gewinner,
- verteilt die Spieler gleichmäßig über die Welt,
- setzt Achse, Messungen, Cooldown und Sondenvorrat zurück.

Ein expliziter Seed ermöglicht reproduzierbare Tests. Ohne Seed wird ein neuer
zufälliger Seed erzeugt.

### Bewegung

`set_axis()` akzeptiert nur `-1`, `0` und `1`. `tick(delta)` begrenzt `delta`
wie die Python-Version auf maximal `0,12 s` und klemmt jedes Schiff an die
Weltgrenzen.

### Sonden

`probe(peer_id, now_seconds)` prüft vor jeder Messung:

- existiert der Spieler,
- läuft die Runde,
- existiert ein Terrain,
- sind Sonden übrig,
- ist der Cooldown abgelaufen.

Ein erfolgreiches Ergebnis enthält nur den lokalen Patch, Tiefe, Gefälle,
verbleibende Sonden und den Fundstatus. Es enthält niemals Seed,
Gesamtterrain oder Schatzposition.

### Informationsgrenze

Die drei Ausgabemethoden haben bewusst verschiedene Sichtbarkeiten:

| Methode | Inhalt | Netzwerkziel |
|---|---|---|
| `snapshot()` | Phase, Runde, Gewinner, öffentliche Spielerdaten | alle Peers |
| `probe()` | genau eine private Messung | nur anfragender Peer |
| `round_result()` | Gesamtterrain und Schatzposition | alle Peers, aber nur nach `finished` |

`round_result()` liefert während `lobby` und `playing` ein leeres Dictionary.
Damit kann Phase 3 das Terrain nicht versehentlich vorzeitig versenden.

---

## 5. Automatisierte Tests

Die Tests prüfen unter anderem:

- Godot 4.7 oder neuer und das Projekt-Feature `4.7`,
- Punktzahl und Grenzen des Terrains,
- Interpolation, Clamping, Patch und öffentliches Profil,
- Mindestspielerzahl und doppelte Peer-IDs,
- eindeutige Spielerfarben,
- Startpositionen und Rundenzähler,
- Begrenzung des Tick-Deltas,
- Validierung der Bewegungsachse,
- Verbrauch einer Sonde und Cooldown,
- Fund des Schatzes und Wechsel zu `finished`,
- Abwesenheit von Seed, Gesamtterrain und Schatzposition in Snapshots und
  privaten Sondenergebnissen,
- Freigabe des Gesamtterrains erst nach Rundenende.

Sobald Godot 4.7+ im `PATH` verfügbar ist, werden alle Phase-2-Tests so gestartet:

```powershell
godot --headless --path C:\Users\zorn_a\Code\gradient_descent_lan `
  --script res://tests/run_phase2.gd
```

Alternativ heißt der Befehl je nach Installation `godot4`.

---

## 6. Abnahmekriterien für Phase 2

- [x] Alle Konstanten aus `game.py` sind zentral portiert.
- [x] Spielerzustand und öffentlicher Spieler-Snapshot sind implementiert.
- [x] Terrainformel, Interpolation, Gefälle und Mess-Patches sind portiert.
- [x] Spieleraufnahme, Rundenstart und Bewegung sind implementiert.
- [x] Sondenverbrauch, Cooldown, Gewinner und Rundenende sind implementiert.
- [x] Snapshot, privates Sondenergebnis und Rundenergebnis sind getrennt.
- [x] Automatisierte Paritäts- und Datenschutztests sind vorhanden.
- [x] `git diff --check` meldet keine Formatfehler.
- [ ] Godot-Headless-Tests laufen ohne Parser- oder Laufzeitfehler.

Der letzte Punkt bleibt offen, bis eine Godot-4.7+-Installation im `PATH`
verfügbar ist. Danach beginnt Phase 3 mit ENet und den in `phase1.md`
definierten RPC-Grenzen.
