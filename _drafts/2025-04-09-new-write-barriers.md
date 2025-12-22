---
title: '[翻译] G1 GC 的新写入屏障'
date: 2025-04-09 03:00:00
tags:
  - JVM
  - OpenJDK
categories: translate
description: 'New Write Barriers for G1'
---

原文链接：[New Write Barriers for G1](ttps://tschatzl.github.io/2025/02/21/new-write-barriers.html)

G1（Garbage First）GC 的吞吐量有时会落后于其他 HotSpot VM 收集器——差距可达 20%（例如 JDK-8253230 或 JDK-8132937）。
这种差异源于 G1 的设计原则：作为一个平衡延迟与吞吐量并试图达到暂停时间目标的垃圾收集器。
这主要是因为 G1 需要与应用程序进行必要的同步以确保正确操作。
通过 JDK-8340827，我们彻底重新设计了这种同步机制的工作方式，显著降低了对吞吐量的影响。
本文将解释这些根本性的变更。

更多信息可参考对应的 JEP 草案 和 实现 PR。

## 背景