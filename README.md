# Gradient Descent – Schatzsuche im LAN

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
