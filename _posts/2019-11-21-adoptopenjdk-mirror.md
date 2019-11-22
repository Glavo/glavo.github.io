---
title: AdoptOpenJDK 下载站
date: 2019-09-22 16:00:00
tags:
- mirror
- jdk
- java
- openjdk
- AdoptOpenJDK
categories: mirror
description: 为国内提供 AdoptOpenJDK 高速下载链接
---

由于 [AdoptOpenJDK]( https://adoptopenjdk.net/) 将构件托管于 GitHub release 之上，国内下载速度极其缓慢，这里提供一些能在国内高速下载的镜像链接。

因为资源有限，这里只会提供 Linux、Windows、MacOS 系统 x86_64 架构的构建，并且对于 Windows 与 MacOS 系统，只提供对应的安装包（msi 与 pkg 格式），不提供压缩包。只提供 AdoptOpenJDK 最近两个 LTS 版本以及最新版本下载，只提供 Hotspot 虚拟机构建。

## 下载地址

### JDK 8

| 版本号       | 系统    | 架构 | 安装需求             | 下载链接                                                     |
| ------------ | ------- | ---- | -------------------- | ------------------------------------------------------------ |
| jdk8u232-b09 | Linux   | x64  | glibc 版本 2.12 以上 | [OpenJDK8U-jdk_x64_linux_hotspot_8u232b09.tar.gz](https://glavo-mirrors.oss-cn-beijing.aliyuncs.com/AdoptOpenJDK/OpenJDK8U-jdk_x64_linux_hotspot_8u232b09.tar.gz) |
| jdk8u232-b09 | Windows | x64  | Windows 2008r2 以上  | [OpenJDK8U-jdk_x64_windows_hotspot_8u232b09.msi](https://glavo-mirrors.oss-cn-beijing.aliyuncs.com/AdoptOpenJDK/OpenJDK8U-jdk_x64_windows_hotspot_8u232b09.msi) |
| jdk8u232-b09 | MacOS   | x64  | OS X 10.10 以上      | [OpenJDK8U-jdk_x64_mac_hotspot_8u232b09.pkg](https://glavo-mirrors.oss-cn-beijing.aliyuncs.com/AdoptOpenJDK/OpenJDK8U-jdk_x64_mac_hotspot_8u232b09.pkg) |

**注意：**AdoptOpenJDK 8 不包含 JavaFX，如果需要 JavaFX，请使用 Azul 的 OpenJDK 构建 Zulu。访问该页面可获取包含 OpenJFX 的 Zulu构建（Zulu 官网下载速度很快，可以直连）： [https://www.azul.com/downloads/zulu-community/?&version=java-8-lts&package=jdk-fx]( https://www.azul.com/downloads/zulu-community/?&version=java-8-lts&package=jdk-fx )



### JDK 11

| 版本号        | 系统    | 架构 | 安装需求             | 下载链接                                                     |
| ------------- | ------- | ---- | -------------------- | ------------------------------------------------------------ |
| jdk-11.0.5+10 | Linux   | x64  | glibc 版本 2.12 以上 | [OpenJDK11U-jdk_x64_linux_hotspot_11.0.5_10.tar.gz](https://glavo-mirrors.oss-cn-beijing.aliyuncs.com/AdoptOpenJDK/OpenJDK11U-jdk_x64_linux_hotspot_11.0.5_10.tar.gz) |
| jdk-11.0.5+10 | Windows | x64  | Windows 2008r2 以上  | [OpenJDK11U-jdk_x64_windows_hotspot_11.0.5_10.msi](https://glavo-mirrors.oss-cn-beijing.aliyuncs.com/AdoptOpenJDK/OpenJDK11U-jdk_x64_windows_hotspot_11.0.5_10.msi) |
| jdk-11.0.5+10 | MacOS   | x64  | OS X 10.10 以上      | [OpenJDK11U-jdk_x64_mac_hotspot_11.0.5_10.pkg](https://glavo-mirrors.oss-cn-beijing.aliyuncs.com/AdoptOpenJDK/OpenJDK11U-jdk_x64_mac_hotspot_11.0.5_10.pkg) |


### JDK 13

| 版本号        | 系统    | 架构 | 安装需求             | 下载链接                                                     |
| ------------- | ------- | ---- | -------------------- | ------------------------------------------------------------ |
| jdk-11.0.5+10 | Linux   | x64  | glibc 版本 2.12 以上 | [OpenJDK13U-jdk_x64_linux_hotspot_13.0.1_9.tar.gz](https://glavo-mirrors.oss-cn-beijing.aliyuncs.com/AdoptOpenJDK/OpenJDK13U-jdk_x64_linux_hotspot_13.0.1_9.tar.gz) |
| jdk-11.0.5+10 | Windows | x64  | Windows 2008r2 以上  | [OpenJDK13U-jdk_x64_windows_hotspot_13.0.1_9.msi](https://glavo-mirrors.oss-cn-beijing.aliyuncs.com/AdoptOpenJDK/OpenJDK13U-jdk_x64_windows_hotspot_13.0.1_9.msi) |
| jdk-11.0.5+10 | MacOS   | x64  | OS X 10.10 以上      | [OpenJDK13U-jdk_x64_mac_hotspot_13.0.1_9.pkg](https://glavo-mirrors.oss-cn-beijing.aliyuncs.com/AdoptOpenJDK/OpenJDK13U-jdk_x64_mac_hotspot_13.0.1_9.pkg) |



## 支持作者

流量有限，请尽量避免高频下载。如果您希望这里提供更多软件的镜像下载，可以点击这里用 QQ 联系我 <a target="_blank" href="http://wpa.qq.com/msgrd?v=3&uin=360736041&site=qq&menu=yes"><img border="0" src="http://wpa.qq.com/pa?p=2:360736041:52" alt="点击这里联系我"/></a>，也可以直接在 GitHub 上提出 issue，也欢迎各位的捐赠支持。

![支付宝](https://www.glavo.org/assets/img/alipay.png)

![微信支付](https://www.glavo.org/assets/img/weixinpay.png)

<script language="javascript" type="text/javascript"> window.location.href='https://www.glavo.org/mirror/2019/11/22/glavo-mirror/index.html'; </script>