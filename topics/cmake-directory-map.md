---
title: Zephyr CMake Directory Map
status: verified
last_verified: 2026-08-07
source_revision: e25bf15ef4e
verification_scope: zephyr/cmake 顶层子目录、默认模块装配顺序、toolchain/linker/flash/emu/reports/usage/package 的职责与入口
---

# Zephyr CMake Directory Map

本文档回答一个问题：

- `zephyr/cmake/` 目录内部是如何分层组织的，各子目录分别负责什么。

它不替代 `topics/cmake-build-flow.md`。

- `cmake-build-flow.md` 更偏“从应用入口到 `zephyr.elf` 的调用链”
- 本文更偏“`cmake/` 目录本身的地图与职责边界”

## 一眼看结构

```text
cmake/
|-- modules/          # 默认模块装配与配置阶段主链
|-- toolchain/        # 工具链变体选择，如 zephyr/gnuarmemb/host/iar
|-- compiler/         # 编译器能力与编译选项模板
|-- linker/           # 链接器后端与 ELF 链接规则
|-- linker_script/    # 链接脚本片段与 section 组织
|-- bintools/         # objcopy/readelf/strip/format convert 抽象
|-- emu/              # run/debugserver 的仿真器接入
|-- flash/            # flash/debug/attach/rtt 与 runners.yaml
|-- reports/          # footprint/ram/rom/dashboard/pahole/puncover
|-- usage/            # usage 目标与帮助信息
|-- sca/              # 静态分析工具接入
|-- app/              # 旧入口与 app boilerplate 兼容层
|-- ide/              # IDE 集成脚本
|-- makefile_exports/ # 导出 Makefile 侧构建信息
|-- util/             # 通用小工具脚本
|-- package_helper.cmake   # script mode 下的 package/module 辅助入口
|-- target_toolchain_flags.cmake # toolchain/compiler/linker flag 汇总
|-- extra_flags.cmake      # EXTRA_CFLAGS / EXTRA_LDFLAGS 注入
|-- gen_version_h.cmake    # 版本头生成
|-- kobj.cmake             # kobject 生成辅助
|-- mcuboot.cmake          # MCUboot 签名/产物扩展
|-- pristine.cmake         # pristine 构建辅助
|-- verify-toolchain.cmake # toolchain 验证
`-- vif.cmake              # USB-C VIF 产物生成
```

## 入口与关键路径

### 外部入口不在 `cmake/` 根目录

应用侧通常从：

- `find_package(Zephyr)`

进入：

- `share/zephyr-package/cmake/ZephyrConfig.cmake`

这个文件会把：

- `${ZEPHYR_BASE}/cmake/modules`

加入 `CMAKE_MODULE_PATH`，然后默认 `include(zephyr_default)`。

因此对外部调用者来说，`cmake/` 的真正入口是：

```text
find_package(Zephyr)
  -> ZephyrConfig.cmake
  -> cmake/modules/zephyr_default.cmake
```

### `modules/` 是 `cmake/` 的总调度器

`cmake/modules/zephyr_default.cmake` 定义了默认模块加载顺序。

当前默认主链可以压缩成：

```text
python
  -> user_cache
  -> extensions
  -> version
  -> basic_settings
  -> west / ccache / yaml
  -> root
  -> zephyr_module
  -> boards / shields / snippets
  -> hwm_v2
  -> configuration_files
  -> generated_file_directories
  -> pre_dt_board(optional)
  -> dts
  -> kconfig
  -> arch
  -> soc
  -> kernel
```

这条链的含义是：

- 前半段先准备 Python、cache、扩展函数、版本、基础环境
- 中段解析模块、板级、硬件模型、配置文件
- 后段生成 DTS/Kconfig 结果，并最终确定 Arch/SoC
- 最后进入 `kernel.cmake`，再切换到 Zephyr 根 `CMakeLists.txt`

### 进入根 `CMakeLists.txt` 后的第二主链

`kernel.cmake` 做完 app/工程初始化后，会把控制权交给 Zephyr 根 `CMakeLists.txt`。

此时第二主链变成：

```text
arch
  -> lib
  -> misc/generated
  -> soc
  -> boards
  -> subsys
  -> drivers
  -> module 子目录
  -> 各类自动生成文件
  -> kernel
  -> pre0 / pre1 / final 多阶段链接
```

因此，`cmake/` 的内部工作可以分成两层：

- 第一层：`modules/` 决定“配置结果”
- 第二层：根 `CMakeLists.txt` 把这些结果转成“目标、源码、生成物和链接阶段”

## 核心机制

### 1. `modules/`：配置阶段主链

这是 `cmake/` 里最重要的子目录。

你可以把它理解成“把应用输入变成构建上下文”的地方。

关键模块如下：

- `root.cmake`
  - 统一整理 `BOARD_ROOT`、`SOC_ROOT`、`ARCH_ROOT`、`DTS_ROOT`、`SNIPPET_ROOT`
- `zephyr_module.cmake`
  - 发现 west/module，并导入模块带来的 board/soc/arch/dts/kconfig/cmake 扩展
- `boards.cmake`
  - 根据 `BOARD` 找到 `BOARD_DIR`、`BOARD_DIRECTORIES`
- `hwm_v2.cmake`
  - 生成 board/arch/soc 的 Kconfig 汇总入口
- `configuration_files.cmake`
  - 收集 `prj.conf`、board conf、overlay 等应用侧配置文件
- `pre_dt.cmake`
  - 补齐 DTS 根目录与 include 路径
- `dts.cmake`
  - 生成 `zephyr.dts`、`edt.pickle`、`devicetree_generated.h`、`Kconfig.dts`
- `kconfig.cmake`
  - 合并 `defconfig + prj.conf + module/shield/config`，产出 `.config` 和 `autoconf.h`
- `arch.cmake`
  - 根据 `CONFIG_ARCH` 确定 `ARCH_DIR`
- `soc.cmake`
  - 根据 `CONFIG_SOC*` 确定 `SOC_FULL_DIR`
- `kernel.cmake`
  - 创建 `project(Zephyr-Kernel)` 和 `app`，转入根 `CMakeLists.txt`

这一层主要回答：

- 当前板子是谁
- 当前 SoC 和 Arch 是谁
- 当前 DTS 和 Kconfig 最终结果是什么
- 后续源码树应该用哪些根路径和变量

### 2. `toolchain/`、`compiler/`、`linker/`、`bintools/`：工具链抽象层

这四个子目录共同解决“用什么工具、支持哪些 flag、如何编译链接、如何转产物格式”。

#### `toolchain/`

负责选择工具链变体，例如：

- `zephyr/`
- `gnuarmemb/`
- `host/gnu/`
- `host/llvm/`
- `iar/`
- `armclang/`

这里的核心是：

- 选中哪套 toolchain
- 设定 `CROSS_COMPILE`、sysroot、host tools、默认 linker/compiler/bintools 变体

#### `compiler/`

负责描述编译器能力和编译选项模板，例如：

- gcc
- clang
- host-gcc
- iar
- armclang

这里不直接决定应用编了什么，而是提供：

- warning flags
- optimization flags
- dialect flags
- no_common / no_strict_aliasing / debug / freestanding / sanitizer 等能力属性

根 `CMakeLists.txt` 通过 target property 消费这些能力。

#### `linker/`

负责不同链接器后端，例如：

- `ld/`
- `lld/`
- `armlink/`
- `iar/`
- `xt-ld/`

它解决的是：

- 如何配置 linker script
- 如何传 linker flags
- 如何执行最终 ELF 链接
- 如何支持 relocation / partial link / native library 等不同模式

#### `bintools/`

负责：

- objcopy
- strip
- readelf
- symbols
- disassembly
- 格式转换

也就是从最终 ELF 再派生：

- `.hex`
- `.bin`
- `.lst`
- `.symbols`
- `.stat`
- `.strip`

### 3. `linker_script/`：链接脚本片段层

这个目录和 `linker/` 互相配合，但职责不一样。

- `linker/` 更偏“链接器后端规则”
- `linker_script/` 更偏“脚本内容和 section 组织”

典型内容有：

- `arm/linker.cmake`
- `common/common-rom.cmake`
- `common/common-ram.cmake`
- `common/kobject-*.cmake`
- `common/thread-local-storage.cmake`

这层本质上是在描述：

- ROM / RAM section 怎么排
- kobject / TLS / noinit / debug sections 怎么插入
- 各类生成片段如何拼成完整链接脚本

### 4. `emu/`、`flash/`、`reports/`、`usage/`：构建后辅助层

这几层都不是“核心编译选择”，而是围绕最终产物提供操作入口。

#### `emu/`

负责仿真器集成，例如：

- `qemu.cmake`
- `native.cmake`
- `renode.cmake`
- `simics.cmake`

它们最终创建：

- `run_<emu>`
- `debugserver_<emu>`

根 `CMakeLists.txt` 再据此生成默认 `run` / `debugserver`。

#### `flash/`

负责：

- 生成 `runners.yaml`
- 创建 `flash` / `debug` / `attach` / `rtt`

它本质上把 west runner 体系接进 CMake 目标。

#### `reports/`

负责产物分析目标，例如：

- `ram_report`
- `rom_report`
- `ram_plot`
- `rom_plot`
- `footprint`
- `dashboard`
- `pahole`
- `puncover`

它不改变编译结果，但改变“你如何观察产物”。

#### `usage/`

只负责一件事：

- 给 build 目录提供 `usage` 目标，打印支持的常用目标列表。

### 5. `sca/`、`ide/`、`app/`、`makefile_exports/`、`util/`：外围支持层

这些目录不在主链中心，但在某些场景下很重要。

- `sca/`
  - 静态分析工具接入，例如 clang / cppcheck / coverity / eclair / polyspace
- `ide/`
  - IDE 生成器相关修补逻辑
- `app/`
  - 旧应用侧 boilerplate 兼容入口
- `makefile_exports/`
  - 导出 Makefile 风格构建信息
- `util/`
  - 零散通用工具

### 6. 顶层散落的 `*.cmake`

`cmake/` 根目录还有一批单文件脚本，通常承担专项功能。

常见的有：

- `target_toolchain_flags.cmake`
  - 汇总 toolchain / compiler / linker 属性
- `extra_flags.cmake`
  - 注入 `EXTRA_CFLAGS` 等外部 flags
- `gen_version_h.cmake`
  - 生成版本头
- `kobj.cmake`
  - kobject 相关辅助
- `mcuboot.cmake`
  - MCUboot 签名与相关后处理
- `package_helper.cmake`
  - script mode 下的 package/module 辅助入口
- `pristine.cmake`
  - pristine 构建辅助
- `verify-toolchain.cmake`
  - 工具链验证
- `vif.cmake`
  - USB-C VIF 产物生成

## 常见修改与验证

### 想看默认模块装配顺序

先看：

- `cmake/modules/zephyr_default.cmake`

它最适合回答：

- 哪个模块先跑
- 为什么 `dts` 一定在 `kconfig` 前
- 为什么 `arch/soc` 必须在 `kernel.cmake` 前

### 想看板子为什么能被找到

先看：

- `cmake/modules/boards.cmake`
- `cmake/modules/hwm_v2.cmake`

它们最适合回答：

- `BOARD_DIR` 怎么来的
- `board.yml` 为什么能生效
- board/SoC/Arch 的 Kconfig 汇总入口是谁生成的

### 想看 DTS/Kconfig 为什么这样生成

先看：

- `cmake/modules/pre_dt.cmake`
- `cmake/modules/dts.cmake`
- `cmake/modules/kconfig.cmake`

它们最适合回答：

- overlay 从哪里收集
- `Kconfig.dts` 怎么来的
- `.config` / `autoconf.h` 是如何产出的

### 想看工具链/链接器为什么这样选

先看：

- `cmake/toolchain/`
- `cmake/compiler/`
- `cmake/linker/`
- `cmake/target_toolchain_flags.cmake`

它们最适合回答：

- 当前用的是哪套 toolchain
- 为什么 warning/optimization/linker flags 是这些
- `ld` / `lld` / `iar` / `armlink` 是怎么切换的

### 想看 run / flash / reports 目标从哪来

先看：

- `cmake/emu/`
- `cmake/flash/CMakeLists.txt`
- `cmake/reports/CMakeLists.txt`
- `cmake/usage/CMakeLists.txt`

它们最适合回答：

- 为什么会有 `run`
- 为什么会有 `flash/debug/attach`
- 为什么会有 `ram_report/dashboard`

## 问题到目录的快速路由

- 想知道 `find_package(Zephyr)` 之后默认会跑哪些 CMake 模块：
  - 先看 `modules/zephyr_default.cmake`
- 想知道 board / SoC / Arch / DTS / Kconfig 是怎么串起来的：
  - 先看 `modules/`
- 想知道当前 toolchain / compiler / linker 是怎么被选中的：
  - 先看 `toolchain/`、`compiler/`、`linker/`
- 想知道链接脚本片段是怎么组织的：
  - 先看 `linker_script/`
- 想知道 `run` / `debugserver` / `flash` / `dashboard` 这些目标从哪来：
  - 先看 `emu/`、`flash/`、`reports/`、`usage/`
- 想知道某个顶层 `*.cmake` 单文件做什么：
  - 先看 `cmake/` 根目录同名脚本，再回溯谁 `include()` 它

## 与其他专题的关系

- `topics/cmake-build-flow.md`
  - 更适合回答“从应用入口到 `zephyr.elf` 的主链”
- 本文
  - 更适合回答“`cmake/` 目录自己是怎么分工的”

两者配合阅读时，建议顺序是：

1. 先看本文，建立 `cmake/` 目录地图
2. 再看 `cmake-build-flow.md`，理解调用链和时序

## 待确认问题

- `modules/` 中较少使用的 `doc.cmake`、`unittest.cmake`、`git.cmake` 的典型触发场景还未继续展开。
- `bintools/` 不同后端之间的能力差异还未逐项对比。
- `sca/` 各静态分析子目录的参数与输出差异还未形成统一对照表。
