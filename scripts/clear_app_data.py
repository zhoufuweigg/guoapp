#!/usr/bin/env python3
import os
import shutil
import subprocess
import sys
from pathlib import Path

EXECUTABLES = ("zhenguojian.exe", "hongguojian.exe")


def running(executable: str) -> bool:
    output = subprocess.run(
        ["tasklist", "/FI", f"IMAGENAME eq {executable}", "/NH"],
        capture_output=True,
        text=True,
    ).stdout
    return executable.lower() in output.lower()


def main() -> int:
    for executable in EXECUTABLES:
        if running(executable):
            print(f"{executable} 正在运行，请先退出应用")
            return 1
    directory = Path(os.environ["APPDATA"]) / "真果鉴"
    if not directory.exists():
        print(f"数据目录 {directory} 不存在，无需清理")
        return 0
    shutil.rmtree(directory)
    print(f"已删除 {directory}")
    print("完成，真果鉴与红果鉴共用此目录，两者的设置、追剧、收藏、缓存、日志和默认下载目录均已清空")
    return 0


if __name__ == "__main__":
    sys.exit(main())
