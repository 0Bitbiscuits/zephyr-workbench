# West 使用说明

本文档说明当前 Zephyr 工作区中 West 的定位、工作区管理、项目同步、目标板查询、构建及常用排错方法。

文档基于当前本地环境验证：

- West：`1.5.0`
- conda 环境：`zephyr-dev`
- workspace：`C:\Workspace\3-Code\Private\zephyr-workspace`
- Zephyr：`C:\Workspace\3-Code\Private\zephyr-workspace\zephyr`
- Zephyr SDK：`C:\Workspace\4-Plugin\zephyr-sdk`

以下命令均使用 PowerShell。推荐使用 `python -m west`，确保调用的是当前 conda 环境中的 West。

## 1. West 是什么

West 是 Zephyr 的多仓库管理和命令扩展工具，主要承担两类职责：

1. 管理 workspace、manifest 和外部项目。
2. 加载 Zephyr 提供的 `boards`、`build`、`flash`、`debug`、`twister` 等扩展命令。

一个典型 workspace 如下：

```text
zephyr-workspace/
├── .west/                 # workspace 元数据和本地配置
├── zephyr/                # manifest repository，包含 west.yml
├── modules/               # west 管理的外部项目
├── bootloader/
└── tools/
```

核心概念：

- **workspace**：包含 `.west/` 的目录；所有项目路径都相对于它。
- **manifest**：描述项目、版本、URL、分组和导入关系的 YAML。
- **manifest repository**：保存顶层 manifest 的仓库；当前是 `zephyr/`。
- **project**：manifest 管理的一个 Git 仓库，例如 `cmsis`、`hal_stm32`。
- **extension command**：由 Zephyr 等项目提供的 West 子命令，例如 `west boards`。

## 2. 环境初始化

每次打开新 shell 后执行：

```powershell
conda activate zephyr-dev
cd C:\Workspace\3-Code\Private\zephyr-workspace

$env:ZEPHYR_BASE = "C:\Workspace\3-Code\Private\zephyr-workspace\zephyr"
$env:ZEPHYR_SDK_INSTALL_DIR = "C:\Workspace\4-Plugin\zephyr-sdk"

python -m west --version
python -m west topdir
python -m west list zephyr
python --version
cmake --version
```

预期 `west topdir` 输出：

```text
C:\Workspace\3-Code\Private\zephyr-workspace
```

`ZEPHYR_BASE` 通常可以由 manifest project 自动定位；显式设置它有利于脚本和独立 CMake 调用保持一致。

## 3. 命令帮助与全局参数

```powershell
# 查看全部可用命令
python -m west --help

# 查看某个子命令的帮助
python -m west boards --help
python -m west build --help
python -m west update --help

# 等价写法
python -m west help build
```

常用全局参数：

| 参数 | 作用 |
|---|---|
| `-h`, `--help` | 显示帮助 |
| `-V`, `--version` | 显示 West 版本 |
| `-v`, `--verbose` | 增加日志，可重复使用，如 `-vv` |
| `-q`, `--quiet` | 减少日志，可重复使用 |
| `-z <path>`, `--zephyr-base <path>` | 临时覆盖 Zephyr base 目录 |

短选项由各子命令独立定义。例如 `update -n` 表示 narrow fetch，而 `build -n` 表示只打印构建命令，不能脱离子命令解释。

## 4. 查看 workspace 和 manifest

### 4.1 定位 workspace

```powershell
python -m west topdir
python -m west manifest --path
python -m west manifest --validate
```

- `topdir`：打印 `.west/` 所在的 workspace 根目录。
- `manifest --path`：打印顶层 manifest 文件路径。
- `manifest --validate`：验证当前 manifest 能否正确解析。

查看合并所有 import 后的 manifest：

```powershell
python -m west manifest --resolve
python -m west manifest --resolve -o resolved-west.yml
```

生成固定到当前 SHA 的 manifest：

```powershell
python -m west manifest --freeze -o frozen-west.yml
```

`--freeze` 适合记录可复现版本，不应用它直接覆盖正在维护的 `west.yml`。

### 4.2 查看项目

```powershell
# 查看 active projects
python -m west list

# 查看指定项目
python -m west list zephyr cmsis

# 包含 inactive projects
python -m west list --all

# 只看 inactive projects
python -m west list --inactive

# 自定义输出
python -m west list -f '{name} | {path} | {revision} | {cloned} | {active}'
```

常用格式字段包括 `name`、`path`、`abspath`、`url`、`revision`、`sha`、`cloned`、`active` 和 `groups`。

### 4.3 查看多仓库状态

```powershell
# 对所有 active 且已克隆项目执行 git status
python -m west status

# 查看相对 manifest-rev 的差异
python -m west diff --manifest

# 检查 HEAD、分支或工作区是否偏离最近一次 west update
python -m west compare

# 有差异时返回非零退出码，适合脚本
python -m west compare --exit-code
```

对多个项目运行同一条命令：

```powershell
python -m west forall -c "git rev-parse --short HEAD"
python -m west forall -g hal -c "git status --short"
```

`forall` 会调用 shell，应注意参数引用和命令本身的副作用。

## 5. 初始化和更新 workspace

当前 workspace 已经初始化，不需要再次执行 `west init`。创建新 workspace 时才使用：

```powershell
# 从远端 manifest repository 创建
python -m west init -m <manifest-url> <workspace-dir>

# 围绕已有本地 Zephyr 仓库创建
python -m west init -l <local-zephyr-dir>
```

### 5.1 更新项目

```powershell
# 更新全部 active projects
python -m west update

# 只更新一个或多个项目；项目名是位置参数
python -m west update cmsis
python -m west update cmsis hal_stm32

# 查询项目名后再更新
python -m west list --all | Select-String 'cmsis|stm32'
```

`west update` 会把项目更新到 manifest 指定的 revision，默认通常以 detached HEAD 检出；它不会修改 manifest repository 自身的内容。

常用参数：

| 参数 | 作用 |
|---|---|
| `<PROJECT ...>` | 按名称或路径指定项目；省略时更新全部 active projects |
| `-n`, `--narrow` | fetch 时只取目标 revision，并且不取 tags；不是“指定项目” |
| `-f smart` | 默认策略，本地已有 SHA 或 tag 时尽量不 fetch |
| `-f always` | 每个项目更新前都 fetch |
| `-o <option>` | 向 `git fetch` 追加参数，可重复使用 |
| `-k`, `--keep-descendants` | 当前分支是新 revision 后代时保留该分支 |
| `-r`, `--rebase` | 将当前分支 rebase 到新的 manifest revision |
| `--group-filter <filter>` | 临时追加项目分组过滤条件 |
| `--name-cache`, `--path-cache`, `--auto-cache` | 从本地 Git 缓存初始化项目 |

最小同步的正确写法：

```powershell
# 只更新 cmsis
python -m west update cmsis

# 只更新 cmsis，并采用 narrow fetch
python -m west update --narrow cmsis
```

执行大范围更新前建议先运行 `west status` 和 `west compare`，确认各项目是否存在本地分支或未提交修改。

## 6. 查询支持的 boards

`west boards` 会扫描：

- Zephyr 自身的 board roots。
- 当前 manifest modules 声明的额外 board roots。

因此它比手工遍历 `zephyr/boards/` 更接近当前 workspace 的完整支持范围。

### 6.1 Board 名称与完整 target

```powershell
# 每行输出一个 board 名称
python -m west boards

# 输出所有可直接传给 west build -b 的完整 target
python -m west boards --all-targets
python -m west boards -a
```

Board V2 中，一个 board 可以具有 revision 和 qualifier。完整 target 通常形如：

```text
<board>@<revision>/<qualifier>
```

没有 revision 时常见形式为：

```text
native_sim/native/64
qemu_cortex_m3/ti_lm3s6965
qemu_riscv32/qemu_virt_riscv32
```

实际构建前优先查询 `boards -a`，不要仅根据目录名猜测 `-b` 参数。

### 6.2 过滤 QEMU 相关 BSP

查看可构建的 QEMU targets：

```powershell
python -m west boards -a | Select-String '^qemu_'
```

同时查看 QEMU 和 native simulator：

```powershell
python -m west boards -a | Select-String '^(qemu_|native_sim)'
```

按 board 名称正则过滤，并显示说明：

```powershell
python -m west boards -n '^qemu_' `
  -f '{name} | {full_name} | {vendor} | {qualifiers}'
```

只看 Cortex-M 相关 QEMU board：

```powershell
python -m west boards -n '^qemu_cortex_m' `
  -f '{name} | {full_name} | {qualifiers}'
```

### 6.3 boards 参数

| 参数 | 作用 |
|---|---|
| `-a`, `--all-targets` | 展开 revision 和 qualifier，输出所有合法构建 target |
| `-n <regex>`, `--name <regex>` | 用 Python 正则匹配 board 名称 |
| `-f <format>`, `--format <format>` | 自定义每块 board 的输出格式 |
| `--board <name>` | 精确查询指定 board |
| `--fuzzy-match <name>` | 查找名称相近的 board |
| `--board-dir <dir>` | 只在指定 board 目录查询 |
| `--board-root <dir>` | 增加 board root，可重复使用 |
| `--arch-root`, `--soc-root` | 增加架构或 SoC root，通常用于外部硬件树 |

`--format` 支持以下主要字段：

| 字段 | 含义 |
|---|---|
| `{name}` | board 名称 |
| `{full_name}` | 完整或商业名称 |
| `{vendor}` | vendor |
| `{revision_default}` | 默认 revision |
| `{revisions}` | revision 列表 |
| `{qualifiers}` | qualifier 列表 |
| `{dir}` | board 定义目录 |

查看单块 board 的详细信息：

```powershell
python -m west boards --board qemu_cortex_m3 `
  -f '{name} | {full_name} | {vendor} | {revisions} | {qualifiers} | {dir}'
```

Board target 选择配置和源码的简化链路：

```text
west build -b <target>
  -> 解析 board.yml 中的 board、revision 和 SoC qualifier
  -> 合入 board defconfig 和应用 prj.conf
  -> 读取 board DTS 及 SoC DTSI
  -> 选择 SoC、架构、驱动和链接配置
  -> 生成最终配置并编译
```

## 7. 构建应用

基本语法：

```powershell
python -m west build [options] <source_dir> -- [cmake_options]
```

构建 `hello_world`：

```powershell
python -m west build -p always `
  -b qemu_cortex_m3/ti_lm3s6965 `
  zephyr\samples\hello_world `
  -d build-qemu-cortex-m3-hello-world
```

常用参数：

| 参数 | 作用 |
|---|---|
| `-b <target>`, `--board <target>` | 指定 board target，可带 revision 和 qualifier |
| `-d <dir>`, `--build-dir <dir>` | 指定构建目录 |
| `-p auto` | West 判断是否需要 pristine，适合日常增量构建 |
| `-p always` | 每次清理指定构建目录后重新配置 |
| `-p never` | 禁止自动 pristine |
| `-c`, `--cmake` | 强制重新运行 CMake |
| `--cmake-only` | 只配置，不执行编译 |
| `-t <target>` | 执行构建系统 target，例如 `run`、`menuconfig`、`clean` |
| `-n`, `--dry-run` | 只打印将执行的构建命令 |
| `-o <option>` | 向 Ninja 或 Make 传递参数，可重复使用 |
| `-S <snippet>` | 添加 snippet，可重复使用 |
| `--shield <shield>` | 添加 shield，可重复使用 |
| `--extra-conf <file>` | 合入额外 Kconfig `.conf` 文件，可重复使用 |
| `--extra-dtc-overlay <file>` | 合入额外 Devicetree overlay，可重复使用 |
| `--sysbuild`, `--no-sysbuild` | 启用或禁用 multi-domain sysbuild |
| `--domain <name>` | 只对指定 sysbuild domain 执行构建 target |
| `-- <cmake options>` | 将后续参数直接传给 CMake |

常见后续操作：

```powershell
# 增量构建
python -m west build -d build-qemu-cortex-m3-hello-world

# 运行模拟器
python -m west build -d build-qemu-cortex-m3-hello-world -t run

# 打开 Kconfig 菜单
python -m west build -d build-qemu-cortex-m3-hello-world -t menuconfig

# 仅重新执行 CMake
python -m west build -d build-qemu-cortex-m3-hello-world --cmake-only

# 查看构建系统提供的 targets
python -m west build -d build-qemu-cortex-m3-hello-world -t usage
```

切换 board、SDK、重要 overlay 或基础配置后，建议使用新的构建目录，或者明确执行 `-p always`。

## 8. Flash、调试和运行器

```powershell
# 烧写默认构建目录
python -m west flash

# 烧写指定构建目录
python -m west flash -d <build-dir>

# 查看当前构建支持的 runner 及其参数
python -m west flash -d <build-dir> --context

# 指定 runner
python -m west flash -d <build-dir> -r <runner>

# 启动调试
python -m west debug -d <build-dir>

# 启动调试服务器
python -m west debugserver -d <build-dir>
```

runner 的附加参数不是固定的，应先运行 `west flash --context` 或对应命令的 `--help`。

对于支持模拟运行的 board，也可以使用：

```powershell
python -m west build -d <build-dir> -t run
```

## 9. Twister 测试入口

West 提供 `twister` 扩展命令：

```powershell
python -m west twister -T zephyr\tests\kernel\common `
  -p qemu_cortex_m3/ti_lm3s6965 `
  --outdir twister-out-kernel-common `
  --inline-logs -v
```

只编译、不运行：

```powershell
python -m west twister -T zephyr\tests\kernel\common `
  -p qemu_cortex_m3/ti_lm3s6965 `
  --outdir twister-out-kernel-common-build-only `
  --build-only --inline-logs -v
```

如果加载 `west twister` 时提示缺少 `natsort` 等模块，安装 Zephyr 的测试依赖：

```powershell
python -m pip install -r zephyr\scripts\requirements-base.txt
python -m pip install -r zephyr\scripts\requirements-run-test.txt
```

## 10. West 配置

West 配置分为 system、global 和 local 三层，local 优先级最高。当前 workspace 的 local 配置位于 `.west/config`。

```powershell
# 查看合并后的配置
python -m west config --list

# 读取配置
python -m west config manifest.path

# 写入当前 workspace 的本地配置
python -m west config --local <section.key> <value>

# 写入用户级配置
python -m west config --global <section.key> <value>

# 删除本地或首先命中的配置
python -m west config --delete <section.key>
```

修改配置前先使用 `west config <section.key>` 确认当前值及用途，不建议在文档中预设大量全局配置。

## 11. 常见问题

### shell 找不到 `west`

优先确认 conda 环境，并使用模块调用：

```powershell
conda activate zephyr-dev
python -m west --version
```

### 提示不在 West workspace 中

```powershell
cd C:\Workspace\3-Code\Private\zephyr-workspace
python -m west topdir
```

### 找不到 `boards` 或 `build` 命令

这些是 Zephyr extension commands。检查 manifest project 和 Zephyr base：

```powershell
python -m west list zephyr
python -m west manifest --path
python -m west -z C:\Workspace\3-Code\Private\zephyr-workspace\zephyr boards --help
```

### 提示 unknown board 或 target

```powershell
python -m west boards -a | Select-String '<关键字>'
python -m west boards --fuzzy-match '<近似名称>'
```

复制 `boards -a` 输出的完整 target，并在切换 target 后使用新构建目录或 `-p always`。

### 缺少模块

```powershell
python -m west list --all | Select-String '<project>'
python -m west update <project>
```

不要把 `-n` 当作项目选择参数；需要 narrow fetch 时才额外添加 `--narrow`。

### 构建目录配置冲突

不同 board、sample 和测试使用独立目录：

```text
build-<board>-<sample>
twister-out-<platform>-<test>
```

无法确认旧缓存是否兼容时，对明确的构建目录执行 `west build -p always ...`。

## 12. 常用命令速查

```powershell
conda activate zephyr-dev
cd C:\Workspace\3-Code\Private\zephyr-workspace

python -m west topdir
python -m west list
python -m west status
python -m west compare
python -m west manifest --validate

python -m west boards
python -m west boards -a
python -m west boards -a | Select-String '^qemu_'

python -m west update cmsis

python -m west build -p always `
  -b qemu_cortex_m3/ti_lm3s6965 `
  zephyr\samples\hello_world `
  -d build-qemu-cortex-m3-hello-world

python -m west build -d build-qemu-cortex-m3-hello-world -t run
```
