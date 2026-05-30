#!/usr/bin/env python3
"""Run repeatable Godot headless runtime smoke tests for the v1 build."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SMOKE_PASSWORD = "smoke-pass"
SMOKE_ENV = {
    **os.environ,
    "SHOOTER_DISABLE_NETWORK_SETTINGS": "1",
}


def godot_cmd(user_args: list[str], headless: bool = True) -> list[str]:
    godot_args = ["--headless"] if headless else []
    return ["./run.sh", *godot_args, "--", *user_args]


def output_has_runtime_problem(output: str) -> bool:
    markers = ("SCRIPT ERROR", "\nERROR:", "\nWARNING:")
    return any(marker in output for marker in markers)


def collect_process(name: str, proc: subprocess.Popen[str], timeout_sec: float) -> bool:
    try:
        output, _ = proc.communicate(timeout=timeout_sec)
    except subprocess.TimeoutExpired:
        proc.kill()
        output, _ = proc.communicate()
        print(f"===== {name} TIMEOUT =====")
        print(output)
        return False

    print(f"===== {name} exit={proc.returncode} =====")
    print(output)
    return proc.returncode == 0 and "SMOKE_PASS" in output and not output_has_runtime_problem(output)


def run_single(name: str, user_args: list[str], timeout_sec: float, headless: bool = True) -> bool:
    proc = subprocess.Popen(
        godot_cmd(user_args, headless),
        cwd=ROOT,
        env=SMOKE_ENV,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    return collect_process(name, proc, timeout_sec)


def run_group(name: str, port: int, expected_clients: int, lobby: bool, timeout_sec: float) -> bool:
    if lobby:
        host_args = [
            "--smoke-test=lobby-host",
            f"--smoke-expected-peers={expected_clients}",
            f"--smoke-port={port}",
            f"--smoke-timeout-sec={int(timeout_sec)}",
        ]
        client_base = [
            "--smoke-test=lobby-client",
            "--smoke-host=127.0.0.1",
            f"--smoke-port={port}",
            f"--smoke-timeout-sec={int(timeout_sec)}",
        ]
    else:
        host_args = [
            "--host",
            f"--port={port}",
            f"--password={SMOKE_PASSWORD}",
            "--smoke-test=network-game",
            f"--smoke-expected-peers={expected_clients}",
            f"--smoke-timeout-sec={int(timeout_sec)}",
        ]
        client_base = [
            "--join=127.0.0.1",
            f"--port={port}",
            f"--password={SMOKE_PASSWORD}",
            "--smoke-test=network-game",
            f"--smoke-timeout-sec={int(timeout_sec)}",
        ]

    procs: list[tuple[str, subprocess.Popen[str]]] = []
    host = subprocess.Popen(
        godot_cmd(host_args),
        cwd=ROOT,
        env=SMOKE_ENV,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    procs.append((f"{name}-host", host))
    time.sleep(1.0)

    for index in range(expected_clients):
        client = subprocess.Popen(
            godot_cmd(client_base),
            cwd=ROOT,
            env=SMOKE_ENV,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        procs.append((f"{name}-client-{index + 1}", client))
        time.sleep(0.3)

    ok = True
    for proc_name, proc in procs:
        ok = collect_process(proc_name, proc, timeout_sec + 8.0) and ok

    for _, proc in procs:
        if proc.poll() is None:
            proc.kill()

    return ok


def run_lan_discovery(port: int, timeout_sec: float) -> bool:
    procs: list[tuple[str, subprocess.Popen[str]]] = []
    host = subprocess.Popen(
        godot_cmd([
            "--smoke-test=lan-discovery-host",
            "--smoke-expected-peers=1",
            f"--smoke-port={port}",
            f"--smoke-timeout-sec={int(timeout_sec)}",
        ]),
        cwd=ROOT,
        env=SMOKE_ENV,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    procs.append(("lan-discovery-host", host))
    time.sleep(1.0)

    client = subprocess.Popen(
        godot_cmd([
            "--smoke-test=lan-discovery-client",
            f"--smoke-timeout-sec={int(timeout_sec)}",
        ]),
        cwd=ROOT,
        env=SMOKE_ENV,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    procs.append(("lan-discovery-client", client))

    ok = True
    for proc_name, proc in procs:
        ok = collect_process(proc_name, proc, timeout_sec + 8.0) and ok

    for _, proc in procs:
        if proc.poll() is None:
            proc.kill()

    return ok


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "suite",
        nargs="?",
        default="all",
        choices=("all", "offline", "weapons", "network", "lobby", "lan-discovery", "lobby-validation", "2v2", "3v3"),
    )
    parser.add_argument("--base-port", type=int, default=24610)
    args = parser.parse_args()

    suites = [args.suite] if args.suite != "all" else [
        "offline",
        "weapons",
        "network",
        "lobby",
        "lan-discovery",
        "lobby-validation",
        "2v2",
        "3v3",
    ]
    ok = True
    for suite in suites:
        if suite == "offline":
            ok = run_single("offline", ["--smoke-test=offline", "--smoke-timeout-sec=30"], 40.0, headless=False) and ok
        elif suite == "weapons":
            ok = run_single("weapons", ["--smoke-test=weapons", "--smoke-timeout-sec=45"], 60.0) and ok
        elif suite == "network":
            ok = run_group("network", args.base_port + 1, 1, False, 14.0) and ok
        elif suite == "lobby":
            ok = run_group("lobby", args.base_port + 2, 1, True, 16.0) and ok
        elif suite == "lan-discovery":
            ok = run_lan_discovery(args.base_port + 5, 24.0) and ok
        elif suite == "lobby-validation":
            ok = run_single(
                "lobby-validation",
                ["--smoke-test=lobby-validation", "--smoke-timeout-sec=4"],
                8.0,
            ) and ok
        elif suite == "2v2":
            ok = run_group("2v2", args.base_port + 3, 3, False, 24.0) and ok
        elif suite == "3v3":
            ok = run_group("3v3", args.base_port + 4, 5, False, 32.0) and ok

    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
