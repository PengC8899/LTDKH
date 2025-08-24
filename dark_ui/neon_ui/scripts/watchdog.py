#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
本脚本提供一个本地进程守护机制：
- 持续拉起并监控 `main.py`；
- 健康检查失败或进程退出后自动重启（带指数回退）；
- 单实例 PID 锁；
- 将子进程 stdout/stderr 写入日志并进行简单滚动；
- 优雅退出（SIGTERM/SIGINT）。

使用示例：
  python3 scripts/watchdog.py
或自定义命令：
  python3 scripts/watchdog.py --command "python3 -m uvicorn main:app --host 0.0.0.0 --port 8001" --health-url http://127.0.0.1:8001/health
"""

from __future__ import annotations

import argparse
import os
import shlex
import signal
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import List, Optional

import json
import urllib.request
import urllib.error


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CMD: List[str] = [sys.executable, str(PROJECT_ROOT / "main.py")]
LOG_DIR = PROJECT_ROOT / "data" / "logs"
PID_FILE = PROJECT_ROOT / "data" / "watchdog.pid"
CHILD_LOG_FILE = LOG_DIR / "app.out.log"
WATCHDOG_LOG_FILE = LOG_DIR / "watchdog.log"


def ensure_dirs() -> None:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    PID_FILE.parent.mkdir(parents=True, exist_ok=True)


def is_process_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except Exception:
        return False


def write_pidfile(pidfile: Path) -> None:
    if pidfile.exists():
        try:
            old = int(pidfile.read_text().strip() or "0")
        except Exception:
            old = 0
        if old > 0 and is_process_alive(old):
            print(f"检测到已有守护进程在运行（PID={old}），本次退出。", file=sys.stderr)
            sys.exit(1)
    pidfile.write_text(str(os.getpid()))


def remove_pidfile(pidfile: Path) -> None:
    try:
        if pidfile.exists():
            pidfile.unlink()
    except Exception:
        pass


def rotate_file_if_oversize(file_path: Path, max_bytes: int = 20 * 1024 * 1024, backups: int = 5) -> None:
    try:
        if not file_path.exists():
            return
        if file_path.stat().st_size < max_bytes:
            return
        # 从旧到新滚动：.4 -> .5，.3 -> .4 ...
        for i in range(backups, 0, -1):
            older = file_path.with_suffix(file_path.suffix + f".{i}")
            if older.exists():
                if i == backups:
                    older.unlink(missing_ok=True)  # type: ignore[arg-type]
                else:
                    newer = file_path.with_suffix(file_path.suffix + f".{i+1}")
                    older.rename(newer)
        # 当前文件 -> .1
        file_path.rename(file_path.with_suffix(file_path.suffix + ".1"))
    except Exception as e:
        print(f"日志滚动失败：{e}", file=sys.stderr)


def now_str() -> str:
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


class GracefulExit(Exception):
    pass


class Watchdog:
    def __init__(
        self,
        command: List[str],
        health_url: Optional[str] = None,
        health_startup_timeout: int = 60,
        health_interval: int = 5,
        restart_backoff_initial: int = 1,
        restart_backoff_max: int = 60,
        child_env: Optional[dict] = None,
    ) -> None:
        self.command = command
        self.health_url = health_url
        self.health_startup_timeout = health_startup_timeout
        self.health_interval = health_interval
        self.restart_backoff_initial = restart_backoff_initial
        self.restart_backoff_max = restart_backoff_max
        self.child_env = child_env or os.environ.copy()
        self.stop_requested = False
        self.child: Optional[subprocess.Popen] = None
        self.current_backoff = restart_backoff_initial

    def _log(self, message: str) -> None:
        line = f"[{now_str()}] {message}\n"
        sys.stdout.write(line)
        sys.stdout.flush()
        try:
            with WATCHDOG_LOG_FILE.open("a", encoding="utf-8") as f:
                f.write(line)
        except Exception:
            pass

    def _open_child_logs(self):
        rotate_file_if_oversize(CHILD_LOG_FILE)
        stdout = CHILD_LOG_FILE.open("ab", buffering=0)
        stderr = stdout  # 合并到同一个文件
        return stdout, stderr

    def _spawn_child(self) -> subprocess.Popen:
        stdout, stderr = self._open_child_logs()
        self._log(f"启动子进程：{' '.join(self.command)}")
        p = subprocess.Popen(
            self.command,
            cwd=str(PROJECT_ROOT),
            stdout=stdout,
            stderr=stderr,
            stdin=subprocess.DEVNULL,
            preexec_fn=os.setsid if hasattr(os, "setsid") else None,
            env=self.child_env,
            close_fds=True,
            text=False,
        )
        return p

    def _terminate_child(self, timeout: int = 15) -> None:
        if not self.child:
            return
        try:
            if self.child.poll() is None:
                self._log("发送 SIGTERM 以优雅停止子进程…")
                try:
                    os.killpg(self.child.pid, signal.SIGTERM)
                except Exception:
                    self.child.terminate()
                # 等待
                t0 = time.time()
                while time.time() - t0 < timeout:
                    if self.child.poll() is not None:
                        break
                    time.sleep(0.2)
            if self.child.poll() is None:
                self._log("子进程未在超时内退出，发送 SIGKILL…")
                try:
                    os.killpg(self.child.pid, signal.SIGKILL)
                except Exception:
                    self.child.kill()
        except Exception as e:
            self._log(f"停止子进程异常：{e}")

    def _health_ok(self) -> bool:
        if not self.health_url:
            # 未配置健康检查时，仅以进程存活作为判断
            return bool(self.child and self.child.poll() is None)
        try:
            req = urllib.request.Request(self.health_url, method="GET")
            with urllib.request.urlopen(req, timeout=5) as resp:
                if resp.status != 200:
                    return False
                try:
                    data = json.loads(resp.read().decode("utf-8"))
                    return data.get("status") == "ok"
                except Exception:
                    return True  # 200 即认为健康
        except urllib.error.URLError:
            return False
        except Exception:
            return False

    def _wait_until_healthy(self) -> bool:
        t0 = time.time()
        while time.time() - t0 < self.health_startup_timeout:
            if self.stop_requested:
                return False
            if self.child and self.child.poll() is not None:
                # 进程已退出
                return False
            if self._health_ok():
                return True
            time.sleep(self.health_interval)
        return False

    def _reset_backoff(self) -> None:
        self.current_backoff = self.restart_backoff_initial

    def _increase_backoff(self) -> None:
        self.current_backoff = min(self.current_backoff * 2, self.restart_backoff_max)

    def run(self) -> int:
        def _signal_handler(signum, _frame):
            self._log(f"收到信号 {signum}，准备退出…")
            self.stop_requested = True
            self._terminate_child()

        signal.signal(signal.SIGINT, _signal_handler)
        signal.signal(signal.SIGTERM, _signal_handler)

        self._log("守护进程启动")

        while not self.stop_requested:
            # 启动子进程
            self.child = self._spawn_child()
            start_time = time.time()

            # 启动期健康检查
            if not self._wait_until_healthy():
                self._log("启动期健康检查失败，将重启子进程…")
                self._terminate_child()
            else:
                self._log("健康检查通过，进入运行期监控…")

            # 运行期：轮询健康检查
            while not self.stop_requested and self.child and self.child.poll() is None:
                if self.health_url:
                    if not self._health_ok():
                        self._log("运行期健康检查失败，准备重启…")
                        break
                time.sleep(self.health_interval)

            # 走到这里：要么 stop，要么子进程异常/不健康
            uptime = time.time() - start_time
            self._terminate_child()

            if self.stop_requested:
                break

            if uptime >= 600:  # 运行超过 10 分钟，视为稳定，重置回退
                self._reset_backoff()
            else:
                self._increase_backoff()

            self._log(f"将在 {self.current_backoff}s 后重启子进程…")
            for _ in range(self.current_backoff):
                if self.stop_requested:
                    break
                time.sleep(1)

        self._log("守护进程退出")
        return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="LTDKH_BOT 本地守护进程")
    parser.add_argument(
        "--command",
        type=str,
        default=" ".join(shlex.quote(p) for p in DEFAULT_CMD),
        help="要执行的命令（缺省为 python3 main.py）",
    )
    parser.add_argument(
        "--health-url",
        type=str,
        default="http://127.0.0.1:8000/health",
        help="健康检查地址（置空则仅检查进程存活）",
    )
    parser.add_argument("--startup-timeout", type=int, default=60, help="启动期健康检查超时（秒）")
    parser.add_argument("--interval", type=int, default=5, help="健康检查间隔（秒）")
    parser.add_argument("--backoff-initial", type=int, default=1, help="重启初始回退（秒）")
    parser.add_argument("--backoff-max", type=int, default=60, help="重启最大回退（秒）")
    return parser.parse_args()


def main() -> int:
    ensure_dirs()
    write_pidfile(PID_FILE)
    try:
        args = parse_args()
        cmd = shlex.split(args.command)
        health_url = args.health_url.strip() if args.health_url else None
        wd = Watchdog(
            command=cmd,
            health_url=health_url,
            health_startup_timeout=args.startup_timeout,
            health_interval=args.interval,
            restart_backoff_initial=args.backoff_initial,
            restart_backoff_max=args.backoff_max,
        )
        code = wd.run()
        return code
    finally:
        remove_pidfile(PID_FILE)


if __name__ == "__main__":
    sys.exit(main())


