# West / Twister 命令模板

本文档用于替代 `quick_start.py` 的“手工命令版”流程。

适用场景：

- 已有可用的 `conda` 环境
- 希望手工执行 `west` / `cmake` / `twister`
- 希望最小化 `west update`，避免全量拉取仓库

当前环境假设：

- conda 环境名：`zephyr-dev`
- workspace 根目录：`C:\Workspace\3-Code\Private\zephyr-workspace`
- Zephyr 基座：`C:\Workspace\3-Code\Private\zephyr-workspace\zephyr`
- SDK 目录：`C:\Workspace\4-Plugin\zephyr-sdk`

## 最常用流程

```powershell
# 1) 激活 conda 环境
conda activate zephyr-dev

# 2) 进入 west workspace 根目录
cd C:\Workspace\3-Code\Private\zephyr-workspace

# 3) 设置关键环境变量
$env:ZEPHYR_BASE = "C:\Workspace\3-Code\Private\zephyr-workspace\zephyr"
$env:ZEPHYR_SDK_INSTALL_DIR = "C:\Workspace\4-Plugin\zephyr-sdk"

# 4) 检查基础工具
python -m west --version
python --version
cmake --version

# 5) 可选：首次或依赖缺失时，做最小化 update
python -m west update -n cmsis

# 6) 构建 sample
python -m west build -p always -b qemu_cortex_m3 zephyr\samples\hello_world -d build-qemu_cortex_m3-hello_world

# 7) 可选：运行 sample
python -m west build -d build-qemu_cortex_m3-hello_world -t run
```

## 命令模板总表

```powershell
# =========================================================
# 0. 环境初始化
# =========================================================
conda activate zephyr-dev
cd C:\Workspace\3-Code\Private\zephyr-workspace

$env:ZEPHYR_BASE = "C:\Workspace\3-Code\Private\zephyr-workspace\zephyr"
$env:ZEPHYR_SDK_INSTALL_DIR = "C:\Workspace\4-Plugin\zephyr-sdk"

python -m west --version
python --version
cmake --version


# =========================================================
# 1. 构建 sample 模板
# 用法：
# - 把 <board> 改成目标板
# - 把 <sample_path> 改成 zephyr 下的 sample 相对路径
# - 把 <build_dir> 改成独立构建目录
# =========================================================
python -m west build -p always -b <board> zephyr\<sample_path> -d <build_dir>

# 示例：hello_world
python -m west build -p always -b qemu_cortex_m3 zephyr\samples\hello_world -d build-qemu_cortex_m3-hello_world

# 如果板子支持仿真运行，可继续：
python -m west build -d build-qemu_cortex_m3-hello_world -t run


# =========================================================
# 2. 跑 tests/ 下测试模板
# 用法：
# - <test_path> 改成 zephyr\tests\... 路径
# - <platform> 改成平台名
# - <outdir> 改成独立输出目录
# =========================================================
python zephyr\scripts\twister -T zephyr\<test_path> -p <platform> --outdir <outdir> --inline-logs -v

# 示例：tests/kernel/common
python zephyr\scripts\twister -T zephyr\tests\kernel\common -p qemu_cortex_m3 --outdir twister-out-kernel-common --inline-logs -v


# =========================================================
# 3. 跑 sample 对应 testcase 模板
# 适用于 sample 自带 tests.yaml / sample.yaml 的情况
# =========================================================
python zephyr\scripts\twister -T zephyr\<sample_path> -p <platform> --outdir <outdir> --inline-logs -v

# 示例：hello_world 的 testcase
python zephyr\scripts\twister -T zephyr\samples\hello_world -p qemu_cortex_m3 --outdir twister-out-hello-world --inline-logs -v


# =========================================================
# 4. 跑指定 testcase 名称模板
# 当一个目录下有多个 testcase 时，用 -s 精确挑一个
# =========================================================
python zephyr\scripts\twister -T zephyr\<test_root> -s <testcase_name> -p <platform> --outdir <outdir> --inline-logs -v

# 示例：hello_world 指定 testcase
python zephyr\scripts\twister -T zephyr\samples\hello_world -s sample.basic.helloworld -p qemu_cortex_m3 --outdir twister-out-hello-world-one --inline-logs -v


# =========================================================
# 5. 只验证“能否编过”，不真正运行
# =========================================================
python zephyr\scripts\twister -T zephyr\<test_path> -p <platform> --outdir <outdir> --build-only --inline-logs -v

# 示例
python zephyr\scripts\twister -T zephyr\tests\kernel\common -p qemu_cortex_m3 --outdir twister-out-kernel-common-buildonly --build-only --inline-logs -v


# =========================================================
# 6. 最小 west update 模板
# 缺模块时按需补，不做 full west update
# =========================================================
python -m west update -n <project_name>

# 常见示例
python -m west update -n cmsis
python -m west update -n mbedtls
python -m west update -n mcuboot
python -m west update -n hal_stm32
python -m west update -n hal_nordic
python -m west update -n tinycrypt


# =========================================================
# 7. 真的需要全量同步时才用
# =========================================================
python -m west update


# =========================================================
# 8. 常用排查命令
# =========================================================
python -m west topdir
python -m west list zephyr
python -m west boards | Select-String qemu
```

## 每类命令在做什么

- `conda activate zephyr-dev`
  - 进入当前项目使用的 Python / west / cmake 环境。
- `$env:ZEPHYR_BASE=...`
  - 告诉 `find_package(Zephyr)` 去哪里找 Zephyr 基座。
- `$env:ZEPHYR_SDK_INSTALL_DIR=...`
  - 告诉构建系统去哪里找 SDK、toolchain 和 host tools。
- `python -m west update -n <project>`
  - 最小化同步 west 项目，只补当前缺少的模块。
- `python -m west build ...`
  - 走标准 Zephyr 构建链，适合 sample / app。
- `python -m west build -t run`
  - 运行当前 build 目录对应的仿真目标。
- `python zephyr\scripts\twister ...`
  - 走测试框架，适合 `tests/` 或带 `tests.yaml` 的 sample。
- `--build-only`
  - 只做配置与编译，不真正运行。

## 参数速记

- `-b <board>`
  - 目标板名，例如 `qemu_cortex_m3`
- `-d <build_dir>`
  - 构建输出目录，建议始终独立命名
- `-T <path>`
  - Twister 的测试根路径
- `-p <platform>`
  - Twister 的平台名，通常与 board 对应
- `-s <testcase_name>`
  - 指定 testcase 名称
- `--outdir <dir>`
  - Twister 输出目录
- `-p always`
  - `west build` 的 pristine 方式，每次先清理旧配置

## 推荐命名方式

- sample 构建目录：
  - `build-<board>-<sample>`
- Twister 输出目录：
  - `twister-out-<platform>-<test>`

示例：

- `build-qemu_cortex_m3-hello_world`
- `twister-out-qemu_cortex_m3-kernel-common`

这样做的好处是：

- 避免不同源码树共用默认 `build/`
- 避免不同板子、不同 sample、不同测试互相污染
- 出错时更容易从目录名直接看出上下文

## 最小 update 对照表

- `hello_world` / `qemu_cortex_m3`
  - 常见先试：`cmsis`
- 涉及加密或 TLS
  - 常见先试：`mbedtls`、`tinycrypt`
- 涉及 MCUboot
  - 常见先试：`mcuboot`
- 涉及厂商 HAL
  - STM32：`hal_stm32`
  - Nordic：`hal_nordic`

注意：

- 这只是常用经验表，不是完整依赖求解。
- 如果仍然提示缺模块，再按报错继续补指定 project。
- 实在不确定时，最后再执行全量 `python -m west update`。

## 推荐使用顺序

1. 先做环境初始化
2. 优先执行最小 `west update -n <project>`
3. 先用 `west build` 或 `twister --build-only` 验证能否编过
4. 编译通过后再执行 `run` 或完整 Twister 运行

## 指定目标板后系统如何选择配置和源码

下面以 `-b qemu_cortex_m3` 为例，说明 Zephyr 是如何根据板名决定：

- 用哪个板目录
- 合入哪些默认 Kconfig
- 选择哪个 SoC
- 使用哪个 DTS
- 最终编译哪些目录和源文件

### 1. `west build -b qemu_cortex_m3 ...` 先把 `BOARD=qemu_cortex_m3` 传给 CMake

你在命令行里写：

```powershell
python -m west build -p always -b qemu_cortex_m3 zephyr\samples\hello_world -d build-qemu_cortex_m3-hello_world
```

这一步的意义不是“直接编译 qemu_cortex_m3”，而是先把 `BOARD` 这个高层输入传进 Zephyr 的 CMake 配置流程。

### 2. `boards.cmake` 根据板名找到板目录

Zephyr 在 `cmake/modules/boards.cmake` 中通过 `--board=${BOARD}` 查询板信息，并把结果拆成：

- `BOARD_DIR`
- `BOARD_DIRECTORIES`
- board name / qualifiers / revisions / socs

对 `qemu_cortex_m3`，当前结果可以在构建输出里看到：

- `board.name = qemu_cortex_m3`
- `board.path = boards/qemu/cortex_m3`
- `board.qualifiers = ti_lm3s6965`

也就是这块板最终定位到：

- `boards/qemu/cortex_m3`

### 3. board 元数据声明了它绑定的 SoC

`boards/qemu/cortex_m3/board.yml` 里写明：

- board 名称：`qemu_cortex_m3`
- SoC：`ti_lm3s6965`

这一步提供的是“板到 SoC”的硬件模型关系。

### 4. board Kconfig 再显式选择 SoC 符号

`boards/qemu/cortex_m3/Kconfig.qemu_cortex_m3` 中：

- `config BOARD_QEMU_CORTEX_M3`
- `select SOC_TI_LM3S6965`

也就是说，当板符号 `BOARD_QEMU_CORTEX_M3` 生效时，SoC 符号 `SOC_TI_LM3S6965` 也会被拉起。

这一步很关键，因为后续：

- `soc/` 目录选择
- 架构能力选择
- 某些驱动和默认值

都会继续依赖这些 `CONFIG_SOC_*` / `CONFIG_BOARD_*` 符号。

### 5. board defconfig 会并入最终 `.config`

`boards/qemu/cortex_m3/qemu_cortex_m3_defconfig` 会和应用自己的 `prj.conf` 一起并入 Kconfig。

当前 `hello_world` 构建里，`build_info.yml` 已经记录了这次真正并入的 Kconfig 文件：

- `boards/qemu/cortex_m3/qemu_cortex_m3_defconfig`
- `samples/hello_world/prj.conf`

所以板子不仅决定“选谁”，还决定“默认开哪些配置”。

例如这个 defconfig 里会打开：

- `CONFIG_CONSOLE=y`
- `CONFIG_UART_CONSOLE=y`
- `CONFIG_SERIAL=y`

这些配置会继续影响后面哪些驱动目录会进入编译。

### 6. board DTS 会成为当前板的硬件描述入口

`boards/qemu/cortex_m3/qemu_cortex_m3.dts` 是当前板的 DTS 入口。

它会：

- `#include <ti/lm3s6965.dtsi>`
- 声明当前板的 `model` 和 `compatible`
- 在 `chosen` 节点里指定：
  - `zephyr,sram`
  - `zephyr,flash`
  - `zephyr,console`
  - `zephyr,shell-uart`
- 把 `uart0`、`uart1`、`eth`、多个 `gpio` 节点置为 `"okay"`

这意味着它不仅告诉系统“这是什么板”，还告诉系统：

- 控制台走哪个 UART
- 哪些设备存在
- 哪些设备启用
- SRAM/FLASH 的 chosen 节点是谁

这些信息会继续影响：

- 生成的 devicetree 头文件
- 某些 Kconfig 默认值
- 驱动实例化与设备初始化

### 7. SoC 目录和 SoC 源码随后被选中

当 `SOC_TI_LM3S6965` 生效后，Zephyr 会把 SoC 目录切到：

- `soc/ti/lm3s6965`

这个目录下的 `CMakeLists.txt` 会把 SoC 源码加入构建，例如：

- `soc_config.c`
- `reboot.S`
- `sys_arch_reboot.c`

并设置 ARM Cortex-M 对应的 SoC linker script。

所以板名并不是直接决定某几个 `.c` 文件，而是通过：

- board -> SoC -> arch / drivers / linker script

这条链间接决定编译内容。

### 8. `board.cmake` 决定运行器和仿真参数

`boards/qemu/cortex_m3/board.cmake` 中定义了：

- `SUPPORTED_EMU_PLATFORMS qemu`
- `QEMU_CPU_TYPE_${ARCH} cortex-m3`
- `-machine lm3s6965evb`

这部分不直接决定“编译哪些 C 文件”，但会决定：

- `west build -t run` 用哪个模拟器
- QEMU 以什么 CPU / machine 参数启动

所以它更多属于“运行阶段配置”。

### 9. 最终进入编译的是“由 board + SoC + DTS + Kconfig 共同筛出来的目录和源码”

以当前 `hello_world + qemu_cortex_m3` 为例，build 目录已经记录了：

- board：`qemu_cortex_m3`
- qualifiers：`ti_lm3s6965`
- DTS：`boards/qemu/cortex_m3/qemu_cortex_m3.dts`
- Kconfig：`qemu_cortex_m3_defconfig + prj.conf`

在这组输入下，Zephyr 会进一步决定：

- 当前架构走 ARM / Cortex-M
- 当前 SoC 走 `soc/ti/lm3s6965`
- 串口、控制台、定时器、GPIO、网络等对应驱动是否进入构建
- 最终链接脚本和中间生成文件如何产生

所以你可以把 `-b qemu_cortex_m3` 理解成一个“高层选择器”：

```text
BOARD=qemu_cortex_m3
  -> 找到 boards/qemu/cortex_m3
  -> 合入 qemu_cortex_m3_defconfig
  -> 读取 qemu_cortex_m3.dts
  -> 选择 SOC_TI_LM3S6965
  -> 定位 soc/ti/lm3s6965
  -> 影响 arch / drivers / linker / run target
  -> 最终筛出这次真正要编译和链接的文件集合
```

## 常用最小命令

### 构建 hello_world

```powershell
conda activate zephyr-dev
cd C:\Workspace\3-Code\Private\zephyr-workspace
$env:ZEPHYR_BASE = "C:\Workspace\3-Code\Private\zephyr-workspace\zephyr"
$env:ZEPHYR_SDK_INSTALL_DIR = "C:\Workspace\4-Plugin\zephyr-sdk"
python -m west update -n cmsis
python -m west build -p always -b qemu_cortex_m3 zephyr\samples\hello_world -d build-qemu_cortex_m3-hello_world
```

### 跑一个测试目录

```powershell
conda activate zephyr-dev
cd C:\Workspace\3-Code\Private\zephyr-workspace
$env:ZEPHYR_BASE = "C:\Workspace\3-Code\Private\zephyr-workspace\zephyr"
$env:ZEPHYR_SDK_INSTALL_DIR = "C:\Workspace\4-Plugin\zephyr-sdk"
python zephyr\scripts\twister -T zephyr\tests\kernel\common -p qemu_cortex_m3 --outdir twister-out-kernel-common --inline-logs -v
```
