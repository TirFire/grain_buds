# 🌾 小满日记 (GrainBuds) V1.2.0

> **“物致于此小得盈满，记录生活点滴的美好。”**
> 
> 小满日记是一款纯净、极简、支持多端无感同步的本地多媒体日记本。我们坚信**数据主权属于用户**，承诺 100% 本地离线存储，用最克制的设计，守护你每一颗闪念的种子。

[![Flutter Version](https://img.shields.io/badge/Flutter-3.x-blue.svg)](https://flutter.dev/)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20Windows%20%7C%20macOS-lightgrey.svg)]()
[![License](https://img.shields.io/badge/License-MIT-green.svg)]()

---

## 📥 下载与安装 (Releases)

**🎉 最新版本：V1.2.0 (手机端正式发布！)**

我们强烈推荐普通用户直接下载编译好的安装包：

* 👉 **[点击获取最新版 APK 及桌面端程序 (GitHub Releases)](https://github.com/TirFire/grain_buds/releases/latest)**

*(注：Android 用户请直接下载 `GrainBuds_V1.2.x.apk` 安装。从 V1.2.0 起，所有更新均支持无损覆盖安装。)*

---

## ✨ 核心特性

### 🔒 绝对的数据主权
* **本地优先**：所有日记文本、照片、视频均默认存储在设备的本地沙盒目录中，没有云端偷窥，没有隐私泄露。
* **AES-256 加密**：支持开启全局应用密码锁，配合底层加密算法，银行级守护你的私人领地。
* **数据随心带走**：支持将全部图文数据一键打包为 `.zip` 完整备份包，随时导出到电脑或网盘。

### ☁️ WebDAV 多端无感同步
* **跨设备漫游**：内置强大的 WebDAV 同步引擎，支持坚果云、Nextcloud 等标准协议。
* **智能双向对齐**：独创时间容差与“墓碑机制 (Tombstone)”，彻底解决多端数据冲突与误删复活问题。
* **无死角合并**：支持从 ZIP 备份包“智能增量合并”数据，新旧设备迁移就像搬家一样简单安全。

### 🎬 丝滑的富媒体记录
* **万物皆可记录**：不仅支持纯文本，更完美支持插入高清图片、本地视频、Live 图与音频，点开即播，告别卡顿。
* **极客打卡热力图**：内置类似 GitHub 的年度打卡热力图，让每天的坚持清晰可见。
* **高颜值的分享**：支持一键生成带有日历水印的长图海报，或无损导出为 PDF / Markdown 格式。

### 🎨 沉浸式视觉体验
* **莫兰迪美学**：内置 8 种精美的莫兰迪高级强调色，随心定义你的界面。
* **日夜交替**：完美适配 Android 12+ 原生启动页，支持深色模式 (Dark Mode) 与纸张护眼模式。

---

## 🛠️ 开发者指南 (Build Setup)

如果你是一名开发者，想要自行编译或二次开发本项目：

### 1. 环境准备
确保你的电脑已安装 Flutter SDK (推荐 3.22+ 版本)，并配置好 Android Studio / Visual Studio 开发环境。

### 2. 克隆项目
```bash
git clone [https://github.com/TirFire/grain_buds.git](https://github.com/TirFire/grain_buds.git)
cd grain_buds
