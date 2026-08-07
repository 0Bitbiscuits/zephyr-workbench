# 1. 创建 conda 环境（Python 3.12，与 Zephyr uv 编译版本对齐）
conda create -n zephyr-dev python=3.12 -y

# 2. 激活环境
conda activate zephyr-dev

# 3. 安装构建工具（cmake、ninja、dtc 通过 conda-forge 安装）
conda install -c conda-forge cmake ninja dtc -y

# 4. 安装 Zephyr 基础 Python 依赖（含 west）
pip install -r c:\Workspace\3-Code\Private\zephyr\scripts\requirements-base.txt

# 5. 验证
west --version
cmake --version
ninja --version