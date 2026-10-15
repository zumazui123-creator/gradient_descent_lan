"""Spiellogik für Gradient Descent – ohne Pygame und ohne Netzwerkcode."""

from __future__ import annotations

from dataclasses import dataclass, field
import math
import random
import time
from typing import Any


WIDTH, HEIGHT = 1200, 760
WORLD_LEFT, WORLD_RIGHT = 72, 2184  # Bisher 1056, jetzt 2112 befahrbare Pixel
SEA_Y = 247
PROBES_PER_PLAYER = 40
SHIP_SPEED = 280.0  # Pixel pro Sekunde
TREASURE_RADIUS = 22.0
PLAYER_COLORS = ("#40e6ff", "#ffbd56", "#c295ff", "#74f49d")


def clamp(value: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, value))


class Seabed:
    """Geglättete 1D-Landschaft mit mehreren Tälern und einem tiefsten Punkt."""

    STEP = 4

    def __init__(self, seed: int):
        rng = random.Random(seed)
        width = WORLD_RIGHT - WORLD_LEFT
        # Die doppelte Breite enthält auch ungefähr doppelt so viele Täler.
        # Ihre Breite in Welt-Pixeln bleibt dadurch ähnlich wie zuvor.
        centers = [(i + 0.5) / 6 + rng.uniform(-0.016, 0.016)
                   for i in range(6)]
        amplitudes = [rng.uniform(77, 107) for _ in centers]
        amplitudes[rng.randrange(len(centers))] += 31
        phase = rng.uniform(-math.pi, math.pi)
        self.points: list[tuple[int, float]] = []
        for x in range(WORLD_LEFT, WORLD_RIGHT + 1, self.STEP):
            t = (x - WORLD_LEFT) / width
            y = 426 + 15 * math.sin(2 * math.pi * 1.1 * t + phase)
            for center, height in zip(centers, amplitudes):
                y += height * math.exp(-0.5 * ((t - center) / 0.039) ** 2)
            y += 7 * math.sin(2 * math.pi * 9.2 * t + phase * 0.57)
            self.points.append((x, clamp(y, 380, 665)))
        candidates = self.points[7:-7]
        self.treasure_x = max(candidates, key=lambda p: p[1])[0]

    def depth_at(self, x: float) -> float:
        x = clamp(x, WORLD_LEFT, WORLD_RIGHT)
        i = min(int((x - WORLD_LEFT) // self.STEP), len(self.points) - 2)
        x0, y0 = self.points[i]
        return y0 + (self.points[i + 1][1] - y0) * (x - x0) / self.STEP

    def slope_at(self, x: float) -> float:
        left = max(WORLD_LEFT, x - 12)
        right = min(WORLD_RIGHT, x + 12)
        return (self.depth_at(right) - self.depth_at(left)) / (right - left)

    def patch_at(self, x: float) -> list[list[int]]:
        left = max(WORLD_LEFT, int(x) - 55)
        right = min(WORLD_RIGHT, int(x) + 55)
        xs = list(range(left, right + 1, 5))
        if xs[-1] != right:
            xs.append(right)
        return [[px, round(self.depth_at(px))] for px in xs]

    def public_profile(self) -> list[list[int]]:
        return [[x, round(y)] for x, y in self.points]


@dataclass
class Player:
    id: int
    name: str
    color: str
    x: float
    probes_left: int = PROBES_PER_PLAYER
    axis: int = 0
    last_probe: float = -10.0
    measurements: int = 0

    def public(self) -> dict[str, Any]:
        return {"id": self.id, "name": self.name, "color": self.color,
                "x": round(self.x, 1), "probes_left": self.probes_left,
                "measurements": self.measurements}


@dataclass
class GameState:
    players: dict[int, Player] = field(default_factory=dict)
    phase: str = "lobby"  # lobby, playing, finished
    round_number: int = 0
    winner: int | None = None
    seabed: Seabed | None = None
    next_id: int = 1

    def add_player(self, name: str) -> Player | None:
        if self.phase not in ("lobby", "finished") or len(self.players) >= len(PLAYER_COLORS):
            return None
        player_id = self.next_id
        self.next_id += 1
        player = Player(player_id, name[:18] or f"Spieler {player_id}",
                        PLAYER_COLORS[(player_id - 1) % len(PLAYER_COLORS)],
                        WORLD_LEFT + (WORLD_RIGHT - WORLD_LEFT) / 2)
        self.players[player_id] = player
        return player

    def remove_player(self, player_id: int) -> None:
        self.players.pop(player_id, None)
        if self.phase == "playing" and self.players and all(
            p.probes_left == 0 for p in self.players.values()
        ):
            self.phase = "finished"

    def start_round(self, seed: int | None = None) -> bool:
        if self.phase not in ("lobby", "finished") or len(self.players) < 2:
            return False
        self.seabed = Seabed(seed if seed is not None else random.SystemRandom().randrange(2**32))
        self.round_number += 1
        self.winner = None
        self.phase = "playing"
        ordered = sorted(self.players.values(), key=lambda p: p.id)
        for i, player in enumerate(ordered):
            player.x = WORLD_LEFT + (WORLD_RIGHT - WORLD_LEFT) * (i + 1) / (len(ordered) + 1)
            player.axis = 0
            player.probes_left = PROBES_PER_PLAYER
            player.measurements = 0
            player.last_probe = -10.0
        return True

    def set_axis(self, player_id: int, axis: int) -> None:
        player = self.players.get(player_id)
        if player and self.phase == "playing" and axis in (-1, 0, 1):
            player.axis = axis

    def tick(self, dt: float) -> None:
        if self.phase != "playing":
            return
        for player in self.players.values():
            player.x = clamp(player.x + player.axis * SHIP_SPEED * min(dt, 0.12),
                             WORLD_LEFT, WORLD_RIGHT)

    def probe(self, player_id: int, now: float | None = None) -> dict[str, Any] | None:
        player = self.players.get(player_id)
        if player is None or self.phase != "playing" or self.seabed is None:
            return None
        stamp = time.monotonic() if now is None else now
        if player.probes_left <= 0 or stamp - player.last_probe < 0.40:
            return None
        player.last_probe = stamp
        player.probes_left -= 1
        player.measurements += 1
        x = player.x
        depth = self.seabed.depth_at(x)
        slope = self.seabed.slope_at(x)
        found = abs(x - self.seabed.treasure_x) <= TREASURE_RADIUS
        if found:
            self.winner = player_id
            self.phase = "finished"
        elif all(p.probes_left == 0 for p in self.players.values()):
            self.phase = "finished"
        return {"type": "probe_result", "x": round(x, 1), "y": round(depth, 1),
                "slope": round(slope, 3), "patch": self.seabed.patch_at(x),
                "probes_left": player.probes_left, "found": found}

    def snapshot(self) -> dict[str, Any]:
        return {"type": "state", "phase": self.phase,
                "round": self.round_number, "winner": self.winner,
                "players": [p.public() for p in sorted(self.players.values(), key=lambda p: p.id)]}
