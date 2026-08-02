# Changelog / 更新日志

## R3 - Real Maneuver Sync / 真实 Maneuver 同步版 (2026-08-02)

Base: [`luka-dev/mib2q-carplay-rgi`](https://github.com/luka-dev/mib2q-carplay-rgi), upstream commit `1832d6e`.

Build ID: `2026-08-02-real-maneuver-sync-r3`

### 中文

#### 修改目标

R3 取消冷启动时固定发送 `FOLLOW_STREET` 直行占位符。自定义小窗在收到有效的真实 maneuver 且进入接近区之后才显示，使窗口出现、真实箭头淡入和滑入动画属于同一次显示流程。

#### 源码差异

| 文件 | 相比上游原版的变化 |
| --- | --- |
| `java_patch/com/luka/carplay/routeguidance/BAPBridge.java` | 新增按需显示状态机；启动 renderer 时保持隐藏；进入接近区后预加载真实 maneuver；按 `frame ready -> route info -> gfx=true -> 100 ms -> context 74 -> animation` 激活；离开接近区或 maneuver 无效时立即隐藏；导航结束采用 2500 ms 防抖后完整关闭；保留 renderer 断线恢复逻辑。 |
| `java_patch/com/luka/carplay/routeguidance/RendererServer.java` | 新增 `PRELOAD_MANEUVER`、`START_ANIMATION` 和 `HIDE_DISPLAY` 三种命令及发送接口；每次预加载前重置 frame-ready 状态。 |
| `c_render/main.c` | 将“绘制真实 maneuver 的透明准备帧”和“开始淡入/滑入动画”拆开；预加载会完整覆盖 perspective 与 bargraph，避免继承旧箭头状态；隐藏时暂停 30 秒焦点恢复检查。 |
| `c_render/protocol.h` | 增加命令 `0x07`、`0x08`、`0x09` 的协议定义。 |
| `compile_render_qnx_windows.ps1` | 新增 QNX SDP 6.5 Windows ARMv7 构建脚本。 |

源代码统计：4 个既有文件共增加 317 行、删除 79 行；另新增 64 行 Windows 构建脚本。

#### 部署文件

`dist/r3` 中的 `carplay_hook.jar` 与 `maneuver_render` 是 R3 配套版本，必须同时替换。`libcarplay_hook.so` 与 `flag_atlas.rgba` 沿用原版内容，放入目录是为了提供完整、可直接部署的四文件组合。

| 文件 | R3 状态 | SHA-256 |
| --- | --- | --- |
| `carplay_hook.jar` | 已修改 | `53fb011f2d042c74ffa8f16228b5fc5f0e9f1edf9dafbc7719819f38c1ec481f` |
| `maneuver_render` | 已修改并使用 QNX SDP 6.5 ARMv7 编译 | `51bd8df19ec7852754e8a0669417fea78663def944a9f7dcee8d331e05bd2c63` |
| `libcarplay_hook.so` | 未修改 | `ef56dfebea0d99c0bb8b9633e34028b77b8233a7f8e2861e25e733ed4667cf3a` |
| `flag_atlas.rgba` | 未修改 | `b1985705eabcb0379bed9a5c0055694a4b3db7ac28cef29c57a9d7f2e619dd11` |

与 `730-1/Toolbox/apps/carplay-rgi` 中原始四文件的二进制对比：

| 文件 | 原版 | R3 | 结论 |
| --- | --- | --- | --- |
| `carplay_hook.jar` | 102297 bytes, `b839122c1a14379407884d58747a57d6b5026db8d04e485752d34dbd22a85e76` | 105030 bytes, `53fb011f2d042c74ffa8f16228b5fc5f0e9f1edf9dafbc7719819f38c1ec481f` | Java 激活与隐藏逻辑已修改 |
| `maneuver_render` | 119415 bytes, `686c151aff4edc55aa734cdd9bd1e6aff0152fef6722dcfddadb0f7fad3c054c` | 120356 bytes, `51bd8df19ec7852754e8a0669417fea78663def944a9f7dcee8d331e05bd2c63` | renderer 协议与透明预加载逻辑已修改 |
| `libcarplay_hook.so` | 249646 bytes | 249646 bytes | SHA-256 完全一致，未修改 |
| `flag_atlas.rgba` | 917504 bytes | 917504 bytes | SHA-256 完全一致，未修改 |

JAR 条目级对比仅发现 7 项变化：`CarPlayHook.class`（R3 build ID）、`BAPBridge.class`、`BAPBridge$2.class`、新增的 `BAPBridge$3.class`，以及 `RendererServer.class`、`RendererServer$1.class`、`RendererServer$2.class`。其余 JAR 条目与原版一致。

#### 各种工况下的显示逻辑

| 工况 | R3 行为 | 仪表显示结果 |
| --- | --- | --- |
| CarPlay 导航刚启动，但没有有效 maneuver | renderer 进程和连接可提前准备，gfx/context 保持关闭 | 不显示小窗，不显示直行占位符 |
| 距离下一动作较远 | BAP/HUD 可保持 `FOLLOW_STREET`，自定义 renderer 保持隐藏 | 小窗关闭，避免长时间残留箭头 |
| 首个真实 maneuver 进入接近区 | 先以 alpha=0 预加载真实箭头并等待 frame-ready，再开启 gfx，等待 100 ms，仅激活一次 context 74，最后启动动画 | 小窗与首个真实箭头同步出现；不会先显示固定直行箭头 |
| 接近区内距离持续变化 | 不重启窗口，只更新 bargraph/perspective 等状态 | 当前箭头稳定显示，距离条正常更新 |
| 接近区内切换到下一 maneuver | 发送正常 maneuver 更新并使用 renderer 原有过渡动画 | 后续箭头按正常切换逻辑显示，无额外直行占位符 |
| 驶离接近区 | 发送隐藏命令，停用 context 74，并设置 gfx=false；renderer 进程保留 | 小窗立即消失，旧箭头不会残留 |
| 再次进入接近区 | 完整预加载当前真实 maneuver，并重新执行一次 100 ms 后激活流程 | 新箭头重新淡入，不继承上一枚箭头的 bargraph/perspective |
| maneuver 列表为空、无效或被明确清除 | 立即走隐藏流程 | 小窗消失，不保留上一枚箭头 |
| 到达类 maneuver | 不受距离为 0 的限制，按接近区处理 | 可以显示真实终点/到达图标 |
| `route_state=0` 瞬时抖动 | 立即隐藏小窗，但延迟 2500 ms 才终止 renderer；期间恢复会取消终止 | 不会因瞬时状态反复拉起进程，也不会残留窗口 |
| 导航确认结束 | 2500 ms 内未恢复后关闭 renderer、连接和相关状态 | 完整退出 |
| CarPlay 断开或系统 shutdown | 不等待防抖，立即完整关闭 | 立即清理 |
| renderer 通信故障 | 连续 3 次发送失败后尝试重启，重启冷却时间 5 秒 | 尽量自动恢复，恢复后仍按真实 maneuver 激活 |

接近区阈值：城市道路为下一 maneuver 距离不大于 `1500 m`；高速道路为不大于 `3000 m`。当前代码以原始 step 距离大于 `1500 m` 为主要高速判断，并保留 maneuver 类型回退判断。到达类 maneuver 始终视为位于接近区。

#### 验证状态

- `maneuver_render` 已确认是 ARM 32-bit little-endian ELF、EABI5、ARMv7/VFPv3。
- 动态依赖与原版一致：`libEGL.so.1`、`libGLESv2.so.1`、`libsocket.so.3`、`libm.so.2`、`libc.so.3`。
- `carplay_hook.jar` 中 41 个 class 均保持 Java class major version 46。
- Windows/QNX 重复编译得到相同的 `maneuver_render` SHA-256。
- 尚未完成覆盖所有固件和道路场景的实车验证，建议先在已备份原车文件的测试车辆上使用，并同时收集 `carplay_hook.log` 与 `maneuver_render.log`。

### English

#### Goal

R3 removes the synthetic `FOLLOW_STREET` straight-ahead placeholder used during a cold start. The custom window is exposed only after a valid real maneuver enters the approach zone, so window activation and the real arrow's fade/slide animation form one display sequence.

#### Source changes

| File | Change from upstream |
| --- | --- |
| `java_patch/com/luka/carplay/routeguidance/BAPBridge.java` | Adds an on-demand display state machine; starts the renderer in a hidden prepared state; preloads the real maneuver on approach; activates in the order `frame ready -> route info -> gfx=true -> 100 ms -> context 74 -> animation`; hides immediately outside approach or on invalid data; fully stops after a 2500 ms route-stop debounce; retains renderer recovery. |
| `java_patch/com/luka/carplay/routeguidance/RendererServer.java` | Adds `PRELOAD_MANEUVER`, `START_ANIMATION`, and `HIDE_DISPLAY` commands and resets frame-ready state before each preload. |
| `c_render/main.c` | Separates the transparent prepared frame from animation start; a preload fully replaces perspective and bargraph state; suppresses the 30-second focus watchdog while hidden. |
| `c_render/protocol.h` | Defines protocol commands `0x07`, `0x08`, and `0x09`. |
| `compile_render_qnx_windows.ps1` | Adds a QNX SDP 6.5 Windows ARMv7 build script. |

Source statistics: 317 insertions and 79 deletions across four existing files, plus the new 64-line Windows build script.

#### Deployment set

The R3 `carplay_hook.jar` and `maneuver_render` in `dist/r3` are a matched pair and must be deployed together. `libcarplay_hook.so` and `flag_atlas.rgba` are unchanged from upstream and are included to make the directory a complete four-file deployment set. SHA-256 values are listed in the Chinese table above and in `dist/r3/SHA256SUMS.txt`.

Compared byte-for-byte with the original four-file set in `730-1/Toolbox/apps/carplay-rgi`, the JAR changes from 102297 to 105030 bytes and the renderer from 119415 to 120356 bytes. The hook library (249646 bytes) and flag atlas (917504 bytes) have identical SHA-256 values in both sets.

At JAR-entry level, only seven entries differ: `CarPlayHook.class` (R3 build ID), `BAPBridge.class`, `BAPBridge$2.class`, the new `BAPBridge$3.class`, and `RendererServer.class`, `RendererServer$1.class`, `RendererServer$2.class`. Every other JAR entry matches the original.

#### Behavior by scenario

| Scenario | R3 behavior | Cluster result |
| --- | --- | --- |
| Navigation starts without a valid maneuver | Renderer may start and connect, while gfx/context remain disabled | No window and no straight-ahead placeholder |
| Next action is outside the approach zone | BAP/HUD may remain on `FOLLOW_STREET`; the custom renderer stays hidden | No long-lived arrow window |
| First real maneuver enters approach | Preload it at alpha 0, wait for frame-ready, enable gfx, wait 100 ms, activate context 74 once, then start animation | The window appears with the real arrow; no fixed straight arrow first |
| Distance changes inside approach | Update bargraph/perspective without restarting the window | Stable arrow and normal distance updates |
| Primary maneuver changes inside approach | Send the normal maneuver update through the renderer's existing transition | Normal subsequent-arrow transition; no placeholder |
| Vehicle leaves approach | Send hide, deactivate context 74, set gfx=false, keep renderer prepared | Window disappears and the old arrow cannot remain latched |
| Vehicle re-enters approach | Fully preload the current real maneuver and repeat the single activation sequence | Fresh fade-in without inherited bargraph/perspective state |
| Maneuver list is empty, invalid, or explicitly cleared | Hide immediately | No stale arrow |
| Arrival maneuver | Treat as approach regardless of zero distance | Real destination/arrival symbol can be shown |
| Transient `route_state=0` | Hide immediately; wait 2500 ms before process teardown; recovery cancels teardown | Avoids process churn and stale display |
| Confirmed navigation end | Stop renderer and connection after the grace period | Full teardown |
| CarPlay disconnect or shutdown | Perform immediate full teardown | Immediate cleanup |
| Renderer communication failure | Respawn after 3 consecutive send failures, with a 5-second cooldown | Best-effort recovery using the same real-maneuver activation flow |

Approach thresholds are `1500 m` for city driving and `3000 m` for highway driving. A raw step distance above `1500 m` is the primary highway heuristic, with maneuver-type fallback logic. Arrival maneuvers are always treated as being inside the approach zone.

#### Validation

- `maneuver_render` is an ARM 32-bit little-endian ELF, EABI5, ARMv7/VFPv3 binary.
- Its dynamic dependencies match upstream: `libEGL.so.1`, `libGLESv2.so.1`, `libsocket.so.3`, `libm.so.2`, and `libc.so.3`.
- All 41 classes in `carplay_hook.jar` retain Java class major version 46.
- Rebuilding the renderer with the Windows/QNX script produced the same SHA-256.
- Full vehicle coverage is not yet complete. Test only with original firmware files backed up, and collect both `carplay_hook.log` and `maneuver_render.log` during validation.
