"""Credential-free, one-program scratch runner. Isolation is enforced by the host."""
import argparse
import json
import os
from pathlib import Path
import resource
import signal
import stat
import subprocess
import sys
import time

parser = argparse.ArgumentParser(add_help=False)
parser.add_argument("--scratch", default="/workspace")
parser.add_argument("--max-bytes", type=int, default=2 * 1024**3)
parser.add_argument("--max-file-bytes", type=int, default=64 * 1024**2)
options, arguments = parser.parse_known_args()
sys.argv[1:] = arguments
ROOT = Path(options.scratch).resolve()
MAX_BYTES = options.max_bytes
MAX_FILES = 100
MAX_FILE_BYTES = options.max_file_bytes
if MAX_BYTES <= 0 or MAX_FILE_BYTES <= 0:
    raise ValueError("Scratch and file budgets must be positive")


def safe_path(name):
    path = ROOT / name
    if not name or Path(name).is_absolute() or ".." in Path(name).parts:
        raise ValueError("Invalid scratch path")
    if path.is_symlink() or not path.resolve().is_relative_to(ROOT):
        raise ValueError("Scratch symlinks are not supported")
    return path


def emit(value):
    print(json.dumps(value), flush=True)


def limits():
    os.setsid()
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    resource.setrlimit(resource.RLIMIT_NOFILE, (256, 256))
    resource.setrlimit(resource.RLIMIT_NPROC, (64, 64))
    resource.setrlimit(resource.RLIMIT_FSIZE, (MAX_BYTES, MAX_BYTES))


def execute():
    control = ROOT / ".control"
    # Exec may be retried after a transport failure. Never launch twice.
    try:
        lock = os.open(control / "executing", os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        os.close(lock)
    except FileExistsError:
        return
    spec = json.loads((control / "request.json").read_text())
    timeout = min(300, max(1, int(spec.get("timeoutSeconds", 300))))
    environment = {
        "PATH": os.environ.get("PATH", "/usr/local/bin:/usr/bin:/bin"),
        "HOME": str(ROOT), "TMPDIR": str(ROOT / "tmp"),
        "MPLCONFIGDIR": str(ROOT / ".matplotlib"),
        "PYTHONUNBUFFERED": "1", "PYTHONDONTWRITEBYTECODE": "1",
        "OPENBLAS_NUM_THREADS": "1", "OMP_NUM_THREADS": "1",
    }
    (ROOT / "tmp").mkdir(exist_ok=True)
    (ROOT / "outputs").mkdir(exist_ok=True)
    with (control / "stdout").open("wb") as out, (control / "stderr").open("wb") as err:
        process = subprocess.Popen([sys.executable, str(control / "program.py")],
                                   cwd=ROOT, env=environment, stdout=out, stderr=err,
                                   preexec_fn=limits)
        timed_out = False
        try:
            process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
        finally:
            # Also kill detached children when the main program exits normally.
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
    result = {"state": "finished", "exitCode": process.returncode, "timedOut": timed_out}
    temporary = control / "result.tmp"
    temporary.write_text(json.dumps(result))
    temporary.replace(control / "result.json")


def main():
    ROOT.mkdir(parents=True, exist_ok=True)
    command = sys.argv[1]
    if command == "put":
        path = safe_path(sys.argv[2])
        path.parent.mkdir(parents=True, exist_ok=True)
        total = 0
        with path.open("wb") as target:
            while chunk := sys.stdin.buffer.read(65536):
                total += len(chunk)
                if total > MAX_BYTES:
                    raise ValueError("Scratch input exceeds the configured storage budget")
                target.write(chunk)
        emit({"bytes": total})
    elif command == "get":
        path = safe_path(sys.argv[2])
        if not stat.S_ISREG(path.stat().st_mode) or path.stat().st_size > MAX_BYTES:
            raise ValueError("Invalid output file")
        with path.open("rb") as source:
            while chunk := source.read(65536):
                sys.stdout.buffer.write(chunk)
    elif command == "status":
        result = ROOT / ".control/result.json"
        emit(json.loads(result.read_text()) if result.exists() else {"state": "running" if (ROOT / ".control/executing").exists() or (ROOT / ".control/start").exists() else "pending"})
    elif command == "outputs":
        files = []
        total = 0
        for path in sorted((ROOT / "outputs").rglob("*")):
            path = safe_path(str(path.relative_to(ROOT)))
            if path.is_dir():
                continue
            if not stat.S_ISREG(path.stat().st_mode):
                raise ValueError("Only regular output files are supported")
            total += path.stat().st_size
            files.append({"path": str(path.relative_to(ROOT)), "sizeBytes": path.stat().st_size})
            if len(files) > MAX_FILES or total > MAX_BYTES or path.stat().st_size > MAX_FILE_BYTES:
                raise ValueError("Generated outputs exceed the configured budget")
        emit(files)
    elif command == "logs":
        logs = {}
        for name in ("stdout", "stderr"):
            path = ROOT / ".control" / name
            with path.open("rb") as source:
                data = source.read(32769)
            logs[name] = data[:32768].decode("utf8", errors="replace")
            logs[name + "Truncated"] = len(data) > 32768
        emit(logs)
    elif command == "execute":
        execute()
    elif command == "serve":
        deadline = time.monotonic() + 600
        while not (ROOT / ".control/start").exists():
            if time.monotonic() >= deadline:
                raise TimeoutError("Sandbox was not initialized")
            time.sleep(0.2)
        execute()
        # Collection is explicit; the job deadline bounds an abandoned runner.
        while time.monotonic() < deadline:
            time.sleep(1)
    else:
        raise ValueError("Unknown runner command")


if __name__ == "__main__":
    main()
