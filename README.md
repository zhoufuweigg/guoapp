# 红果鉴 / 真果鉴

> ⚠️ **免责声明**：本项目源码来自网上大名鼎鼎的**鱼佬**（原作者）。我只是把它拿来打包、测试着玩，方便自己用，**不保证任何可用性，随时可能删库**。

Flutter 多端独立短剧 / 影视应用，原名「短剧库 APP」。站源请求、解析、下载和播放均在设备上完成，不依赖自建服务。当前源码版本：**0.2.76+83**。

本轮在 0.2.50 基线上新增两个原生站源：**韩小圈**（`hanxiaoquan`，韩剧 / 韩国电影 / 韩国综艺 / 韩国动漫）与**鬼片网**（`guipian`，鬼片 / 电视剧 / 动漫）。默认可见站源顺序为：**红果 → 韩小圈 → 鬼片 → 青空**。

> 说明：应用长期按「只维护源码与定向测试，集中验证另行安排」的方式推进。未完成集中验证与真机验收的项目保持未验收状态；历史版本的检查记录不能作为后续新增功能的验收结论。

| 编译方式 | 应用名称 | 可用站源 |
| --- | --- | --- |
| 默认（不加参数） | 红果鉴 | 仅红果 |
| 加 `--all-sources` | 真果鉴 | 红果、韩小圈、鬼片、青空，以及黄豆、剧果、野果、帝果、黄果视频、黄果 AI、黄果旧版 |

默认可见站源（红果、韩小圈、鬼片、青空）无需密码；其余站源默认隐藏，在站源管理里通过密码锁解锁后显示。已有受限用户不会自动获得新增站源权限，管理员可在用户管理中勾选。

这是**编译选项**，应用内不能切换版本。标题、Android 桌面名称与电视横幅、Windows 窗口与分发文件名、iOS 显示名随编译选项变化。界面、站源调用、原生下载调度同时限制可用站源；红果版不会访问或继续执行其他站源的旧任务。

两版保留原 Android / iOS 应用标识及数据目录；Android 使用同一签名可相互覆盖升级，不能作为两个独立正式应用并排安装。切换版本保留追剧、观看记录、用户权限和下载记录；备份格式保持兼容。

## 使用

| 功能 | 操作 |
| --- | --- |
| 浏览 | 标题栏依次提供排序与筛选、榜单、多选下载和展开搜索。分类保持独立一行，内容区左右滑动切类；支持默认、名称、自然季号、上线日期、热度、播放量排序及连载状态筛选。列表下滑接近底部自动加载下一页，底部「加载更多」为兜底 |
| 搜索 | 红果合并官网与名称索引，输入停顿 300 毫秒显示最多 10 条联想；韩小圈、剧果、野果、鬼片调用各自的在线搜索并按分页继续加载。部分失败保留有效结果；最近 20 次搜索按用户保存 |
| 推荐 | 仅红果分类栏在「全部」后显示「推荐」，可切换真人剧、漫剧、AI 剧并分别记住位置 |
| 详情 | 普通点剧直接进入播放；下载和兜底入口保留详情页。详情页浏览封面、资料、追剧状态与可展开简介；底部固定「立即播放 / 继续播放」和下载入口。选集默认折叠，展开后每组 50 集，可切换范围、定位当前或输入集数跳转；宽屏与电视采用资料、选集分栏 |
| 追剧与历史 | 按想看 / 在看 / 已看 / 有更新筛选；红果已追剧发现新季后进入「有更新」。追剧和历史均可搜索。每个用户独立保存，每 5 秒及退出播放时记录真实进度 |
| 卡片与批量下载 | 卡片「更多」提供收藏、状态和下载选集；电脑右键，电视菜单键。发现页长按卡片或点标题栏「多选下载」，一次最多 50 部 |
| VIP | 全站源版浏览黄豆或全部站源时显示 VIP 图标，仅过滤黄豆；默认隐藏已确认的 VIP。未知、免费、VIP 分别保存，未知不会覆盖已知状态 |
| 手机播放 | 上滑下一集、下滑上一集；长按 350 毫秒临时 3 倍速。竖屏轻点播放 / 暂停，横屏轻点控制条，双击播放 / 暂停。视频下方为「选集 / 简介 / 下载」Tab |
| 画中画 | Android 手机 / 平板播放器接入画中画按钮；进入前隐藏自绘控制层与弹幕，小窗只保留画面。Android TV、Windows、iOS 暂未接入 |
| 画质增强 | 仅 Windows 桌面端显示并运行增强链路（关闭 / 自动 / 省电增强 / 清晰优先）；移动端与电视端隐藏 |
| 弹幕 | 红果在线播放默认开启；播放器侧边圆形「弹」字按钮可关闭、查看状态及失败重试。本地播放不加载弹幕 |
| 下载 | 播放页「下载」Tab 和详情页下载入口均可选择分集与画质；支持批量暂停、继续、重试、删除及清理任务但保留视频。「更新本剧」补新增或缺失分集 |
| 更多 | 站源管理、用户管理、下载、界面模式、关于。底栏最右侧为「设置」（与原「下载」位置互换，点按直接打开设置页） |

| 站源 | 浏览与播放 | 搜索 |
| --- | --- | --- |
| 红果 | 真人剧、漫剧、AI 剧及分集 | 联网搜索与官网搜索联想 |
| 韩小圈 | MacCMS 模板：最新韩剧 / 韩国电影 / 韩国综艺 / 韩国动漫，多线路分集 | 站源在线搜索 |
| 鬼片 | MacCMS 站点：鬼片 / 电视剧 / 动漫，多线路分集 | RSS 最新条目标题匹配（站点搜索已停用） |
| 青空 | 番剧、剧场动画、特摄及分集 | 站源在线搜索 |
| 黄豆 | 列表、VIP 标记及分集 | 筛选已加载短剧 |
| 剧果 | 热门、最新、接口分类、详情及可播放分集；签名 Cookie 接入在线播放、预加载和下载 | 站源在线搜索，支持继续加载 |
| 野果 | 接口实际分类、目录、详情及真实分集；按分集重新取流，保留 H.264 / H.265 地址 | 站源在线分页搜索 |
| 帝果 | 网页分类、目录、详情及分集；vplayer 签名解析 | 站源在线分页搜索 |
| 黄果视频 / 黄果 AI / 黄果旧版 | 列表、分类、详情及分集 | 筛选已加载短剧 |

站源可用性、清晰度和区域限制取决于源站及网络；应用不解除源站 VIP 或其他授权限制。

### 网络与资源设置

管理员从「设置与备份 → 网络与资源」选择自动、直连或手动代理，手动地址支持 HTTP、HTTPS、SOCKS5 / SOCKS5h。代理地址默认遮蔽、不进入备份；设备内播放服务始终绕过代理。自动模式读取系统静态代理与排除列表，恢复前台及每 30 秒更新；代理不会关闭 TLS 校验。

目录请求并发可设 1–6、间隔 0–5000 毫秒（默认 3 / 250ms）；下载并发默认 2、可设 1–6。仍保留前台优先、后台让行、取消、退避及请求数量边界。

### 局域网互联：追剧同步与推送播放（已接入，待验证）

两台设备在同一局域网直连，自动同步追剧记录或接续播放，不依赖账号服务器。服务类型 `_zgj-link._tcp`（DNS-SD / mDNS），按设备 ID 合并多网卡地址，首次配对记录证书指纹，后续连接固定校验。

入口：「追剧 → 标题栏同步」或「设置与备份 → 设备互联」。手动同步默认「双向合并」，可选覆盖对方 / 覆盖本机，先「查看预览」再执行；自动同步仅发送改动条目与删除标记，播放期间约每 10 秒发送进度。冲突记录保留候选，用户从同步页逐项处理。

### WebDAV 备份：配置与追剧云端同步（已接入，待设备验证）

入口：「设置与备份 → WebDAV 备份」。填写地址、账号、密码与目录（留空使用默认目录 duanju），「保存并测试连接」通过后即可「备份到 WebDAV」或「从 WebDAV 恢复」。

备份内容与「导出配置备份」一致：各用户配置、观看记录、追剧状态、收藏与播放进度，不含视频文件；恢复沿用既有备份格式与确认流程。账号密码只保存在本机，不进入备份内容，也不参与局域网互联同步。备份文件名按平台区分（如 zhenguojian-backup-android.json），多设备各存一份，互不覆盖。

### 播放器手势修复：倍速锁定 / 音量 / 亮度（0.2.66+73）

- **倍速上滑锁定**：修复长按倍速中手指刚移动就恢复原速并弹出「恢复 1 倍速」的问题——倍速保持期间的指针移动现在只服务于锁定/解锁手势，不再触发音量、亮度与进度滑动；锁定态再次长按不会重新调速，仅提示「下滑解锁」，松手未滑过阈值则保持锁定。
- **音量手势**：改为以手势起点音量快照本地推算，消除异步音量流滞后导致的显示与实际漂移；移除「超过 100%」音量增强（对 libmpv 无效，实际音量不会变化），音量上限即 100%，设置项中相应开关已移除。
- **亮度手势**：手势起点改为同步读取缓存亮度作为基准，不再被异步平台读取覆盖，显示数字与实际亮度一致；手势结束后回读平台实际值刷新缓存。

### 播放体验优化：倍速隐藏控件 / 播放常亮（0.2.67+74）

- **长按倍速时控件全隐藏**：倍速起始瞬间自动隐藏全部播放器控件（顶栏、播放/暂停、进度条、底栏等），只保留倍速 HUD pill 与锁定提示；倍速结束后恢复进入倍速前的显隐状态——此前控件已隐藏则保持隐藏，倍速中的「恢复 1 倍速」提示也不会把控件弹回。倍速期间 4 秒自动隐藏计时暂停，控件不会中途闪回。
- **播放时屏幕常亮**：播放中通过 `FLAG_KEEP_SCREEN_ON` 保持屏幕常亮，不受系统省电策略的自动息屏与降亮度影响；暂停、退出播放或切换页面即解除，恢复系统默认行为。

### 红果源修复与液态玻璃界面（0.2.68+75）

合入上游 PR #12（红果源失效修复 + 液态玻璃 UI），要点：

- **红果源签名与解析修复**：请求签名改用 nonce 随机数体系（X-Argus / X-Ladon / X-Gorgon），`video_model` 解析兼容对象、base64 JSON 与明文 JSON 三种下发结构，媒体地址提取覆盖 `main_url` / `backup_url` / `backup_urls` / `url_list` 并跳过 bytevc2 等不兼容编码。
- **Android 播放器切换为 libmpv + MediaCodec 硬解**：Android 端不再走 ExoPlayer（`video_player` 依赖已移除），统一使用 media_kit 的 libmpv，硬解方案改为 `mediacodec-copy`（解码后拷贝回 GPU，兼顾兼容与亮度/色彩增强）；新增硬解自愈——播放 8 秒仍无视频尺寸时自动回退软件解码并seek 回原位。
- **HLS 识别改为内容嗅探优先**：以 `#EXTM3U` 文件头嗅探结果覆盖 Content-Type，避免 CDN 把 MP4 误标为 mpegurl；HEAD 请求对无 Content-Type / octet-stream / text-plain 的场景补一次 512 字节 Range 探测。
- **液态玻璃界面**：新增主题设置页（液态玻璃模糊、悬浮底栏、深浅色、界面缩放），设置页加入后台缓存优化，底栏与首页改为玻璃质感导航。
- **剔除**：上游分支中误提交的工作产物（记忆文件、验证截图、中文说明文档）未纳入本仓库。

### 设置页 Material 化、液态玻璃移植与红果取流修复（0.2.69+76）

- **设置页 UI 统一为 Flutter Material 风格**：主题设置页不再依赖 `flutter_miuix`（该依赖已从工程移除），改用标准 Material 组件——`Scaffold` / `AppBar` / `ChoiceChip`（主题三选）/ `SwitchListTile.adaptive` / `Slider.adaptive` / `ScaffoldMessenger`，排布与「播放器与手势」等设置页保持一致；模糊、悬浮底栏、液态玻璃、返回手势、界面缩放四组功能与联动规则不变。
- **液态玻璃效果改用 SukiSU-Ultra 实现**：视觉算法移植自 [SukiSU-Ultra](https://github.com/ShirkNeko/SukiSU-Ultra)（`ui/component/liquid` 与 `FloatingBottomBar.kt`，上游 [AndroidLiquidGlass](https://github.com/Kyant0/AndroidLiquidGlass)，Apache-2.0）：
  - 新增透镜折射着色器 `shaders/liquid_glass.frag`，经 `BackdropFilter` + `ImageFilter.shader` 对底栏背后内容做**圆角矩形边缘透镜折射**（圆角 SDF + circleMap 位移），选中项 pill 额外带**深度折射与色散**；
  - 玻璃面叠加饱和度提升（vibrancy 1.5×）与轻度模糊，容器色 `surfaceContainer @ 0.4`，轮廓为方向光高光描边（BloomStroke 简化移植），选中 pill 带内阴影，整体投影 10dp；
  - 玻璃渲染区相对胶囊形外扩 40dp 为折射提供真实背景采样，形状之外由着色器裁掉；
  - 运行环境不支持 `ImageFilter.shader`（非 Impeller 后端）或着色器加载失败时，自动回退到纯 Flutter 毛玻璃外观，功能不受影响。
- **红果取流修复（服务端风控旧链路）**：旧 `video_model` 接口与五签名头已被风控（任何请求均返回空 body），改为移植 [hongguo-web](https://github.com/sunnysky123/hongguo-web) 的新链路：
  - `POST /novel/player/multi_video_model/v1/`，完整合成真机设备参数（28 字段保序）与 python 风格 URL 编码；
  - 六签名头（X-Gorgon / X-Khronos / X-Ladon / X-Argus / X-Helios / X-Medusa）以纯 Go 重写（`native/core/provider_hongguo_pure_sign.go`），含 RC4 变体、位旋转、md5 V3、hashF13、Feistel 与 AesV3，与 Node 参考实现逐项对拍一致；
  - 响应经 `fallback_api` 二次裸请求取媒体列表，`key_seed` 经双 SHA-512 派生 AES-128-CBC 密钥解密媒体地址；选流优先 H.264/HEVC 并校验 VOD 域名白名单。

### 液态玻璃定位修复与底栏导航互换（0.2.70+77）

- **液态玻璃定位修复**：修复玻璃效果渲染到屏幕正中、顶/底栏无变化的问题。根因是 `ImageFilter.shader` 的滤镜输入纹理恒为整屏快照（`Canvas::SaveLayer` 对 backdrop filter 的 `flood_input_coverage` 语义），旧着色器用 `u_size * 0.5` 反推形状位置必然落在屏幕中心；现新增 `u_shape_center` uniform 显式传入形状的屏幕坐标（`LiquidGlassSurface` 以后置帧回调 `localToGlobal` 动态跟踪位置，缓存键含中心点），并移除 GLES 端错误的 y 翻转（经引擎源码与实验双重确认 Impeller-GLES / Vulkan 均无需翻转）。
- **顶栏液态玻璃**：新增 `LiquidGlassPanel` 通栏玻璃面板与 `LiquidGlassStyle.top`（直角通栏），首页顶栏在液态玻璃开启时获得与底栏一致的透镜折射质感（tint 0.45，可透视列表内容）；着色器不可用时退化为纯模糊。
- **底栏与三点菜单互换**：底栏最右侧由「下载」改为「设置」（点按直接推设置页，不抢当前 tab 选中态），「下载」移入右上角三点菜单（仅在有下载权限时显示），TV 侧栏与桌面 Rail 同步互换。

### 液态玻璃效果链对齐 Kyant0/AndroidLiquidGlass（0.2.71+78）

- **模糊改为真实高斯**：原着色器内十字 5 抽头等效 sigma 仅 ~1.4px，远弱于 SukiSU `blur(4dp)`（按 AOSP 换算 sigma = 0.57735·radius + 0.5）。现移除 `u_blur_radius` 与抽头模糊，改由 `ImageFilter.compose(outer: shader, inner: blur)` 在上游做真实高斯，sigma 按同一公式换算；着色器只负责透镜折射与色散。
- **色散强度对齐**：Kyant0 `Lens.kt` 将 chromaticAberration 作布尔量传入（uniform 恒 1f），原实现传 0.5 只有一半强度，现改为 1（`u_chromatic_aberration` 按 >0 量化）。
- **逐行核对确认无偏差项**：负折射符号（`refractionAmount` 取负）与我方一致；vibrancy（`saturation 1.5×`）等价；辉光层级（bar 高光 0.75 → InteractiveHighlight → 隐形行捕获 → pill 最上层）与 SukiSU `FloatingBottomBar.kt` 的 `combinedBackdrop` 语义一致。
- **动效核对**：指针 / 六弹簧（press、value、scaleX/Y、velocity）与 `DampedDragAnimation.kt` 逐条一致（velocity = 速度 / span 且每帧 snap、release 待 |value-target| < span·0.025 才归零按压与缩放）；色散 A/B 与透镜位移经截图量化验证（色散仅激活于透镜带、右缘位移 ~7-8px）。

### 页面切换滑动化与桌面鼠标拖拽支持（0.2.72+79）

- **底栏 tab 点按平滑滑动**：移动端内容区由直接切换改为 `PageView`，点按底栏 tab 时内容区以 320ms `easeOutCubic` 平滑滑到目标页（类左右刷浏览图片体验），底栏高亮即时同步。
- **内容区左右划切换**：`PageView.onPageChanged` 驱动底栏高亮，内容区支持左右划跟手切换，与底栏双向同步；小距离拖动（不足半页）弹回原页。
- **桌面鼠标拖拽支持**：Flutter 默认 `ScrollBehavior.dragDevices` 不含 `PointerDeviceKind.mouse`（拖拽手势预留给文本选择），导致 Windows / Linux 桌面版鼠标无法滑动切换页面；新增 `_PageSwipeBehavior` 显式纳入鼠标，使桌面端与触屏、触控板行为一致。
- **发现页去滑动冲突**：移除发现页左右划切换剧集类目的手势，避免与页面滑动手势冲突。
- **设置一级化**：设置与其他 tab 同为一级页面（有底栏、无左上返回按钮），非 push 二级界面。
- **药丸通透修复**：液态玻璃选中 pill 移除 `vibrancy` 与 `blurRadius`（仅透镜折射），达到「透明且边缘光线扭曲」的通透效果。

### 倍速锁定切集行为、目录浏览进度与野果网关迁移（0.2.73+80）

- **倍速锁定跨集行为可选**：修复长按倍速锁定后切换上/下一集时锁定被重置为 1 倍速、需重新下滑解锁的问题。松手锁定时记录锁定倍速，切集后按「手势设置 → 切换剧集时的倍速」二选一：**保持锁定**（默认，延续锁定的倍速继续播放）或**恢复正常倍速**（退出锁定态回到基础倍速）。
- **目录浏览进度**：自动保存每个剧源分组（视频列表目录）中刷到的断点位置——记录断点视频的编号与名称，并关联前后最多 24 个相邻视频作为锚点；再次进入该源时自动从断点处继续（列表更新导致断点视频移位时按邻居锚定恢复，仍在加载则继续翻页查找）。入口在「设置 → 其他设置 → 保存浏览进度」（默认开启），可一键清除全部进度；进度随配置备份（含 WebDAV）逐用户导出与恢复，旧备份无该字段时自动兼容。
- **野果源 API 网关迁移修复**：野果前端将接口入口从页面 `__NUXT_DATA__` 动态 `apiBaseURL` 迁移为品牌域固定网关 `https://www.yeguodj.com/api.php`（所有 `/api/*` 路由拼接到该单入口），旧发现逻辑因取不到 `apiBaseURL` 直接判源失效。现新增网关回退：页面无 `apiBaseURL` 时自动使用固定网关，加密配置仍从入口 JS 模块动态提取（`version:v0` / `CBC` / `Pkcs7`，key/iv/sign_key 16/16/32 字节），分类、目录、详情、取流全链路经实网验证恢复。

### 红果备用取流通道修复（0.2.76+83）

- **红果备用取流（djapi）TLS 握手失败修复**：红果取流三渠道（App / 网页 / 备用代理）中，备用代理 `djapi.999888456.xyz` 此前报 `tls: no application protocol` 而整体失败。根因为标准 HTTP 客户端对 HTTPS 自动协商 HTTP/2（ALPN），而该代理服务端不支持 h2 协商。现为其单独建立一条**禁用 HTTP/2 的取流通道**（空 `TLSNextProto` 关掉 h2 且不强制 ALPN，优雅回退 HTTP/1.1），红果在 App 接口被风控、网页无公开地址时，可经备用通道取得该集媒体与密钥。

### 音量亮度映射实际设备、红果二级分类页修复（0.2.75+82）

- **音量手势映射系统媒体音量**：播放器右侧音量手势、键盘 ↑↓（±5%）、M 静音与音量面板此前只改 libmpv 内部音量（`player.setVolume`），与系统音量各管一摊、互不影响。现在 Android 上统一映射到系统媒体音量（AudioManager `STREAM_MUSIC`，参考 PiliNara 默认行为）：libmpv 内部音量保持满值作为唯一衰减环节，系统音量条随之同步，退出播放器后音量设置仍然保留；系统音量不可用（服务异常 / 勿扰策略拒绝写入）时自动回退到播放器内部音量。亮度侧在原有窗口内调亮的基础上，具备 `WRITE_SETTINGS` 授权时同步写入系统亮度（自动亮度切手动、按 0-255 档位落值）。
- **红果二级分类页打开失败修复**：漫剧 / AI 剧等二级分类此前只回退「真人剧」网页路由，App 接口被风控（空响应）时直接报「接口未返回有效数据」。现按分类补齐网页回退路由——「全部」聚合真人剧 / 漫剧 / AI 剧三条路由并去重，「真人剧 / 漫剧 / AI 剧」各自回退对应路由，部分路由失败仅提示失败的分类，全部失败时附上 App 侧原始错误便于定位。
- **浏览进度加固**：推荐视图（红果「推荐」）不再被过期目录网格状态覆盖断点；目录加载失败或恢复目标为死分支（错误态 / 空态）时清除待恢复标记，避免该分类永远无法保存新断点。

### 浏览进度细化到「源 × 二级分类」（0.2.74+81）

- **断点按「源分组 + 二级分类」分别存储**：原先每个源分组只保留一个断点，切换分类（如红果的「全部 / 真人剧 / 漫剧 / AI 剧」）会互相覆盖，体感上「只有特定几个源可保存」。现在目录断点键改为「源分组:分类」，每个源、每个二级分类各自独立记忆滚动位置；切换分类 / 站源时自动装载对应断点，离开前立即落盘，杜绝防抖未触发导致的位置丢失。
- **红果「推荐」视图纳入进度体系**：推荐页此前完全不保存 / 恢复进度，现按真人剧 / 漫剧 / AI 剧三个二级分类分别记录断点，进入推荐或切换二级分类时自动定位到上次浏览处（断点视频下架时按相邻视频锚定到附近）。
- **全部站源覆盖**：所有源分组（含「全部站源」聚合视图）的每个二级分类均有独立断点。
- **存储上限调整**：断点条目上限由 64 提升至 256（按「源 × 分类」维度增长），超出仍按最旧优先淘汰；配置备份校验同步放宽。
- **设置文案同步**：「其他设置 → 保存浏览进度」说明更新为按「站源 × 分类」记录，清除入口显示断点总数。

## 安装包与平台状态

| 平台 | 包与状态 |
| --- | --- |
| Android 8.0+ | 三架构（arm64-v8a / armeabi-v7a / x86_64）APK；同一签名可覆盖升级 |
| Windows 10/11 x64 | 完整 ZIP 解压后运行 `hongguojian.exe` / `zhenguojian.exe`，保留所有 DLL 与 `data`；局域网原生发现依赖 Windows 10 1903+ |
| Android TV | 与手机共用源码，自动识别电视模式并保持横屏；待电视 / 盒子实机验收 |
| iOS 15.1+ | 已加入工程、Go 核心链接、媒体依赖、文件管理与构建脚本；iOS 播放页禁用 media_kit_video 硬件纹理加速以规避 libmpv 渲染崩溃；待 Xcode 构建与真机验收，无已签名 IPA |

`INSTALL_FAILED_NO_MATCHING_ABIS` 表示 APK 与设备架构不匹配，请更换对应架构安装包。

### GitHub Actions

推送 `main` / `master`、`v*` 标签、提交 PR，或手动运行 **Build app packages**，会先检查再构建两版（默认与 `--all-sources`）：

| 产物 | 内容 |
| --- | --- |
| `*-android` | 三种架构 APK 和 SHA256 |
| `*-windows` | 完整 ZIP 和 SHA256 |
| `*-ios-unsigned` | 未签名 `.app` ZIP 和 SHA256，不能直接当已签名 IPA 安装 |

推送 `main` 且 android / ios / windows 全部构建成功时，自动创建 / 更新 GitHub Release（tag `app-v{version}`）。发布新版本前需先在 `pubspec.yaml` 提升 `version`，否则会覆盖同名 tag 的 Release。

Android 正式发布使用同一签名并递增构建号，在仓库 Secrets 配置：`ANDROID_KEYSTORE_BASE64`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`。未配置时生成 debug 签名预览包。

本地不入库的 `android/key.properties`：

~~~properties
storeFile=/absolute/path/zhenguojian-release.jks
storePassword=你的密码
keyAlias=zhenguojian
keyPassword=你的密码
~~~

## 开发与构建

Flutter `3.47.4`、Dart `3.12+`、Go `1.24.1+`、Python `3.10+`。Android 需要 JDK 17、SDK 36、NDK `28.2.13676358`；Windows 需要 Visual Studio C++ 桌面组件及 MinGW-w64 x64；iOS 需要 macOS、完整 Xcode 和 CocoaPods。

构建脚本对子进程默认设置 `GOPROXY=https://goproxy.cn,direct`、`GOSUMDB=off`，同名环境变量可覆盖。

~~~sh
python3 scripts/build_android.py                 # 红果鉴
python3 scripts/build_android.py --all-sources   # 真果鉴
python3 scripts/build_android.py --abi arm64-v8a
python3 scripts/build_android.py --cn-mirrors    # 国内镜像
~~~

~~~powershell
.\scripts\build_windows.ps1
.\scripts\build_windows.ps1 -AllSources
.\scripts\build_windows.ps1 -ChinaMirrors
~~~

~~~sh
python3 scripts/build_ios.py
python3 scripts/build_ios.py --all-sources
python3 scripts/build_ios.py --core-only [--simulator]
python3 scripts/build_ios.py --export-options /path/to/ExportOptions.plist
~~~

产物在 `dist/android`、`dist/windows`、`dist/ios`，红果版以 `hongguojian-` 开头，全站源版以 `zhenguojian-` 开头。

首次 Android 调试先编译对应架构核心，再运行：

~~~sh
python3 scripts/build_native.py --platform android --abi arm64-v8a
flutter pub get --enforce-lockfile
flutter run
~~~

调试全站源版：先给 `build_native.py` 加 `--all-sources`，再 `flutter run --dart-define=ALL_SOURCES=true`；iOS 对应 `build_ios.py --core-only --all-sources`。脚本会同步设置 Dart 常量和 Go 编译参数，应用启动时校验二者一致，避免混装原生库。

播放器使用 [media_kit](https://github.com/media-kit/media-kit) / libmpv，合并和导出使用 [FFmpegKit min-gpl](https://github.com/sk3llo/ffmpeg_kit_flutter)（含 GPL 媒体组件）。FFmpegKit 不参与正常播放或下载的转码。

### 集中检查与真机回归

~~~sh
python3 -m unittest discover -s scripts -p 'test_*.py'
dart format --output=none --set-exit-if-changed lib test integration_test test_driver
dart analyze --fatal-infos lib test integration_test test_driver
flutter test --dart-define=DISABLE_REMOTE_IMAGES=true
flutter test --dart-define=DISABLE_REMOTE_IMAGES=true --dart-define=ALL_SOURCES=true
cd native
go test -race ./...
go test -race -ldflags="-X duanjuapp/native/core.buildAllSources=true" ./...
~~~

Android 设备回归（连接并授权 USB 调试、保持解锁）：

~~~sh
python3 scripts/create_test_media.py
python3 scripts/serve_test_media.py
adb reverse tcp:38473 tcp:38473
flutter drive --driver=test_driver/playback.dart --target=integration_test/playback_test.dart \
  --dart-define=DISABLE_REMOTE_IMAGES=true --dart-define=FIXTURE_BASE_URL=http://127.0.0.1:38473
~~~

结果在 `build/device-test/results/`；结束后停服务并 `adb reverse --remove tcp:38473`。

### 源码同步

~~~sh
python3 scripts/finish_task.py --message "本次实际完成的变更"
python3 scripts/sync_source.py --check
~~~

脚本只同步纯源码到同级 `../guoapp`，并生成 `真果·鉴-YYYYMMDDHHMM.zip` 源码压缩包；不执行 Git 提交、分支或推送。

## 目录结构

| 目录 | 内容 |
| --- | --- |
| `lib` | 页面、播放器、本地用户、FFI、下载和媒体处理 |
| `native/core`、`native/bridge` | 独立站源核心、缓存、下载、目录迁移及 C ABI |
| `android`、`windows`、`ios` | 平台工程与必要资源 |
| `assets/video_enhancement`、`packages/media_kit_libs_windows_video` | 增强 Shader 与许可、固定 Windows 媒体依赖插件 |
| `scripts`、`.github/workflows` | 构建、签名、验证、同步和版本快照 |
| `test`、`integration_test` | 自动化与设备回归 |

## 站源开发约定

站源是 Go 原生 provider（`native/core/provider_*.go`），不是运行期加载的 Python 源。新增站源需接入：`provider_huangguo.go`（常量 / 白名单 / `canonicalProviderSource` / `GetHuangguoChapters`）、`provider_media.go`（baseURL / host 反查 / 播放分派）、`app_categories.go`、`app_cover_metadata.go`、`app_runtime.go`（Config 字段 + 目录 / 搜索 / 详情分派 + 空页放行），并在 `lib/models.dart` 登记 `SourceSite`。

注意：Go RE2 正则**不支持 lookahead**。解析多线路播放列表时不能用 `(?=...)` 做分段，否则非捕获组会消耗下一段开头；应改用显式字符串截断（从容器标记之后查找下一段标记）。
