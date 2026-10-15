"""TCP-LAN-Protokoll: Der Host verwaltet die Spielwelt und prüft alle Aktionen.

Nachrichten sind UTF-8-JSON, jeweils eine Nachricht pro Zeile. Nur der Host
kennt den ganzen Meeresboden vor dem Ende einer Runde.
"""

from __future__ import annotations

from dataclasses import dataclass
import json
import queue
import secrets
import socket
import threading
import time
from typing import Any

from game import GameState


DEFAULT_PORT = 50415
MAX_LINE = 16_384


def _encode(message: dict[str, Any]) -> bytes:
    return (json.dumps(message, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")


def local_ip() -> str:
    """Bestmögliche LAN-Adresse für die Anzeige im Host-Menü."""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.connect(("10.255.255.255", 1))
            return sock.getsockname()[0]
    except OSError:
        try:
            return socket.gethostbyname(socket.gethostname())
        except OSError:
            return "127.0.0.1"


@dataclass(eq=False)
class _Peer:
    sock: socket.socket
    player_id: int | None = None
    joined: bool = False
    gone: bool = False


class LANServer:
    def __init__(self, port: int = DEFAULT_PORT):
        self.game = GameState()
        self.host_token = secrets.token_urlsafe(24)
        self.host_id: int | None = None
        self._listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._listener.bind(("0.0.0.0", port))
        self.port = self._listener.getsockname()[1]
        self._listener.listen(6)
        self._listener.settimeout(0.05)
        self._events: queue.SimpleQueue[tuple[_Peer, dict[str, Any] | None]] = queue.SimpleQueue()
        self._peers: set[_Peer] = set()
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._run, name="gradient-lan-server", daemon=True)

    def start(self) -> None:
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        try:
            self._listener.close()
        except OSError:
            pass
        if self._thread.is_alive():
            self._thread.join(timeout=2)
        for peer in list(self._peers):
            try:
                peer.sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            peer.sock.close()

    def _read_peer(self, peer: _Peer) -> None:
        data = bytearray()
        deadline = time.monotonic() + 6
        try:
            while not self._stop.is_set():
                if not peer.joined and time.monotonic() > deadline:
                    break
                try:
                    chunk = peer.sock.recv(4096)
                except socket.timeout:
                    continue
                if not chunk:
                    break
                data.extend(chunk)
                while b"\n" in data:
                    line, _, rest = data.partition(b"\n")
                    data = bytearray(rest)
                    if len(line) > MAX_LINE:
                        return
                    try:
                        message = json.loads(line.decode("utf-8"))
                    except (UnicodeError, ValueError):
                        return
                    if not isinstance(message, dict):
                        return
                    self._events.put((peer, message))
                if len(data) > MAX_LINE:
                    break
        except OSError:
            pass
        finally:
            self._events.put((peer, None))

    def _send(self, peer: _Peer, message: dict[str, Any]) -> None:
        if peer.gone:
            return
        try:
            peer.sock.sendall(_encode(message))
        except OSError:
            self._drop(peer)

    def _broadcast(self, message: dict[str, Any]) -> None:
        for peer in list(self._peers):
            if peer.joined:
                self._send(peer, message)

    def _drop(self, peer: _Peer) -> None:
        if peer.gone:
            return
        peer.gone = True
        self._peers.discard(peer)
        if peer.player_id is not None:
            self.game.remove_player(peer.player_id)
        try:
            peer.sock.close()
        except OSError:
            pass

    def _handle(self, peer: _Peer, message: dict[str, Any]) -> None:
        if peer.gone:
            return
        kind = message.get("type")
        if not peer.joined:
            if kind != "hello":
                self._drop(peer)
                return
            name = message.get("name", "Spieler")
            if not isinstance(name, str):
                name = "Spieler"
            name = "".join(c for c in name.strip() if c.isprintable())[:18] or "Spieler"
            player = self.game.add_player(name)
            if player is None:
                self._send(peer, {"type": "error", "message": "Runde läuft oder Lobby voll."})
                self._drop(peer)
                return
            peer.player_id = player.id
            peer.joined = True
            is_host = message.get("host_token") == self.host_token and self.host_id is None
            if is_host:
                self.host_id = player.id
            self._send(peer, {"type": "welcome", "id": player.id, "host": is_host,
                              "port": self.port})
            self._send(peer, self.game.snapshot())
            if self.game.phase == "finished" and self.game.seabed:
                self._send(peer, {"type": "finished", "winner": self.game.winner,
                                  "terrain": self.game.seabed.public_profile(),
                                  "treasure_x": self.game.seabed.treasure_x})
            return

        player_id = peer.player_id
        if kind == "axis" and type(message.get("value")) is int:
            self.game.set_axis(player_id, message["value"])
        elif kind == "probe":
            result = self.game.probe(player_id)
            if result is not None:
                self._send(peer, result)
        elif kind in ("start", "restart") and player_id == self.host_id:
            if self.game.start_round():
                self._broadcast({"type": "round", "number": self.game.round_number})
            else:
                self._send(peer, {"type": "notice", "message": "Mindestens zwei Spieler benötigt."})

    def _run(self) -> None:
        last = time.monotonic()
        next_state = last
        previous_phase = self.game.phase
        while not self._stop.is_set():
            try:
                conn, _address = self._listener.accept()
            except socket.timeout:
                pass
            except OSError:
                break
            else:
                conn.settimeout(0.25)
                peer = _Peer(conn)
                self._peers.add(peer)
                threading.Thread(target=self._read_peer, args=(peer,), daemon=True).start()

            for _ in range(100):
                try:
                    peer, message = self._events.get_nowait()
                except queue.Empty:
                    break
                if message is None:
                    self._drop(peer)
                else:
                    self._handle(peer, message)

            now = time.monotonic()
            self.game.tick(now - last)
            last = now
            if self.game.phase == "finished" and previous_phase != "finished":
                assert self.game.seabed is not None
                self._broadcast({"type": "finished", "winner": self.game.winner,
                                 "terrain": self.game.seabed.public_profile(),
                                 "treasure_x": self.game.seabed.treasure_x})
            previous_phase = self.game.phase
            if now >= next_state:
                self._broadcast(self.game.snapshot())
                next_state = now + 0.08


class LANClient:
    def __init__(self, address: str, port: int, name: str, host_token: str | None = None):
        self.sock = socket.create_connection((address, port), timeout=4)
        self.sock.settimeout(0.25)
        self._send_lock = threading.Lock()
        self._closed = threading.Event()
        self._inbox: queue.SimpleQueue[dict[str, Any]] = queue.SimpleQueue()
        self._thread = threading.Thread(target=self._read, name="gradient-lan-client", daemon=True)
        self._thread.start()
        hello: dict[str, Any] = {"type": "hello", "name": name}
        if host_token is not None:
            hello["host_token"] = host_token
        self.send(hello)

    def send(self, message: dict[str, Any]) -> None:
        if self._closed.is_set():
            return
        try:
            with self._send_lock:
                self.sock.sendall(_encode(message))
        except OSError:
            self._inbox.put({"type": "disconnected"})
            self.close()

    def poll(self) -> list[dict[str, Any]]:
        messages = []
        for _ in range(100):
            try:
                messages.append(self._inbox.get_nowait())
            except queue.Empty:
                break
        return messages

    def _read(self) -> None:
        data = bytearray()
        try:
            while not self._closed.is_set():
                try:
                    chunk = self.sock.recv(4096)
                except socket.timeout:
                    continue
                if not chunk:
                    break
                data.extend(chunk)
                if len(data) > 131_072:
                    break
                while b"\n" in data:
                    line, _, rest = data.partition(b"\n")
                    data = bytearray(rest)
                    try:
                        message = json.loads(line.decode("utf-8"))
                    except (UnicodeError, ValueError):
                        continue
                    if isinstance(message, dict):
                        self._inbox.put(message)
        except OSError:
            pass
        if not self._closed.is_set():
            self._inbox.put({"type": "disconnected"})
        self.close()

    def close(self) -> None:
        if self._closed.is_set():
            return
        self._closed.set()
        try:
            self.sock.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        self.sock.close()
