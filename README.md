# DiskPulse

轻量的 Mac 菜单栏磁盘用量日记。每小时记录启动磁盘的已用、可用和总容量，点击菜单栏容量环查看变化。

原生 Swift 6、SwiftUI、Swift Charts、系统 SQLite；没有第三方依赖、后台服务器或联网请求。支持 macOS 14 及以上，构建产物对应构建机器的 CPU 架构。

## 安装与使用

双击项目中的 `Install.command`，自动安装到 `~/Applications/DiskPulse.app` 并启动。已有 `dist/DiskPulse.app` 时直接安装；首次从源码安装需要 Xcode Command Line Tools 及 Swift 6。也可将已构建的 `.app` 拖进“应用程序”后双击打开。

菜单栏会出现容量环和已用比例。点击可查看当前容量、24 小时／7 天／30 天趋势；面板提供“记录一次”“暂停”，以及偏好设置中的 CSV 导出、记录文件夹和登录启动开关。

首次启动立即记录，之后在每个本地整点附近自动记录。建议在偏好设置开启“登录后自动启动”，重启登录后即可继续积累；该选项默认关闭，注册状态以系统实际反馈为准。

读取容量无需管理员密码、完全磁盘访问、辅助功能或屏幕录制权限。登录启动使用 macOS 自带的登录项，个别系统会要求在“系统设置 → 通用 → 登录项”中允许。

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

```bash
./scripts/build.sh
./scripts/test.sh
./dist/DiskPulse.app/Contents/MacOS/DiskPulse --read
```

构建输出为 `dist/DiskPulse.app` 和 `dist/DiskPulse-macOS.zip`。构建脚本使用本地临时签名；该版本适合本机安装，尚未做 Developer ID 签名及 Apple 公证。分发到另一台 Mac 时，下载文件可能被 Gatekeeper 拦截，正式对外分发前应增加签名、公证和按架构发布。

无需打开界面即可检查采样与持久化，测试目录可自行指定：

```bash
./dist/DiskPulse.app/Contents/MacOS/DiskPulse --sample --data-dir /tmp/DiskPulse-check
./dist/DiskPulse.app/Contents/MacOS/DiskPulse --history --data-dir /tmp/DiskPulse-check
```

`--read` 只读取当前容量，不创建记录。`--sample` 记录真实容量；`--history` 输出 CSV。应用的定时器随菜单栏进程运行，不安装守护进程，也不唤醒休眠中的 Mac。

## 项目状态

当前版本为 0.1.0，本文件是项目当前状态入口。功能覆盖小时采样、本地持久化、容量趋势、菜单栏短动画、暂停与手动记录、CSV 导出、可选登录启动和应用打包。

2026-10-27 已通过 release 构建、8 项核心测试、应用签名校验、本机真实采样／小时去重／CSV 读回和数据库完整性检查；安装后的菜单栏进程已写入首条真实记录。实测环境为 Apple Silicon、macOS 27.0.1、Swift 6.4。应用约 736 KB，ZIP 约 255 KB；启动后的单次空闲抽样约 27 MB 常驻内存，不能视为长期性能测量。

未做界面验收，界面由用户手动检查。登录启动及跨休眠、跨整点的长期行为需在实际使用中观察；核心时间边界和持久化逻辑已通过测试。当前仓库为本地项目，尚未配置 GitHub 远端或发布版本。

## 系统接口依据

- [Apple：卷的可用容量](https://developer.apple.com/documentation/foundation/urlresourcekey/volumeavailablecapacitykey)
- [Apple：主应用登录启动](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp)
- [Apple：隐私清单的 API 使用理由](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)
