---
title: 'flattened-values'
date: 2024-06-14 19:05:19
tags:
  - JVM
  - Valhalla
categories: translate
description: ''
---

原文链接：[encodings for flattened heap values](https://cr.openjdk.org/~jrose/values/flattened-values.html#requirements)

---

Project Valhalla 的一个关键目标是将值对象展平至其堆容器中，同时维持这些容器所有规定的行为。值的展平表示必须为值的每个字段提供存储位，并直接在容器中分配（或至少可以间接访问）；当容器允许存储 `null` 时，它也必须可以表示 `null`。如果读写容器时线程间发生数据争用，那么容器通常还必须保证一致性。

本文档讨论了此类堆容器的多种实现方案。我们特别关注了展平值存储的一种常见但麻烦的场景，其中容器被组织为不大于 64bit（或者可能是 126bit）的单个机器字。

我们将考虑在容器中引入 *null 通道*的方法，以便在必须将空引用（逻辑上）存储到容器中时表示空引用。这个 null 通道可能在机器字内部，也可能需要在机器字外有额外的字节。

## 必要条件