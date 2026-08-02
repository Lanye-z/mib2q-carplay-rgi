# R3 Deployment Set / R3 部署文件

This directory contains the matched `2026-08-02-real-maneuver-sync-r3` four-file set.

此目录包含配套的 `2026-08-02-real-maneuver-sync-r3` 四文件组合。

- `carplay_hook.jar`: modified R3 Java patch / R3 Java 修改版
- `maneuver_render`: modified R3 QNX ARMv7 renderer / R3 QNX ARMv7 renderer 修改版
- `libcarplay_hook.so`: unchanged upstream hook library / 未修改的上游 hook 库
- `flag_atlas.rgba`: unchanged upstream renderer resource / 未修改的上游 renderer 资源

Do not mix the R3 JAR with an older renderer. Replace `carplay_hook.jar` and `maneuver_render` together.

请勿将 R3 JAR 与旧版 renderer 混用；`carplay_hook.jar` 和 `maneuver_render` 必须同时替换。

See [`../../CHANGELOG.md`](../../CHANGELOG.md) for behavior details and test status.
