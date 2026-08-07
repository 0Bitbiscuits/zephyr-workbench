import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

ZEPHYR_DIR = Path(__file__).parent.resolve()
WS_DIR = ZEPHYR_DIR.parent
WEST = [sys.executable, "-m", "west"]
SDK_DIR = Path(r"C:\Workspace\4-Plugin\zephyr-sdk")
DEFAULT_BOARD = "qemu_cortex_m3"
DEFAULT_APP = "samples/hello_world"


def _run(cmd, cwd=None, env=None, capture=False):
    print(f"\n$ {' '.join(str(c) for c in cmd)}")
    return subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        env=env,
        check=False,
        capture_output=capture,
        text=True,
    )


def _sanitize(name):
    return re.sub(r"[^A-Za-z0-9_.-]+", "-", name).strip("-") or "target"


def _resolve_repo_path(path_text, kind):
    path = Path(path_text)
    if not path.is_absolute():
        path = ZEPHYR_DIR / path
    path = path.resolve()
    if not path.exists():
        raise FileNotFoundError(f"{kind} path not found: {path}")
    return path


def _to_west_arg(path):
    try:
        return path.relative_to(ZEPHYR_DIR).as_posix()
    except ValueError:
        return str(path)


def _default_build_dir(board, app_path):
    return ZEPHYR_DIR / f"build-{_sanitize(board)}-{_sanitize(app_path.name)}"


def _default_twister_out(board, test_path):
    return ZEPHYR_DIR / f"twister-out-{_sanitize(board)}-{_sanitize(test_path.name)}"


def _dedupe(items):
    unique = []
    for item in items:
        if item and item not in unique:
            unique.append(item)
    return unique


def _infer_update_projects(board, app_path=None, test_path=None):
    projects = []
    board_name = board.lower()

    if "cortex_m" in board_name or board_name.startswith("qemu_cortex_"):
        projects.append("cmsis")

    text = " ".join(
        str(item).lower() for item in (app_path, test_path) if item is not None
    )
    if "mbedtls" in text or "tls" in text:
        projects.append("mbedtls")
    if "mcuboot" in text:
        projects.append("mcuboot")
    if "openthread" in text or "thread" in text:
        projects.append("openthread")

    return projects


def _parse_args():
    parser = argparse.ArgumentParser(
        description="Initialize a Zephyr workspace, sync required modules, "
                    "build an app, and optionally run a Twister test."
    )
    parser.add_argument("--board", default=DEFAULT_BOARD,
                        help="Board to build or test on.")
    parser.add_argument("--app", default=DEFAULT_APP,
                        help="Application path for west build.")
    parser.add_argument("--build-dir",
                        help="Build directory for the app stage.")
    parser.add_argument("--update", choices=("none", "minimal", "all"),
                        default="minimal",
                        help="Module sync mode before build/test.")
    parser.add_argument("--update-project", action="append", default=[],
                        help="Extra west projects to update in minimal mode.")
    parser.add_argument("--no-run", action="store_true",
                        help="Build the app but do not run it.")
    parser.add_argument("--test-path",
                        help="Optional Twister test or sample path.")
    parser.add_argument("--test-name",
                        help="Optional Twister testcase id passed to -s.")
    parser.add_argument("--test-platform",
                        help="Twister platform. Defaults to --board.")
    parser.add_argument("--twister-out",
                        help="Output directory for the Twister stage.")
    parser.add_argument("--twister-arg", action="append", default=[],
                        help="Extra argument forwarded to Twister.")
    parser.add_argument("--test-only", action="store_true",
                        help="Skip app build/run and execute only the test stage.")
    return parser.parse_args()


def _ensure_west():
    result = _run(WEST + ["--version"], capture=True)
    if result.returncode != 0:
        print("ERROR: west not importable from current Python interpreter.",
              file=sys.stderr)
        print("Expected: zephyr-dev conda env with requirements-base.txt "
              "installed.", file=sys.stderr)
        if result.stderr:
            print(result.stderr, file=sys.stderr)
        return result.returncode

    print(result.stdout.strip())
    return 0


def _ensure_workspace():
    west_dir = WS_DIR / ".west"
    if not west_dir.exists():
        print(f"\n==> [1/5] Initializing west workspace in {WS_DIR}")
        result = _run(WEST + ["init", "-l", str(ZEPHYR_DIR)], cwd=WS_DIR)
        return result.returncode

    print(f"\n==> [1/5] west workspace already exists in {WS_DIR}")
    return 0


def _ensure_sdk():
    if SDK_DIR.exists():
        os.environ["ZEPHYR_SDK_INSTALL_DIR"] = str(SDK_DIR)
        print(f"\n==> [2/5] ZEPHYR_SDK_INSTALL_DIR = {SDK_DIR}")
    else:
        print(f"\nWARNING ==> [2/5] Zephyr SDK not found at {SDK_DIR}; "
              "toolchain / compile phases may fail.")
    return 0


def _sync_modules(args, app_path, test_path):
    if args.update == "none":
        print("\n==> [3/5] Skipping west update")
        return 0

    if args.update == "all":
        print("\n==> [3/5] Updating all active west projects with narrow fetch")
        result = _run(WEST + ["update", "-n"], cwd=ZEPHYR_DIR)
        return result.returncode

    projects = _dedupe(
        _infer_update_projects(args.board, app_path, test_path) +
        args.update_project
    )
    if not projects:
        print("\n==> [3/5] No inferred module update required")
        return 0

    print(f"\n==> [3/5] Updating required west projects: {', '.join(projects)}")
    result = _run(WEST + ["update", "-n"] + projects, cwd=ZEPHYR_DIR)
    return result.returncode


def _build_and_run_app(args, app_path, build_dir):
    print(f"\n==> [4/5] Building {_to_west_arg(app_path)} for {args.board}")
    result = _run(
        WEST + ["build", "-p", "always", "-b", args.board,
                _to_west_arg(app_path), "-d", str(build_dir)],
        cwd=ZEPHYR_DIR,
    )
    if result.returncode != 0 or args.no_run:
        return result.returncode

    print(f"\n==> [5/5] Running app from {build_dir}...")
    result = _run(WEST + ["build", "-d", str(build_dir), "-t", "run"],
                  cwd=ZEPHYR_DIR)
    return result.returncode


def _run_twister(args, test_path):
    platform = args.test_platform or args.board
    outdir = Path(args.twister_out) if args.twister_out else \
        _default_twister_out(platform, test_path)
    cmd = [
        sys.executable,
        str(ZEPHYR_DIR / "scripts" / "twister"),
        "-T",
        _to_west_arg(test_path),
        "-p",
        platform,
        "--outdir",
        str(outdir),
    ]
    if args.test_name:
        cmd += ["-s", args.test_name]
    cmd += args.twister_arg

    print(f"\n==> Running Twister for {_to_west_arg(test_path)} on {platform}")
    result = _run(cmd, cwd=ZEPHYR_DIR)
    return result.returncode


def main():
    args = _parse_args()
    if args.test_only and not args.test_path:
        print("ERROR: --test-only requires --test-path.", file=sys.stderr)
        return 1

    app_path = None if args.test_only else _resolve_repo_path(args.app, "app")
    test_path = _resolve_repo_path(args.test_path, "test") if args.test_path else None
    build_dir = Path(args.build_dir).resolve() if args.build_dir else (
        _default_build_dir(args.board, app_path) if app_path else None
    )

    for step in (_ensure_west, _ensure_workspace, _ensure_sdk):
        result = step()
        if result != 0:
            return result

    result = _sync_modules(args, app_path, test_path)
    if result != 0:
        return result

    if app_path is not None:
        result = _build_and_run_app(args, app_path, build_dir)
        if result != 0:
            return result

    if test_path is not None:
        result = _run_twister(args, test_path)
        if result != 0:
            return result

    return 0


if __name__ == "__main__":
    sys.exit(main())
