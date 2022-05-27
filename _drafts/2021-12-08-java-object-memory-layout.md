---
title: Java 对象内存布局 —— 走向“小人国”
date: 2021-09-22 22:25:00
tags:
- JVM
description: Java 对象内存布局 —— 走向“小人国”
---

Java 程序的巨大内存占用问题常常被人诟病。
一直有人好奇，差不多写法的 Java 和 C/C++ 应用相比，为什么 Java 应用的内存占用总是高得多呢？

这篇文章中，我会讲述目前 Java 应用内存占用庞大的主要原因，同时也会介绍 OpenJDK/HotSpot 中目前用于减少内存占用的方案。
除此之外，这里还会介绍一些更振奋人心的事情 —— HotSpot 在节约内存方面即将取得的巨大进展。

## 对象内存布局


让我们直切主题，从 Java 内存占用庞大的首凶开始说起，它就是 Java 对象的内存布局。

想要分析 Java 对象布局，OpenJDK 项目已经给我们提供了一个实用的分析工具——[JOL \(Java Object Layout\)](https://github.com/openjdk/jol) 。
通过它我们可以直观的查看 Java 对象在运行时的实际的布局。 

以一个简单但是常用的 Java 类——`java.lang.Integer`——为例，它的声明类似这样：

```java
public final class Integer {
    private final int value;
}
```

在命令中执行这段命令，让我们看看它的内存布局：

```
java -XX:-UseCompressedClassPointers -jar jol-cli.jar internals java.lang.Integer
```

这段命令中 `-XX:-UseCompressedClassPointers` 关闭了压缩类指针功能。
这个功能能够有效降低内存占用，不过现在让我们先关闭它，在这篇文章的后续段落中再详细解释它是怎么节约的内存。 

通过这段命令，JOL 打印出了以下结果：

```
Instantiated the sample instance via public java.lang.Integer(int)

java.lang.Integer object internals:
OFF  SZ   TYPE DESCRIPTION               VALUE
  0   8        (object header: mark)     0x0000000000000001 (non-biasable; age: 0)
  8   8        (object header: class)    0x00007f9c9d93aab8
 16   4    int Integer.value             0
 20   4        (object alignment gap)
Instance size: 24 bytes
Space losses: 0 bytes internal + 4 bytes external = 4 bytes total
```

嚯，这样一个简单的 `int` 包装器对象，实际居然占用了 24 字节！

为什么会这样？我们仔细看看上面的输出结果，可以注意到，`Integer` 唯一的字段 `value` 的 offset 已经是 16 了，也就是说在第一个字段之前已经有 16 字节的数据，难怪一个简单的小对象的内存占用会怎么打。

JOL 在 `TYPE DESCRIPTION` 的下面已经告诉了我们，字段前面的部分属于**对象头**，而对象头又分为两部分，在 64 位虚拟机中两部分各占 8 字节。

对象头的第一部分没有很准确的名称，我们这里将它称为 `mark word`。JVM 的多个功能使用它作为标记，而它拥有多种状态，在不同状态下各个位有不同含义。

<!--
* 当 `mark word` 全 0 时，代表对象在初始化过程中。
* 通常，`mark word` 的最低两位或三位用于表示锁定的状态： 
  * 当最低两位为 `00` 时，表示对象被锁定，高 62 位此时是指向锁记录的指针。
  * 当最低三位为 `001` 时，表示对象未锁定，高 61 位是常规对象头。
    * 此时对象高 25 位未被使用，其后 31 位用作存储 i-hash，之后1位未被使用，之后 4 位存储分代年龄。
  * 当最低两位位 `10` 时，高 62 位指向
-->

而对象头的第二部分是类指针，简单来说就是指向其类型信息的指针。

由于对象头本身占据了大量空间，这导致 Java 对象（特别是小型对象）往往比布局本应类似的 C/C++ 对象体积大出很多。

## HotSpot 节约内存的杀手锏——压缩指针

Java 对象因为内存布局问题往往过于庞大，不过在 64 位平台上，HotSpot 也有一套杀手锏级的手段来节约内存使用。

通常来说，在 32 位平台上指针的大小是 4 字节，而在 64 位平台上是 8 字节。但实际上绝大多数应用并不需要 64 位指针这么庞大的寻址空间，32 位指针的 4G 寻址空间足够满足很多应用了，
此时 64 位指针浪费了一小半甚至一多半位。

很多人注意到这个问题，比如 Linux 内核就有一套 [x32 ABI](https://en.wikipedia.org/wiki/X32_ABI) 接口，
允许在使用 AMD64 指令集的同时使用 32 位指针，以此降低内存开销。

不过可惜的是，x32 ABI 在 C/C++ 中被运用的并不广泛。C/C++ 静态编译的制约让它们很难了解运行时的内存大小信息，DLL 这种预编译库更很难去假设调用者的运行环境，
C/C++ 代码中遗留的对类型大小的假设也是令人头疼的问题……

值得庆幸的是，这些问题在 Java 中都不存在！JIT 编译器完全了解堆的最大大小，运行时链接让它能够跨越类库边界进行充分的优化和统一的编译，
用户更不太可能对被严格限制语义的引用有任何额外的假设。因此，HotSpot 引入了**压缩指针**功能。

对于堆大小小于 4GB 的情况，JVM 将堆内存移入低位虚拟地址空间中，直接使用 32 位的指针索引对象。

而堆大小大于 4GB 时，32 位指针显然无法直接索引整个堆。不过让我们把视线放在指针的低位上，我们会发现指针的最低数位往往都是 0。
这不是什么巧合，由于 CPU 很多指令处理能整除字长的地址时效率更高，甚至一些指令只能处理这类地址，为了效率起见，我们会填充一些字节，让对象和字段的读写尽可能的高效。

在 64 位平台上，JVM 默认情况下是 8 字节对齐的，也就是说其对象指针最后三位实际上总是 0。既然如此，我们在字段中存放指针时可以将其先减去堆的起始地址，
再右移三位，读取到栈上时再左移三位然后加上堆起始地址还原它，这样我们就能在 32 位空间内存放 35 位指针，用来索引整整 32 位的堆空间！

虽然每次读取指针需要进行位移运算会造成额外的开销，不过在常见平台上位移运算效率是相当高的，
而且压缩指针也会降低 CPU cache miss 的概率，所以总体上并不会带来明显的性能降低，而内存占用方面却会有明显的改善。

在 HotSpot 中，这项功能可以由 `-XX:+(-)UseCompressedOops` 和 `-XX:+(-)UseCompressedClassPointers` 控制，
两个选项分别能开关压缩对象指针与压缩类指针功能。这两项功能目前是互相独立的，可以开关其中之一而不影响另外一个。
现在默认情况下，只要堆内存小于 32GB，CompressedOops 就会开启，而由于存放类数据的元空间几乎总是小于 4GB，
即使有很大的堆或者开启了 ZGC 这样与压缩对象指针功能冲突的功能，CompressedClassPointers 依然默认被开启。

前面的例子中，我们用 JOL 显示了关闭了压缩类指针时的 `Integer` 的布局，那么现在我们就看看默认情况下它的布局：

```
Instantiated the sample instance via public java.lang.Integer(int)

java.lang.Integer object internals:
OFF  SZ   TYPE DESCRIPTION               VALUE
  0   8        (object header: mark)     0x0000000000000001 (non-biasable; age: 0)
  8   4        (object header: class)    0x0004d638
 12   4    int Integer.value             0
Instance size: 16 bytes
Space losses: 0 bytes internal + 0 bytes external = 0 bytes total

```

可以看到，`Integer` 对象节约了对象头中的 4 字节内存，同时还能省去末尾的 4 字节填充，现在整个对象比刚才小了 1/3，只有 16 字节了。

由于压缩指针的存在，对于有大量引用（指针）成员的类型，Java 对象反而可能比 C/C++ 对象更省空间。
比如说，同为 64 位平台上，C/C++ 中一个长度为 4096 的指针数组大小为 32768 字节，而 Java 中长度为 4096 的对象数组通常只有 16400 字节。