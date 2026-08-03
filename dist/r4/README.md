# R4 Deployment Set / R4 部署文件

Build ID: `2026-08-03-neutral-context-uturn-r4`

This directory contains the matched R4 four-file deployment set.

此目录包含配套的 R4 四文件组合。

- `carplay_hook.jar`: R4 Java lifecycle and U-turn direction fixes / R4 Java 生命周期与掉头方向修复
- `maneuver_render`: R4 QNX ARMv7 neutral-context restore / R4 QNX ARMv7 中性 context 恢复
- `libcarplay_hook.so`: unchanged from R3 / 与 R3 相同，未修改
- `flag_atlas.rgba`: unchanged from R3 / 与 R3 相同，未修改

Replace `carplay_hook.jar` and `maneuver_render` together. Do not combine the R4 JAR with an older renderer because both teardown paths must agree on context 72.

必须同时替换 `carplay_hook.jar` 和 `maneuver_render`。请勿将 R4 JAR 与旧版 renderer 混用，因为 Java 与 QNX 两条退出路径都必须统一恢复到 context 72。

U-turn direction priority / 掉头方向优先级：

```text
turn_angle < 0       -> left U-turn / 左掉头
turn_angle > 0       -> right U-turn / 右掉头
turn_angle 0 or +/-1000 -> China RHT fallback: left / 中国右侧通行回退：左掉头
```

See [`../../CHANGELOG.md`](../../CHANGELOG.md) for lifecycle details.

