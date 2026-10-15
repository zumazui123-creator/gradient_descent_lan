# Gradient Descent – Schatzsuche im LAN

## Lernziel

Das Spiel erklärt Kindern das Grundprinzip des maschinellen Lernens am Beispiel
von Gradient Descent. Die Kinder spielen selbst die KI: Das Schiff stellt ihre
aktuelle Vermutung dar, jede
Sonde einen Lernschritt und das gemessene Gefälle den Hinweis für die nächste
Verbesserung. Der Schatz steht für die beste gefundene Lösung. Die wiederholte
Schleife lautet: **vermuten → messen → verbessern**. Ein lokales Tal zeigt
zugleich, warum eine KI trotz sinnvoller Einzelschritte bei einer nur scheinbar
guten Lösung landen kann. Die gefahrene Strecke veranschaulicht die Lernrate:
Zu große Schritte sind schnell, können das Ziel aber überspringen. Echte
Lernverfahren verändern statt eines Schiffes Zahlen und versuchen damit
meistens, einen Fehler schrittweise zu verkleinern.

## Godot-Port (Phase 4)

Der laufende Port liegt direkt in diesem Ordner und benötigt **Godot 4.8 oder
neuer**. `project.godot` im Godot Project Manager importieren und das Projekt
mit **F6/F5** starten. Für einen lokalen Mehrspieler-Test zwei Instanzen öffnen:
Eine Instanz hostet, die zweite verbindet sich mit `127.0.0.1`. Der Godot-Port
nutzt ENet über **UDP-Port 3131**.

Das Projekt deklariert `4.8` als Engine-Feature und prüft die Mindestversion
auch im automatischen Testlauf. Ältere Godot-Versionen werden nicht unterstützt.

In der Lobby legt der Host fest, ob nur eigene oder alle Messungen sichtbar
sind. Optional können bis zu sechs Spieler frei auf drei Teams verteilt werden,
etwa als 2 gegen 2, 3 gegen 3 oder 2 gegen 1 gegen 3. Jede Sonde verankert das
Schiff für drei Sekunden. Messkurven- und Tangentenlänge stehen zentral in
`GameConstants.gd`.

Die automatischen Prüfskripte können mit einer Godot-Kommandozeile ausgeführt
werden:

```bash
godot --headless --path . res://tests/RunPhase4.tscn
```

Die folgende Beschreibung dokumentiert weiterhin die Python-Referenzversion,
an der der Port funktional ausgerichtet ist.

Ein eigenständiges Pygame-Lernspiel: Zwei bis vier Personen fahren auf derselben
versteckten Seekarte. Die befahrbare Karte ist doppelt so breit wie in der ersten
Version (2112 statt 1056 Pixel) und enthält etwa doppelt so viele Täler.
Das Fenster folgt dem eigenen Schiff. Jede Person
hat 40 Sonden. Eine Messung zeigt ein Stück Meeresboden,
die Tiefe und das lokale Gefälle. Die erste Sonde in der Nähe des tiefsten Punktes
findet den Schatz. Die Karte wird nach der Runde vollständig sichtbar.

## Installation

Python 3.10 oder neuer wird benötigt. In diesem Ordner ausführen:

```bash
python -m pip install -r requirements.txt
python main.py
```

Im Menü wählt eine Person **Spiel hosten**. Die anderen geben die angezeigte
Host-IP ein und wählen **Beitreten**. Alle Rechner müssen im selben LAN/WLAN
sein. Der Host startet die Runde, sobald mindestens zwei Spieler verbunden sind.
Bis zu vier Personen können mitspielen. Falls eine Firewall fragt, eingehendes
TCP auf Port **50415** für den Host freigeben. Der Port lässt sich über `--port`
auf allen Rechnern gleich ändern.

Alternativ direkt über die Kommandozeile:

```bash
# Host
python main.py --host --name Ada

# Anderer Rechner (IP durch die im Host-Fenster angezeigte Adresse ersetzen)
python main.py --join 192.168.1.42 --name Ben
```

Für einen Test auf einem einzigen Rechner den Host starten und ein zweites
Fenster mit `python main.py --join 127.0.0.1 --name Ben` öffnen.

## Steuerung

- **← / →** oder **A / D**: Schiff bewegen.
- **Leertaste**, **↓** oder **S**: Sonde absenken.
- **H**: Hilfe anzeigen.
- **Enter**: Runde in der Lobby starten (Host).
- **R**: Nach der Runde neue Karte starten (Host).
- **Esc**: Hilfe schließen oder Spiel verlassen.

Nach Rundenende zentriert sich die Ansicht auf den Schatz. Mit **← / →**
oder **A / D** lässt sich die gesamte aufgedeckte Karte durchsehen.

`main.py` startet das Spiel, `gui.py` zeichnet und verarbeitet Eingaben,
`network.py` übernimmt die TCP-Verbindungen, und `game.py` enthält die
autoritative Spiellogik. Vor dem Rundenende sendet der Host nur die jeweiligen
Sondenmessungen an die einzelnen Spieler, nicht den gesamten Meeresboden.

Die Tangente ist am letzten Messpunkt **48 Pixel** breit.
