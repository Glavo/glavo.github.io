---
title: Glavo 的下载站
date: 2019-11-22 20:00:00
tags:
- mirror
categories: mirror
description: 提供常用软件国内下载链接
---

由于某些原因，部分常用软件在国内下载速度极其缓慢，这里为国内用户提供能告诉下载的镜像链接。

请善用目录以及浏览器的查找功能来查找软件。请如果软件版本过时，或者想要其他软件的支持，可以直接在 GitHub 上提出 issue，也可以[点击这里](http://wpa.qq.com/msgrd?v=3&uin=360736041&site=qq&menu=yes)用 QQ 联系我。

部分文件由我托管于阿里云上，流量有限，请尽量避免高频下载。捐赠支持请[点击这里](#支持作者)。


## OpenJDK

**对于一般的用户和开发者，OpenJDK 里首选推荐 [Liberica JDK](https://bell-sw.com/)。Liberica JDK 不仅包含了 JavaFX，还继续为 Windows 以及 Linux 提供 32 位构建，国内裸连下载速度也相当不错（有时候不稳定，等一会就好）。** 

### Liberica JDK （推荐）

建议直接从[Liberica JDK 官网](https://bell-sw.com/)下载。

JDK 8 (LTS)：[Download JDK 8](https://bell-sw.com/java8)

JDK 11 (LTS): [Download JDK 11](https://bell-sw.com/java11)

JDK 13 (Current): [Download JDK 13](https://bell-sw.com/java13)



### AdoptOpenJDK

因为资源有限，这里只会提供 Linux、Windows、MacOS 系统 x86_64 架构的构建，并且对于 Windows 与 MacOS 系统，只提供对应的安装包（msi 与 pkg 格式），不提供压缩包。只提供 AdoptOpenJDK 最近两个 LTS 版本以及最新版本下载，只提供 Hotspot 虚拟机构建。

#### JDK 8

| 版本号       | 系统    | 架构 | 安装需求             | 下载链接                                                     |
| ------------ | ------- | ---- | -------------------- | ------------------------------------------------------------ |
| jdk8u232-b09 | Linux   | x64  | glibc 版本 2.12 以上 | [OpenJDK8U-jdk_x64_linux_hotspot_8u232b09.tar.gz](https://glavo-mirrors.oss-cn-beijing.aliyuncs.com/AdoptOpenJDK/OpenJDK8U-jdk_x64_linux_hotspot_8u232b09.tar.gz) |
| jdk8u232-b09 | Windows | x64  | Windows 2008r2 以上  | [OpenJDK8U-jdk_x64_windows_hotspot_8u232b09.msi](https://glavo-mirrors.oss-cn-beijing.aliyuncs.com/AdoptOpenJDK/OpenJDK8U-jdk_x64_windows_hotspot_8u232b09.msi) |
| jdk8u232-b09 | MacOS   | x64  | OS X 10.10 以上      | [OpenJDK8U-jdk_x64_mac_hotspot_8u232b09.pkg](https://glavo-mirrors.oss-cn-beijing.aliyuncs.com/AdoptOpenJDK/OpenJDK8U-jdk_x64_mac_hotspot_8u232b09.pkg) |

**注意：**AdoptOpenJDK 8 不包含 JavaFX，需要使用 JavaFX 请下载 [Zulu](#Zulu)。



#### JDK 11

| 版本号        | 系统    | 架构 | 安装需求             | 下载链接                                                     |
| ------------- | ------- | ---- | -------------------- | ------------------------------------------------------------ |
| jdk-11.0.5+10 | Linux   | x64  | glibc 版本 2.12 以上 | [OpenJDK11U-jdk_x64_linux_hotspot_11.0.5_10.tar.gz](https://glavo-mirrors.oss-cn-beijing.aliyuncs.com/AdoptOpenJDK/OpenJDK11U-jdk_x64_linux_hotspot_11.0.5_10.tar.gz) |
| jdk-11.0.5+10 | Windows | x64  | Windows 2008r2 以上  | [OpenJDK11U-jdk_x64_windows_hotspot_11.0.5_10.msi](https://glavo-mirrors.oss-cn-beijing.aliyuncs.com/AdoptOpenJDK/OpenJDK11U-jdk_x64_windows_hotspot_11.0.5_10.msi) |
| jdk-11.0.5+10 | MacOS   | x64  | OS X 10.10 以上      | [OpenJDK11U-jdk_x64_mac_hotspot_11.0.5_10.pkg](https://glavo-mirrors.oss-cn-beijing.aliyuncs.com/AdoptOpenJDK/OpenJDK11U-jdk_x64_mac_hotspot_11.0.5_10.pkg) |


#### JDK 13

| 版本号        | 系统    | 架构 | 安装需求             | 下载链接                                                     |
| ------------- | ------- | ---- | -------------------- | ------------------------------------------------------------ |
| jdk-11.0.5+10 | Linux   | x64  | glibc 版本 2.12 以上 | [OpenJDK13U-jdk_x64_linux_hotspot_13.0.1_9.tar.gz](https://glavo-mirrors.oss-cn-beijing.aliyuncs.com/AdoptOpenJDK/OpenJDK13U-jdk_x64_linux_hotspot_13.0.1_9.tar.gz) |
| jdk-11.0.5+10 | Windows | x64  | Windows 2008r2 以上  | [OpenJDK13U-jdk_x64_windows_hotspot_13.0.1_9.msi](https://glavo-mirrors.oss-cn-beijing.aliyuncs.com/AdoptOpenJDK/OpenJDK13U-jdk_x64_windows_hotspot_13.0.1_9.msi) |
| jdk-11.0.5+10 | MacOS   | x64  | OS X 10.10 以上      | [OpenJDK13U-jdk_x64_mac_hotspot_13.0.1_9.pkg](https://glavo-mirrors.oss-cn-beijing.aliyuncs.com/AdoptOpenJDK/OpenJDK13U-jdk_x64_mac_hotspot_13.0.1_9.pkg) |



### Zulu

Zulu 同样是 OpenJDK 的构建，因为已经提供了 AdoptOpenJDK，这里只提供捆绑了 JavaFX 的 Java 8 发行版下载链接，其他版本请直接访问[官网]( https://www.azul.com/downloads/zulu-community/ )下载（下载速度时快时慢，不稳定）。

| 版本号       | 系统    | 架构   | 安装需求            | 下载链接                                                     |
| ------------ | ------- | ------ | ------------------- | ------------------------------------------------------------ |
| jdk8u232-b18 | Linux   | x86_64 | glibc 版本 2.5 以上 | [zulu8.42.0.23-ca-fx-jdk8.0.232-linux_x64.tar.gz](https://glavo-mirrors.oss-cn-beijing.aliyuncs.com/Zulu/zulu8.42.0.23-ca-fx-jdk8.0.232-linux_x64.tar.gz) |
| jdk8u232-b18 | Linux   | x86    | glibc 版本 2.5 以上 | [zulu8.42.0.23-ca-fx-jdk8.0.232-linux_i686.tar.gz](https://glavo-mirrors.oss-cn-beijing.aliyuncs.com/Zulu/zulu8.42.0.23-ca-fx-jdk8.0.232-linux_i686.tar.gz) |
| jdk8u232-b18 | Windows | x86_64 | Windows 2008r2 以上 | [zulu8.42.0.23-ca-fx-jdk8.0.232-win_x64.zip](https://glavo-mirrors.oss-cn-beijing.aliyuncs.com/Zulu/zulu8.42.0.23-ca-fx-jdk8.0.232-win_x64.zip) |
| jdk8u232-b18 | Windows | x86    | Windows 2008r2 以上 | [zulu8.42.0.23-ca-fx-jdk8.0.232-win_i686.zip](https://glavo-mirrors.oss-cn-beijing.aliyuncs.com/Zulu/zulu8.42.0.23-ca-fx-jdk8.0.232-win_i686.zip) |
| jdk8u232-b18 | MacOS   | x86_64 | OS X 10.10 以上     | [zulu8.42.0.23-ca-fx-jdk8.0.232-macosx_x64.zip](https://glavo-mirrors.oss-cn-beijing.aliyuncs.com/Zulu/zulu8.42.0.23-ca-fx-jdk8.0.232-macosx_x64.zip) |



## Git for Windows

下载地址来自于[淘宝 NPM 镜像]( https://npm.taobao.org/mirrors/git-for-windows/ )。

版本 v2.24.0 (2019-11-04)

### Git for Windows Setup

* [32-bit Git for Windows Setup](https://npm.taobao.org/mirrors/git-for-windows/v2.24.0.windows.1/Git-2.24.0-32-bit.exe)
* [64-bit Git for Windows Setup](https://npm.taobao.org/mirrors/git-for-windows/v2.24.0.windows.1/Git-2.24.0-64-bit.exe)

### Git for Windows Portable （"thumbdrive edition"）

* [32-bit Git for Windows Portable](https://npm.taobao.org/mirrors/git-for-windows/v2.24.0.windows.1/PortableGit-2.24.0-32-bit.7z.exe)
* [64-bit Git for Windows Portable](https://npm.taobao.org/mirrors/git-for-windows/v2.24.0.windows.1/PortableGit-2.24.0-64-bit.7z.exe)



## 支持作者

流量有限，请尽量避免高频下载。如果您希望这里提供更多软件的镜像下载，可以点击这里用 QQ 联系我 <a target="_blank" href="http://wpa.qq.com/msgrd?v=3&uin=360736041&site=qq&menu=yes"><img border="0" src="http://wpa.qq.com/pa?p=2:360736041:52" alt="点击这里联系我"/></a>，也可以直接在 GitHub 上提出 issue，也欢迎各位的捐赠支持。

![支付宝](https://www.glavo.org/assets/img/alipay.png)

![微信支付](https://www.glavo.org/assets/img/weixinpay.png)