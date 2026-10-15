"""Startpunkt: python main.py [--host | --join HOST-IP] [--name NAME]."""

import argparse

from gui import GameUI
from network import DEFAULT_PORT


def main() -> None:
    parser = argparse.ArgumentParser(description="Gradient Descent: LAN-Schatzsuche mit Pygame")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--host", action="store_true", help="LAN-Runde hosten")
    mode.add_argument("--join", metavar="HOST-IP", help="Einer LAN-Runde beitreten")
    parser.add_argument("--name", default="Spieler", help="Angezeigter Name (maximal 18 Zeichen)")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help=f"TCP-Port (Standard: {DEFAULT_PORT})")
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error("Der Port muss zwischen 1 und 65535 liegen.")
    GameUI(mode="host" if args.host else "join" if args.join else None,
           address=args.join or "127.0.0.1", port=args.port, name=args.name).run()


if __name__ == "__main__":
    main()

