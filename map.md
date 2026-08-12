---
title: Zephyr Source Map
status: draft
last_verified: 2026-08-11
source_revision: e25bf15ef4e
verification_scope: 顶层入口文件和主要目录的一层结构；应用入口、源码选择到最终 ELF 的构建路由
---

# Zephyr Source Map

本文档为人和 AI 提供系统级源码路由。它只回答“应该先看哪里”，具体行为必须进入源码、构建结果或测试验证。

## 一眼看目录

下面的树状图用于快速建立“顶层目录关系”的空间感。它不是完整文件清单，而是面向阅读路由的压缩视图。

```text
zephyr/
|-- CMakeLists.txt        # Zephyr 基座 CMake 入口，不是应用顶层工程
|-- Kconfig               # Kconfig 主入口
|-- Kconfig.zephyr        # 配置汇聚入口，继续分发到 boards/soc/arch/kernel 等
|-- west.yml              # west manifest，定义外部项目、路径和分组
|-- VERSION               # Zephyr 版本号
|-- SDK_VERSION           # 推荐 SDK 版本信息
|-- version.h.in          # 版本头文件模板
|-- arch/                 # 架构支持层
|   |-- Kconfig           # 架构选择相关配置
|   |-- arc/              # ARC 架构实现
|   |-- arm/              # ARM 架构实现
|   |-- x86/              # x86 架构实现
|   `-- ...
|-- boards/               # 板级定义、board 默认配置、shield 接入
|   |-- Kconfig           # BOARD、BOARD_TARGET 等板级配置入口
|   `-- <vendor>/<board>/ # 具体板目录
|-- soc/                  # SoC 选择与 SoC 相关支撑代码
|   |-- Kconfig           # SoC 配置入口
|   |-- Kconfig.v2        # 新版 SoC 硬件模型相关入口
|   `-- <vendor>/<series>/<soc>/ # 具体 SoC 目录
|-- dts/                  # Devicetree 源、binding 与架构 DTS 入口
|   |-- Kconfig           # 引入生成后的 Kconfig.dts
|   |-- bindings/         # Devicetree binding 定义
|   |-- common/           # 通用 DTS 片段
|   `-- <arch>/           # 各架构 DTS 目录
|-- drivers/              # 设备驱动分类目录
|   |-- Kconfig           # 各类驱动配置入口
|   `-- <type>/           # 如 gpio/i2c/spi/serial/usb 等
|-- kernel/               # 内核核心运行时机制
|   |-- Kconfig           # 内核配置入口
|   |-- init.c            # 初始化流程
|   |-- thread.c          # 线程核心实现
|   |-- sched.c           # 调度相关实现
|   |-- device.c          # 设备模型关键实现
|   `-- ...
|-- lib/                  # 基础库能力与通用辅助组件
|   |-- Kconfig           # lib 层配置入口
|   |-- libc/             # C 库适配与封装
|   |-- os/               # OS 常用基础能力
|   |-- utils/            # 通用工具库
|   `-- ...
|-- subsys/               # 上层子系统与 OS services
|   |-- Kconfig           # 子系统配置入口
|   |-- logging/          # 日志子系统
|   |-- fs/               # 文件系统子系统
|   |-- pm/               # 电源管理子系统
|   |-- usb/              # USB 子系统
|   `-- ...
|-- include/              # 公共头文件与 API 入口
|   `-- zephyr/
|       |-- kernel.h      # 内核 API 总入口之一
|       |-- device.h      # 设备模型 API
|       |-- devicetree.h  # Devicetree 宏入口
|       `-- ...
|-- modules/              # 外部模块的配置汇聚入口
|   `-- Kconfig           # 外部模块 Kconfig 接入点
|-- scripts/              # 构建、生成、测试与维护脚本
|   |-- twister           # 测试执行入口脚本
|   `-- ...
|-- samples/              # 示例工程，适合看最小可运行路径
|   |-- hello_world/      # 最小 hello world 示例
|   |-- basic/            # 基础功能示例
|   |-- drivers/          # 驱动相关示例
|   |-- net/              # 网络相关示例
|   `-- ...
|-- tests/                # 测试集合，适合找验证路径
|   |-- kernel/           # 内核测试
|   |-- drivers/          # 驱动测试
|   |-- subsys/           # 子系统测试
|   |-- net/              # 网络测试
|   `-- ...
|-- doc/                  # 官方文档源码
|   |-- index.rst         # 文档首页入口
|   `-- ...
`-- zephyr-workbench/     # 本地工作台与导读资料
    |-- map.md            # 顶层源码路由图
    |-- script/           # 脚本说明与补充文档
    |-- template/         # 可直接复用的命令模板
    |   `-- west-template.md # 手工 west / twister 构建与测试命令手册
    `-- topics/           # 专题化知识沉淀
        `-- cmake-build-flow.md # CMake 主线、源码选择与 hello_world 到 zephyr.elf 调用链
```

阅读建议：

- 先把 `CMakeLists.txt`、`Kconfig`、`Kconfig.zephyr`、`west.yml` 当作“总入口”。
- `kernel/`、`arch/`、`soc/`、`boards/`、`drivers/`、`subsys/` 是运行与硬件接入的主体。
- `include/zephyr/` 更像 API 入口；`samples/`、`tests/` 更像验证入口。
- `zephyr-workbench/` 是工作台和导读，不替代源码本体。

## 主要理解维度

### 1. 构建与配置链路

已确认入口：

- `west.yml`：upstream Zephyr 的 west manifest，列出外部项目、路径和分组。
- `CMakeLists.txt`：Zephyr 基座的 CMake 文件；文件开头明确说明它不是应用工程的顶层 `CMakeLists.txt`，构建应从应用目录进入。
- `Kconfig`：配置主入口，声明 `mainmenu "Zephyr Kernel Configuration"` 并引入 `Kconfig.zephyr`。
- `Kconfig.zephyr`：配置汇聚入口，直接引入 `dts/Kconfig`、`modules/Kconfig`、`boards/Kconfig`、`soc/Kconfig`、`arch/Kconfig`、`kernel/Kconfig`、`drivers/Kconfig`、`lib/Kconfig`、`subsys/Kconfig` 等。
- `VERSION`、`SDK_VERSION`、`version.h.in`：版本和版本头模板入口。
- `topics/cmake-build-flow.md`：已验证的专题文件，收敛了 `find_package(Zephyr)` 到 `zephyr.elf` 的主链，以及 Kconfig/CMake 如何选择源码、怎样从构建产物反查。
- `topics/cmake-directory-map.md`：已验证的专题文件，收敛了 `zephyr/cmake/` 目录的结构、职责分层和关键入口。

适合先看这里的问题：

- 为什么某个 Kconfig 选项出现、默认值来自哪里、哪个目录参与了配置。
- 应用如何把 Zephyr 作为基座纳入 CMake 构建。
- west 会拉取或声明哪些外部项目。
- 构建输出、链接阶段、生成头文件等问题：先看 `topics/cmake-build-flow.md`，再进入根 `CMakeLists.txt` 和 build 目录。
- 某个源文件为什么参与编译、是否进入静态库或最终 ELF：先看 `topics/cmake-build-flow.md` 的源码选择和构建反查章节。
- 想知道 `zephyr/cmake/` 目录本身如何分层、各子目录分别负责什么：先看 `topics/cmake-directory-map.md`。

待补充：

- Devicetree 到 `Kconfig.dts`、生成头文件、链接脚本的完整生成链。
- west manifest 与 `modules/`、`submanifests/` 的实际装配关系。

### 2. 核心运行层

已确认入口：

- `kernel/`：包含 `thread.c`、`sched.c`、`scheduler.c`、`sem.c`、`mutex.c`、`timer.c`、`timeout.c`、`work.c`、`init.c`、`device.c`、`fatal.c` 等运行时机制文件；也包含 `Kconfig` 和 `CMakeLists.txt`。
- `kernel/Kconfig`：进入 “General Kernel Options”，可见多线程、优先级等内核配置。
- `kernel/CMakeLists.txt`：创建和组织 `kernel` 目标，并注册若干 syscall header。
- `arch/`：按架构分目录，包括 `arc/`、`arm/`、`arm64/`、`mips/`、`posix/`、`riscv/`、`x86/`、`xtensa/` 等。
- `arch/Kconfig`：定义架构选择相关符号。
- `arch/CMakeLists.txt`：加入 `arch/common` 和当前 `${ARCH}` 对应目录。

适合先看这里的问题：

- 线程、调度、同步、定时器、工作队列、初始化、fatal 路径等运行时问题：先看 `kernel/`。
- 架构选择、架构能力、CPU/ABI/上下文切换等问题：先看 `arch/Kconfig`、`arch/CMakeLists.txt` 和对应 `arch/<arch>/`。
- 内核 API 与 syscall 入口：先看 `kernel/CMakeLists.txt` 中注册的 header，再进入对应头文件和实现。具体 API 边界待补充。

待补充：

- `kernel/` 内部文件与机制之间的依赖图。
- `arch/common` 与各架构目录的职责边界。
- `include/` 中公共 API 与内部头文件的分层。

### 3. 设备、板级与硬件接入

已确认入口：

- `boards/`：按厂商或组织分目录，另有 `common/`、`shields/` 和顶层 `Kconfig`、`CMakeLists.txt`。
- `boards/Kconfig`：定义 `BOARD`、`BOARD_REVISION`、`BOARD_TARGET` 等板级配置，并引入 shield 相关 Kconfig。
- `boards/CMakeLists.txt`：如果 `${BOARD_DIR}/CMakeLists.txt` 存在，则加入当前板目录；同时加入 `shields/`。
- `soc/`：按厂商或平台分目录，包含 `common/`、`Kconfig`、`Kconfig.v2`、`CMakeLists.txt`。
- `soc/Kconfig`：进入 “Hardware Configuration”，引入 SoC root 生成的 Kconfig 和 `soc/common/Kconfig`。
- `soc/CMakeLists.txt`：根据 `SOC_NAME`、`SOC_SERIES`、`SOC_FAMILY` 选择具体 SoC 目录。
- `dts/`：按架构分目录，并包含 `bindings/`、`common/`、`vendor/`。
- `dts/Kconfig`：引入构建目录中的 `Kconfig.dts`。
- `drivers/`：按设备类型分目录，例如 `gpio/`、`i2c/`、`spi/`、`sensor/`、`serial/`、`flash/`、`ethernet/`、`wifi/`、`usb/` 等。
- `drivers/Kconfig`：在 “Device Drivers” 下引入各驱动类别的 Kconfig。
- `drivers/CMakeLists.txt`：通过 `add_subdirectory_ifdef(CONFIG_...)` 按配置加入各驱动目录，少量目录无条件加入。

适合先看这里的问题：

- 某块板子的配置、板级文件、shield 接入：先看 `boards/Kconfig`、`boards/CMakeLists.txt` 和对应 `boards/<vendor>/<board>/`。
- 某个 SoC 的选择和 SoC 目录定位：先看 `soc/Kconfig`、`soc/CMakeLists.txt`，再看对应 `soc/<vendor>/...`。
- Devicetree binding、架构 DTS、vendor 前缀等：先看 `dts/`，再看 `dts/bindings/` 或对应架构目录。
- 某类外设驱动是否参与构建：先看 `drivers/Kconfig` 和 `drivers/CMakeLists.txt`，再进 `drivers/<type>/`。
- 设备模型、初始化顺序、设备依赖生成：当前只能定位到 `kernel/device.c`、`kernel/init.c`、`drivers/`、`dts/` 和根 `CMakeLists.txt` 中提到的 device dependency 生成；完整链路待补充。

待补充：

- `boards/`、`soc/`、`dts/`、`drivers/` 之间的完整硬件接入路径。
- 设备模型宏、Devicetree binding、驱动实例化之间的直接关系。
- board v1/v2、SoC HWMv2 等模型差异。

### 4. 上层子系统与 OS Services

已确认入口：

- `subsys/`：按系统能力分目录，包括 `bluetooth/`、`net/`、`fs/`、`shell/`、`logging/`、`settings/`、`mgmt/`、`pm/`、`usb/`、`zbus/` 等。
- `subsys/Kconfig`：进入 “Subsystems and OS Services”，引入各子系统 Kconfig。
- `subsys/CMakeLists.txt`：部分子系统无条件加入，部分通过 `add_subdirectory_ifdef(CONFIG_...)` 按配置加入。

适合先看这里的问题：

- 网络、蓝牙、文件系统、shell、logging、settings、USB、管理协议等能力入口：先看 `subsys/<name>/Kconfig` 和 `subsys/<name>/CMakeLists.txt`。
- 某个上层能力是否参与构建：先看 `subsys/Kconfig` 和 `subsys/CMakeLists.txt`。
- 子系统和驱动之间的边界：先从 `subsys/<name>/` 与相关 `drivers/<type>/` 双向定位，具体依赖待补充。

待补充：

- 主要子系统的入口专题，例如 `net`、`bluetooth`、`fs`、`shell`、`logging`。
- `subsys/` 与 `lib/`、`drivers/`、`include/` 之间的边界。

### 5. 验证与示例

已确认入口：

- `tests/`：按主题分目录，包括 `kernel/`、`drivers/`、`subsys/`、`net/`、`arch/`、`boards/`、`kconfig/`、`ztest/` 等；顶层有 `test_config.yaml`、`test_config_ci.yaml`、`tests.dox`。
- `samples/`：按主题分目录，包括 `hello_world/`、`basic/`、`drivers/`、`kernel/`、`net/`、`subsys/`、`bluetooth/` 等。
- `samples/hello_world/` 和 `samples/basic/blinky/` 都有 `CMakeLists.txt`、`prj.conf`、`README.rst`，并带有测试或样例 YAML 文件。

适合先看这里的问题：

- 想找最小应用入口：先看 `samples/hello_world/` 或相关主题下的 `samples/<topic>/`。
- 想验证内核、驱动、子系统行为：先看 `tests/<area>/`。
- 想理解某功能的典型配置：先看对应 sample 的 `prj.conf` 和 `CMakeLists.txt`。

待补充：

- Twister/ztest 的执行入口和测试选择规则。
- `samples/` 与 `tests/` 的分类标准。
- 常用最小复现路径。

## 顶层目录职责索引

| 路径 | 当前确认的职责 | 主要证据 | 状态 |
|---|---|---|---|
| `CMakeLists.txt` | Zephyr 基座构建入口，不是应用顶层入口 | 文件开头注释和 `ZEPHYR_BINARY_DIR` 检查 | 已确认 |
| `Kconfig` | Kconfig 主入口 | `source "Kconfig.zephyr"` | 已确认 |
| `Kconfig.zephyr` | 配置汇聚入口 | 直接 source boards/soc/arch/kernel/drivers/lib/subsys 等 | 已确认 |
| `west.yml` | west manifest | `manifest:`、`projects:`、模块路径 | 已确认 |
| `kernel/` | 核心运行时机制 | 一层文件名和 `kernel/Kconfig`、`kernel/CMakeLists.txt` | 已确认到目录级 |
| `arch/` | 架构支持 | 按架构分目录，CMake 加入 `${ARCH}` | 已确认到目录级 |
| `boards/` | 板级定义和 shield 接入 | `BOARD` 配置和 `${BOARD_DIR}` CMake 入口 | 已确认到目录级 |
| `soc/` | SoC 选择和 SoC 支撑 | `SOC_NAME`/`SOC_SERIES`/`SOC_FAMILY` CMake 选择 | 已确认到目录级 |
| `dts/` | Devicetree 架构目录、binding、生成 Kconfig 入口 | `dts/Kconfig` 引入 `Kconfig.dts` | 已确认到目录级 |
| `drivers/` | 设备驱动类别 | `drivers/Kconfig` 与 `drivers/CMakeLists.txt` 分类加入 | 已确认到目录级 |
| `subsys/` | 上层子系统和 OS services | `subsys/Kconfig` 与 `subsys/CMakeLists.txt` 分类加入 | 已确认到目录级 |
| `tests/` | 测试集合 | 一层目录按 kernel/drivers/subsys/net/ztest 等分类 | 已确认到目录级 |
| `samples/` | 示例和最小应用入口 | 一层目录和 sample 内 `CMakeLists.txt`/`prj.conf` | 已确认到目录级 |
| `modules/` | 外部模块相关配置入口 | `Kconfig.zephyr` 引入 `modules/Kconfig`，`west.yml` 项目路径指向 `modules/...` | 待补充 |
| `scripts/` | 构建、生成和维护脚本 | 顶层目录名；未深入 | 待补充 |
| `include/` | 公共头文件或 API 入口 | `kernel/CMakeLists.txt` 引用 `include/zephyr/...` | 待补充 |
| `lib/` | 基础库能力 | `Kconfig.zephyr` 引入 `lib/Kconfig`；未深入 | 待补充 |

## 问题到目录的快速路由

- 配置为什么生效或不生效：先看 `Kconfig.zephyr`，再按来源进入 `boards/`、`soc/`、`arch/`、`kernel/`、`drivers/`、`subsys/` 或 `lib/`。
- 构建为什么进入或没有进入某个目录：先看根 `CMakeLists.txt`，再看对应目录的 `CMakeLists.txt` 和 `CONFIG_*` 条件。
- 板子、SoC、shield、硬件描述相关：先看 `boards/`、`soc/`、`dts/`。
- 外设驱动相关：先看 `drivers/<type>/`，同时检查 `drivers/Kconfig` 和 `drivers/CMakeLists.txt`。
- 线程、调度、同步、定时器、初始化、fatal 等内核行为：先看 `kernel/`。
- 架构相关行为：先看 `arch/Kconfig`、`arch/CMakeLists.txt` 和 `arch/<arch>/`。
- 网络、蓝牙、shell、文件系统、logging、settings、USB 等系统能力：先看 `subsys/<name>/`。
- 找最小可运行例子：先看 `samples/hello_world/`，再看对应主题的 `samples/`。
- 找验证路径：先看 `tests/<area>/`，再结合相关 sample。

## 本版边界

- 本版没有深入具体驱动、具体架构或具体子系统实现。
- 本版没有建立完整启动路径、设备模型路径或构建生成链。
- 本版结论主要来自顶层入口文件、主要目录的一层结构，以及各主目录的 `Kconfig` 和 `CMakeLists.txt`。
- 后续已确认的子系统细节进入 `topics/<topic>.md`，不继续堆入本页。
