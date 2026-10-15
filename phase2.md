# Phase 2: Die Kernlogik portieren (`game.py` \$\\rightarrow\$ GDScript)

In dieser Phase portieren wir die komplette mathematische und spielerische Logik aus `game.py` in native Godot-GDScript-Klassen.

## 1\. Übersicht der Konstanten und Parameter

In GDScript definieren wir die globalen Konstanten am besten in einem eigenen Skript oder direkt im Game-Manager (Autoload):

class\_name GameConstants

const WIDTH: float \= 1200.0

const HEIGHT: float \= 760.0

const WORLD\_LEFT: float \= 72.0

const WORLD\_RIGHT: float \= 2184.0

const SEA\_Y: float \= 247.0

const PROBES\_PER\_PLAYER: int \= 40

const SHIP\_SPEED: float \= 280.0

const TREASURE\_RADIUS: float \= 22.0

const PLAYER\_COLORS: Array\[String\] \= \["\#40e6ff", "\#ffbd56", "\#c295ff", "\#74f49d"\]

---

## 2\. Schritt 2.1: Der Terrain-Generator (`Seabed`)

Der Meeresboden wird durch eine Kombination aus Sinuswellen und Gaußschen Glockenkurven erzeugt, um realistische Täler und einen eindeutigen tiefsten Punkt (`treasure_x`) zu berechnen.

### GDScript-Implementierung (`Seabed.gd`):

class\_name Seabed

extends RefCounted

const STEP: int \= 4

var points: Array \= \[\] \# Enthält Arrays aus \[x, y\]

var treasure\_x: float \= 0.0

func \_init(seed\_value: int) \-\> void:

    var rng \= RandomNumberGenerator.new()

    rng.seed \= seed\_value

    

    var world\_width \= GameConstants.WORLD\_RIGHT \- GameConstants.WORLD\_LEFT

    var centers: Array\[float\] \= \[\]

    for i in range(6):

        centers.append((i \+ 0.5) / 6.0 \+ rng.randf\_range(-0.016, 0.016))

    

    var amplitudes: Array\[float\] \= \[\]

    for c in centers:

        amplitudes.append(rng.randf\_range(77.0, 107.0))

    amplitudes\[rng.randi\_range(0, centers.size() \- 1)\] \+= 31.0

    

    var phase \= rng.randf\_range(-PI, PI)

    points.clear()

    

    var x \= GameConstants.WORLD\_LEFT

    while x \<= GameConstants.WORLD\_RIGHT:

        var t \= (x \- GameConstants.WORLD\_LEFT) / world\_width

        var y \= 426.0 \+ 15.0 \* sin(2.0 \* PI \* 1.1 \* t \+ phase)

        

        for i in range(centers.size()):

            var center \= centers\[i\]

            var amp \= amplitudes\[i\]

            y \+= amp \* exp(-0.5 \* pow((t \- center) / 0.039, 2))

            

        y \+= 7.0 \* sin(2.0 \* PI \* 9.2 \* t \+ phase \* 0.57)

        points.append(\[x, clamp(y, 380.0, 665.0)\])

        x \+= STEP

        

    \# Tiefsten Punkt (Schatz) finden (höchster y-Wert in Pixeln, da y nach unten zeigt)

    var max\_y \= \-1.0

    var cand\_x \= GameConstants.WORLD\_LEFT

    for i in range(7, points.size() \- 7):

        var pt \= points\[i\]

        if pt\[1\] \> max\_y:

            max\_y \= pt\[1\]

            cand\_x \= pt\[0\]

    treasure\_x \= cand\_x

func depth\_at(x: float) \-\> float:

    x \= clamp(x, GameConstants.WORLD\_LEFT, GameConstants.WORLD\_RIGHT)

    var i \= int(floor((x \- GameConstants.WORLD\_LEFT) / STEP))

    i \= clampi(i, 0, points.size() \- 2\)

    var p0 \= points\[i\]

    var p1 \= points\[i \+ 1\]

    return p0\[1\] \+ (p1\[1\] \- p0\[1\]) \* (x \- p0\[0\]) / float(STEP)

func slope\_at(x: float) \-\> float:

    var left \= max(GameConstants.WORLD\_LEFT, x \- 12.0)

    var right \= min(GameConstants.WORLD\_RIGHT, x \+ 12.0)

    return (depth\_at(right) \- depth\_at(left)) / (right \- left)

func patch\_at(x: float) \-\> Array:

    var left \= max(GameConstants.WORLD\_LEFT, int(x) \- 55\)

    var right \= min(GameConstants.WORLD\_RIGHT, int(x) \+ 55\)

    var xs: Array\[int\] \= \[\]

    var px \= left

    while px \<= right:

        xs.append(px)

        px \+= 5

    if xs.back() \!= right:

        xs.append(int(right))

    

    var patch: Array \= \[\]

    for p in xs:

        patch.append(\[p, round(depth\_at(float(p)))\])

    return patch

func public\_profile() \-\> Array:

    var profile: Array \= \[\]

    for p in points:

        profile.append(\[p\[0\], round(p\[1\])\])

    return profile

---

## 3\. Schritt 2.2: Spieler-Datenstruktur (`Player`)

Der Spieler speichert alle zustandsbezogenen Daten für das Multiplayer-Spiel.

### GDScript-Implementierung (`Player.gd`):

class\_name Player

extends RefCounted

var id: int

var name: String

var color: String

var x: float

var probes\_left: int \= GameConstants.PROBES\_PER\_PLAYER

var axis: int \= 0

var last\_probe: float \= \-10.0

var measurements: int \= 0

func \_init(p\_id: int, p\_name: String, p\_color: String, p\_x: float) \-\> void:

    id \= p\_id

    name \= p\_name.substr(0, 18\)

    color \= p\_color

    x \= p\_x

func public\_dict() \-\> Dictionary:

    return {

        "id": id,

        "name": name,

        "color": color,

        "x": snappedf(x, 0.1),

        "probes\_left": probes\_left,

        "measurements": measurements

    }

---

## 4\. Schritt 2.3: Spielschleife & Spielzustand (`GameState`)

Der `GameState` verwaltet die Spieler, Phasen (`lobby`, `playing`, `finished`) sowie die Physik-Ticks und Sondenabfragen.

### GDScript-Implementierung (`GameState.gd` als Autoload oder Node):

class\_name GameStateClass

extends Node

var players: Dictionary \= {} \# id \-\> Player

var phase: String \= "lobby" \# lobby, playing, finished

var round\_number: int \= 0

var winner \= null \# int or null

var seabed: Seabed \= null

var next\_id: int \= 1

func add\_player(p\_name: String) \-\> Player:

    if phase \!= "lobby" and phase \!= "finished":

        return null

    if players.size() \>= GameConstants.PLAYER\_COLORS.size():

        return null

        

    var pid \= next\_id

    next\_id \+= 1

    var color \= GameConstants.PLAYER\_COLORS\[(pid \- 1\) % GameConstants.PLAYER\_COLORS.size()\]

    var start\_x \= GameConstants.WORLD\_LEFT \+ (GameConstants.WORLD\_RIGHT \- GameConstants.WORLD\_LEFT) / 2.0

    

    var player \= Player.new(pid, p\_name if p\_name \!= "" else "Spieler %d" % pid, color, start\_x)

    players\[pid\] \= player

    return player

func remove\_player(pid: int) \-\> void:

    players.erase(pid)

    if phase \== "playing" and not players.is\_empty():

        var all\_empty \= true

        for p in players.values():

            if p.probes\_left \> 0:

                all\_empty \= false

                break

        if all\_empty:

            phase \= "finished"

func start\_round(seed\_value: int \= \-1) \-\> bool:

    if phase \!= "lobby" and phase \!= "finished":

        return false

    if players.size() \< 2:

        return false

        

    var rng\_seed \= seed\_value if seed\_value \!= \-1 else randi()

    seabed \= Seabed.new(rng\_seed)

    round\_number \+= 1

    winner \= null

    phase \= "playing"

    

    var ordered\_ids \= players.keys()

    ordered\_ids.sort()

    for i in range(ordered\_ids.size()):

        var p \= players\[ordered\_ids\[i\]\]

        p.x \= GameConstants.WORLD\_LEFT \+ (GameConstants.WORLD\_RIGHT \- GameConstants.WORLD\_LEFT) \* (i \+ 1\) / float(ordered\_ids.size() \+ 1\)

        p.axis \= 0

        p.probes\_left \= GameConstants.PROBES\_PER\_PLAYER

        p.measurements \= 0

        p.last\_probe \= \-10.0

    return true

func set\_axis(pid: int, ax: int) \-\> void:

    if players.has(pid) and phase \== "playing" and (ax \== \-1 or ax \== 0 or ax \== 1):

        players\[pid\].axis \= ax

func tick(dt: float) \-\> void:

    if phase \!= "playing":

        return

    for p in players.values():

        p.x \= clamp(p.x \+ p.axis \* GameConstants.SHIP\_SPEED \* min(dt, 0.12), GameConstants.WORLD\_LEFT, GameConstants.WORLD\_RIGHT)

func probe(pid: int, now: float \= \-1.0) \-\> Dictionary:

    if not players.has(pid) or phase \!= "playing" or seabed \== null:

        return {}

        

    var p: Player \= players\[pid\]

    var stamp \= Time.get\_unix\_time\_from\_system() if now \== \-1.0 else now

    

    if p.probes\_left \<= 0 or (stamp \- p.last\_probe \< 0.40):

        return {}

        

    p.last\_probe \= stamp

    p.probes\_left \-= 1

    p.measurements \+= 1

    

    var x \= p.x

    var depth \= seabed.depth\_at(x)

    var slope \= seabed.slope\_at(x)

    var found \= abs(x \- seabed.treasure\_x) \<= GameConstants.TREASURE\_RADIUS

    

    if found:

        winner \= pid

        phase \= "finished"

    else:

        var all\_empty \= true

        for pl in players.values():

            if pl.probes\_left \> 0:

                all\_empty \= false

                break

        if all\_empty:

            phase \= "finished"

            

    return {

        "type": "probe\_result",

        "x": snappedf(x, 0.1),

        "y": snappedf(depth, 0.1),

        "slope": snappedf(slope, 0.001),

        "patch": seabed.patch\_at(x),

        "probes\_left": p.probes\_left,

        "found": found

    }

func snapshot() \-\> Dictionary:

    var p\_list \= \[\]

    var ordered\_ids \= players.keys()

    ordered\_ids.sort()

    for pid in ordered\_ids:

        p\_list.append(players\[pid\].public\_dict())

        

    return {

        "type": "state",

        "phase": phase,

        "round": round\_number,

        "winner": winner,

        "players": p\_list

    }