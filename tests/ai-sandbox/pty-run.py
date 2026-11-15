"""Runs a command with a pseudo-terminal for its standard streams, for the tests of the
confirmation question (U12): the command is a session leader whose controlling terminal is the
pseudo-terminal, so it is in the terminal's foreground group unless --background says otherwise.

  pty-run.py [--stdin tty|pipe] [--stderr tty|pipe] [--answer TEXT] [--interrupt]
             [--background] [--timeout S] -- command [argument...]

What the terminal showed goes to standard output with the line ends left alone; with --stderr
pipe, what the command wrote to standard error goes to this program's standard error. --answer (a line) is
sent after the question mark "[y/N] " appears (with --stdin pipe it is the pipe's whole content,
sent at once); --interrupt sends ^C instead. The exit status is the command's, 124 on the timeout."""
import argparse
import fcntl
import os
import select
import signal
import sys
import termios
import time

ap = argparse.ArgumentParser()
ap.add_argument("--stdin", choices=("tty", "pipe"), default="tty")
ap.add_argument("--stderr", choices=("tty", "pipe"), default="tty")
ap.add_argument("--answer")
ap.add_argument("--interrupt", action="store_true")
ap.add_argument("--background", action="store_true")
ap.add_argument("--timeout", type=float, default=120)
ap.add_argument("command", nargs=argparse.REMAINDER)
a = ap.parse_args()
cmd = a.command[1:] if a.command[:1] == ["--"] else a.command

master, slave = os.openpty()
attrs = termios.tcgetattr(slave)
attrs[1] &= ~termios.OPOST      # no CR before every newline
attrs[3] &= ~termios.ECHO       # the answer is not echoed into the transcript
termios.tcsetattr(slave, termios.TCSANOW, attrs)
in_r = in_w = err_r = err_w = None
if a.stdin == "pipe":
    in_r, in_w = os.pipe()
if a.stderr == "pipe":
    err_r, err_w = os.pipe()

pid = os.fork()
if pid == 0:
    os.setsid()
    fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
    os.dup2(in_r if in_r is not None else slave, 0)
    os.dup2(slave, 1)
    os.dup2(err_w if err_w is not None else slave, 2)
    for fd in {master, slave, in_r, in_w, err_r, err_w} - {None}:
        if fd > 2:
            os.close(fd)
    if a.background:
        # a second process group of the same session: not the terminal's foreground group
        g = os.fork()
        if g == 0:
            os.setpgid(0, 0)
            os.execvp(cmd[0], cmd)
        _, st = os.waitpid(g, 0)
        os._exit(os.waitstatus_to_exitcode(st))
    os.execvp(cmd[0], cmd)

os.close(slave)
if in_r is not None:
    os.close(in_r)
    if a.answer is not None:
        os.write(in_w, (a.answer + "\n").encode())
    os.close(in_w)
if err_w is not None:
    os.close(err_w)

seen = b""
sent = False
deadline = time.time() + a.timeout
status = None
rd = [master] + ([err_r] if err_r is not None else [])
out = sys.stdout.buffer
while rd:
    left = deadline - time.time()
    if left <= 0:
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass
        status = 124
        break
    ready, _, _ = select.select(rd, [], [], min(left, 0.2))
    for fd in ready:
        try:
            data = os.read(fd, 65536)
        except OSError:
            data = b""
        if not data:
            rd.remove(fd)
            continue
        if fd == master:
            out.write(data)
            out.flush()
        else:
            sys.stderr.buffer.write(data)
            sys.stderr.buffer.flush()
        seen += data
        if not sent and b"[y/N] " in seen:
            if a.interrupt:
                os.write(master, b"\x03")
                sent = True
            elif a.answer is not None and a.stdin == "tty":
                os.write(master, (a.answer + "\n").encode())
                sent = True
if status is None:
    _, st = os.waitpid(pid, 0)
    status = os.waitstatus_to_exitcode(st)
    if status < 0:
        status = 128 - status
sys.exit(status)
