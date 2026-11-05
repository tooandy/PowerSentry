# PowerSentry

**[简体中文](README.zh-CN.md) | [English](README.md)**

[![CI](https://github.com/tooandy/PowerSentry/actions/workflows/ci.yml/badge.svg)](https://github.com/tooandy/PowerSentry/actions/workflows/ci.yml)
[![Latest Release](https://img.shields.io/github/v/release/tooandy/PowerSentry)](https://github.com/tooandy/PowerSentry/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**一款完全在本机运行的 macOS 电源诊断与异常监控工具。**

PowerSentry 常驻 macOS 菜单栏，通过观察电池遥测、进程资源占用、网络吞吐和睡眠 / 唤醒活动，帮助定位 Mac 的耗电来源。它会学习个人功耗基线并报告持续异常，但不会自动结束进程，也不会上传遥测数据。

> **当前发行目标：** Apple Silicon（arm64），macOS 14 或更高版本。应用界面支持 9 种语言，会自动跟随 macOS 首选语言。公开发行包使用 Ad-hoc 签名，未经 Apple 公证。

## 功能特性

- **菜单栏监控：** 显示电池电量、实时放电功率，以及预计降至 20% 电量的剩余时间。
- **个人功耗基线：** 从稳定、低负载的电池供电样本中学习个人基线。
- **异常检测：** 检测整机功耗持续异常、进程 CPU 长时间过高、进程大量下载，以及频繁 DarkWake。
- **进程诊断：** 查看各进程 CPU 和内存排行。
- **网络诊断：** 基于 macOS nettop 累计计数器差分，查看各进程下载和上传吞吐。
- **睡眠与唤醒诊断：** 读取 pmset 最近电源事件和当前电源断言。
- **本地历史：** 使用 SQLite 保存遥测和异常事件，采样数据保留最近 7 天。
- **本地通知：** 通过 macOS 通知提醒新发现的异常。
- **九语言界面：** 支持英文、简体中文、繁体中文、西班牙语、韩语、日语、德语、法语和荷兰语，自动跟随 macOS 首选语言。
- **纯菜单栏生命周期：** 不显示 Dock 图标或 Cmd+Tab 项目；关闭仪表盘后监控仍会继续运行。

## 下载与安装

1. 打开 [GitHub Releases](https://github.com/tooandy/PowerSentry/releases)。
2. 下载最新的 PowerSentry-*-arm64.dmg 或 PowerSentry-*-arm64.zip。
3. 将 PowerSentry.app 移动到 /Applications 或 ~/Applications。
4. 公开发行包**没有使用 Apple Developer ID 签名，也未经 Apple 公证**。如果 Gatekeeper 阻止首次启动，可以在 Finder 中按住 Control 键点击应用并选择“打开”，或前往“系统设置 → 隐私与安全性”查看针对该应用的允许选项。具体提示会因 macOS 版本而异。

PowerSentry 不会要求用户全局关闭 Gatekeeper。请只安装你信任的构建版本；源码和构建工作流均公开可供检查。

## 语言设置

PowerSentry 当前完整支持以下 9 种界面语言：

- 英文（en）
- 简体中文（zh-Hans）
- 繁体中文（zh-Hant）
- 西班牙语（es）
- 韩语（ko）
- 日语（ja）
- 德语（de）
- 法语（fr）
- 荷兰语（nl）

应用会自动跟随 macOS 首选语言；其他语言会回退到英文。修改语言后，请重新启动 PowerSentry。语言设置位于 **系统设置 → 通用 → 语言与地区**。

## 隐私与安全

- **仅本地存储：** 数据库位于 ~/Library/Application Support/PowerSentry/powersentry.sqlite。
- **不上传遥测：** 应用不包含云端服务、分析统计、远程监听端口或外发遥测。
- **仅读取网络计数器：** 使用 nettop 获取进程级字节计数；不捕获网络包载荷、消息内容，也不归因到单个远端地址。
- **结束进程必须明确审批：** PowerSentry 不会自动结束进程。用户选择终止高 CPU 进程时，应用会重新核验 PID、进程启动时间、可执行文件路径和当前 CPU 占用，然后只发送 SIGTERM，绝不会升级为 SIGKILL。
- **不安装特权辅助程序：** 不安装管理员权限的 helper，也不修改系统睡眠、VPN 或登录项设置。
- **系统通知：** 为本地异常提醒请求 macOS 通知权限。

进程和电源信息通过 macOS 系统接口及命令行遥测获取。受 macOS 或当前用户权限限制，部分进程详情可能无法读取。

## 采样与检测规则

| 信号 | 采样 / 判定规则 |
|---|---|
| 电池与进程 CPU / 内存 | 约每 10 秒采样 |
| 持久化遥测 | 每 30 秒一次；最多记录前 20 个进程和前 12 个网络进程 |
| 进程网络吞吐 | 约每 30 秒采样 |
| 电源断言与睡眠 / 唤醒事件 | 约每 60 秒采样 |
| 整机功耗异常 | 持续约 2 分钟高于 max(2.2 × 基线, 基线 + 2 W) |
| 进程 CPU 异常 | CPU 至少 85%，持续约 2 分钟 |
| 进程下载异常 | 两个独立网络采样周期均达到至少 1 MB/s |
| DarkWake 异常 | 10 分钟内至少发生 10 次 |

功耗基线从保守默认值开始，并根据稳定、低负载的电池供电样本逐步学习。剩余时间估算仅供参考，不能替代电池健康度检测。

## 从源码构建

环境要求：

- macOS 14 或更高版本
- Apple Swift 工具链 / Xcode Command Line Tools
- Swift 5.10 或更高版本
- 当前发行打包流程要求 Apple Silicon

    git clone https://github.com/tooandy/PowerSentry.git
    cd PowerSentry

    # 运行内置逻辑测试
    ./scripts/self-test.sh

    # 构建应用包、打包中英文资源并进行 Ad-hoc 签名
    ./scripts/build-app.sh

    # 启动应用
    open dist/PowerSentry.app

命令行遥测检查：

    swift run PowerSentry --diagnose

构建不需要 Apple Developer 会员资格、Developer ID 证书、签名 Secrets 或公证凭据。

## CI 与版本发布

GitHub Actions 已配置以下流程：

- **Pull Request 和推送到 main：** 校验应用元数据和本地化资源，编译应用、运行自测、验证应用包和 Ad-hoc 签名，并上传短期保留的 CI 构建产物。
- **版本 Tag（v*）：** 检查 Tag 是否与 CFBundleShortVersionString 一致，构建并测试应用，打包 ZIP 和 DMG，生成 SHA256SUMS，再使用仓库内的中英文发布记录自动创建 GitHub Release。

发布新版本的步骤：

1. 更新 Resources/Info.plist 中的 CFBundleShortVersionString。
2. 更新 CHANGELOG.md，并新增 .github/release-notes/vX.Y.Z.md，同时填写英文和简体中文发布记录。
3. 提交并推送到 main。
4. 创建并推送匹配的版本 Tag：

    git tag v0.2.0
    git push origin v0.2.0

Tag 版本必须与应用的 CFBundleShortVersionString 一致。Release 工作流会自动发布 ZIP、DMG 和校验文件。

## 当前限制

- 可以查看进程网络吞吐，但不会归因到具体远端地址。
- Mac 完全进入睡眠后，采样会暂停，直到 macOS 唤醒。
- 个人功耗基线需要数分钟正常使用数据才能初步可用；历史数据越长，基线越稳定。
- 暂未注册登录时自动启动。
- 当前公开发行包仅面向 Apple Silicon（arm64），暂不发布 Intel 版本。
- Ad-hoc 签名不等同于 Developer ID 签名。首次启动时 macOS 可能要求手动确认；替换应用后也可能要求重新确认通知权限。

## 许可证

MIT，详见 [LICENSE](LICENSE)。
