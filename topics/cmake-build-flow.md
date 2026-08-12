---
title: Zephyr CMake Build Flow
status: verified
last_verified: 2026-08-11
source_revision: e25bf15ef4e
verification_scope: 应用入口到 Zephyr 基座 CMake、配置与源文件选择、目录接入、自动生成文件、多阶段链接与最终产物
---

# Zephyr CMake Build Flow

本文档回答三个问题：

- `find_package(Zephyr)` 之后，CMake 是如何把一个应用组织成完整内核镜像的。
- 以 `samples/hello_world` 为例，从应用入口到 `zephyr.elf` 的调用链是怎样串起来的。
- 内核、驱动和子系统的源文件如何被选中，以及怎样确认它们是否真的进入最终镜像。

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

## 源文件如何被选中并进入最终镜像

内核、库、驱动和子系统基本遵循同一套选择流程：

```text
board target / DTS / defconfig / prj.conf / overlay / snippet
  -> Kconfig 计算最终 CONFIG_*
  -> build/zephyr/.config
  -> CMake 导入 CONFIG_* 变量
  -> 顶层 CMake 进入源码域或类别目录
  -> 子目录 CMake 选择具体源文件
  -> 编译器处理源文件内部的 #if 和 Devicetree 宏
  -> 对象文件进入 Zephyr 库或普通静态库
  -> 链接器按符号引用提取对象并执行 section garbage collection
  -> zephyr.elf
```

这条链上有四层不同含义，排查时不能混为一谈：

1. 进入目录不表示目录中所有源文件都会编译。
2. 源文件参与编译不表示文件中所有条件代码都会保留。
3. 对象文件进入静态库不表示它一定被最终链接提取。
4. 对象文件被提取也不表示它的每个 section 都会保留。

### 1. Kconfig 先形成最终配置

`Kconfig.zephyr` 汇聚 board、SoC、arch、kernel、drivers、lib 和 subsys 等配置入口。构建时，board 默认配置、应用 `prj.conf`、额外配置片段及 Kconfig 依赖共同计算出：

```text
<build-dir>/zephyr/.config
```

`cmake/modules/kconfig.cmake` 随后通过 `import_kconfig()` 把 `.config` 中的 `CONFIG_*` 导入 CMake。于是下面这样的判断才能在 CMake 配置阶段成立：

```cmake
if(CONFIG_MULTITHREADING)
  # ...
endif()
```

因此，分析“为什么编译了某文件”时，应该先确认最终 `.config`，而不是只看应用的 `prj.conf`。`prj.conf` 是输入之一，`.config` 才是 Kconfig 计算后的结果。

### 2. 顶层 CMake 接入源码域

Zephyr 根 `CMakeLists.txt` 会进入这些主要源码域：

```cmake
add_subdirectory(arch)
add_subdirectory(lib)
add_subdirectory(soc)
add_subdirectory(subsys)
add_subdirectory(drivers)
add_subdirectory(kernel)
```

这里的 `add_subdirectory()` 只表示把该目录的构建规则纳入处理。真正的文件选择通常还在各目录自己的 `CMakeLists.txt` 中继续完成。

### 3. 内核文件选择

`kernel/CMakeLists.txt` 同时使用无条件源文件、条件源文件和条件子目录。例如：

```cmake
kernel_sources(
  main_weak.c
  busy_wait.c
  device.c
  fatal.c
  init.c
  # ...
)

kernel_sources_ifdef(CONFIG_MULTITHREADING
  idle.c
  mutex.c
  sem.c
  thread.c
  sched.c
  scheduler.c
  # ...
)

kernel_sources_ifdef(CONFIG_TIMESLICING timeslicing.c)
target_sources_ifdef(CONFIG_SYS_CLOCK_EXISTS kernel PRIVATE timeout.c timer.c)
add_subdirectory_ifdef(CONFIG_USERSPACE userspace)
```

选择过程可以概括为：

```text
Kconfig.zephyr
  -> kernel/Kconfig
  -> 最终 CONFIG_MULTITHREADING、CONFIG_TIMESLICING 等
  -> kernel/CMakeLists.txt
  -> kernel_sources* / target_sources* / add_subdirectory*
  -> kernel/libkernel.a
  -> zephyr.elf
```

部分共享源文件会无条件编译，再由文件内部的 `#if defined(CONFIG_...)` 选择实现分支。例如某种调度策略不一定对应独立的 `.c` 文件，也可能是同一源文件中的编译期分支。

### 4. 驱动文件选择

驱动遵循相同主线，但比内核多一层 Devicetree 输入。以当前 QEMU Cortex-M3 构建中的 Stellaris UART 为例：

```text
qemu_cortex_m3/ti_lm3s6965
  -> board/SoC DTS 启用 UART 节点
  -> Kconfig 最终得到 CONFIG_SERIAL=y 和 CONFIG_UART_STELLARIS=y
  -> drivers/CMakeLists.txt 进入 serial/
  -> drivers/serial/CMakeLists.txt 选择 uart_stellaris.c
  -> libdrivers__serial.a
  -> zephyr.elf
```

类别目录由 `drivers/CMakeLists.txt` 选择：

```cmake
add_subdirectory_ifdef(CONFIG_SERIAL serial)
```

具体实现再由 `drivers/serial/CMakeLists.txt` 选择：

```cmake
zephyr_library_sources_ifdef(CONFIG_UART_STELLARIS uart_stellaris.c)
```

Devicetree 通常不直接把任意 `.c` 文件交给编译器。它提供启用状态、`compatible`、寄存器、中断等硬件信息，并生成 `DT_HAS_*_ENABLED` 和设备实例相关信息；这些信息会参与 Kconfig 选择，并由驱动源码中的 `DEVICE_DT_DEFINE`、`DT_INST_*` 等宏完成实例化。

因此，驱动问题通常需要同时检查：

- board 和 SoC 的 DTS/DTSI、overlay
- 对应 Devicetree binding
- 最终 `.config`
- `drivers/<type>/Kconfig*`
- `drivers/<type>/CMakeLists.txt`
- 驱动源码中的 DT 实例宏

### 5. 子系统和库文件选择

子系统也是同一模式。例如 `subsys/CMakeLists.txt` 对较大的功能域直接做条件选择：

```cmake
add_subdirectory_ifdef(CONFIG_BT bluetooth)
add_subdirectory_ifdef(CONFIG_NETWORKING net)
add_subdirectory_ifdef(CONFIG_SHELL shell)
```

也有一些上层目录会无条件进入，再由下层继续筛选。例如 POSIX portability 目录中的：

```cmake
add_subdirectory_ifdef(CONFIG_POSIX_C_LIB_EXT c_lib_ext)
```

当前 QEMU 构建得到 `CONFIG_POSIX_C_LIB_EXT=y`，因此 `fnmatch.c`、`getentropy.c` 和 `getopt_shim.c` 参与编译，并形成 `libsubsys__portability__posix__c_lib_ext.a`。

`lib/` 也使用相同的 Kconfig、CMake 和源码内条件编译机制，只是产物可能进入目录级 Zephyr library，也可能直接聚合进 `libzephyr.a`。

### 6. 不同源码域的入口差异

| 源码域 | 主要入口条件 | 需要额外注意的层次 |
|---|---|---|
| `kernel/`、`lib/`、`subsys/` | Kconfig + CMake | 共享文件内部可能继续使用 `#if CONFIG_*` |
| `drivers/` | Kconfig + Devicetree + CMake | DTS 节点启用和驱动实例化 |
| `boards/`、`soc/`、`arch/` | `west build -b <target>` 解析出的硬件目标 | board、revision、qualifier、SoC 和架构在普通源码筛选前已经确定 |
| 外部 Zephyr module | west manifest 项目或显式 module 路径 + `zephyr/module.yml` + Kconfig/CMake | “仓库存在”不等于“功能已经编译” |
| sysbuild image | sysbuild 的 image/domain 配置 | 每个 image 都有各自的 `.config`、CMake 构建和 ELF |
| 生成代码 | Kconfig、Devicetree、syscall 或预链接 ELF | 由脚本生成，不一定对应一个手写 `.c` 文件 |

它们的共同点是：最终都要落实为当前 image 的构建规则、编译单元和链接输入。差异只在于最前面的选择入口。

### 7. 链接阶段还会继续裁剪

Zephyr 通常为函数和数据启用独立 section，并在链接阶段使用 garbage collection。于是即使一个源文件已经被编译成对象文件，最终 ELF 仍可能只保留其中被引用或通过 linker section 明确保留的部分。

静态库还多一层“按未解析符号提取对象”的规则。例如 `kernel/libkernel.a` 中的对象通常只有在满足链接引用关系后才被提取。检查 `zephyr.map` 时也要注意：出现在 map 中不一定代表内容被保留；位于 `Discarded input sections` 或地址为零的 section 可能已经被裁剪。

## 如何确认当前构建了什么

下面假设命令从 workspace 根目录执行，并把构建目录保存在变量中：

```powershell
$buildDir = "build-qemu-cortex-m3-hello-world"
```

### 1. 查看最终配置

```powershell
rg "^CONFIG_(MULTITHREADING|TIMESLICING|SERIAL|UART_STELLARIS)=" `
  "$buildDir/zephyr/.config"
```

如果要反查某个配置的定义、默认值和依赖：

```powershell
rg "config UART_STELLARIS|select UART_STELLARIS|default UART_STELLARIS" `
  zephyr/boards zephyr/soc zephyr/drivers zephyr/subsys zephyr/kernel
```

### 2. 列出实际参与编译的源文件

`compile_commands.json` 是判断“某个源文件有没有调用编译器”的直接证据：

```powershell
$compileCommands = Get-Content -Raw "$buildDir/compile_commands.json" |
  ConvertFrom-Json

$compileCommands.file | Sort-Object -Unique
```

只看内核文件：

```powershell
$compileCommands.file |
  Where-Object { $_ -match '[/\\]kernel[/\\]' } |
  Sort-Object -Unique
```

只查一个具体驱动：

```powershell
$compileCommands.file |
  Where-Object { $_ -match 'uart_stellaris\.c$' }
```

### 3. 查看构建目标和实际命令

```powershell
ninja -C $buildDir -t targets all
ninja -C $buildDir -t commands
```

前者用于查看 CMake 最终生成的目标，后者用于查看 Ninja 会执行的完整编译、归档和链接命令。输出较多时可以用 `Select-String` 过滤：

```powershell
ninja -C $buildDir -t targets all |
  Select-String 'libkernel|drivers__serial|zephyr\.elf'
```

### 4. 查看静态库和最终链接结果

```powershell
Select-String -Path "$buildDir/zephyr/zephyr.map" `
  -Pattern 'libkernel','libdrivers__serial','uart_stellaris'
```

判定结果时按下面的证据强度区分：

- `.config`：功能配置最终是否启用。
- `CMakeLists.txt`：该配置如何映射到目录或源文件。
- `compile_commands.json`：源文件是否实际参与编译。
- `build.ninja` / `ninja -t commands`：对象如何归档和链接。
- `zephyr.map`：对象和 section 如何参与最终链接，以及哪些内容被丢弃。
- `zephyr.elf`：最终可执行镜像的事实结果。

分析任意模块时，可以固定使用这条反查路径：

```text
.config
  -> Kconfig 定义和依赖
  -> 父目录及当前目录 CMakeLists.txt
  -> compile_commands.json
  -> 静态库和链接命令
  -> zephyr.map / zephyr.elf
```

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
- 本文只用串口驱动和 POSIX portability 说明通用选择模式，没有穷举具体驱动或子系统。
- 本文说明了 sysbuild image 会重复独立构建链，但没有展开多镜像装配、签名或 domain 依赖。

这些都已经有入口，但还不是这份最小主链导图的范围。
