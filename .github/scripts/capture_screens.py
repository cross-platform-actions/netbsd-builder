#!/usr/bin/env python3
"""Photograph a QEMU guest's screen at an interval, through QMP.

Usage: capture_screens.py <qmp-socket> <directory> [interval-seconds]

Runs until it is killed. Each picture is a PNG named after the time it was
taken, so the last ones show where a build that stopped making progress got
stuck. Before QEMU starts, and after it exits, there is no socket to talk to;
those attempts are skipped.
"""

import json
import socket
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


class Monitor:
    """A QMP monitor, connected afresh for each command."""

    def __init__(self, path):
        self.path = path

    def execute(self, command, arguments=None):
        with socket.socket(socket.AF_UNIX) as connection:
            connection.settimeout(10)
            connection.connect(self.path)
            stream = connection.makefile("rw")
            stream.readline()  # the greeting
            self._send(stream, "qmp_capabilities")
            return self._send(stream, command, arguments)

    def _send(self, stream, command, arguments=None):
        message = {"execute": command}
        if arguments:
            message["arguments"] = arguments
        stream.write(json.dumps(message) + "\n")
        stream.flush()
        return self._reply(stream)

    def _reply(self, stream):
        while True:
            reply = json.loads(stream.readline())
            if "return" in reply or "error" in reply:
                return reply


class Camera:
    """Saves the guest's screen into a directory, one PNG per picture."""

    def __init__(self, monitor, directory):
        self.monitor = monitor
        self.directory = directory

    def photograph(self):
        name = datetime.now(timezone.utc).strftime("%H%M%S") + ".png"
        path = (self.directory / name).resolve()
        arguments = {"filename": str(path), "format": "png"}
        self.monitor.execute("screendump", arguments)


def main(socket_path, directory, interval="60"):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    camera = Camera(Monitor(socket_path), directory)

    while True:
        try:
            camera.photograph()
        except (OSError, ValueError):
            pass
        time.sleep(int(interval))


if __name__ == "__main__":
    main(*sys.argv[1:])
