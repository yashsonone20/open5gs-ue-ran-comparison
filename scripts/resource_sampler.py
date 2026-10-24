#!/usr/bin/env python3
"""Sample CPU % and RAM of the 5G processes once per second into a CSV.

Tracks Open5GS NFs (open5gs-*), UERANSIM (nr-gnb, nr-ue), srsRAN / OAI binaries
if present, and mongod, plus whole-system CPU and memory.

Usage:  python3 resource_sampler.py out.csv [duration_seconds]
        (no duration = run until Ctrl+C / SIGTERM)
Needs:  pip install psutil   (or: sudo apt install python3-psutil)
"""
import csv, signal, sys, time

try:
    import psutil
except ImportError:
    sys.exit("psutil missing: sudo apt install -y python3-psutil")

PATTERNS = ("open5gs-", "nr-gnb", "nr-ue", "gnb", "srsue", "nr-softmodem", "nr-uesoftmodem", "free-ran-ue", "mongod")

def wanted(name: str) -> bool:
    return any(name.startswith(p) for p in PATTERNS)

def label(p):
    """Process name, except free-ran-ue (one binary for both roles) gets its role appended."""
    name = p.name()
    if name == "free-ran-ue":
        try:
            args = p.cmdline()
            role = "gnb" if "gnb" in args else "ue" if "ue" in args else "other"
        except psutil.Error:
            role = "other"
        return f"free-ran-ue-{role}"
    return name

def root_of(p):
    """Topmost ancestor with the same program name. OAI forks a child process, so
    parent + child = one program instance; they share one root_pid."""
    root = p
    try:
        while True:
            par = root.parent()
            if par is None or par.name() != p.name():
                return root.pid
            root = par
    except psutil.Error:
        return root.pid

def main():
    out = sys.argv[1]
    duration = float(sys.argv[2]) if len(sys.argv) > 2 else None
    stop = False
    def handler(*_):
        nonlocal stop
        stop = True
    signal.signal(signal.SIGTERM, handler)
    signal.signal(signal.SIGINT, handler)

    procs = {}
    psutil.cpu_percent(None)
    t0 = time.time()
    with open(out, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["t_s", "process", "pid", "root_pid", "cpu_percent", "rss_mb"])
        while not stop and (duration is None or time.time() - t0 < duration):
            # pick up new processes (UEs start and stop during tests)
            for p in psutil.process_iter(["name"]):
                if p.info["name"] and wanted(p.info["name"]) and p.pid not in procs:
                    try:
                        p.cpu_percent(None)  # first call primes the counter
                        procs[p.pid] = (p, root_of(p), label(p))
                    except psutil.Error:
                        pass
            time.sleep(1.0)
            t = round(time.time() - t0, 2)
            for pid, (p, root, name) in list(procs.items()):
                try:
                    w.writerow([t, name, pid, root, p.cpu_percent(None),
                                round(p.memory_info().rss / 2**20, 2)])
                except psutil.Error:
                    procs.pop(pid)
            vm = psutil.virtual_memory()
            w.writerow([t, "SYSTEM", 0, 0, psutil.cpu_percent(None),
                        round((vm.total - vm.available) / 2**20, 2)])
            fh.flush()

if __name__ == "__main__":
    main()
