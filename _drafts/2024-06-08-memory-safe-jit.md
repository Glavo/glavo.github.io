---
title: '[翻译] 内存安全的'
date: 2024-06-08 21:17:24
tags:
  - JVM
  - GraalVM
categories: translate
---

原文链接：[Writing Truly Memory Safe JIT Compilers](https://medium.com/graalvm/writing-truly-memory-safe-jit-compilers-f79ad44558dd)


Last month the V8 team published an excellent blog post on what they call [the V8 Sandbox](https://v8.dev/blog/sandbox). This isn’t a sandbox for your JavaScript code — it’s intended to mitigate browser exploits caused by bugs in the JIT compiler itself. That’s important work because they report that most Chrome exploits start with a V8 memory safety bug.

V8 是用 C++ 编写的，因此这些错误似乎是因为使用内存不安全的语言所导致的。
但不幸的是，实际情况比这更加复杂。为什么呢？V8 团队解释道：

> 这里有一个问题：V8 的漏洞很少是“典型的”内存破坏 BUG（释放后访问、越界访问等），而往往会是一些微妙的逻辑问题，这些问题又会被利用于破坏内存。
> 因此，现有的内存安全解决方案大多不适用于 V8。无论是[改用内存安全的编程语言](https://www.cisa.gov/resources-tools/resources/case-memory-safe-roadmaps)（如 Rust），还是使用硬件内存安全功能（如[内存标记](https://newsroom.arm.com/blog/memory-safety-arm-memory-tagging-extension)），都无助于解决 V8 目前面临的安全挑战。

它们举了一个例子，这个例子中引擎本身不包含任何常规的内存安全问题，
但它可能会导致内存损坏，因为 VM intrinsics 或 JIT 编译器编译出来的机器代码可能会意外的依赖于关于内存的无效假设。

如果能有一种严谨的方法来编写语言运行时，从设计上彻底消除这些错误，那就太好了。


---


GraalVM 有一个名为 [GraalJS](https://www.graalvm.org/javascript/) 的 JavaScript 引擎。
它基于 [Truffle 语言框架](https://www.graalvm.org/latest/graalvm-as-a-platform/language-implementation-framework/)，使用 Java 编写。
它的峰值性可以和 V8 相媲美，而且在一些基准测试（例如光线追踪）上比 V8 更快！

尽管用 Java 编写确实可以提高内存安全性，但就像我们刚刚所看到的，用内存安全的语言重写 V8 并不能解决例子中的那类错误，
所以我们可能会觉得 GraalJS 一定存在这样的错误，然而事实并非如此。让我们来看看为什么会这样。
在此过程中，我们将探索 Truffle 的核心理论：*第一类二村映射（first Futamura projection）*。

所有高性能语言虚拟机的工作方式都是一样的。虚拟机将程序从硬盘上加载为内存中代表程序的数据结构（如 AST 或字节码）。
程序最开始会通过解释器执行，然后很快虚拟机会发现其中一部分代码是*热点（hot spot）*，程序在这些热点上花的时间比在其他地方多得多。
这些热点被传递给 JIT 编译器，编译器将它们转换为经过优化的机器码，之后的运行过程里程序会在解释器和编译后的程序片段集之间来回跳转，这大大提高了性能。

这种架构是很规范的，JVM 和 V8 都基于这种架构。但从安全角度来看，这个设计有一个缺陷：它很容易出错。
虚拟机需要实现两次语言的语义，一次用于解释器，另一次用于 JIT 编译器。
这不仅要确保两处实现都完全正确，还要确保它们的行为完全一致，这一点至关重要，不然虚拟机就会被人利用。

Truffle 是一个 Java 库，可帮助你构建先进的高性能的语言运行时。
使用 Truffle 框架构建的虚拟机的运行方式与传统虚拟机完全不同，这不仅让开发语言运行时更轻松，而且还从设计上消除了内存安全隐患。
这一切都从你用 Java 为你的语言编写解释器开始。
这并不意味着你的目标语言会被编译为 Java 字节码——事实上字节码不会出现在这个故事的任何地方。
你需要的只是编写一个普通的解释器。由于解释器的代码被 GC 管理且受到边界检查，恶意的用户代码通过内存安全漏洞来利用它。

如果使用传统的 Java，那么这个过程听起来会很慢——Java 程序本身在被 JIT 编译之前是被解释执行的，我们要解释执行一个解释器。
但幸运的是，实际并不需要这样，因为基于 Truffle 的语言运行时可以用 Graal 编译器 AOT 编译为机器码，并作为本机可执行文件分发。

因此，在用户程序启动时，他们的 JavaScript 程序会被一个解释器所解释执行，这个解释器本身是一个普通的二进制可执行文件或者动态库，但仍然能受益于 Java 的安全特性。
很快，一些方法会变的“热”起来，这时候一些不寻常的事情发生了：Truffle 框架会自动追踪热点函数，并决定安排 JIT 编译编译它们。
与传统的虚拟机设计不同，你无需编写自己的 JIT 编译器，与把你的解释器转换为本机代码的 Graal 编译器也会把

用户的代码将由用于将您的解释器转换为本机代码的相同通用 Graal 编译器自动编译，并且执行将开始在解释器和编译函数之间自动来回切换。这要归功于一种称为部分求值（或第一个 Futamura 投影）的不同寻常的技术。

But unlike in a conventional VM design, you don’t write your own JIT compiler. Instead your user’s code is automatically compiled by the same general-purpose Graal compiler that was used to convert your interpreter to native code, and execution will start automatically switching back and forth between the interpreter and compiled functions. This is possible thanks to an unusual technique called partial evaluation (or the first Futamura projection).
