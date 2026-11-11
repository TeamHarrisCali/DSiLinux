#!/usr/bin/env python3
"""Read the DSLinux kernel log buffer out of a running melonDS through its GDB stub (ARM9, default port 3333).
Usage: klog.py <log_buf_addr> <log_end_addr> [port]   (addresses from `arm-linux-elf-nm linux`: __log_buf, log_end)
The emulation is paused while attached and resumed ('c') afterwards."""
import socket, sys, time

def pkt(s):
    return b"$" + s + b"#" + b"%02x" % (sum(s) & 0xFF)

def rd(sock):
    buf = b""
    while True:
        c = sock.recv(1)
        if not c:
            raise EOFError
        if c == b"$":
            buf = b""
            while True:
                c = sock.recv(1)
                if c == b"#":
                    sock.recv(2)
                    sock.sendall(b"+")
                    return buf
                buf += c

def cmd(sock, s):
    sock.sendall(pkt(s))
    while True:
        c = sock.recv(1)
        if c == b"+":
            break
        if not c:
            raise EOFError
    return rd(sock)

def readmem(sock, addr, n):
    out = b""
    while n > 0:
        k = min(n, 1024)
        r = cmd(sock, b"m%x,%x" % (addr, k))
        out += bytes.fromhex(r.decode())
        addr += k
        n -= k
    return out

def main():
    buf_addr, end_addr = int(sys.argv[1], 16), int(sys.argv[2], 16)
    port = int(sys.argv[3]) if len(sys.argv) > 3 else 3333
    sock = socket.create_connection(("127.0.0.1", port), timeout=20)
    time.sleep(0.3)
    try:
        end = int.from_bytes(readmem(sock, end_addr, 4), "little")
        size = 1 << 14
        data = readmem(sock, buf_addr, size)
        text = data[:end] if end <= size else data[end % size:] + data[:end % size]
        sys.stdout.write(text.decode("latin-1"))
    finally:
        try:
            sock.sendall(pkt(b"c"))
        except OSError:
            pass
        sock.close()

main()
