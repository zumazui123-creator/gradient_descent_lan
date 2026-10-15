# Phase 3: Multiplayer-Netzwerk aufbauen (`network.py` \$\\rightarrow\$ Godot ENetMultiplayerPeer)

In dieser Phase ersetzen wir das manuelle TCP-Socket- und JSON-Protokoll aus Python durch Godots natives High-Level-Multiplayer-Framework (`ENetMultiplayerPeer` und `@rpc`\-Annotationen). Godot kümmert sich hierbei vollautomatisch um die Serialisierung und Netzwerkübertragung.

---

## 1\. Architektur des Godot-Multiplayers

Godot arbeitet mit einem **Client-Server-Modell**:

* Der **Host (Server)** besitzt die absolute Autorität über den Spielzustand (`GameState`).  
* Die **Clients** senden ihre Eingaben (z. B. Bewegungsachsen oder Sonden-Anfragen) an den Server.  
* Der Server verarbeitet die Aktionen und sendet regelmäßige Snapshots oder Ereignisse an alle Clients zurück.

---

## 2\. Schritt 3.1: Host und Client initialisieren (`NetworkManager.gd`)

Erstelle eine globale Autoload-Klasse namens `NetworkManager`, die die Verbindung verwaltet.

### GDScript-Implementierung (`NetworkManager.gd`):

class\_name NetworkManagerClass

extends Node

const DEFAULT\_PORT: int \= 50415

var peer: ENetMultiplayerPeer \= null

var is\_host: bool \= false

var player\_name: String \= "Spieler"

\# Signale für die UI-Aktualisierung

signal connected\_to\_server()

signal connection\_failed()

signal server\_disconnected()

signal player\_list\_changed(players: Array)

func host\_game(port: int \= DEFAULT\_PORT) \-\> Error:

    peer \= ENetMultiplayerPeer.new()

    var err \= peer.create\_server(port, 4\) \# Max 4 Spieler

    if err \!= OK:

        return err

        

    multiplayer.multiplayer\_peer \= peer

    is\_host \= true

    

    \# Signale verknüpfen

    multiplayer.peer\_connected.connect(\_on\_peer\_connected)

    multiplayer.peer\_disconnected.connect(\_on\_peer\_disconnected\_server)

    

    \# Host selbst als Spieler hinzufügen (Peer ID 1 ist immer der Server)

    GameState.add\_player(player\_name)

    print("Server gestartet auf Port ", port)

    return OK

func join\_game(address: String, port: int \= DEFAULT\_PORT) \-\> Error:

    peer \= ENetMultiplayerPeer.new()

    var err \= peer.create\_client(address, port)

    if err \!= OK:

        return err

        

    multiplayer.multiplayer\_peer \= peer

    is\_host \= false

    

    multiplayer.connected\_to\_server.connect(\_on\_connected\_ok)

    multiplayer.connection\_failed.connect(\_on\_connected\_fail)

    multiplayer.server\_disconnected.connect(\_on\_server\_disconnected)

    return OK

func disconnect\_network() \-\> void:

    if peer:

        multiplayer.multiplayer\_peer \= null

        peer \= null

    is\_host \= false

    GameState.players.clear()

    GameState.phase \= "lobby"

func \_on\_connected\_ok() \-\> void:

    print("Erfolgreich mit dem Server verbunden.")

    emit\_signal("connected\_to\_server")

    \# Dem Server den eigenen Namen mitteilen

    register\_player\_name.rpc\_id(1, player\_name)

func \_on\_connected\_fail() \-\> void:

    print("Verbindung fehlgeschlagen.")

    emit\_signal("connection\_failed")

func \_on\_server\_disconnected() \-\> void:

    print("Verbindung zum Server verloren.")

    emit\_signal("server\_disconnected")

    disconnect\_network()

func \_on\_peer\_connected(id: int) \-\> void:

    print("Neuer Peer verbunden: ", id)

    \# Wenn wir Host sind, warten wir, bis der Client uns seinen Namen sendet.

func \_on\_peer\_disconnected\_server(id: int) \-\> void:

    print("Peer getrennt: ", id)

    GameState.remove\_player(id)

    sync\_game\_state\_to\_all()

---

## 3\. Schritt 3.2: RPC-Funktionen (Remote Procedure Calls)

Statt manueller JSON-Zeilen nutzen wir `@rpc`\-Annotationen. Damit können Funktionen direkt über das Netzwerk aufgerufen werden.

### Client-zu-Server Aktionen (`@rpc("any_peer", "reliable")`):

Füge diese Funktionen in deinen zentralen Game-Controller oder den NetworkManager ein, damit Clients Aktionen an den Host senden können:

\# Wird vom Client aufgerufen, um seinen Namen beim Beitritt zu registrieren

@rpc("any\_peer", "reliable")

func register\_player\_name(p\_name: String) \-\> void:

    if not multiplayer.is\_server():

        return

    var sender\_id \= multiplayer.get\_remote\_sender\_id()

    \# Bereinige den Namen

    var clean\_name \= p\_name.strip\_edges().substr(0, 18\)

    if clean\_name \== "":

        clean\_name \= "Spieler %d" % sender\_id

        

    \# Spieler im GameState anlegen und ID mappen (kann in Dictionary gespeichert werden)

    var player \= GameState.add\_player(clean\_name)

    if player:

        \# Hier speichern wir die Zuordnung Godot-Peer-ID \-\> Game-Player-ID

        \# (Beispielhaft vereinfacht: wir nutzen die Peer-ID als Spieler-ID)

        player.id \= sender\_id

        GameState.players\[sender\_id\] \= player

        GameState.players.erase(player.id \- player.id) \# Dummy-Cleanup falls nötig

        

        \# Aktuellen Zustand an alle synchronisieren

        sync\_game\_state\_to\_all()

@rpc("any\_peer", "unreliable")

func send\_axis(axis\_value: int) \-\> void:

    if not multiplayer.is\_server():

        return

    var sender\_id \= multiplayer.get\_remote\_sender\_id()

    GameState.set\_axis(sender\_id, axis\_value)

@rpc("any\_peer", "reliable")

func request\_probe() \-\> void:

    if not multiplayer.is\_server():

        return

    var sender\_id \= multiplayer.get\_remote\_sender\_id()

    var result \= GameState.probe(sender\_id)

    if not result.is\_empty():

        \# Sende das Sonden-Ergebnis an den anfragenden Client zurück

        receive\_probe\_result.rpc\_id(sender\_id, result)

        sync\_game\_state\_to\_all()

### Server-zu-Client Synchronisation (`@rpc("authority")`):

@rpc("authority", "reliable")

func sync\_state(state\_data: Dictionary) \-\> void:

    \# Clients empfangen hier den aktualisierten Spielzustand vom Server

    GameState.phase \= state\_data\["phase"\]

    GameState.round\_number \= state\_data\["round"\]

    GameState.winner \= state\_data\["winner"\]

    \# Spieler-Daten aktualisieren...

@rpc("authority", "reliable")

func receive\_probe\_result(result: Dictionary) \-\> void:

    \# Client verarbeitet das Ergebnis seiner Sonde (z.B. Anzeige in UI)

    print("Sondenergebnis empfangen: ", result)

func sync\_game\_state\_to\_all() \-\> void:

    if not multiplayer.is\_server():

        return

    var snapshot \= GameState.snapshot()

    sync\_state.rpc(snapshot)

---

## 4\. Schritt 3.3: Lobby-Verwaltung & Spielstart

Der Host steuert den Start der Runde und synchronisiert die Spielerliste in der Lobby.

@rpc("any\_peer", "reliable")

func request\_start\_round() \-\> void:

    if not multiplayer.is\_server():

        return

    \# Nur der Host darf die Runde starten (Prüfung der Peer ID \== 1\)

    if multiplayer.get\_remote\_sender\_id() \== 1 or multiplayer.is\_server():

        if GameState.start\_round():

            broadcast\_round\_started.rpc(GameState.round\_number)

@rpc("authority", "reliable")

func broadcast\_round\_started(round\_num: int) \-\> void:

    GameState.round\_number \= round\_num

    GameState.phase \= "playing"

    \# Wechsel zur Spielfeld-Szene auf allen Clients

    get\_tree().change\_scene\_to\_file("res://scenes/Game.tscn")

---

## Nächste Schritte:

Sobald das Netzwerk stabil läuft, gehen wir zu **Phase 4** über: Die Benutzeroberfläche (`gui.py` \$\\rightarrow\$ Godot Control-Nodes, `Line2D` für das Terrain und die Kameraführung).