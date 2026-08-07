---
id: ZEPHYR-TASK-0001
title: 初始 Zephyr 系统地图建立
type: research
status: in_progress
priority: high
---

# 初始 Zephyr 系统地图建立

## 目标与范围

建立第一版 Zephyr 源码路由，并选择少量高价值主题继续验证。

包含顶层构建配置、内核运行、硬件接入、上层子系统和验证入口；不包含全面扫描或所有子系统的深入审阅。

## 完成标准

- `map.md` 能把常见问题路由到首批源码入口。
- 至少完成一个经过源码验证的专题文件。
- 明确下一轮最值得深入的 3 个方向。

## 当前结论

- 第一版目录级源码路由已经迁移到 `map.md`。
- 已形成首个经过源码验证的专题文件：`topics/cmake-build-flow.md`。
- 当前已优先覆盖“构建配置”方向；下一轮优先候选方向是内核和设备模型。

## 下一步

- 继续从真实维护问题出发，补充 `dts -> Kconfig.dts -> 生成头文件/链接脚本` 主链。
- 补充内核运行层专题，优先覆盖 `init/device/thread/sched` 入口关系。
- 补充设备模型专题，优先覆盖 `boards/soc/dts/drivers` 之间的接入路径。
