---
title: 为什么你不应该使用 LinkedList？
date: 2021-09-22 22:25:00
tags:
- Java
- JVM
description: Java LinkedList 内存布局与性能分析
---

我们知道，在 `java.util` 包中提供了两种常见的 `List` 实现：基于数组的 `ArrayList` 与基于双链表的 `LinkedList`。

几乎所有 Java 开发者对 `ArrayList` 都很熟悉，因为它非常常用，而 `LinkedList` 就稍显陌生了。
我注意到似乎有很多开发者对于它存在一些误解，并因此造成了很多误用。 
一个例子是，HMCL 之前大量使用 `LinkedList` 存放创建后只调用一次 `add` 的 `List`，
似乎认为这种情况下 `LinkedList` 会比 `ArrayList` 节约空间。在这里，我会通过剖析其内存布局破除这种误解。

太长不看版：大多数情况下都不应该使用 `LinkedList`，它的内存占用非常巨大，同时大多数操作都有很高的复杂度系数，
除了需要经常删除首元素这样的情况，否则通常来说性能相比 `ArrayList` 更糟糕。

这篇文章适用于 Oracle JDK/OpenJDK HotSpot 从 Java 8 到目前的所有版本，
可能也适用于很多其他 JDK/JVM 实现。

这篇文章假设您已经对它们的具体实现方式已经有所了解，所以不会赘述它们具体实现方式，
只会简单讲述几个容易被忽视的实现细节。
如果你现在对它们一无所知，那么请先看看其他文章以及源码了解一下，再来看这篇文章。

## 准备工作

在分析它们内存布局之前，我们先快速来看一遍它们的声明简化后的形式。
我相信您对这些应该已经很熟悉了，但请耐心看完这一节，其中可能会有一些您所遗漏的细节。

`ArrayList` 的声明简化后类似如下：

```java
public class ArrayList<E> implements List<E> {
    private static final int DEFAULT_CAPACITY = 10;
    private static final Object[] EMPTY_ELEMENTDATA = {};
    private static final Object[] DEFAULTCAPACITY_EMPTY_ELEMENTDATA = {};

    int modCount = 0;
    
    Object[] elementData;
    int size;
    
    ...
}
```

其中，`modCount` 继承自 `AbstractList`，它用于实现“快速失败”机制：
每次修改操作都会更改这个计数。`iterator` 以及 `forEach` 等方法都会记录开始调用时该计数器的数值，
每次迭代都会对其进行检查，如果此过程中计数器发生了变化，那么会直接抛出一个 `ConcurrentModificationException`，
提醒用户列表在不应该变化的过程中被修改了。

`EMPTY_ELEMENTDATA` 和 `DEFAULTCAPACITY_EMPTY_ELEMENTDATA` 这两个静态共享的空数组用于在 `ArrayList` 为空的时候填充 `elementData` 字段。
它使得 `new ArrayList<>()` 或者 `new ArrayList<>(0)` 的时候 `ArrayList` 不需要分配一个新数组，
直到往 `ArrayList` 中添加元素时才会真正分配数组。

`EMPTY_ELEMENTDATA` 和 `DEFAULTCAPACITY_EMPTY_ELEMENTDATA` 的区别在于，
`new ArrayList<>()` 时会使用 `DEFAULTCAPACITY_EMPTY_ELEMENTDATA`，
而 `new ArrayList<>(0)` 时会使用 `EMPTY_ELEMENTDATA`。
`ArrayList` 用这种区别使得它们扩容行为有所差异：
`new ArrayList<>()` 在添加元素时会一下增大到 `DEFAULT_CAPACITY`，也就是 `10`，以避免多余地多次扩容；
而 `new ArrayList<>(0)` 的内部数组会按一般规则，`0 -> 1 -> 2 -> 3 -> 4 -> 6 -> 9 -> ...` 这样每次扩容到原先的 1.5 倍大小。

`LinkedList` 的声明简化后类似如下：

```java
public class LinkedList<E> {
    int modCount = 0;
    
    int size = 0;
    Node<E> first;
    Node<E> last;

    private static class Node<E> {
        E item;
        Node<E> next;
        Node<E> prev;
    }
}
```

其中 `modCount` 与 `ArrayList` 中的一样，是从 `AbstractList` 中继承而来用于实现“快速失败”的。

`first` 和 `last` 分别存放首尾节点，在 `LinkedList` 为空时它们都为 `null`，也就是无需额外的空间。

## 内存布局

想要分析它们的内存布局，首先我们需要知道 在 HotSpot 中每个对象都有一个**对象头**，
它用来存储每个对象的 GC 状态、锁状态以及类型信息等元数据。

另一个需要了解的知识点是，为了节约内存使用，HotSpot 中引入了一种叫做**压缩指针**的技术。
通过该技术，64 位的 JVM 上也能够让指针减小到 32 位，大大降低了内存占用。

当然，将 64 位指针压缩到 32 位后，能够索引的地址范围有限。
这个范围对于元空间来说非常充裕，所以对象头中用于指向对应类型数据的**类指针**几乎总是可以压缩，
拥有一个单独的 JVM 参数 `UseCompressedClassPointers` 可以开启关闭。

但是对于对象指针来说，需要考虑堆大小才能开启压缩指针。

对于 <4G 的小堆无需多说，32 位指针可以直接索引。
而对于 >4G <32G 的堆来说，由于 64 位机器上 JVM 堆通常是 8 字节对齐的，
所以对象指针的最后最后三位总是 0，于是 JVM 通过将它们右移三位压缩到 32 位，同时还能索引 32GB 的堆，
这就能够满足大部分用户的需求了。

因此，在 `-Xmx` <32G 时，压缩对象指针通常默认开启，而 >32G 时默认关闭。
您也可以使用 `UseCompressedOops` JVM 参数手动控制此行为。

由于 ZGC 使用的染色指针技术需要使用指针中的一些位做标记，与压缩指针技术冲突，所以使用 ZGC 时压缩指针会自动关闭，
但压缩类指针依然工作。另外，另一个低暂停 GC —— Shenandoah GC，它使用了其他技术实现，能够与压缩指针同时开启，
想要同时享受低暂停与压缩指针的话可以考虑用它替代 ZGC。

通常来说，大部分 Java 应用的堆大小都要小于 32G，此时压缩指针默认开启，就让我们先来看看这种情况下的 `LinkedList` 内存布局吧：

```
java.util.LinkedList object internals:
OFF  SZ                        TYPE DESCRIPTION               VALUE
  0   8                             (object header: mark)     0x0000000000000001 (non-biasable; age: 0)
  8   4                             (object header: class)    0x001ee1a8
 12   4                         int AbstractList.modCount     0
 16   4                         int LinkedList.size           0
 20   4   java.util.LinkedList.Node LinkedList.first          null
 24   4   java.util.LinkedList.Node LinkedList.last           null
 28   4                             (object alignment gap)
Instance size: 32 bytes
```

使用 JOL，我们能够能很简单地查看一个 Java 对象运行时的实际内存布局。

可以看到，在这种情况下对象头占用了 8+4 字节，四个字段各占用 4 字节，再加上为了满足 JVM 堆 8 字节对齐的约束，
对象末尾还需要填充 4 字节，一个 `LinkedList` 对象本身的大小是 32 字节。

而 `LinkedList` 用于存储数据的 `LinkedList.Node` 布局如下：

```
java.util.LinkedList$Node object internals:
OFF  SZ                        TYPE DESCRIPTION               VALUE
  0   8                             (object header: mark)     N/A
  8   4                             (object header: class)    N/A
 12   4            java.lang.Object Node.item                 N/A
 16   4   java.util.LinkedList.Node Node.next                 N/A
 20   4   java.util.LinkedList.Node Node.prev                 N/A
Instance size: 24 bytes
```

每个 `Node` 对象的大小为 24 字节。`LinkedList` 中每存储一个数据都需要创建一个 `Node` 对象，也就是额外需要 24 字节。

而另一边，`ArrayList` 的内存布局如下：

```
java.util.ArrayList object internals:
OFF  SZ                 TYPE DESCRIPTION               VALUE
  0   8                      (object header: mark)     0x0000000000000001 (non-biasable; age: 0)
  8   4                      (object header: class)    0x0000d7a0
 12   4                  int AbstractList.modCount     0
 16   4                  int ArrayList.size            0
 20   4   java.lang.Object[] ArrayList.elementData     []
Instance size: 24 bytes
```

一个 `ArrayList` 对象自身大小是 24 字节，比 `LinkedList` 要小 8 字节。

而空的 `ArrayList` 由于使用了全局共享的空数组，不需要额外的空间。

而存储了元素的 `ArrayList` 内部使用数组实际存储元素内容。一个大小为 10（`ArrayList.DEFAULT_CAPACITY`）的数组内存布局如下：

```
[Ljava.lang.Object; object internals:
OFF  SZ               TYPE DESCRIPTION               VALUE
  0   8                    (object header: mark)     0x0000000000000001 (non-biasable; age: 0)
  8   4                    (object header: class)    0x00001528
 12   4                    (array length)            10
 12   4                    (alignment/padding gap)
 16  40   java.lang.Object Object;.<elements>        N/A
Instance size: 56 bytes
```

可以看到，每个数组的对象头与 `length` 字段一共 16 字节，这也是空数组的大小。
而由于启用了压缩指针，数组每个元素都只需要 4 字节存储内容，所以存储了 `N` 个对象的数组对象大小为 `16 + 4 * N`
（实际上大小为奇数的数组还需额外 4 字节对齐填充，为了方便计算，这里不再关注这个填充）。

由此我们可以得到结论，在 CompressedOops 开启时：

* 存储了 `N` 个元素的 `LinkedList` 占用的内存空间为 `32 + N * 24` 字节。
* 存储了 `N` 个元素的 `ArrayList` 占用的内存空间为：
  * 空的 `ArrayList` 占用的内存空间为 `24` 字节；
  * <= 10 个元素的 `ArrayList` 占用的内存空间为 `80` 字节；
  * \> 10 个元素的 `ArrayList` 占用的内存空间大于等于 `40 + N * 4` 字节（数组已满），小于 `40 + N * 6` 字节（数组刚扩容）。

通过这个结论，我们就可以知道：

* 空的 `LinkedList` 比空的 `ArrayList` 大 8 字节；
* 存储 1 个元素时，`LinkedList` 比 `ArrayList` 小 24 字节；
* 存储 2 个元素时，`LinkedList` 和 `ArrayList` 一样大；
* 存储 10 个元素时，`LinkedList` 和 `ArrayList` 大 192 字节；
* 随着元素进一步增加，存储相同个数元素时，`LinkedList` 占用的内存空间是 `ArrayList` 的 4~6 倍。

可以看到，只有存储 1 个元素的时候 `LinkedList` 的内存占用才会小于 `ArrayList`，
随着元素的增加，`LinkedList` 占用的内存空间很快就会达到 `ArrayList` 的 4~6 倍。

而且，即便只存储 1 个元素，我们也可以将数组大小作为参数传递给 `ArrayList` 的构造器，
`new ArrayList<>(1)` 或者 `new ArrayList<>(0)` 创建的 `List` 在存放 1 个元素时比 `LinkedList` 还要小 8 字节。

而在 CompressedOops 关闭时（堆 >32G，或开启了 ZGC，或使用了 `-XX:-UseCompressedOops` 参数）：

* 存储了 `N` 个元素的 `LinkedList` 占用的内存空间为 `40 + N * 40` 字节。
* 存储了 `N` 个元素的 `ArrayList` 占用的内存空间为：
    * 空的 `ArrayList` 占用的内存空间为 `32` 字节；
    * <= 10 个元素的 `ArrayList` 占用的内存空间为 `128` 字节；
    * \> 10 个元素的 `ArrayList` 占用的内存空间大于等于 `48 + N * 8` 字节（数组已满），小于 `40 + N * 12` 字节（数组刚扩容）。

此时 `LinkedList` 与 `ArrayList` 内存占用的差距会稍微小一点，但依然在 `ArrayList` 的 3.3~5 倍之间。

如果之前您一直忽视了 `LinkedList` 的内存占用问题，相信这些数据足够让您重新审视这些问题。


