# Windows Local Renderer / Windows 本地测试渲染器

## 中文

该工具直接编译并运行项目中的 `render.c`、`maneuver.c`、`route_path.c` 和 R3 状态机，并非重新绘制的示意程序。Windows 只替换车机特有的平台部分：GLFW/OpenGL 代替 QNX EGL，WinSock 代替 QNX socket，PowerShell harness 代替 Java `RendererServer`。

| R3 首个真实箭头 | 普通后续箭头 | 隐藏后重新进入 |
| --- | --- | --- |
| ![R3 first maneuver](preview_r3_first.png) | ![Normal next maneuver](preview_r3_next.png) | ![R3 re-entry](preview_r3_reenter.png) |

运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\local_test_renderer.ps1
```

也可以直接双击 `run_local_test.cmd`。预编译 EXE 的 SHA-256 为
`565a0f6f885dd122c9732759676340c051170516a15cb2f7dd9a739e2ed83d09`，
其余文件见 `SHA256SUMS.txt`。

主要按键：

| 按键 | 功能 |
| --- | --- |
| `F` | 模拟 R3 首个真实箭头：透明预加载、等待 frame-ready、等待 100 ms、开始动画 |
| `E` | 隐藏后选择下一预设，并模拟重新进入接近区 |
| `H` | 隐藏预览窗口 |
| `←` / `→` | 切换并发送普通后续箭头 |
| `↑` / `↓` | 调整 bargraph |
| `B` | 切换 bargraph 关闭/常亮/闪烁 |
| `P` | 切换 2D/3D perspective |
| `S` | 保存 PPM 截图到当前目录 |
| `G` | 切换调试网格 |
| `A` | 自动执行首箭头、后续箭头、隐藏和再次进入测试 |
| `Q` / `Esc` | 退出 |

窗口默认以 2 倍尺寸显示，但 framebuffer 仍遵循 macOS Retina 测试路径的逻辑。可使用 `-Scale 1` 到 `-Scale 4` 调整显示尺寸。

重新编译：

```powershell
.\compile_render_windows.ps1
```

构建脚本会将 Zig 0.16.0 和 GLFW 3.4 下载到 `.tools`，校验 Zig 官方 SHA-256，并固定 GLFW commit。`.tools` 不会提交到 Git。

## English

This utility compiles and runs the project's actual `render.c`, `maneuver.c`, `route_path.c`, and R3 state machine. It is not a visual reimplementation. Only device-specific layers are replaced: GLFW/OpenGL for QNX EGL, WinSock for QNX sockets, and a PowerShell harness for Java `RendererServer`.

Run `run_local_test.cmd` or `powershell -ExecutionPolicy Bypass -File .\local_test_renderer.ps1`. Press `F` for the exact R3 preload/frame-ready/100 ms/start sequence, arrow keys for normal subsequent maneuvers, `E` for hide/re-entry, and `A` for the automated scenario. The Windows executable has no bundled runtime DLL dependency.

This preview validates renderer geometry, command handling, and animation timing. It cannot reproduce the vehicle's display manager, MOST encoder, context 72/74 switching, or cluster LCD timing.
