# R4.2.2 Context 72

Branch: `r4.2.2-context72`  
Build ID: `2026-08-05-r4.2.2-context72`  
Base: R4.1 (`main` at branch creation)

> Vehicle-test candidate. Back up the original files before deployment.

## Shared changes / 共同修改

- City/normal route step: real maneuver appears at **350 m**.
- Route step longer than **2 km**: real maneuver appears at **1000 m**.
- If step length is unavailable, explicit highway/ramp maneuver types are used only as a fallback.
- The first valid primary maneuver is shown immediately: `ICON_APPROACH` while far, real maneuver inside the threshold.
- Renderer preparation overlaps the BAP descriptor/distance/ExitView work.
- Retains the safe conditional context bounce: when already on context 74, switch `74 → 72 → 74`; otherwise perform a real transition into 74.
- `RouteGuidance.java` lifecycle, activation gating, disconnect handling, and destination handling are restored exactly to R4.1.
- `RouteGuidance.java` 的生命周期、激活判断、断开处理及目的地处理已完整恢复为 R4.1 原版。
- Straight-arrow mapping remains unchanged from R4.1.

- 普通/城市路段在 **350 m** 内显示真实转向。
- 相邻 maneuver 路段长度超过 **2 km** 时，在 **1000 m** 内显示真实转向。
- 路段长度缺失时，仅以明确的高速/匝道 maneuver 类型兜底。
- 本次导航的首个有效主 maneuver 立即显示：距离较远显示 `ICON_APPROACH`，进入阈值后显示真实箭头。
- renderer 准备过程与 BAP 描述符、距离及 ExitView 发送重叠执行。
- 保留安全的条件式 Context bounce：当前已是 74 时执行 `74 → 72 → 74`，其他情况下保证真实切入 74。
- 直行箭头映射保持 R4.1 原样。

## Variant behavior / 本版本窗口策略

After the first primary maneuver, hide the renderer and return to context 72 outside the approach zone.

首个主 maneuver 结束后，接近区外隐藏 renderer 并明确返回 Context 72。

## Output / 输出

- `dist/r4.2.2/carplay_hook.jar`
- GitHub Actions artifact: `r4.2.2-final`

The C hook and renderer binary are unchanged from R4.1. Deploy this JAR with the matching R4.1 `maneuver_render`, `libcarplay_hook.so`, and `flag_atlas.rgba`.

C hook 与 renderer 二进制沿用 R4.1。部署时应搭配 R4.1 对应的 `maneuver_render`、`libcarplay_hook.so` 和 `flag_atlas.rgba`。
