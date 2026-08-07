# 安装 Zephyr SDK（假设安装到 C:\zephyr-sdk）
# 下载地址参考：https://github.com/zephyrproject-rtos/sdk-ng/releases
# 安装后设置环境变量：
$env:ZEPHYR_SDK_INSTALL_DIR = "C:\zephyr-sdk"

# 初始化 Zephyr workspace（如果当前目录还没做 west init）
# cd 到 workspace 父目录后：
# west init -l c:\Workspace\3-Code\Private\zephyr
# west update