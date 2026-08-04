# R4.1 Diagnostic Candidate / R4.1 诊断候选版

Build ID: `2026-08-04-lazy-renderer-gate-release-r4.1`

This matched four-file set addresses the R4 report where both CarPlay and stock
navigation remained stuck on a straight arrow. It has passed local protocol and
renderer tests, but still requires vehicle validation.

该四文件组合用于修复 R4 中 CarPlay 与原车导航均卡在直行箭头的问题。目前已通过
本地协议与 renderer 测试，但仍需进行实车验证。

## Changes / 修改

- Start `maneuver_render` only after a valid real maneuver enters the approach
  zone. / 仅在有效真实 maneuver 进入接近区后启动 `maneuver_render`。
- Keep the renderer framebuffer fully transparent until a maneuver has been
  received. / 收到 maneuver 之前保持 renderer 帧缓冲完全透明。
- Commit maneuver deduplication state only after a successful socket send, so a
  startup race is retried. / 仅在 socket 发送成功后提交去重状态，首次发送失败时可重试。
- Always release `GatedCombiService.blockRouteGuidance` during shutdown, even if
  an earlier BAP cleanup step throws. / 即使前面的 BAP 清理抛出异常，退出时也始终释放原车导航拦截。
- Keep the R4 neutral-context teardown and directional U-turn mapping. /
  保留 R4 的中性 context 退出逻辑和掉头方向映射。

Replace `carplay_hook.jar` and `maneuver_render` together. The other two files
are unchanged from R4.

必须同时替换 `carplay_hook.jar` 与 `maneuver_render`；另外两个文件与 R4 相同。
