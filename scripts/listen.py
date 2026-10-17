#!/usr/bin/env python3
# Copyright 2026 The obeam Authors. All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.

"""listen.py prints what a P2 board sends over its serial line, at 230400
baud, for some seconds, without a loader: how a program the board booted by
itself, from an SD card or from its flash, is watched. With -r it resets the
board first by its DTR line, as a loader does, and with -t it says when each
piece arrived, in seconds from the start.

Usage: scripts/listen.py [-r] [-t] PORT SECONDS

Run it under the shared board lock, as every use of the port is:

    flock -o -w 900 /tmp/p2-board.lock scripts/listen.py -r /dev/ttyUSB0 15
"""

import fcntl
import os
import select
import struct
import sys
import termios
import time


def main():
    args = sys.argv[1:]
    reset = "-r" in args
    stamp = "-t" in args
    args = [a for a in args if a not in ("-r", "-t")]
    if len(args) != 2:
        sys.exit("usage: listen.py [-r] [-t] PORT SECONDS")
    port, secs = args[0], float(args[1])
    fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    attrs = termios.tcgetattr(fd)
    attrs[0] = attrs[1] = attrs[3] = 0
    attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
    attrs[4] = attrs[5] = termios.B230400
    attrs[6][termios.VMIN] = attrs[6][termios.VTIME] = 0
    termios.tcsetattr(fd, termios.TCSANOW, attrs)
    if reset:
        dtr = struct.pack("I", termios.TIOCM_DTR)
        fcntl.ioctl(fd, termios.TIOCMBIS, dtr)
        time.sleep(0.05)
        fcntl.ioctl(fd, termios.TIOCMBIC, dtr)
        time.sleep(0.05)
        fcntl.ioctl(fd, termios.TIOCMBIS, dtr)
        termios.tcflush(fd, termios.TCIFLUSH)
    start = time.time()
    out = sys.stdout.buffer
    while time.time() - start < secs:
        ready, _, _ = select.select([fd], [], [], 0.2)
        if not ready:
            continue
        try:
            b = os.read(fd, 4096)
        except BlockingIOError:
            continue
        if stamp:
            out.write(b"%.2f " % (time.time() - start))
        out.write(b)
        out.flush()
    os.close(fd)


if __name__ == "__main__":
    main()
