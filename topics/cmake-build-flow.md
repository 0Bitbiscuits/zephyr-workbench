---
title: Zephyr CMake Build Flow
status: verified
last_verified: 2026-08-07
source_revision: e25bf15ef4e
verification_scope: 应用入口到 Zephyr 基座 CMake、目录接入、自动生成文件、多阶段链接与最终产物
---

# Zephyr CMake Build Flow

本文档回答两个问题：

- `find_package(Zephyr)` 之后，CMake 是如何把一个应用组织成完整内核镜像的。
- 以 `samples/hello_world` 为例，从应用入口到 `zephyr.elf` 的调用链是怎样串起来的。

本文只覆盖已通过源码确认的主链；具体驱动、具体子系统和具体板级细节，需要再进入各自目录继续展开。

## 一眼看主线

```text
应用 CMakeLists.txt
  -> find_package(Zephyr)
  -> ZephyrConfig.cmake
  -> zephyr_default.cmake
  -> 依次准备 python / user_cache / extensions / version / basic_settings
  -> 查找 west / ccache / yaml
  -> 装配 root / module / boards / shields / snippets / hwm_v2 / configuration_files
  -> 解析 dts / kconfig / arch / soc
  -> kernel.cmake
  -> 创建 app 目标，并 add_subdirectory(${ZEPHYR_BASE})
  -> Zephyr 根 CMakeLists.txt
  -> 接入 arch / lib / misc/generated / soc / boards / subsys / drivers / modules / kernel
  -> 生成 version / syscall / kobject / device deps / isr table 等中间文件
  -> 多阶段链接 zephyr_pre0 -> zephyr_pre1 -> zephyr_final
  -> 统一命名为最终 zephyr.elf
  -> post-build 生成 map / hex / bin / uf2 / lst / symbols / stat 等派生产物
```

## 构建时序图

### 1. 应用进入 Zephyr

`samples/hello_world/CMakeLists.txt` 只有三件事：

- 声明最低 CMake 版本
- `find_package(Zephyr REQUIRED ...)`
- 把 `src/main.c` 加进 `app`

源码见：

- `samples/hello_world/CMakeLists.txt`

这意味着应用本身并不负责组织整个内核构建，它只提供应用源文件和进入 Zephyr 的入口。

### 2. `ZephyrConfig.cmake` 找到 Zephyr 基座

`find_package(Zephyr)` 先进入 `share/zephyr-package/cmake/ZephyrConfig.cmake`。

它主要做这些事：

- 确定 `ZEPHYR_BASE`
- 确定 `APPLICATION_SOURCE_DIR` 和 `APPLICATION_BINARY_DIR`
- 计算内部使用的 `__build_dir`
- 默认加载 `zephyr_default.cmake`

这里的关键点是：应用和 Zephyr 基座从这一步开始被绑定到同一个 CMake 配置过程里。

## 3. `zephyr_default.cmake` 先把环境准备好

`cmake/modules/zephyr_default.cmake` 不是最终构建逻辑，而是默认“装配顺序”的定义。

它按顺序加载这些模块：

- `python`
- `user_cache`
- `extensions`
- `version`
- `basic_settings`
- `west`
- `ccache`
- `yaml`
- `root`
- `zephyr_module`
- `boards`
- `shields`
- `snippets`
- `hwm_v2`
- `configuration_files`
- `generated_file_directories`
- `pre_dt_board.cmake`
- `dts`
- `kconfig`
- `arch`
- `soc`
- `kernel`

这一步的作用是先把“配置世界”建立起来，让后面的根 `CMakeLists.txt` 可以直接消费已经解析好的：

- 板子信息
- DTS 信息
- Kconfig 结果
- toolchain 属性
- module 根路径

### 4. `kernel.cmake` 建立应用和 Zephyr 的桥

`cmake/modules/kernel.cmake` 做三件关键事：

- 打开 `ASM` 支持，并检查 toolchain 是否能正常工作
- 创建 `app` 目标
- `add_subdirectory(${ZEPHYR_BASE} ${__build_dir})`，把 Zephyr 根 `CMakeLists.txt` 真正拉进来

这一步之后，构建主导权从“应用入口”切换到“Zephyr 基座总装”。

## 根 `CMakeLists.txt` 在做什么

Zephyr 根 `CMakeLists.txt` 是基座总装脚本，不是应用入口。

它的工作可以分成七段。

### 1. 建立全局构建骨架

它先检查：

- 是否误把 Zephyr 根目录当成应用目录直接配置
- `ZEPHYR_BASE` 是否和当前源码路径一致

然后定义：

- ELF 后缀
- 当前链接阶段 `zephyr_pre0`
- 最终逻辑目标 `zephyr_final`
- 供生成流程使用的一组 phony target

### 2. 建立全局接口库和编译规则

它创建：

- `zephyr_interface`：承载全局 include、defines、compile options、link options
- `zephyr`：聚合库

然后统一配置：

- `include/`、`build/include/generated/`、SoC 目录等头文件路径
- `KERNEL`、`__ZEPHYR__` 等宏
- 优化等级、C/C++ 标准、warning、安全强化、LTO、freestanding、sanitizer、调试信息
- `AUTOCONF_H` 自动注入

这里的本质是：所有 Zephyr 目录后面创建出来的 target，都会继承这套公共编译语义。

### 3. 接入各大源码域

它按顺序接入：

- `arch/`
- `lib/`
- `misc/generated/`
- `soc/`
- `boards/`
- `subsys/`
- `drivers/`
- `modules/...`
- `kernel/`

这个顺序不是随意的。

- `arch/` 早进入，是为了先确立重要的编译和链接属性
- `misc/generated/` 在中间进入，是为了让生成文件能被后续目录直接消费
- `kernel/` 放得较后，是为了在前面目录把大量输入条件先准备好

### 4. 生成自动文件

这一步会生成很多后续构建必须依赖的文件，例如：

- `include/generated/zephyr/version.h`
- `include/generated/zephyr/app_version.h`
- `misc/generated/syscalls.json`
- `misc/generated/struct_tags.json`
- `include/generated/zephyr/syscall_list.h`
- `include/generated/zephyr/syscall_dispatch.c`
- `include/generated/device-api-sections.ld`
- `include/generated/device-api-sections.cmake`

它们分别服务于：

- 版本信息
- syscall 桥接
- 用户态与对象校验
- 设备 API linker section

### 5. 生成与链接阶段强相关的中间源

如果配置命中对应功能，还会从预链接 ELF 中再反向生成源码：

- `device_deps.c`
- `isr_tables.c`
- `symtab.c`
- kobject gperf 哈希表及其重命名对象

所以 Zephyr 不是“先编完所有源码，再直接链接一次”。

它是：

- 先得到一个足够接近最终布局的 ELF
- 再从这个 ELF 里提取信息
- 再生成新的源或目标文件
- 再把这些结果链接回最终镜像

### 6. 多阶段链接

常见阶段是：

```text
zephyr_pre0
  -> zephyr_pre1
  -> zephyr_final
```

只有在功能需要时才会展开成多阶段；否则 `pre0` 可以直接成为逻辑上的最终 ELF。

触发多阶段的典型原因：

- `CONFIG_DEVICE_DEPS`
- `CONFIG_GEN_ISR_TABLES`
- `CONFIG_USERSPACE`

这里的核心原因是：某些生成器必须等到“地址和 section 基本稳定”之后，才能正确提取信息。

### 7. post-build 派生产物

最终 ELF 产出后，还会继续派生：

- `zephyr.map`
- `zephyr.hex`
- `zephyr.bin`
- `zephyr.uf2`
- `zephyr.lst`
- `zephyr.symbols`
- `zephyr.stat`
- `zephyr.strip`
- `zephyr.meta`

并补充：

- `run` / `debugserver`
- `flash`
- `usage`
- `reports`

所以从使用者视角看，Zephyr 的 CMake 不只是“编译源码”，而是完整地组织了：

- 配置
- 代码生成
- 多轮链接
- 产物转换
- 运行与烧录入口

## `hello_world` 到 `zephyr.elf` 的调用链

下面用 `samples/hello_world` 走一次最小路径。

```text
samples/hello_world/CMakeLists.txt
  -> find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})
  -> share/zephyr-package/cmake/ZephyrConfig.cmake
  -> cmake/modules/zephyr_default.cmake
  -> cmake/modules/kernel.cmake
  -> 创建 app
  -> add_subdirectory(${ZEPHYR_BASE} ${__build_dir})
  -> Zephyr 根 CMakeLists.txt
  -> add_subdirectory(arch)
  -> add_subdirectory(lib)
  -> include(misc/generated/CMakeLists.txt)
  -> add_subdirectory(soc)
  -> add_subdirectory(boards)
  -> add_subdirectory(subsys)
  -> add_subdirectory(drivers)
  -> add_subdirectory(kernel)
  -> 生成 version/syscall/kobject/device-api 等
  -> 链接 zephyr_pre0 或 zephyr_pre1
  -> 必要时继续到 zephyr_final
  -> 逻辑输出命名为 zephyr.elf
```

### 应用层只负责一件事

`hello_world` 只把 `src/main.c` 注册给 `app` 目标。

源码本体极小，但最终参与编译的不止应用源码，还包括：

- Zephyr 内核
- 当前架构目录
- 当前 SoC 目录
- 当前板级输入触发的驱动和子系统
- 构建过程中生成的 `*.c` / `*.h` / `*.ld` 片段

这就是为什么一个最小 sample 也会对应上百个编译单元。

### `tests.yaml` 在这里扮演什么角色

`samples/hello_world/tests.yaml` 定义了 testcase `sample.basic.helloworld`。

它不直接控制 CMake 主链，但会被 Twister 用来：

- 识别 testcase 名称
- 选择可集成平台
- 应用 harness 规则

当 Twister 触发该 sample 构建时，底层仍然会走同一套 `find_package(Zephyr)` 到 `zephyr.elf` 的 CMake 主链。

## 如何阅读这条构建链

如果你下次要重新定位构建问题，推荐按这个顺序读：

1. `samples/<app>/CMakeLists.txt`
2. `share/zephyr-package/cmake/ZephyrConfig.cmake`
3. `cmake/modules/zephyr_default.cmake`
4. `cmake/modules/kernel.cmake`
5. `CMakeLists.txt`
6. 对应父目录的 `CMakeLists.txt`
7. `build/compile_commands.json`
8. `build/build.ninja`

各自回答的问题分别是：

- 应用如何进入 Zephyr
- Zephyr 是怎么被定位和加载的
- 默认装配顺序是什么
- `app` 和 Zephyr 根工程是怎么接上的
- 根脚本按阶段做了什么
- 某个目录为什么会进入或不进入构建
- 最终到底编译了哪些文件
- 最终到底按什么规则链接

## 当前边界

- 本文没有逐项展开 DTS 到 `Kconfig.dts` 的完整生成细节。
- 本文没有逐项展开某个具体驱动或子系统在父目录中的纳入条件。
- 本文没有覆盖 sysbuild、多镜像或签名脚本的更深层次分支。

这些都已经有入口，但还不是这份最小主链导图的范围。
