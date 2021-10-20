---
title: 更快的字符集编码
date: 2021-10-18 14:42:00
tags:
- JVM
  categories: translate
  description: Faster Charset Encoding 翻译
---

原文链接：[Faster Charset Encoding | Claes Redestad's blog](https://cl4es.github.io/2021/10/17/Faster-Charset-Encoding.html)

太长不看版：在 JDK 17 中，`CharsetDecoder` 的性能高了几倍，而 `CharsetEncoder` 的性能相对落后了。
经过几次错误的开始和社区的一些帮助后，我找到了一个以类似方式加速 `CharsetEncoder` 的技巧。
这或许会在未来加速您的程序。

这是一篇技术文章，也是一个关于失败与重试过程的故事。抱歉，这里没有图表和分散注意力的大量源代码链接，
But there will be cake.

## 编码/解码

我以前在 [更快的字符集解码](2021-10-18-faster-charset-decoding.md)