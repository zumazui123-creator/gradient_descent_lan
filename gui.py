"""Pygame-Oberfläche für das LAN-Schatzsuchspiel."""

from __future__ import annotations

import random
import time
from typing import Any

import pygame

from game import (HEIGHT, PROBES_PER_PLAYER, SEA_Y, WIDTH, WORLD_LEFT,
                  WORLD_RIGHT, clamp)
from network import DEFAULT_PORT, LANClient, LANServer, local_ip


BG = (7, 13, 32)
PANEL = (15, 28, 54)
PANEL_EDGE = (44, 76, 113)
WHITE = (229, 246, 255)
MUTED = (137, 172, 197)
CYAN = (64, 230, 255)
GOLD = (255, 191, 86)
GREEN = (116, 244, 157)
RED = (255, 111, 132)
WATER = (9, 31, 60)
VIEW_LEFT, VIEW_RIGHT = 72, 1128
VIEW_WIDTH = VIEW_RIGHT - VIEW_LEFT
MAX_CAMERA = WORLD_RIGHT - WORLD_LEFT - VIEW_WIDTH


def color(hex_value: str) -> tuple[int, int, int]:
    return pygame.Color(hex_value).r, pygame.Color(hex_value).g, pygame.Color(hex_value).b


class GameUI:
    def __init__(self, mode: str | None = None, address: str = "127.0.0.1",
                 port: int = DEFAULT_PORT, name: str = "Spieler"):
        pygame.init()
        pygame.display.set_caption("Gradient Descent – Schatzsuche im LAN")
        self.screen = pygame.display.set_mode((WIDTH, HEIGHT))
        self.canvas = pygame.Surface((WIDTH, HEIGHT)).convert()
        self.clock = pygame.time.Clock()
        self.font = pygame.font.SysFont("dejavusans", 19)
        self.small = pygame.font.SysFont("dejavusans", 15)
        self.tiny = pygame.font.SysFont("dejavusans", 13)
        self.bold = pygame.font.SysFont("dejavusans", 23, bold=True)
        self.title_font = pygame.font.SysFont("dejavusans", 40, bold=True)

        self.initial_mode = mode
        self.address = address
        self.port = port
        self.name = name[:18]
        self.focus: str | None = None
        self.server: LANServer | None = None
        self.client: LANClient | None = None
        self.player_id: int | None = None
        self.is_host = False
        self.phase = "menu"
        self.players: list[dict[str, Any]] = []
        self.round_number = 0
        self.winner: int | None = None
        self.terrain: list[list[int]] | None = None
        self.treasure_x: int | None = None
        self.observations: list[dict[str, Any]] = []
        self.last_observation: dict[str, Any] | None = None
        self.probe_animation: dict[str, float] | None = None
        self.notice = ""
        self.notice_until = 0.0
        self.help_open = False
        self._last_axis = 0
        self.camera_x = 0.0
        self._buttons: list[tuple[pygame.Rect, str]] = []
        rng = random.Random(35)
        self.stars = [(rng.randrange(WIDTH), rng.randrange(170), rng.choice((1, 1, 2)))
                      for _ in range(78)]

    def _text(self, value: str, x: int, y: int, font: pygame.font.Font | None = None,
              ink: tuple[int, int, int] = WHITE, center: bool = False) -> None:
        surface = (font or self.font).render(value, True, ink)
        rect = surface.get_rect(center=(x, y)) if center else surface.get_rect(topleft=(x, y))
        self.canvas.blit(surface, rect)

    def _panel(self, rect: pygame.Rect, fill: tuple[int, int, int] = PANEL,
               edge: tuple[int, int, int] = PANEL_EDGE, radius: int = 16) -> None:
        pygame.draw.rect(self.canvas, fill, rect, border_radius=radius)
        pygame.draw.rect(self.canvas, edge, rect, 2, border_radius=radius)

    def _button(self, rect: pygame.Rect, label: str, action: str, enabled: bool = True) -> None:
        fill = (22, 75, 98) if enabled else (28, 42, 57)
        edge = CYAN if enabled else PANEL_EDGE
        self._panel(rect, fill, edge, 10)
        self._text(label, rect.centerx, rect.centery, self.small,
                   WHITE if enabled else MUTED, center=True)
        if enabled:
            self._buttons.append((rect, action))

    def _notice(self, message: str, seconds: float = 4.0) -> None:
        self.notice = message
        self.notice_until = time.monotonic() + seconds

    def _host(self) -> None:
        try:
            self.server = LANServer(self.port)
            self.server.start()
            self.client = LANClient("127.0.0.1", self.server.port, self.name,
                                    self.server.host_token)
            self.phase = "connecting"
        except OSError as exc:
            if self.server:
                self.server.stop()
            self.server = None
            self.client = None
            self.phase = "menu"
            self._notice(f"Host konnte nicht starten: {exc}", 7)

    def _join(self) -> None:
        try:
            self.client = LANClient(self.address.strip() or "127.0.0.1", self.port, self.name)
            self.phase = "connecting"
        except OSError as exc:
            self._notice(f"Verbindung fehlgeschlagen: {exc}", 7)

    def _disconnect(self) -> None:
        if self.client:
            self.client.close()
            self.client = None
        if self.server:
            self.server.stop()
            self.server = None

    def _network_message(self, message: dict[str, Any]) -> None:
        kind = message.get("type")
        if kind == "welcome":
            self.player_id = message["id"]
            self.is_host = bool(message.get("host"))
            self.phase = "lobby"
        elif kind == "state":
            self.phase = message["phase"]
            self.players = message["players"]
            self.round_number = message["round"]
            self.winner = message["winner"]
        elif kind == "round":
            self.round_number = message["number"]
            self.phase = "playing"
            self.winner = None
            self.terrain = None
            self.treasure_x = None
            self.observations.clear()
            self.last_observation = None
            self.probe_animation = None
            self._last_axis = 0
            self.camera_x = 0.0
        elif kind == "probe_result":
            self.observations.append(message)
            self.last_observation = message
            self.probe_animation = {"x": message["x"], "y": SEA_Y,
                                    "target": message["y"], "age": 0.0}
            if message.get("found"):
                self._notice("Schatz gefunden!", 5)
        elif kind == "finished":
            self.phase = "finished"
            self.terrain = message["terrain"]
            self.treasure_x = message["treasure_x"]
            self.winner = message["winner"]
            self.camera_x = clamp(self.treasure_x - WIDTH / 2, 0, MAX_CAMERA)
        elif kind in ("error", "notice"):
            self._notice(str(message.get("message", "Unbekannter Fehler")), 6)
            if kind == "error":
                self._disconnect()
                self.phase = "menu"
        elif kind == "disconnected":
            if self.phase == "menu" and self.client is None:
                return
            self._disconnect()
            self.phase = "menu"
            self._notice("Verbindung zum Host verloren.", 7)

    def _update(self, dt: float) -> None:
        if self.client:
            for message in self.client.poll():
                self._network_message(message)
        if self.phase == "playing":
            own = next((p for p in self.players if p["id"] == self.player_id), None)
            if own:
                target = clamp(own["x"] - WIDTH / 2, 0, MAX_CAMERA)
                self.camera_x += (target - self.camera_x) * min(1.0, dt * 10)
        elif self.phase == "finished" and not self.help_open:
            keys = pygame.key.get_pressed()
            axis = int(bool(keys[pygame.K_RIGHT] or keys[pygame.K_d])) - int(
                bool(keys[pygame.K_LEFT] or keys[pygame.K_a]))
            self.camera_x = clamp(self.camera_x + axis * 700 * dt, 0, MAX_CAMERA)
        if self.client and self.phase == "playing":
            keys = pygame.key.get_pressed()
            axis = 0 if self.help_open else (
                int(bool(keys[pygame.K_RIGHT] or keys[pygame.K_d])) -
                int(bool(keys[pygame.K_LEFT] or keys[pygame.K_a])))
            if axis != self._last_axis:
                self.client.send({"type": "axis", "value": axis})
                self._last_axis = axis
        if self.probe_animation:
            animation = self.probe_animation
            animation["age"] += dt
            animation["y"] = min(animation["target"], animation["y"] + dt * 680)
            if animation["age"] > 1.1:
                self.probe_animation = None

    def _input(self, event: pygame.event.Event) -> bool:
        if event.type == pygame.QUIT:
            return False
        if event.type == pygame.KEYDOWN:
            if event.key == pygame.K_ESCAPE:
                if self.help_open:
                    self.help_open = False
                    return True
                return False
            if self.phase == "menu":
                self._menu_key(event)
            elif event.key == pygame.K_h:
                self.help_open = not self.help_open
            elif self.client and not self.help_open:
                if self.phase == "playing" and event.key in (pygame.K_SPACE, pygame.K_DOWN, pygame.K_s):
                    self.client.send({"type": "probe"})
                elif self.is_host and self.phase == "lobby" and event.key == pygame.K_RETURN:
                    self.client.send({"type": "start"})
                elif self.is_host and self.phase == "finished" and event.key == pygame.K_r:
                    self.client.send({"type": "restart"})
        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            pos = event.pos
            if self.phase == "menu":
                name_rect = pygame.Rect(405, 315, 390, 46)
                address_rect = pygame.Rect(405, 389, 390, 46)
                self.focus = ("name" if name_rect.collidepoint(pos) else
                              "address" if address_rect.collidepoint(pos) else None)
            if not self.help_open:
                for rect, action in self._buttons:
                    if rect.collidepoint(pos):
                        if action == "host":
                            self._host()
                        elif action == "join":
                            self._join()
                        elif action in ("start", "restart") and self.client:
                            self.client.send({"type": action})
                        elif action == "help":
                            self.help_open = True
                        break
        return True

    def _menu_key(self, event: pygame.event.Event) -> None:
        if self.focus is None:
            return
        value = getattr(self, self.focus)
        if event.key == pygame.K_BACKSPACE:
            value = value[:-1]
        elif event.key == pygame.K_TAB:
            self.focus = "address" if self.focus == "name" else "name"
            return
        elif event.key == pygame.K_RETURN:
            self.focus = None
            return
        elif event.unicode.isprintable() and len(value) < (18 if self.focus == "name" else 80):
            value += event.unicode
        setattr(self, self.focus, value)

    def _background(self) -> None:
        self.canvas.fill(BG)
        for x, y, radius in self.stars:
            pygame.draw.circle(self.canvas, (57, 95, 133), (x, y), radius)
        pygame.draw.line(self.canvas, PANEL_EDGE, (0, 88), (WIDTH, 88), 1)
        self._text("GRADIENT DESCENT", 32, 22, self.bold, CYAN)
        self._text("Schatzsuche im LAN", 34, 56, self.small, MUTED)
        if self.phase not in ("menu", "connecting"):
            self._text(f"Runde {self.round_number}  ·  TCP {self.port}", 1060, 44,
                       self.small, MUTED, center=True)

    def _menu(self) -> None:
        self._panel(pygame.Rect(260, 152, 680, 492))
        self._text("Gemeinsam auf Schatzsuche", 600, 211, self.title_font, WHITE, True)
        self._text("Ein Host, zwei bis vier Spieler, eine unbekannte Seekarte.",
                   600, 263, self.small, MUTED, True)
        self._text("Dein Name", 405, 291, self.small, MUTED)
        self._text("Host-IP (zum Beitreten)", 405, 365, self.small, MUTED)
        for field, rect in (("name", pygame.Rect(405, 315, 390, 46)),
                            ("address", pygame.Rect(405, 389, 390, 46))):
            self._panel(rect, (13, 38, 66), CYAN if self.focus == field else PANEL_EDGE, 9)
            self._text(getattr(self, field) or " ", rect.x + 13, rect.y + 11, self.font)
        self._button(pygame.Rect(405, 466, 185, 51), "Spiel hosten", "host")
        self._button(pygame.Rect(610, 466, 185, 51), "Beitreten", "join")
        self._text(f"Port: {self.port}   ·   Gleiche WLAN-/LAN-Verbindung nötig",
                   600, 557, self.small, MUTED, True)
        self._text("← / → bewegen   ·   Leertaste messen   ·   H Hilfe",
                   600, 596, self.small, MUTED, True)

    def _lobby(self) -> None:
        self._panel(pygame.Rect(105, 144, 990, 530))
        self._text("Lobby", 150, 179, self.title_font)
        if self.is_host:
            self._text(f"Mitspieler verbinden sich mit {local_ip()}:{self.port}",
                       150, 244, self.font, CYAN)
        else:
            self._text("Warte, bis der Host die Runde startet.", 150, 244, self.font, CYAN)
        self._text("Spieler", 150, 292, self.bold)
        for i, player in enumerate(self.players):
            y = 339 + i * 57
            pygame.draw.circle(self.canvas, color(player["color"]), (165, y + 12), 9)
            label = player["name"] + ("  (Host)" if player["id"] == self.player_id and self.is_host else "")
            self._text(label, 190, y, self.font)
        self._text("Wer zuerst nahe dem tiefsten Punkt misst, findet den Schatz.",
                   675, 330, self.small, MUTED)
        self._text(f"{PROBES_PER_PLAYER} Sonden pro Spieler – eigene Messpunkte.",
                   675, 367, self.small, MUTED)
        self._text("Folge der Steigung. Ein lokales Tal kann täuschen!",
                   675, 404, self.small, MUTED)
        if self.is_host:
            self._button(pygame.Rect(770, 551, 272, 55), "Runde starten  ↵", "start",
                         enabled=len(self.players) >= 2)
        else:
            self._text("Mindestens zwei Spieler nötig", 783, 572, self.small, MUTED)

    def _ship(self, x: float, ship_color: tuple[int, int, int], name: str,
              own: bool) -> None:
        ix = self._screen_x(x)
        if ix < VIEW_LEFT - 40 or ix > VIEW_RIGHT + 40:
            return
        pygame.draw.polygon(self.canvas, ship_color,
                            [(ix - 29, SEA_Y - 13), (ix + 30, SEA_Y - 13),
                             (ix + 19, SEA_Y + 3), (ix - 19, SEA_Y + 3)])
        pygame.draw.line(self.canvas, WHITE, (ix - 6, SEA_Y - 13), (ix - 6, SEA_Y - 40), 2)
        pygame.draw.polygon(self.canvas, WHITE, [(ix - 5, SEA_Y - 39),
                                                 (ix + 14, SEA_Y - 28), (ix - 5, SEA_Y - 28)])
        self._text(name, ix, SEA_Y - 53, self.tiny, ship_color, True)
        if own:
            pygame.draw.circle(self.canvas, ship_color, (ix, SEA_Y + 12), 3)

    def _screen_x(self, world_x: float) -> int:
        return round(world_x - self.camera_x)

    def _sea(self) -> None:
        pygame.draw.rect(self.canvas, WATER, (VIEW_LEFT - 20, 181,
                                             VIEW_WIDTH + 40, 489), border_radius=13)
        self.canvas.set_clip(pygame.Rect(VIEW_LEFT, 181, VIEW_WIDTH, 489))
        for y in range(295, 653, 65):
            pygame.draw.line(self.canvas, (20, 53, 79), (VIEW_LEFT, y), (VIEW_RIGHT, y), 1)
        for x in range(WORLD_LEFT + 80, WORLD_RIGHT, 88):
            sx = self._screen_x(x)
            if VIEW_LEFT <= sx <= VIEW_RIGHT:
                pygame.draw.line(self.canvas, (17, 46, 73), (sx, 275), (sx, 654), 1)
        pygame.draw.line(self.canvas, CYAN, (VIEW_LEFT, SEA_Y), (VIEW_RIGHT, SEA_Y), 3)
        self._text("MEERESOBERFLÄCHE", VIEW_LEFT + 12, 198, self.tiny, MUTED)

        if self.terrain:
            points = [(self._screen_x(x), int(y)) for x, y in self.terrain]
            pygame.draw.polygon(self.canvas, (20, 50, 60),
                                points + [(self._screen_x(WORLD_RIGHT), 668),
                                          (self._screen_x(WORLD_LEFT), 668)])
            pygame.draw.lines(self.canvas, GREEN, False, points, 3)
            if self.treasure_x is not None:
                sx = self._screen_x(self.treasure_x)
                if VIEW_LEFT - 20 <= sx <= VIEW_RIGHT + 20:
                    y = min(self.terrain, key=lambda p: abs(p[0] - self.treasure_x))[1]
                    pygame.draw.circle(self.canvas, GOLD, (sx, y - 11), 11)
                    self._text("★", sx, y - 32, self.bold, GOLD, True)
        else:
            for observation in self.observations:
                points = [(self._screen_x(x), int(y)) for x, y in observation["patch"]]
                if len(points) >= 2:
                    pygame.draw.lines(self.canvas, GREEN, False, points, 3)
                pygame.draw.circle(self.canvas, WHITE,
                                   (self._screen_x(observation["x"]), int(observation["y"])), 4)

        if self.last_observation and not self.terrain:
            m = self.last_observation
            x, y, slope = m["x"], m["y"], m["slope"]
            # Absichtlich kurze Tangente: insgesamt nur 48 Bildschirmpixel.
            half_span = 24
            a = (self._screen_x(x - half_span), round(y - half_span * slope))
            b = (self._screen_x(x + half_span), round(y + half_span * slope))
            pygame.draw.line(self.canvas, GOLD, a, b, 3)
            pygame.draw.circle(self.canvas, GOLD, (self._screen_x(x), round(y)), 5)

        if self.probe_animation:
            a = self.probe_animation
            sx = self._screen_x(a["x"])
            pygame.draw.line(self.canvas, CYAN, (sx, SEA_Y), (sx, round(a["y"])), 2)
            pygame.draw.circle(self.canvas, CYAN, (sx, round(a["y"])), 6)

        for player in self.players:
            self._ship(player["x"], color(player["color"]), player["name"],
                       player["id"] == self.player_id)
        self.canvas.set_clip(None)

    def _game(self) -> None:
        self._text("Finde den tiefsten Punkt des Meeresbodens", 75, 105, self.bold)
        self._text("KARTE 2×", 1069, 113, self.small, CYAN, True)
        for i, player in enumerate(self.players):
            x = 75 + i * 278
            pygame.draw.circle(self.canvas, color(player["color"]), (x + 8, 158), 7)
            self._text(f"{player['name'][:14]}  {player['probes_left']}/{PROBES_PER_PLAYER}", x + 23, 147,
                       self.small, WHITE if player["id"] == self.player_id else MUTED)
        pygame.draw.line(self.canvas, PANEL_EDGE, (VIEW_LEFT, 175), (VIEW_RIGHT, 175), 2)
        overview_left = round(VIEW_LEFT + self.camera_x / (WORLD_RIGHT - WORLD_LEFT) * VIEW_WIDTH)
        overview_width = round(VIEW_WIDTH * VIEW_WIDTH / (WORLD_RIGHT - WORLD_LEFT))
        pygame.draw.rect(self.canvas, CYAN, (overview_left, 169, overview_width, 12), 1)
        for player in self.players:
            marker_x = round(VIEW_LEFT + (player["x"] - WORLD_LEFT) / (WORLD_RIGHT - WORLD_LEFT) * VIEW_WIDTH)
            pygame.draw.circle(self.canvas, color(player["color"]), (marker_x, 175),
                               5 if player["id"] == self.player_id else 3)
        self._sea()
        self._panel(pygame.Rect(72, 682, 1056, 67), radius=11)
        if self.last_observation:
            m = self.last_observation
            slope = float(m["slope"])
            hint = "tiefer rechts →" if slope > 0.075 else "← tiefer links" if slope < -0.075 else "fast eben"
            self._text(f"Tiefe: {round(m['y'] - SEA_Y)}   ·   Gefälle: {slope:+.2f}   ·   {hint}",
                       91, 699, self.font, GOLD)
        else:
            self._text("Noch keine Messung: Der Boden ist verborgen.", 91, 700, self.font, MUTED)
        controls = ("← → / A D Karte ansehen   ·   H Hilfe" if self.phase == "finished" else
                    "← → / A D bewegen   ·   Leertaste / ↓ / S Sonde   ·   H Hilfe")
        self._text(controls, 91, 727, self.tiny, MUTED)
        self._button(pygame.Rect(996, 695, 118, 37), "Hilfe  H", "help")
        if self.phase == "finished":
            winner = next((p for p in self.players if p["id"] == self.winner), None)
            label = f"{winner['name']} hat den Schatz gefunden!" if winner else "Alle Sonden verbraucht!"
            self._panel(pygame.Rect(328, 289, 544, 190), (19, 36, 58), GOLD, 15)
            self._text("RUNDE BEENDET", 600, 328, self.bold, GOLD, True)
            self._text(label, 600, 373, self.font, WHITE, True)
            if self.is_host:
                self._button(pygame.Rect(463, 411, 274, 48), "Neue Runde  R", "restart",
                             enabled=len(self.players) >= 2)
            else:
                self._text("Warte auf die nächste Runde des Hosts.", 600, 437,
                           self.small, MUTED, True)

    def _help(self) -> None:
        shade = pygame.Surface((WIDTH, HEIGHT), pygame.SRCALPHA)
        shade.fill((3, 9, 22, 218))
        self.canvas.blit(shade, (0, 0))
        self._panel(pygame.Rect(245, 148, 710, 460))
        self._text("So funktioniert die Schatzsuche", 600, 201, self.bold, CYAN, True)
        lines = [
            "Bewege dein Schiff mit ← / → oder A / D.",
            "Leertaste, ↓ oder S senkt eine Sonde ab.",
            "Du erhältst Tiefe und Gefälle nur am Messpunkt.",
            "Steigt die Tiefe nach rechts, suche weiter rechts.",
            "Ein ebenes lokales Tal muss nicht das tiefste Tal sein.",
            f"{PROBES_PER_PLAYER} Sonden pro Spieler; wer den Schatz zuerst trifft, gewinnt.",
            "Das Spielfeld ist doppelt so breit; die Ansicht folgt deinem Schiff.",
            "Alle spielen auf derselben Karte. Nur eigene Messungen sind sichtbar.",
            "Nach der Runde kannst du die Karte mit ← / → ansehen.",
        ]
        for i, line in enumerate(lines):
            self._text(line, 291, 250 + i * 36, self.small)
        self._text("H oder Esc schließt diese Hilfe", 600, 572, self.small, MUTED, True)

    def _draw(self) -> None:
        self._buttons.clear()
        self._background()
        if self.phase == "menu":
            self._menu()
        elif self.phase == "connecting":
            self._text("Verbindung wird aufgebaut …", 600, 375, self.bold, CYAN, True)
        elif self.phase == "lobby":
            self._lobby()
        else:
            self._game()
        if self.notice and time.monotonic() < self.notice_until:
            self._panel(pygame.Rect(225, 92, 750, 47), (61, 37, 47), RED, 9)
            self._text(self.notice[:80], 600, 115, self.small, WHITE, True)
        if self.help_open:
            self._help()
        self.screen.blit(self.canvas, (0, 0))
        pygame.display.flip()

    def run(self) -> None:
        if self.initial_mode == "host":
            self._host()
        elif self.initial_mode == "join":
            self._join()
        running = True
        try:
            while running:
                dt = min(self.clock.tick(60) / 1000.0, 0.10)
                for event in pygame.event.get():
                    if not self._input(event):
                        running = False
                        break
                if running:
                    self._update(dt)
                    self._draw()
        finally:
            self._disconnect()
            pygame.quit()
