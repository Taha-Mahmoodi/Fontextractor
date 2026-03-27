from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable

import psutil


@dataclass
class ProcessTreeResult:
    attempted: int
    succeeded: int
    failed: int


def _collect_tree(root_pid: int) -> list[psutil.Process]:
    root = psutil.Process(root_pid)
    descendants = root.children(recursive=True)
    return [root, *descendants]


def _iter_unique_processes(processes: Iterable[psutil.Process]) -> list[psutil.Process]:
    seen: set[int] = set()
    ordered: list[psutil.Process] = []
    for process in processes:
        if process.pid in seen:
            continue
        seen.add(process.pid)
        ordered.append(process)
    return ordered


def suspend_process_tree(root_pid: int) -> ProcessTreeResult:
    processes = _iter_unique_processes(_collect_tree(root_pid))
    attempted = len(processes)
    succeeded = 0
    failed = 0
    for process in reversed(processes):
        try:
            process.suspend()
            succeeded += 1
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            failed += 1
    return ProcessTreeResult(attempted=attempted, succeeded=succeeded, failed=failed)


def resume_process_tree(root_pid: int) -> ProcessTreeResult:
    processes = _iter_unique_processes(_collect_tree(root_pid))
    attempted = len(processes)
    succeeded = 0
    failed = 0
    for process in processes:
        try:
            process.resume()
            succeeded += 1
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            failed += 1
    return ProcessTreeResult(attempted=attempted, succeeded=succeeded, failed=failed)


def terminate_process_tree(root_pid: int, timeout_seconds: float = 5.0) -> ProcessTreeResult:
    processes = _iter_unique_processes(_collect_tree(root_pid))
    attempted = len(processes)
    succeeded = 0
    failed = 0

    for process in reversed(processes):
        try:
            process.terminate()
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            failed += 1

    alive = psutil.wait_procs(processes, timeout=timeout_seconds)[1]
    for process in alive:
        try:
            process.kill()
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            failed += 1

    for process in processes:
        if not process.is_running():
            succeeded += 1

    return ProcessTreeResult(attempted=attempted, succeeded=succeeded, failed=failed)
