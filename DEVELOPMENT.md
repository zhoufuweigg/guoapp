# 开发指南

## 环境

Flutter `3.47.4`、Dart `3.12+`、Go `1.24.1+`、Python `3.10+`。

- Android：JDK 17、SDK 36、NDK `28.2.13676358`
- Windows：Visual Studio C++ 桌面组件、MinGW-w64 x64
- iOS：macOS、完整 Xcode、CocoaPods
- macOS：完整 Xcode、CocoaPods，打 dmg 需 `pip install dmgbuild Pillow`；`xcode-select` 指向 Command Line Tools 时 `build_macos.py` 会自动改用 `/Applications/Xcode*.app`，也可以在系统层面执行 `sudo xcode-select -s`

构建脚本对子进程默认设置 `GOPROXY=https://goproxy.cn,direct`、`GOSUMDB=off`，同名环境变量可覆盖。

## 调试运行

Flutter 运行前必须先编译对应平台 / 架构的 Go 核心：

~~~sh
python3 scripts/build_native.py --platform android --abi arm64-v8a
flutter pub get --enforce-lockfile
flutter run
~~~

调试真果鉴（全站源版）：`build_native.py` 加 `--all-sources`，再 `flutter run --dart-define=ALL_SOURCES=true`；iOS 对应 `build_ios.py --core-only --all-sources`，macOS 用 `build_native.py --platform darwin --all-sources`。版本是编译期开关，Dart 常量和 Go 编译参数必须一致，应用启动时会校验，避免混装原生库。

## 出包

~~~sh
python3 scripts/build_android.py                 # 红果鉴
python3 scripts/build_android.py --all-sources   # 真果鉴
python3 scripts/build_android.py --abi arm64-v8a
python scripts/build_windows.py [--all-sources]
python3 scripts/build_ios.py [--all-sources]
python3 scripts/build_macos.py [--all-sources]
python3 scripts/build_ios.py --core-only [--simulator]
python3 scripts/build_ios.py --export-options /path/to/ExportOptions.plist
~~~

产物在 `dist/android`、`dist/windows`、`dist/ios`、`dist/macos`，红果鉴以 `hongguojian-` 开头，真果鉴以 `zhenguojian-` 开头。macOS 出 arm64 + x86_64 通用 dmg；dmg 的安装窗口（背景图、图标位置、隐藏工具栏）由 `dmgbuild` 写入 `.DS_Store`，打包机需要 `pip install dmgbuild Pillow`，没装时会退回普通镜像并提示。默认 ad-hoc 签名，从网络下载的 dmg 在其他 Mac 上首次打开会被 Gatekeeper 拦一次（右键「打开」，或执行 `xattr -dr com.apple.quarantine /Applications/红果鉴.app`）。有 Developer ID 时用 `package_release.py --platform macos --identity "Developer ID Application: ..."` 重新打包并公证，才能免掉这一步。本机 Android 签名使用 `android/key.properties`（不入库）。

其他脚本：`generate_brand_assets.py` 从 `brand_icon.svg` 生成各平台图标；`clear_app_data.py`、`clear_catalog_cache.py` 清理 Windows 上的应用数据和剧库缓存。

## 检查与测试

~~~sh
dart format --output=none --set-exit-if-changed lib test
dart analyze --fatal-infos lib test
flutter test --dart-define=DISABLE_REMOTE_IMAGES=true
flutter test --dart-define=DISABLE_REMOTE_IMAGES=true --dart-define=ALL_SOURCES=true
cd native
go test -race ./...
go test -race -ldflags="-X duanjuapp/native/core.buildAllSources=true" ./...
~~~

Flutter 测试一律带 `DISABLE_REMOTE_IMAGES=true`，避免加载站源图片。测试只覆盖数据兼容、权限和逻辑层，界面改动不写测试；公共假仓库在 `test/support/`。

## 架构

Flutter 界面 + Go 原生核心。站源请求、解析、签名、缓存、下载调度和播放代理都在 Go 里完成，Dart 只负责界面、播放器和本地用户数据。

- **FFI**：`native/bridge` 以 `-buildmode=c-shared` 只导出 `DuanjuRequest(json) -> json` 与 `DuanjuFree`。`lib/core_bridge.dart` 的 `NativeRepository` 把每次调用编码成 `{"action": ...}`，在 `Isolate.run` 中调用；Go 侧在 `native/core/app_runtime.go` 的 `NativeRequest` 里按 action 分派。新增能力两端都要改。Android 与 Windows 动态加载（`libduanju_core.so` / `duanju_core.dll`）；iOS 与 macOS 改成 `-buildmode=c-archive` 静态库（`ios/DuanjuCore`、`macos/DuanjuCore`）链进主程序，Dart 侧用 `DynamicLibrary.process()` 查符号，避免 dylib 的签名与库校验问题。
- **Go 核心**（`native/core`，单包）：`provider_*.go` 各站源，`app_*.go` 运行时与业务（目录缓存、下载、弹幕、存储、设置），`network_*.go` HTTP 客户端、DNS、CDN、限流。`app_stream.go` 在本机起播放代理，重写 HLS playlist、透传 Range，并处理带密钥的媒体。
- **Flutter**：界面在 `lib/ui/`（按页面分子目录，入口 `lib/main.dart` → `lib/ui/app.dart`），逻辑层平铺在 `lib/`，状态管理只用 ChangeNotifier。
- **播放与下载**：播放器用 [media_kit](https://github.com/media-kit/media-kit) / libmpv；每集下载完由 [FFmpegKit min-gpl](https://github.com/sk3llo/ffmpeg_kit_flutter)（含 GPL 媒体组件）转成单个 mp4，只换封装、不重新编码，不参与正常播放。
- **本地数据**：存储格式须兼容旧版。本地快照遇到未知键会整体报错，新增设置若要兼容旧版须存为快照外的独立键。

## 目录结构

| 目录 | 内容 |
| --- | --- |
| `lib/ui` | 界面：主题、导航壳、各页面、播放器、公共组件 |
| `lib` | 逻辑层：FFI、站源目录、播放、下载、本地存储与用户 |
| `native/core`、`native/bridge` | Go 站源核心、缓存、下载、播放代理及 C ABI |
| `android`、`windows`、`ios`、`macos` | 平台工程与资源 |
| `packages/media_kit_libs_windows_video` | 本地覆盖的 Windows 媒体依赖插件 |
| `scripts` | 构建、图标生成与数据清理脚本 |
| `test` | 逻辑层测试 |

## 站源开发约定

站源是 Go 原生 provider（`native/core/provider_*.go`），不是运行期加载的脚本。新增站源需接入：`provider_huangguo.go`（常量 / 白名单 / `canonicalProviderSource` / `GetHuangguoChapters`）、`provider_media.go`（baseURL / host 反查 / 播放分派）、`app_categories.go`、`app_cover_metadata.go`、`app_runtime.go`（Config 字段 + 目录 / 搜索 / 详情分派 + 空页放行），并在 `lib/models.dart` 登记 `SourceSite`。

Go RE2 正则**不支持 lookahead**。解析多线路播放列表时不能用 `(?=...)` 分段，否则会消耗下一段开头；应改用显式字符串截断（从容器标记之后查找下一段标记）。

## 发布

工作流 `.github/workflows/build.yml` 只能在 `main` 上手动触发，推送和 PR 不会自动运行。

1. 同时提升 `pubspec.yaml` 的版本号与构建号。
2. 在 `CHANGELOG.md` 新增同名一节（标题如 `## 1.0.1+101`），工作流会把它写入 Release 说明；未验证的改动标为开发快照。
3. 推送到 `main`，在 Actions 中手动运行 **Build app packages**。

工作流先检查版本：tag `app-v{version}`（`+` 替换为 `-`）或同名 Release 已存在时直接失败。随后四个平台各构建红果鉴、真果鉴两版：

| 产物 | 内容 |
| --- | --- |
| `*-android` | 三种架构 APK，使用发布证书签名并通过指纹校验 |
| `*-windows` | Windows x64 ZIP |
| `*-ios-unsigned` | arm64 iPhone 未签名 IPA |
| `*-macos` | arm64 + x86_64 通用 dmg，ad-hoc 签名、未公证 |

格式、分析、测试不阻塞出包；Android、Windows、iOS、macOS 全部成功后才创建 tag 和 Release，任一平台失败就不发布，已有 Release 不会被覆盖。

Android 签名只用仓库 Secrets：`ANDROID_KEYSTORE_BASE64`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`，另需仓库变量 `ANDROID_CERT_SHA256`（证书 SHA-256，冒号和大小写不限），缺任意一项都会失败。CI 通过环境变量把签名传给 Gradle。

## 检查更新与使用统计

接收端是 Cloudflare Worker `guoapp-update`（`worker/`，D1 数据库 `guoapp-stats`），地址在编译期由环境变量 `UPDATE_SERVER_URL` 经 `scripts/app_build.py` 注入 Go（CI 取仓库变量 `UPDATE_SERVER_URL`），没设时检查更新和使用统计都不发请求，fork 和本地构建默认不会连到这里。Go 核心（`native/core/app_update.go`）的 `checkUpdate` 请求 `GET /v1/latest`，只读不写；`reportUsage` 请求 `POST /v1/ping`，按北京时间日期和随机编号在 `pings` 表里每天记一行。两者分别由设置里的「启动时检查更新」和「匿名使用统计」控制。Worker 每小时从 GitHub 读取最新 Release 写入 `meta` 表。改 Worker 后在 `worker/` 下运行 `npx wrangler deploy`。

在 `worker/` 下查询（`--remote` 查线上库）：

~~~sh
npx wrangler d1 execute guoapp-stats --remote --command "SELECT day, COUNT(*) AS users FROM pings GROUP BY day ORDER BY day DESC LIMIT 30"   # 日活
npx wrangler d1 execute guoapp-stats --remote --command "SELECT COUNT(DISTINCT id) FROM pings WHERE day >= date('now', '-30 days')"          # 近 30 天活跃
npx wrangler d1 execute guoapp-stats --remote --command "SELECT COUNT(DISTINCT id) FROM pings"                                               # 累计装机
npx wrangler d1 execute guoapp-stats --remote --command "SELECT platform, build, version, COUNT(*) FROM pings WHERE day = date('now', '+8 hours') GROUP BY 1, 2, 3 ORDER BY 4 DESC"  # 今日分布
~~~

应用显示名：Android 在 `android/app/build.gradle.kts`，Windows 在 `windows/runner/app_branding.cmake`，iOS 由 Xcode「Thin Binary」构建阶段按 `DART_DEFINES` 写入，macOS 由 `scripts/package_release.py` 打包时改 `CFBundleDisplayName` / `CFBundleName` / `CFBundleIdentifier` 后重新签名。iOS 的 `CFBundleDisplayName` 用英文 `HongGuoJian` / `ZhenGuoJian` 以通过侧载工具的名称校验，中文名写在 `zh-Hans.lproj/InfoPlist.strings`。macOS 关闭了 App Sandbox，以便本地播放代理和自选下载目录正常工作；系统代理由 `MainFlutterWindow.swift` 的 `duanju/device` 通道读取。
