# MyChuannong Server Auth

macOS 本机服务器认证辅助程序的 Swift 源码与应用包配置。需要 Xcode Command Line Tools，运行 `./build.sh` 可在 `build/` 重建应用。脚本只构建并对本机应用做 ad-hoc 签名，不安装、不启动、不读取 Keychain、不连接服务器。

程序通过既有本机 Keychain 项和 SSH 配置工作。用户需在本机配置自己的环境；源码仓库不包含密码、Keychain 内容、认证 metadata.json、SSH 私钥或任何服务器运行资料。现有已安装应用及其已保存凭据不因源码归档而改动。

实际使用时遵守已有授权范围：先运行 `status`；缺少凭据由本人在应用中填写。`run COMMAND ARGS...` 只用于已经获准的服务器操作。拥有本工具源码不等于获准执行服务器操作。
