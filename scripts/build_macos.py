import argparse
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path

from app_build import BuildVariant, add_variant_argument

root = Path(__file__).resolve().parents[1]


def run(arguments, env, cwd=root):
    print('+ ' + ' '.join(str(item) for item in arguments), flush=True)
    subprocess.run([str(item) for item in arguments], cwd=cwd, env=env, check=True)


def developer_directory():
    configured = os.environ.get('DEVELOPER_DIR')
    if configured and Path(configured).is_dir():
        return Path(configured)
    selected = subprocess.run(['xcode-select', '-p'], capture_output=True,
                              text=True).stdout.strip()
    if selected.endswith('.app/Contents/Developer'):
        return Path(selected)
    for candidate in sorted(Path('/Applications').glob('Xcode*.app')):
        developer = candidate / 'Contents' / 'Developer'
        if developer.is_dir():
            return developer
    raise SystemExit('需要完整 Xcode：安装后执行 '
                     'sudo xcode-select -s /Applications/Xcode.app/Contents/Developer')


def toolchain_environment(developer):
    env = os.environ.copy()
    env['DEVELOPER_DIR'] = str(developer)
    env.setdefault('GOPROXY', 'https://goproxy.cn,direct')
    env.setdefault('GOSUMDB', 'off')
    shim = root / 'build' / 'macos-toolchain' / 'bin'
    shim.mkdir(parents=True, exist_ok=True)
    script = shim / 'xcrun'
    script.write_text(f'#!/bin/sh\nDEVELOPER_DIR="{developer}" exec /usr/bin/xcrun "$@"\n')
    script.chmod(0o755)
    env['PATH'] = str(shim) + os.pathsep + env.get('PATH', '')
    return env


def package_path(name):
    import json
    config = root / '.dart_tool' / 'package_config.json'
    if not config.is_file():
        return None
    for package in json.loads(config.read_text())['packages']:
        if package['name'] == name:
            path = Path(package['rootUri'].removeprefix('file://'))
            return path if path.is_absolute() else (config.parent / path).resolve()
    return None


def repair_media_kit(env):
    package = package_path('media_kit_libs_macos_video')
    if package is None:
        return
    directory = package / 'macos'
    script = directory / 'create_framework_symlinks.sh'
    linked = directory / 'Frameworks' / '.symlinks' / 'mpv' / 'macos'
    if not script.is_file() or linked.exists():
        return
    script.write_bytes(script.read_bytes().replace(b'\r\n', b'\n'))
    (directory / 'Frameworks' / '.symlinks' / 'mpv').mkdir(parents=True, exist_ok=True)
    run(['sh', 'create_framework_symlinks.sh', 'Frameworks/Mpv.xcframework',
         'Frameworks/.symlinks/mpv'], env, cwd=directory)


def main():
    parser = argparse.ArgumentParser(description='构建红果鉴 / 真果鉴 macOS 应用与 dmg')
    add_variant_argument(parser)
    options = parser.parse_args()
    variant = BuildVariant(options.all_sources)
    if platform.system() != 'Darwin':
        raise SystemExit('macOS 构建需要 macOS 与完整 Xcode。')
    env = toolchain_environment(developer_directory())
    flutter = shutil.which('flutter')
    pod = shutil.which('pod')
    if not flutter:
        raise SystemExit('请先将 Flutter SDK 的 bin 目录加入 PATH。')
    if not pod:
        raise SystemExit('请先安装 CocoaPods（brew install cocoapods）。')
    run([sys.executable, root / 'scripts' / 'build_native.py', '--platform', 'darwin',
         *variant.arguments], env)
    run([flutter, 'pub', 'get', '--enforce-lockfile'], env)
    run([pod, 'install'], env, cwd=root / 'macos')
    repair_media_kit(env)
    run([flutter, 'build', 'macos', '--release', '--no-pub',
         *variant.flutter_arguments], env)
    run([sys.executable, root / 'scripts' / 'package_release.py', '--platform', 'macos',
         *variant.arguments], env)


if __name__ == '__main__':
    main()
