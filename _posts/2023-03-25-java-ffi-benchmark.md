---
title: 'Java 21 FFI 性能测试 —— Panama vs JNI/JNA/JNR'
date: 2023-03-25 22:00:00
tags:
  - Java
  - JDK
  - Project Panama
categories: mirror
description: Panama 
---

作为全新的 Java FFI 方案，从 Java 16 开始孵化的 Panama Foreign Function API 广受关注，
也有一些人将它与 JNI、JNA、JNR 等现在常用的 FFI 方案进行了对比测试。

但是，Panama 从 Java 16 到 21，几乎每个 Java 版本中都有大更新，现有的测试主要基于 Java 16 时的早期 API，结果可能有些过时，
所以我基于 Java 21 重新设计了[一组 JMH 测试](https://github.com/Glavo/java-ffi-benchmark)，向各位展示 Panama 最新的性能表现。

这组测试有四项：

* `NoopBenchmark`: 在 Java 中调用一个无操作的空 C 函数。此测试主要目的是展示调用本机函数的基本开销。
* `SysinfoBenchmark`: 在 Java 中调用 Linux 系统函数 `sysinfo`，并从结果获取 `mem_unit` 的值。此测试主要目的是展现需要操作 C 结构体时各个方案的性能表现。
* `StringConvertBenchmark`: 此测试包含两个子项：将不同长度的 Java 字符串转换为 C 字符串传递给 C 方法，以及接受 C 函数返回的 C 字符串并转换为 Java 字符串。此测试的主要目的是展示字符串转换的性能。
* `QSortBenchmark`: 用一个 Java 方法作为回调函数调用 C 标准库函数 `qsort`。此测试的主要目的是展示 C 一侧调用 Java 回调方法的性能。

而测试中除了 Panama 和 JNI 以外，也会与 [JNA](https://github.com/java-native-access/jna) 和 [JNR](https://github.com/jnr/jnr-ffi) 进行对比。

JNA 的测试结果会包括常规用法和 [Direct Mapping](https://github.com/java-native-access/jna/blob/master/www/DirectMapping.md) 两种模式的对比，Panama 的结果中也会包括对 Java 21 中新提供的 `isTrivial` 链接选项的测试。

## 测试结果

### `NoopBenchmark`

![](https://github.com/Glavo/java-ffi-benchmark/raw/2023-03-25/data/NoopBenchmark.webp)

| 方案                    | 吞吐量 (ops/ms) | 吞吐量百分比 |
|-----------------------|-------------:|-------:|
| JNA                   |    19372.933 |   6.7% |
| JNA Direct Mapping    |    20595.690 |   7.2% |
| JNR                   |   124115.069 |  43.2% |
| JNR (Ignore Error)    |   241616.003 |  84.1% |
| JNI                   |   287143.357 | 100.0% |
| Panama                |   325322.988 | 113.3% |
| Panama (Trivial Call) |   459682.023 | 160.1% |

在数据表格中，我以 JNI 的数据为基准列出了百分比化的吞吐量，这样能更直观的感受它们的性能差异。

作为已经被广为使用的传统方案，JNA 表现出了极为惊人的巨大开销，与 JNI 十四倍的性能差距让它比其他几个方案都要慢出一个数量级，
即使使用 Direct Mapping 也只有轻微的改善。

JNR 默认情况下虽然依然比 JNA 好得多，但仍然难以让人满意。JNR 的表现主要是因为 JNR 默认会保存 errno 值，
虽然通常来说在本机函数的开销很低，但相对于本测试的 noop 函数就无法忽略了。
我们使用 `@IgnoreError` 让 JNR 不报错错误，此时 JNR 的性能损失就只有不到 16% 了。

而默认情况下 Panama 吞吐量已经比 JNI 高出了 13.3%，使用 `isTrivial` 链接器选项时开销还能进一步降低，相比 JNI 有 60.1% 的吞吐量提升。

### `SysinfoBenchmark`

Linux 的 `sysinfo` 函数和很多 C 函数一样，接受一个结构体指针，通过该指针传递结果。

JNI 处理这种惯例只需要传递给它一个局部变量指针即可，JNA/JNR 则可以将结构体映射至 Java 类进行处理。

而在 Panama 中，我们需要为这个结构体创建一个 `StructLayout`，然后在堆上分配一段内存，再将它传递给 C 函数，测试方法如下:

```java
@Benchmark
public int getMemUnitPanama() throws Throwable {
    try (Arena arena = Arena.ofConfined()) {
        MemorySegment info = arena.allocate(sysinfoLayout);
        getMemUnit.invokeExact(info);
        return (int) memUnitHandle.get(info);
    }
}
```

结果：

![](https://github.com/Glavo/java-ffi-benchmark/raw/2023-03-25/data/SysinfoBenchmark.webp)

| 方案                    | 吞吐量 (ops/ms) | 吞吐量百分比 |
|-----------------------|-------------:|-------:|
| JNA                   |      152.826 |   2.0% |
| JNA Direct Mapping    |      152.582 |   2.0% |
| JNR                   |     3531.837 |  47.2% |
| JNI                   |     7482.798 | 100.0% |
| Panama                |     5569.635 |  74.4% |
| Panama (Trivial Call) |     5560.135 |  74.3% |

JNA 再次展现出了它极其夸张的性能，性能仅仅为 JNI 的 2%，而且使用 Direct Mapping 也没有改善。

JNR 性能只有 JNI 的不到一半，这主要是将 C 结构体映射至 Java 类付出的成本。

Panama 在这项测试中表现也不理想，相比 JNI 慢了 25% 左右，原因主要是需要花费时间创建临时的 `Arena` 和在堆上分配结构体。
尝试在测试方法外分配内存并重新进行测试，得到了以下的结果：

![](https://github.com/Glavo/java-ffi-benchmark/raw/2023-03-25/data/SysinfoBenchmark-no-allocate.webp)

现在 Panama 和 JNI 的性能差距不到 1%，可以佐证上面的观点。

此测试展现了 Panama 的缺点：无法在栈上分配局部变量，所以需要更多的在堆上进行分配。

为了缓解分配带来的影响，可以考虑一次性分配一大块内存，然后在需要的时候通过 `SegmentAllocator.slicingAllocator` 分割成小块使用， 最后一次性释放。

### `StringConvertBenchmark`

该测试包含两个子项。

#### 将 Java 字符串转换为 C 字符串

![](https://github.com/Glavo/java-ffi-benchmark/raw/2023-03-25/data/StringConvertBenchmark-j2c.webp)

JNI 没有直接的转换方式，所以此子项中没有对 JNI 进行测试。

JNA/JNR 内置支持将 Java `String` 映射至 C `const char *`，而 Panama 需要手动调用 `Arena::allocateUtf8String` 进行转换。

在此子项测试中，Panama 依然远强于 JNA/JNR，但 JNA 和 JNR 的结果就比较微妙了。

虽然对于小字符串 JNR 依然有优势，但对于较大的字符串 JNR 甚至比 JNA 更慢。
合理怀疑 JNR 的转换实现存在性能问题，小字符串主要是 JNA 基本开销较大，所以没有体现出优势，但对于较大的字符串 JNR 的问题就暴露出来了。

#### 将 C 字符串转换为 Java 字符串

![](https://github.com/Glavo/java-ffi-benchmark/raw/2023-03-25/data/StringConvertBenchmark-c2j.webp)

折线图后半段比较拥挤，下面是放大后的图像：

![](https://github.com/Glavo/java-ffi-benchmark/raw/2023-03-25/data/StringConvertBenchmark-c2j-detail.webp)

JNA/JNR 依然是使用内置的类型映射，JNI 则使用了 JNI 函数 `NewStringUTF`，Panama 则是调用了 `MemorySegment::getUtf8String`.

令人惊讶的是，JNA 对于较大的字符串性能超过了其他方案。

我查看了源码，Panama/JNA/JNR 使用了类似的方式进行转换：

* 扫描 `'\0'` 字符，确定字符串长度；
* 将 C 字符串拷贝至 Java 字节数组中；
* 解码字符串。

其中 Panama 和 JNR 都是在 Java 中使用简单的循环确定 C 字符串长度，而 JNA 使用了 C 标准库函数 `strlen`，
这可能就是性能存在差距的原因。

我已经将此问题反馈给 Panama 开发者，他们正在研究这个问题，希望能在未来的版本中得到改进。

### `QSortBenchmark`

![](https://github.com/Glavo/java-ffi-benchmark/raw/2023-03-25/data/QSortBenchmark.webp)

该测试使用 `qsort` 排序一个 `int` 数组，而传递给 `qsort` 的比较器函数指针则是调用 Java 实现的回调函数。 

对于 JNA/JNR，我使用它们将特定的函数式接口映射为 C 函数指针的内置支持传递回调函数。

对于 JNI，我将回调函数的 `jmethodId` 和相关的 `jclass` 全局引用缓存在 C 的静态变量中，
每次调用回调函数都只需要从 `JavaVM` 中取得 `JNIEnv`，然后调用 `CallStaticIntMethod` 即可。
该回调函数的 Java 实现使用了 `sun.misc.Unsafe` 以解引用指针。

而 Panama，我使用了[文档中的实现方式](https://openjdk.org/jeps/442#Upcalls)，为回调函数生成 upcall stub 并传递。

该测试是 Panama 优势最大的场景。Panama 的性能约为 JNI/JNR 的 3.5~4 倍，JNA 的 20~30 倍。


## 总结

Panama 不仅让 Java FFI 摆脱需要手动编写 C 代码的束缚，而且有比传统 JNI 更优秀的性能，可以期待它未 Java FFI 带来一场变革。

目前 Panama 仍处于 Preview 阶段，正在积极开发。我非常希望更多人参与对它的试用，并在[邮件列表](https://mail.openjdk.org/mailman/listinfo/panama-dev)(panama-dev@openjdk.org)中反馈自己的体验和遇到的问题，
这样能够帮助 Panama 在正式定稿前进行更多改进。
