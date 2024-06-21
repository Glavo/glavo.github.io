---
title: '[新闻] OpenJDK Leyden 项目发布首个 EA 版本'
date: 2024-06-21 13:25:54
tags:
  - Java
  - JDK
categories: translate
description: OpenJDK Leyden 项目发布首个 EA 版本，优化 Java 程序启动时间与资源占用
---

OpenJDK 的子项目 Leyden 在进行开发一年后终于发布了第一个 EA 版本：[Project Leyden Early-Access Builds
](https://jdk.java.net/leyden/)（目前暂时仅为 Linux 和 macOS 提供构建，Windows 平台的构建将在未来提供）

Leyden 项目优化了 Java 程序的启动时间、预热时间以及资源占用。欢迎各位积极尝试此原型，并向 OpenJDK 社区反馈提供反馈意见。

## 概述

此 EA 版本基于 Leyden 项目的“premain”原型。该原型包含很多优化，这些优化将工作从运行时转移到了应用程序的实验性运行中，这被称为**训练运行（training run）**。 在训练运行过程中，JVM 提前计算了各种信息，而且会根据在此阶段对程序行为的观察，将字节码提前编译为机器码。

此原型包含以下优化功能，通过 `-XX:CacheDataStore` 选项能够将这些功能全部启用，不需要再单独添加这些选项；未来 JVM 可能会默认启用它们。

* [统一 CDS (JDK-8320264)](https://openjdk.org/jeps/8320264)：CDS 的这个增强功能是其他功能的基础。
  * 它使 [CDS](https://docs.oracle.com/en/java/javase/22/vm/class-data-sharing.html) 不仅能像以前那样存储类元数据和堆对象，还能存储性能分析数据和经过编译的代码。
  * 这项功能需要通过虚拟机参数 `-XX:CacheDataStore` 启用。
  * 这个选项简化了构建 CDS 以及尝试这里列出的所有原型功能的流程。
* [从 CDS 档案中加载类 (JDK-8315737)](https://openjdk.org/jeps/8315737)：这使得 JVM 在启动时能够立即让类处于已经被加载的状态。因此我们可以用简化的假设来实现很多其他的 time shifting 优化。
  * 这项功能需要通过虚拟机参数 `-XX:+PreloadSharedClasses` 启用。
* [将方法性能分析数据存储至 CDS 档案 (JDK-8325147)](https://openjdk.org/jeps/8325147)：我们将训练运行得到的方法性能分析数据存储至 CDS 档案中，从而使 JIT 在预热期间能够更早地开始编译，使 Java 程序能够更快地达到性能峰值。
  * 这项功能需要通过虚拟机参数 `-XX:+RecordTraining` 和 `-XX:+ReplayTraining` 启用。
* 提前解析常量池条目：新的虚拟机参数 `-XX:+ArchiveFieldReferences`、`-XX:+ArchiveMethodReferences` 和 `-XX:+ArchiveInvokeDynamic` 能够让虚拟机在训练运行期间解析大量常量池条目，这使得程序能够更快地启动。此外，由于存在这些经过解析的常量池条目，AOT 编译器能够生成质量更高的代码。
* AOT 编译 Java 方法：在训练运行期间经常使用的方法可以和 CDS 一起编译与存储。在实际生产运行程序时，可以跳过解释器和 C1 编译阶段，直接运行 AOT 编译的方法。
  * 这项功能需要通过虚拟机参数 `-XX:+StoreCachedCode`、`-XX:+LoadCachedCode` 和 `-XX:CachedCodeFile` 启用。
  * 目前机器码被存储在一个单独的文件，但我们计划会把它存储在 CDS 档案文件内。
* 提前生成[动态代理](https://docs.oracle.com/en/java/javase/22/docs/api/java.base/java/lang/reflect/Proxy.html)：一些流行的框架经常使用动态代理功能，我们可以提前生成这些代理来缩短启动时间。
  * 这项功能需要通过虚拟机参数 `-XX:+ArchiveDynamicProxies` 启用。
* 提前生成反射数据：JVM 会生成反射数据（比如 `java.lang.reflect.Method` 的实例）来支持反射操作，我们可以提前生成它们来缩短启动时间。
  * 这项功能需要通过虚拟机参数 `-XX:+ArchiveReflectionData` 启用。
* 类加载器查找缓存：有些时候一些框架会用名称（通过 `Class.forName(...)` 等方法）对类进行重复查找，这种优化允许在不重复扫描类路径的情况下快速完成此类查找。
  * 这项功能需要通过虚拟机参数 `-XX:+ArchiveLoaderLookupCache` 启用。

## 尝试 Leyden

首先，请从[下载页面](https://jdk.java.net/leyden/)下载 Leyden 项目的 EA 构建。我也把它们上传到了百度网盘，如果大陆地区访问不畅或者无法访问可以尝试从这里下载：[Leyden - 百度网盘](https://pan.baidu.com/s/1mf5pMvisoU921O3rntr-hg?pwd=0000)。

作为演示，OpenJDK 提供了一个简单的基准测试：[JavacBenchApp.java](/assets/posts/2024-06-21-leyden-ea1-release-notes/JavacBenchApp.java)。此基准测试使用 `javac` 编译一些 Java 源文件。

在下载了上面的基准后，我们先将它编译打包成 JAR 文件：

```
$ javac JavacBenchApp.java
$ jar cvf JavacBenchApp.jar JavacBenchApp*.class
added manifest
adding: JavacBenchApp$ClassFile.class(in = 1608) (out= 787)(deflated 51%)
adding: JavacBenchApp$FileManager.class(in = 2090) (out= 979)(deflated 53%)
adding: JavacBenchApp$SourceFile.class(in = 1351) (out= 671)(deflated 50%)
adding: JavacBenchApp.class(in = 7571) (out= 3302)(deflated 56%)
```

然后我们可以尝试在不启用 Leyden 功能的情况下运行此测试，结果花费了 893 毫秒：

```
$ java -cp JavacBenchApp.jar JavacBenchApp 50
Generated source code for 51 classes and compiled them in 893 ms
```

而想要尝试 Leyden，我们首先可以进行**训练运行（training run）**并生成 Leyden 缓存文件：

```
$ rm -fv JavacBenchApp.cds* # 先清理掉之前生成的文件
$ java -XX:CacheDataStore=JavacBenchApp.cds -cp JavacBenchApp.jar JavacBenchApp 50
$ ls -l JavacBenchApp.cds*
-r--r--r-- 1 iklam iklam 30900224 May 20 19:21 JavacBenchApp.cds
-r--r--r-- 1 iklam iklam 16895736 May 20 19:21 JavacBenchApp.cds.code
```

这里创建了两个文件：

* `JavacBenchApp.cds`：该文件包含从训练运行中收集到的类、堆对象和性能分析数据；
* `JavacBenchApp.cds.code`：该文件包含了 AOT 编译的方法，且针对训练运行期间观察到的行为进行了优化。（未来版本中，这个文件会被合并到 `JavacBenchApp.cds` 里）

现在我们可以使用这些缓存文件进行**生产运行（production run）**，此时该测试仅用了 423 毫秒就完成了（耗费的时间减少了 52.63%）：

```
$ java -XX:CacheDataStore=JavacBenchApp.cds -cp JavacBenchApp.jar JavacBenchApp 50
Generated source code for 51 classes and compiled them in 423 ms
```

## Leyden 原型的局限性

目前此 Leyden 原型存在以下限制，它们可能会在未来被解决：

* 目前此 Leyden 原型生成的 CDS 档案是针对特定 GC 生成的，请相同的 GC 进行训练和生产运行。
* 目前此 Leyden 原型仅支持 G1 GC、Serial GC 和 Parallel GC。

此外，此原型为了方便调试性能问题默认指定了 `-Xshare:on`，这使得 CDS 档案不可用时会直接报错退出，你可以通过添加 JVM 选项 `-Xshare:auto` 来恢复标准 JDK 的行为。


训练运行期间可能会有这样的错误信息：

```
Java HotSpot(TM) 64-Bit Server VM warning: Cannot dump shared archive while using shared archive
```

这个消息是误报，CDS 档案实际仍被生成，您可以安全地忽略这条信息。

## 尾声

本文章大体翻译自 Leyden 文档，你可以阅读[此文档](https://github.com/openjdk/leyden/blob/premain/README.md)了解更完整的信息。

欢迎通过 Leyden 邮件列表咨询、讨论、反馈相关问题：[leyden-dev@openjdk.org.](https://mail.openjdk.org/mailman/listinfo/leyden-dev)。
