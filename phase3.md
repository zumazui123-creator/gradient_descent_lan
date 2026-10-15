# Phase 3: ENet-Multiplayer und RPCs

## Ergebnis

Die manuelle TCP-/JSON-Schicht aus `network.py` ist durch Godots
High-Level-Multiplayer mit `ENetMultiplayerPeer` ersetzt. Der Host bleibt die
einzige Autorität über Spieler, Bewegung, Sonden, Terrain und Rundenstatus.

Implementierte beziehungsweise erweiterte Dateien:

```text
scripts/autoload/NetworkManager.gd
scripts/autoload/GameManager.gd
scripts/autoload/ClientSession.gd
tests/test_engine_version.gd
tests/test_network_contract.gd
tests/run_phase3.gd
tests/network_smoke_peer.gd
```

Godot ENet verwendet **UDP**. Für den Godot-Port muss die Firewall daher
eingehendes UDP auf Port `50415` erlauben; der TCP-Hinweis in der bisherigen
Python-README gilt weiterhin nur für die Python-Version.

---

## 1. Netzwerkarchitektur

```text
Client-Eingabe
    │
    v
NetworkManager RPC ──> Host validiert Sender und Aktion
                           │
                           v
                      GameManager
                           │
            ┌──────────────┼────────────────┐
            v              v                v
      Snapshot an alle  Sonde an einen  Ergebnis an alle
            │              │                │
            v              v                v
       GameManager     ClientSession    ClientSession
       (öffentliche    (private         (freigegebenes
        Replik)         Messung)          Terrain)
```

`NetworkManager` ist der einzige Code, der RPCs sendet oder empfängt.
`GameManager` kennt das Netzwerk nicht. `ClientSession` enthält ausschließlich
lokale Darstellungsdaten.

---

## 2. Verbindung und Registrierung

### Host

`host_game(name, port)`:

1. beendet eine eventuell bestehende Verbindung,
2. prüft den Port,
3. startet einen ENet-Server für höchstens drei Remote-Clients,
4. setzt den Host als Spieler mit Peer-ID `1` ein,
5. setzt `ClientSession.local_player_id` auf `1`,
6. veröffentlicht den ersten Lobby-Snapshot.

Mit Host plus drei Clients bleibt die Grenze von vier Spielern erhalten.

### Client

`join_game(address, name, port)` startet zunächst nur die ENet-Verbindung. Nach
`connected_to_server` sendet der Client seinen Namen zuverlässig an Peer `1`.
Erst die serverseitige Bestätigung löst `connection_succeeded(false)` aus.

Der Server:

- ermittelt die echte Absender-ID über `get_remote_sender_id()`,
- bereinigt den Namen und begrenzt ihn auf 18 Zeichen,
- weist die Peer-ID direkt als Spieler-ID zu,
- lehnt Beitritte während `playing` oder bei voller Lobby ab,
- sendet bei Erfolg Snapshot und gegebenenfalls ein bereits freigegebenes
  Rundenergebnis.

Ein Client kann seine Spieler-ID nicht selbst bestimmen.

---

## 3. Transportkanäle

ENet wird mit drei Kanälen initialisiert:

| Kanal | Transfermodus | Daten | Begründung |
|---:|---|---|---|
| `0` | zuverlässig | Registrierung, Sonden, Start/Neustart, Hinweise, Rundenergebnis | darf nicht verloren gehen |
| `1` | unzuverlässig, geordnet | Bewegungsachse | neue Eingabe ersetzt alte Eingabe |
| `2` | unzuverlässig, geordnet | öffentliche Snapshots | nur der neueste Zustand ist wichtig |

Während `playing` sendet der Host ungefähr alle `0,08 s` einen öffentlichen
Snapshot. Zuverlässige Ereignisse enthalten zusätzlich einen Snapshot, wenn
der korrekte Phasenwechsel garantiert sein muss. Dadurch kann ein verlorener
periodischer Snapshot weder Rundenstart noch Rundenende verbergen.

---

## 4. Öffentliche API für die UI

Phase 4 verwendet ausschließlich diese Methoden:

```gdscript
NetworkManager.host_game(name, port)
NetworkManager.join_game(address, name, port)
NetworkManager.disconnect_network()
NetworkManager.submit_axis(axis)
NetworkManager.request_probe()
NetworkManager.request_start_round()
NetworkManager.request_restart_round()
NetworkManager.local_ip()
```

Der Host ruft keine RPCs an sich selbst auf. Die öffentlichen Methoden führen
Host-Aktionen direkt durch und senden Client-Aktionen als RPC an Peer `1`.
Damit bleibt die Absender-ID eindeutig und die Implementierung benötigt kein
fehleranfälliges `call_local`.

---

## 5. RPC-Vertrag

| RPC | Richtung | Modus | Serverprüfung |
|---|---|---|---|
| `_rpc_register_player(name)` | Client → Host | zuverlässig | Phase, Kapazität, echte Peer-ID |
| `_rpc_submit_axis(axis)` | Client → Host | unzuverlässig, geordnet | Spieler, Phase, Wert `-1/0/1` |
| `_rpc_request_probe()` | Client → Host | zuverlässig | Spieler, Phase, Cooldown, Vorrat |
| `_rpc_request_start_round()` | Client → Host | zuverlässig | Absender muss Peer `1` sein |
| `_rpc_request_restart_round()` | Client → Host | zuverlässig | Peer `1`, Phase `finished` |
| `_rpc_receive_state(snapshot)` | Host → Clients | unzuverlässig, geordnet | nur Authority darf senden |
| `_rpc_receive_probe_result(result)` | Host → genau einen Client | zuverlässig | Empfänger ist der Messende |
| `_rpc_round_started(...)` | Host → Clients | zuverlässig | Start-Snapshot enthalten |
| `_rpc_round_finished(...)` | Host → Clients | zuverlässig | finaler Snapshot und Terrain |
| `_rpc_receive_notice(message)` | Host → genau einen Client | zuverlässig | Text wird lokal begrenzt |

Godots RPC-Modus `authority` verhindert, dass Clients Server-zu-Client-RPCs
aufrufen. Bei allen erlaubten Client-RPCs wird die tatsächliche Remote-ID
innerhalb der RPC-Methode gelesen; Nutzdaten enthalten keine behauptete
Spieler-ID.

---

## 6. Datenschutzgrenze

### Öffentlicher Snapshot

Enthält ausschließlich:

- Phase,
- Rundennummer,
- Gewinner-ID,
- öffentliche Spielerdaten.

Auf Clients baut `GameManager.apply_public_snapshot()` daraus eine reine
Replik auf. Dabei wird `seabed` immer auf `null` gesetzt. Achse und
Sonden-Cooldown werden nicht repliziert.

### Private Messung

Der Host sendet das Ergebnis von `GameManager.probe()` mit `rpc_id()` nur an
den anfragenden Peer. Vor dem Speichern verwirft der Client jedes unerwartete
Ergebnis, das `terrain`, `treasure_x` oder `seed` enthält.

Auch die Messung des Hosts läuft durch `ClientSession`. Seine UI darf daher
nicht direkt auf das autoritative Terrain zugreifen.

### Rundenende

Erst `GameManager.round_result()` in Phase `finished` erzeugt:

- vollständiges Terrain,
- `treasure_x`,
- Gewinner-ID.

Dieses Ergebnis wird einmal pro Runde zuverlässig an alle Peers gesendet. Ein
Spieler, der in `finished` beitritt, erhält es gezielt nach der Registrierung.

---

## 7. Abbruch- und Fehlerverhalten

- Bei absichtlicher Trennung werden ENet, öffentliche Replik und lokale
  Messdaten zurückgesetzt.
- Bei `connection_failed` kehrt der Client mit einer Fehlermeldung zurück.
- Bei `server_disconnected` wird der lokale Zustand gelöscht und ein eigenes
  UI-Signal ausgelöst.
- Verlässt ein Client den Host, entfernt dieser den Spieler und veröffentlicht
  sofort einen neuen Snapshot.
- Namen mit Steuerzeichen werden bereinigt; leere Namen werden zu `Spieler`.
- Ungültige Achsen, verfrühte Sonden und unberechtigte Startversuche ändern den
  autoritativen Zustand nicht.

---

## 8. Signale für Phase 4

`NetworkManager` stellt folgende Signale bereit:

```text
connection_succeeded(is_host)
connection_failed(message)
server_disconnected()
state_received(snapshot)
private_probe_received(result)
round_started(round_number)
round_finished(winner_id, terrain, treasure_x)
notice_received(message)
```

Die UI greift nicht direkt auf RPC-Methoden zu und wechselt niemals innerhalb
einer RPC-Methode die Szene.

---

## 9. Tests

### Logik- und Netzwerkvertrag

Sobald Godot 4.7+ im `PATH` verfügbar ist:

```powershell
godot --headless --path C:\Users\zorn_a\Code\gradient_descent_lan `
  --script res://tests/run_phase3.gd
```

Zusätzlich zu Phase 2 wird geprüft:

- öffentlicher Snapshot kann auf einem Client nachgebaut werden,
- Client-Replik besitzt niemals ein `Seabed`,
- Achse und Cooldown werden nicht repliziert,
- ungültige Phasen werden abgewiesen,
- private Messung und freigegebenes Rundenergebnis bleiben getrennt,
- Rundenreset löscht private und freigegebene Daten.

### Zwei-Prozess-Smoke-Test

In zwei Terminals zuerst Host, dann Client starten:

```powershell
# Terminal 1
godot --headless --path C:\Users\zorn_a\Code\gradient_descent_lan `
  --script res://tests/network_smoke_peer.gd -- --role=host --port=50416

# Terminal 2
godot --headless --path C:\Users\zorn_a\Code\gradient_descent_lan `
  --script res://tests/network_smoke_peer.gd -- --role=client --port=50416
```

Der Test registriert zwei Spieler, startet eine Runde und führt eine private
Sonde aus. Beide Prozesse beenden sich bei Erfolg mit Exit-Code `0`.

---

## 10. Abnahmekriterien für Phase 3

- [x] ENet-Host und -Client sind implementiert.
- [x] Maximal vier Spieler einschließlich Host werden zugelassen.
- [x] Registrierung verwendet die echte Remote-Peer-ID.
- [x] Host-Aktionen funktionieren ohne lokale RPC-Sonderbehandlung.
- [x] Bewegungs-, Sonden-, Start- und Neustart-Anfragen sind implementiert.
- [x] Öffentliche Snapshots und zuverlässige Phasenereignisse sind getrennt.
- [x] Sondenergebnisse werden nur an den Messenden gesendet.
- [x] Terrain und Schatz werden erst nach Rundenende freigegeben.
- [x] Verbindungsabbruch und abgelehnte Registrierung werden behandelt.
- [x] Vertrags- und Zwei-Prozess-Smoke-Tests sind vorhanden.
- [x] `git diff --check` meldet keine Formatfehler.
- [ ] Godot-Vertragstests laufen ohne Parser- oder Laufzeitfehler.
- [ ] Zwei lokale Godot-Prozesse bestehen den ENet-Smoke-Test.

Die letzten beiden Punkte bleiben offen, bis eine Godot-4.7+-Installation im
`PATH` verfügbar ist. Phase 4 verbindet diese Netzwerk-API anschließend mit
Menü, Lobby und Spielansicht.
