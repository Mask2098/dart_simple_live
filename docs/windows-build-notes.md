# Windows 构建环境说明（本机实测）

日期：2026-10-25　环境：Windows 11 26200（中文，代码页 936）

## 已安装

| 项 | 路径 / 版本 |
|---|---|
| Flutter | `D:\dev\flutter`（3.38.10，Dart 3.10.9，用 `storage.flutter-io.cn` 镜像下载） |
| Visual Studio Build Tools 2022 | `D:\dev\vs2022bt`（17.14.42，workload `Microsoft.VisualStudio.Workload.VCTools` + `--includeRecommended`） |
| MSVC | `14.44.35207`（含 C11 `<stdatomic.h>`，`dart_quickjs` 必需） |
| Windows SDK | 10.0.26100 |
| NuGet | `D:\dev\tools\nuget\nuget.exe`（`flutter_inappwebview_windows` 需要） |
| media_kit 预置包 | `D:\dev\tools\media_kit_archives\`（mpv、ANGLE 两个 7z，MD5 已校验） |

## 可直接复用的构建命令

```powershell
$env:Path = "D:\dev\flutter\bin;D:\dev\tools\nuget;" + $env:Path
$env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"
$env:CL = "/utf-8"                # 关键：见下
cd D:\src\simple_live\simple_live_app
flutter build windows --debug
```

## 踩过的四个坑

1. **路径超过 260 字符**：工程原先在 `C:\Users\Administrator\Documents\...` 深处，MSBuild 报 `NormalizePath` 失败。已把工作副本移到 `D:\src\simple_live`（工作区旧路径保留 junction）。
2. **`dart_quickjs` 编译失败**：`quickjs-c-atomics.h: fatal error C1083: "stdatomic.h"`。VS2019 的 MSVC 19.29 不带 C11 原子头，必须 VS2022 17.x 的 MSVC 14.4x。
3. **Flutter 不认只装组件的 VS**：`visual_studio.dart:278` 要求 workload `Microsoft.VisualStudio.Workload.NativeDesktop` 或 `Microsoft.VisualStudio.Workload.VCTools`，只加 `VC.Tools.x86.x64` 组件不够，`vswhere -requires` 匹配不到。
4. **C4819 被当成错误**：插件源码含 UTF-8 字符，在代码页 936 下触发 `warning C4819`，而工程开了 `/WX`，于是 `error C2220`。用 `CL=/utf-8` 环境变量让 cl.exe 追加编译参数即可（不需要改插件源码）。

## 注意事项

- `build/windows/x64` 下的 `mpv-dev-*.7z`、`ANGLE.7z` 若被 `flutter clean` 删掉，需要从 `D:\dev\tools\media_kit_archives` 拷回；CMake 的下载逻辑在 GitHub 直连不通时会失败（本机需走 `ghfast.top` 镜像）。
- 安装 VS2022 时不要把带空格的路径直接放进 `Start-Process -ArgumentList` 数组，会被按空格拆分（曾导致装到 `C:\Program`）。
