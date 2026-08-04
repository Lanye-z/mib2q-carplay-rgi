# R4.2.1 Soft Hide

Branch: `r4.2.1-soft-hide`  
Build ID: `2026-08-05-r4.2.1-soft-hide`  
Base: R4.1 (`main` at branch creation)

> Vehicle-test candidate. Back up the original files before deployment.

## Shared changes / 共同修改

- City/normal route step: real maneuver appears at **350 m**.
- Route step longer than **2 km**: real maneuver appears at **1000 m**.
- If step length is unavailable, explicit highway/ramp maneuver types are used only as a fallback.
- The first valid primary maneuver is shown immediately: `ICON_APPROACH` while far, real maneuver inside the threshold.
- Renderer preparation overlaps the BAP descriptor/distance/ExitView work.
- Retains the safe conditional context bounce: when already on context 74, switch `74 → 72 → 74`; otherwise perform a real transition into 74.
- `visible_in_app=0` or `route_state=1 + maneuver_count=0` uses a 5-second soft-inactive grace period.
- `route_state=0`, `source_supports_rg=0`, disconnect, or grace timeout performs full teardown and releases the stock-navigation BAP gate.
- Invalid destinations (`未知位置`, `Unknown Location`, `Unknown destination`, blank text) do not overwrite the last valid destination.
- Straight-arrow mapping remains unchanged from R4.1.

- 普通/城市路段在 **350 m** 内显示真实转向。
- 相邻 maneuver 路段长度超过 **2 km** 时，在 **1000 m** 内显示真实转向。
- 路段长度缺失时，仅以明确的高速/匝道 maneuver 类型兜底。
- 本次导航的首个有效主 maneuver 立即显示：距离较远显示 `ICON_APPROACH`，进入阈值后显示真实箭头。
- renderer 准备过程与 BAP 描述符、距离及 ExitView 发送重叠执行。
- 保留安全的条件式 Context bounce：当前已是 74 时执行 `74 → 72 → 74`，其他情况下保证真实切入 74。
- `visible_in_app=0` 或 `route_state=1 且 maneuver_count=0` 进入 5 秒软失效。
- `route_state=0`、`source_supports_rg=0`、真实断开或软失效超时执行完整清理并释放原车导航 gate。
- 无效目的地文字不覆盖最近一次有效目的地。
- 直行箭头映射保持 R4.1 原样。

## Variant behavior / 本版本窗口策略

After the first primary maneuver, leave context 74 active and hide only the renderer surface outside the approach zone.

首个主 maneuver 结束后，接近区外保持 Context 74，仅软隐藏 renderer 画面。

## Output / 输出

- `dist/r4.2.1/carplay_hook.jar`
- GitHub Actions artifact: `r4.2.1-carplay-hook`

The C hook and renderer binary are unchanged from R4.1. Deploy this JAR with the matching R4.1 `maneuver_render`, `libcarplay_hook.so`, and `flag_atlas.rgba`.

C hook 与 renderer 二进制沿用 R4.1。部署时应搭配 R4.1 对应的 `maneuver_render`、`libcarplay_hook.so` 和 `flag_atlas.rgba`。
