# DiskPulse

轻量的 Mac 菜单栏磁盘用量日记。每小时记录启动磁盘的已用、可用和总容量，点击菜单栏容量环查看变化。

源码仓库：[Mappedinfo/DiskPulse](https://github.com/Mappedinfo/DiskPulse)。

原生 Swift 6、SwiftUI、Swift Charts、系统 SQLite；没有第三方依赖、后台服务器或联网请求。支持 macOS 14 及以上，发布安装包同时包含 Apple Silicon 和 Intel 两种架构。

## 安装与使用

**[下载 DiskPulse 0.1.0 安装包](https://github.com/Mappedinfo/DiskPulse/releases/download/v0.1.0/DiskPulse-macOS-universal.zip)** · [查看所有版本](https://github.com/Mappedinfo/DiskPulse/releases)

系统要求：macOS 14 或更新版本，Apple Silicon／Intel Mac。下载上述 ZIP 即可安装，无需 Xcode、Swift、Homebrew 或自行编译。

1. 下载 `DiskPulse-macOS-universal.zip` 并双击解压。GitHub 自动生成的 `Source code` 是源码，不是安装包。
2. 将 `DiskPulse.app` 拖到“应用程序”；也可以放入个人目录 `~/Applications`。
3. 双击打开。应用出现在屏幕顶部菜单栏，不显示 Dock 图标或独立主窗口。
4. 点击菜单栏容量环。在“偏好设置”中可开启“登录后自动启动”。

### 首次打开

本版本使用本地临时签名，**尚未经过 Developer ID 签名和 Apple 公证**。macOS 首次打开时可能提示无法验证开发者。

如果你确认下载来自本仓库的 Release，可先尝试打开一次，再进入“系统设置 → 隐私与安全性”，按系统提示选择“仍要打开”。系统可能要求登录密码。这是针对该应用的一次性确认，具体步骤见 [Apple 官方说明](https://support.apple.com/zh-cn/102445)。

### 日常使用与升级

菜单栏会出现容量环和已用比例。点击可查看当前容量、24 小时／7 天／30 天趋势；面板提供“记录一次”“暂停”，以及偏好设置中的 CSV 导出、记录文件夹和登录启动开关。

首次启动立即记录，之后在每个本地整点附近自动记录。建议在偏好设置开启“登录后自动启动”，重启登录后即可继续积累；该选项默认关闭，注册状态以系统实际反馈为准。

读取容量无需管理员密码、完全磁盘访问、辅助功能或屏幕录制权限。登录启动使用 macOS 自带的登录项，个别系统会要求在“系统设置 → 通用 → 登录项”中允许。

升级时先在菜单栏面板点击“退出”，再用新版本替换原来的 `DiskPulse.app`。历史数据保存在应用目录之外，替换应用会保留记录。

## 记录规则

- 每小时一行；启动、唤醒或手动记录会更新本小时这一行。暂停期间仍可手动记录。
- 电脑关机、休眠或应用退出期间没有观测，历史保留空缺；唤醒后只记录当前小时，不推算遗漏的容量。
- 定时器允许系统延后约 20 秒执行以减少唤醒；写入失败会显示错误并在 5 分钟内重试。
- 已用容量 = 数据卷总容量 − 数据卷可用容量。使用十进制 GB／TB；APFS 共享空间、快照及可清除空间会影响数值，与“系统设置”的分类统计可能不同。
- 菜单栏小动画播放约 1 秒，仅在记录完成或打开面板时触发。可关闭；系统“减少动态效果”或低电量模式下跳过菜单栏动画。
- 历史长期保留，面板只加载最近 30 天；CSV 导出包含全部小时记录，时间使用 UTC，容量保留原始字节数。

数据存放在 `~/Library/Application Support/DiskPulse/history.sqlite`。容量 API 仅读取卷的元数据，不扫描目录或读取文件内容；应用不上传数据。

退出后可将应用移到废纸篓。卸载前先关闭应用内的登录启动；历史数据独立保留，需要时再自行删除上述 `DiskPulse` 数据目录。

## 开发

从源码构建需要 Xcode Command Line Tools 和 Swift 6。开发者可克隆仓库后构建：

```bash
git clone https://github.com/Mappedinfo/DiskPulse.git
cd DiskPulse
./scripts/build.sh
./scripts/test.sh
./dist/DiskPulse.app/Contents/MacOS/DiskPulse --read
```

默认生成当前机器架构的 `dist/DiskPulse.app` 和 `dist/DiskPulse-macOS-arm64.zip` 或 `dist/DiskPulse-macOS-x86_64.zip`。运行 `./Install.command` 可将构建结果安装到 `~/Applications`；没有构建结果时会先自动编译。

发布通用安装包：

```bash
./scripts/build.sh --universal
```

该命令分别编译 arm64、x86_64，再合并为同一个 `DiskPulse.app`，生成 `dist/DiskPulse-macOS-universal.zip`。安装包只包含应用本身；容量数据库、CSV 和构建缓存不进入安装包。

无需打开界面即可检查采样与持久化，测试目录可自行指定：

```bash
./dist/DiskPulse.app/Contents/MacOS/DiskPulse --sample --data-dir /tmp/DiskPulse-check
./dist/DiskPulse.app/Contents/MacOS/DiskPulse --history --data-dir /tmp/DiskPulse-check
```

`--read` 只读取当前容量，不创建记录。`--sample` 记录真实容量；`--history` 输出 CSV。应用的定时器随菜单栏进程运行，不安装守护进程，也不唤醒休眠中的 Mac。

## 项目状态

当前版本为 0.1.0。功能覆盖小时采样、本地持久化、容量趋势、菜单栏短动画、暂停与手动记录、CSV 导出、可选登录启动和应用打包。

2026-10-27 已通过 release 构建、8 项核心测试、应用签名校验、本机真实采样／小时去重／CSV 读回和数据库完整性检查；本机安装与首次自动记录也已验证。通用安装包包含 arm64 和 x86_64，解压后通过双架构签名校验、arm64 真实采样与 CSV 读回、Rosetta 下的 x86_64 容量读取。实测环境为 Apple Silicon、macOS 27.0.1、Swift 6.4；尚未在 Intel 实机或 macOS 14 上运行验证。

通用应用约 1.3 MB，ZIP 约 0.4 MB。初次 arm64 版本启动后的单次空闲抽样约 27 MB 常驻内存，不能视为长期性能测量。

尚未完成界面交互验收，以及登录启动、跨休眠、跨整点的长期运行验证；核心时间边界和持久化逻辑已通过测试。安装包通过 GitHub Release 分发，当前仍缺少 Developer ID 签名和 Apple 公证。

## 系统接口依据

- [Apple：卷的可用容量](https://developer.apple.com/documentation/foundation/urlresourcekey/volumeavailablecapacitykey)
- [Apple：主应用登录启动](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp)
- [Apple：隐私清单的 API 使用理由](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)
