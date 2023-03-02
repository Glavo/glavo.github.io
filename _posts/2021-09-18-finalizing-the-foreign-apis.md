---
title: \[翻译] 完成 Foreign API
date: 2021-09-18 13:11:00
tags:
- Project Panama
categories: translate
description: 完成 Foreign API 翻译
---

原文链接：[Finalizing the Foreign APIs](https://inside.java/2021/09/16/finalizing-the-foreign-apis/)

## 完成 Foreign API

现在外部内存访问 API（Foreign Memory Access API）和外部链接器 API（Foreign Linker API）已经存在了一段时间，
在我们采取更多步骤完成这些 API 之前，是时候对这些 API 的结构和用途进行更全面的研究，
来看看最后是否还有简化的机会。

在本文档中，我们将重点关注本轮迭代中 API 的未决问题，并为未来铺平道路。
我要感谢 Paul Sandoz、Paul Sandoz 和 Brian Goetz，他们在本文讨论的问题上提供了很多有用的见解。

### 内存解引用

在研究用户如何与外部内存访问 API 交互时（特别是涉及到 jextract 生成的代码时），
我们注意到内存分配与解引用方式之间的不对称。
下面的代码段概述了该问题：

```java
MemorySegment c_sizet_array = allocator.allocateArray(SIZE_T, new long[] { 1L, 2L, 3L });
// print contents
for (int i = 0; i < 3; i++) {
   System.out.println(MemoryAccess.getLongAtIndex(c_sizet_array, i));
}
```

在上面的代码中，我们可以看到用于分配段（segment）的 API（`SegmentAllocator::allocateArray`）
同时接受一个布局（即 `SIZE_T`）和一个 `long[]` 数组。
该惯用法提供了动态安全性：如果数组组件类型的大小与提供的布局大小不匹配，则会抛出异常。
也许令人惊讶的是，解引用 API（`MemoryAccess::getLongAtIndex`）的情况并非如此，
它只接受一个段和一个偏移量；这里没有运行时可用于强制执行附加验证的布局参数。

这种不一致性不仅仅是表面上的问题——它反映了外部内存访问 API 逐渐发展的方式。
在 API 的第一次迭代中，内存段解引用的唯一方式是通过内存访问变量句柄（memory access var handle）。
尽管变量句柄在我们解引用的故事中仍扮演着核心角色，特别是在结构化（想想 C 的结构体和 tensors）方面，
但在之后的 API 中，我们为了易用性做出了一些让步，并最终在一个辅助类（`MemoryAccess`）中添加了一套解引用仿佛，
并且最近又新增加了一套在 Java 数组和内存段之间复制数据的方法（`MemoryCopy`）。
但是，这种方式存在一些问题：

* 这些静态方法与 API 的其他部分很不一致；如上所述，它们不接受布局参数，只接受可选的 `ByteOrder` 参数。
  这不是很普遍，因为字节序只不过能影响内存解引用行为的其中一个维度（例如，对齐怎么样？）。
* 在辅助类上添加方法可以使 `MemorySegment` API 保持简单，但是会产生可见性问题：
  当使用 IDE 时，解引用内存段要在单独的类上调用静态方法这点可能并不明显。

话句话说，现在是时候让我们再次研究这些辅助类，看看是否有更好的方法了。

#### 将载体类型附加给值布局

我们将在本文档的其余部分讨论的一个很可能实现的举措是将载体类型附加到值布局上。
也就是说，如果我们能够表示类似 `ValueLayout<int>` 和 `ValueLayout<double>` 这样的类型，
那么我们的解引用 API 将会是这样：

```java
interface MemorySegment {
   ...
   <Z> Z get(ValueLayout<Z> layout, long offset)
   <Z> void set(ValueLayout<Z> layout, long offset, Z value)
}
```

注意，这是精准对称的：假如我们有像 `JAVA_INT`（类型为 `ValueLayout<int>`）这样的常量，
我们可以用这样更简单的方式从段中读取 `int` 值：

```java
MemorySegment segment = ...
int i = segment.get(JAVA_INT, 0);
```

在这里，布局信息（对其、字节序）很自然地进入解引用操作中，因此不需要支持基于 `ByteOrder` 的重载。
这里展示的解引用 API 也更容易被发现（当使用 IDE 时只需要使用代码完成）[^1]。

这似乎是一场胜利；API 不仅更简洁易用，而且更容易扩展：如果我们要添加另一种载体类型（`float16` 或 `float128`），
我们只需要定义它的布局，而不需要额外的 API。
最后，将载体类型附加到值布局上允许我们显著简化外部链接器 API（稍后将详细介绍）。

由于我们还没有特化泛型，我们如何使用现在的语言来近似以上 API？
我们可以使用的一个技巧是为每个载体类型引入一个额外的值布局类型（例如 `ValueLayout.OfInt`、`ValueLayout.OfFloat` 等），
然后为每个载体对应的布局类型定义一个解引用方法的重载：

```java
byte get(ValueLayout.OfByte layout, long offset)
short get(ValueLayout.OfShort layout, long offset)
int get(ValueLayout.OfInt layout, long offset)
```

这在实践中非常有效：它为我们提供了类型安全性（用户不可能对一个布局使用错误的载体类型），
并且当 Valhalla 准备就绪时，我们可以将这些类重写为 `ValueLayout` 的参数化子类，
并最终弃用它们（因为使用 `ValueLayout<Z>` 就足够了）。
有了这个 API，我们本节开始时使用的有问题的代码片段将变成这样：

```java
MemorySegment c_sizet_array = allocator.allocateArray(SIZE_T, new long[] { 1L, 2L, 3L });
// print contents
for (int i = 0; i < 3; i++) {
   System.out.println(c_sizet_array.get(SIZE_T, i));
}
```

如果 `SIZE_T` 的类型为 `ValueLayout.OfLong`，则在初始化内存段时，
用户将（由静态编译器）被强制使用 `long[]` 数组。
此外，解引用操作现在允许用户指定布局，其静态类型将影响被选择的解引用重载——这意味将传递 `SIZE_T` 传递给 `MemorySegment::get` 时，
它将保证返回 `long`。

#### 不安全解引用

某些情况下，我们也可以使用解引用辅助方法进行不安全的访问——请考虑以下情况：

```java
MemoryAddress addr = ...
int v = MemorySegment.globalNativeSegment().get(JAVA_INT, addr.toRawLongOffset());
```

虽然这段代码工作良好，但是过于冗长。
某种程度上来说，这是设计如此——也就是说用户应该解引用内存段，而不是普通地址，因为前者更安全（例如，内存段同时具有空间和时间边界）。
因此，更安全的替代方案是：

```java
MemoryAddress addr = ...
int v = addr.asSegment(100).get(JAVA_INT, 0);
```

但是对于偶然的本机堆外访问（特别是对于一次性的 upcall stubs），用户最好有能直接在 `MemoryAddress` 实例上工作的方便而不安全的解引用操作：

```java
MemoryAddress addr = ...
int v = addr.get(JAVA_INT, 0);
```

与 `MemorySegments` 中的对应方法不同，`MemoryAddress` 中的解引用方法是受限方法，
需要用户在命令行中提供 `--enable-native-access` 标志。

### 链接器类型

如果载体类型被附加到值布局上，我们也可以简化外部 API 的其他方面。
`CLinker` 提供了两类主要抽象，用于创建 downcall 方法句柄（针对本机函数的方法句柄）
与 upcall stubs （针对 Java 方法句柄的本机函数指针）。
链接时，用户必须同时提供一个 Java 的 `MethodType` 和 `FunctionDescriptor`；
其中前一个描述了调用点处将要处理的 Java 签名，而后一个描述了链接器运行时工作所需的类型信息：

```java
MethodHandle strlen = CLinker.getInstance().downcallHandle(
    strLenAddr, // obtained with SymbolLookup
    MethodType.methodType(long.class, MemoryAddress.class),
    FunctionDescriptor.of(C_LONG, C_POINTER)
);
```

如果载体类型被附加到值布局上，那么很容易看出来链接过程只需要一组信息，即函数描述符：
事实上我们总是可以使用以下简单规则从与函数描述符关联的布局集推导出 Java `MethodType`：

* 如果布局是带有载体类型 `C` 的值布局，则 `C` 是与该布局关联的载体类型。
* 如果布局是组布局，则 `MemorySegment.class` 将作为载体。

换句话说，被附加到值布局上的额外载体信息允许链接器运行时区分大小类似的布局（例如 32 位值布局既可以是 C `int`，又可以是 C `float`）。
此外，我们总是可以通过添加新的载体来添加链接器运行时所需的类型信息。
这意味着上述链接请求可以更简洁地被表示如下：

```java
MethodHandle strlen = CLinker.getInstance().downcallHandle(
    strLenAddr, // obtained with SymbolLookup
    FunctionDescriptor.of(C_LONG, C_POINTER)
);
```

也就是说，只需要一个函数描述符就能推导出相应的 downcall 方法句柄的 Java 类型。

#### 布局属性和常量

以这种方式进行 ABI 分类的一个直接后果是链接器运行时不再依赖布局属性机制区分大小相似的值布局；
事实上，我们建议从布局 API 中完全放弃对布局属性地支持。
虽然我们不希望此功能被广泛使用，但我们可以在以后决定允许用户将自定义 `Map` 实例附加到布局上。
我们的实现不会使用此元数据，只会传递它（例如当使用 `ValueLayout` API 提供的 `wither` 方法修改它时）。

另一个需要注意的重要事项是：由于值布局是强类型化的，因此某些 C 布局常量（例如 `C_INT`）的类型变得不明确
（在 `Windows/x64` 上为 `ValueLayout.OfInt`，在 `Linux/x64` 上为 `ValueLayout.OfLong`）。
我们选择完全从 `CLinker` 中删除这些依赖于平台的 C 布局常量：因为提取器应该为为给定的提取单元提供一组可以工作的布局常量，这不是链接器的工作。
不使用 `jextract` 的用户可以将自定义的 C 布局定义为静态常量，也可以简单地使用 `JAVA_INT`、`JAVA_LONG` 等，
这与在 JNI 代码中使用 `jint` 和 `jdouble` 等类型没有太大区别。
通过这种观察，我们可以去除 `CLinker` API 中的大部分混乱，并给出一个更简单的接口。

### 链接安全

我们想通过外部链接器更明确地解决的另一个问题是外部调用的安全性：换句话说，当通过本机调用按引用传递结构时，
如果在本机调用完成前关闭与结构关联的作用域，会发生什么情况？这在受限或共享的情况下都可能发生，
尽管想要在受限范围内重现该问题需要进行 upcall（例如在 Java upcall 中关闭作用域）。

这里的问题是，链接器 API 强制用户将 downcall 方法句柄的按引用传参参数向下擦除为 `MemoryAddress` 实例，
然后传递这些实例。这在 API 中造成了一些矛盾：要么我们也要把 `MemoryAddress` 添加作用域抽象（以便跟踪它们创建时的作用域），
要么失去安全性。但是为 `MemoryAddress` 添加作用域抽象（正如我们在 17 中所做的）有一些缺陷：
通常在与本机代码交互时使用 `MemoryAddress` 模拟来自 downcall 方法句柄的本机指针；
因此，将 `MemoryAddress` 视作一个 `long` 值（机器地址）的简单包装器是很有吸引力的，
它可以在用户请求时转换为完整的段（通过提供自定义的大小和作用域）。
但如果 `MemoryAddress` 已经存在一个作用域，那么事情就会变得更模糊，
我们必须定义用户恰好（可能是意外的）覆盖了现有作用域时会发生什么。

我们建议采取以下措施解决这一问题：

* `CLinker` 不再将按引用传参参数擦除为 `MemoryAddress`，而是使用载体 `Addressable`；
* `Addressable` 接口同时获取一个资源作用域访问器；链接器运行时将使用该作用域在整个调用过程中保持按引用传递的参数的活动状态；
* `MemoryAddress` 是 `Addressable` 接口的一个实现，其作用域始终为全局作用域。

通过这些更改，当我们链接如上所述的 `strlen` 时，生成的 downcall 方法句柄的类型将不再是 `(MemoryAddress)long`，
而是 `(Addressable)long`。这意味着用户可以直接传递内存段，并让链接器运行时按引用传递它，如下所示：

```java
MemorySegment str = ...
long length = strlen.invokeExact((Addressable)str);
```

或者，不使用 `invokeExact`：

```java
MemorySegment str = ...
long length = strlen.invoke(str);
```

使用 `invokeExact` 语义的额外强制转换的存在是不幸的，但在评估了许多备选方案后，它似乎也不是那么糟糕。
大多数情况下，工具只会对 `Addressable` 感到满意——事实上这正是 `jextract` 生成包装器所需要的：

```java
long strlen(Addressable x1) {
   try {
       return strlen_handle.invokeExact(x1);
   } ...
}
```

注意上面的代码中不需要强制转换，因为 `jextract` 包装器已经是泛化的了。
当不使用 `jextract` 时，用户可以进行选择：
要么向上面那样添加强制转换（这不比添加尾部调用 `.address()` 更冗长），
要么像这样转换方法句柄类型：

```java
MethodHandle strlen_segment = CLinker.getInstance().downcallHandle(
    strLenAddr, // obtained with SymbolLookup
    FunctionDescriptor.of(C_LONG, C_POINTER)
).asType(long.class, MemorySegment.class);

...

MemorySegment str = ...
long length = strlen_exact.invokeExact(str);
```

因为我们可以使用 `MethodHandle::asType` 调整与 downcall 方法句柄相关联的方法类型，
因此可以很容易地将更准确的类型注入 downcall 方法句柄，在调用点处即使使用 `invokeExact` 也不再需要强制转换。

### 资源作用域

目前存在不同种类的资源作用域，彼此之间部分重叠。查看 `ResourceScope` 类，我们发现有三个主要工厂方法，
分别用于创建受限、共享或隐式的作用域。前两者被称为显式作用域——也就是说，用户可以（确切地）使用 `close()` 关闭此类作用域。
剩下的隐式作用域无法关闭——尝试关闭会抛出异常。因此，处理与隐式作用域相关联的资源的唯一方式是让作用域变得不可被访问。

事实上情况更加些复杂，因为 API 还允许创建与 `Cleaner` 关联的显式作用域；
此类作用域可以通过 `close()` 方法关闭（与其他显式作用域一样），但它们也允许在无法被访问的时候被清除。
某种程度上，这类作用域同时是显式和隐式的。

虽然资源作用域 API 本身相对比较简单，但它提供的不同且微妙部分重叠的工厂方法不太协调。
我们打算通过始终将资源作用域注册到一个 Cleaner 解决这个问题；
毕竟作用域是长期存在的实体，向内部 Cleaner 注册的开销是最小的。
由于现在所有作用域都同时具有显式和隐式解除分配的特性，因此 API 只需要提供两种作用域，
分别为受限作用域和共享作用域，同时弃用隐式作用域。
这会使 API 更安全，因为用户不再可能忘记调用 `close()`（Cleaner 将会启动并执行相关的清理）。
API 也会更加统一，因为现在所有作用域（除了单例的全局作用域）都可以关闭，
并可以在 try-with-resources 语句中使用[^2]。

我们在这里讨论我们所考虑的最后一个简化，它用一种更直接的方式来表示作用域之间的依赖关系，
这取代了资源作用域句柄机制。有了此机制，以下代码：

```java
void accept(MemorySegment segment1, MemorySegment segment2) {
   try {
       var handle1 = segment1.scope().acquire();
       var handle2 = segment2.scope().acquire();
       <critical section>
   } finally {
       segment1.scope().release(handle1);
       segment2.scope().release(handle2);
   }
}
```

可以更简洁地表达成这样：

```java
void accept(MemorySegment segment1, MemorySegment segment2) {
   try (ResourceScope scope = ResourceScope.newConfinedScope()) {
       scope.keepAlive(segment1.scope());
       scope.keepAlive(segment2.scope());
       <critical section>
   }
}
```

最后，我们想让 `ResourceScope` 实现 `SegmentAllocator` 接口。
必须在只有作用域可用的时调用需要从上下文中获取段分配器的方法的情况并不少见。
`ResourceScope` 接口的实现已经实现了 `SegmentAllocator`，但是这个实现没有在公共 API 中公开，
而是允许用户使用 `SegmentAllocator::ofScope` 方法从作用域转换到分配器。
我们相信公开作用域与分配器之间的关系有助于减少需要在 Foreign API 提供的不同 API 之间转换的次数。

### Preview reshuffling

为了使这些 API 成为预览 API，我们计划将 `jdk.incubator.foreign` 包[^3]中的所有类移动到 `java.base` 模块的 `java.lang.foreign` 包下[^3]。
此外，我们计划进行以下更改（此工作可能会在单独的分支上进行，以避免冲突）：

* `MemoryHandles` 类将被删除，其所有内容将被移动到 `MethodHandles` 中；
  这是有意义的，因为这个类包含一个内存访问变量句柄的通用工厂，以及一组通用的变量句柄组合器。
* 移除 `SymbolLookup` 抽象；为了查找符号加载器符号，我们计划在 `ClassLoader` 类中添加一个 `lookup` 方法。
  现在移除 `SymbolLookup` 不会阻止我们在未来添加更强大的查找机制；它也不会阻止用户自定义链接查找，例如使用 `Function<String, MemoryAddress>`。
* 重命名 `ResourceScope`。我们注意到 `ResourceScope` 这个名称带来了一些误导，因为单词“scope”有时会被解释为在词法作用域的上下文内。
  虽然 `ResourceScope` 确实可以通过 try-with-resource 构造出一个词法作用域，在该范围内进行分配，
  但是 `ResourceScope` 抽象的某些用法与词法作用域无关（例如存储在字段中的共享段）。因此可能会选择使用更具体的名称。

因为前面段落中描述的更改已经导致许多辅助类（如 `MemoryAccess`、`MemoryCopy` 和 `MemoryLayouts`）被删除，
因此无需进一步调整。

### 总结

总的来说，这里描述的更改让 Foreign API 更紧凑、简单和安全。
将载体附加到值布局上允许解引用操作更通用、统一和静态安全；它还允许我们简化链接器的类型问题，
因为在构造 downcall 方法句柄时不再需要使用单独的 `MethodType` 参数冗余地提供相同的信息。
而且，由于 downcall 方法句柄不再要求用户将按引用传参参数擦除到 `MethodAddress`，
用户只需传递 `Addressable` 的任意子类型（最值得注意的是 `MemorySegment` ）实例，
链接器 API 将在调用期间保持引用参数的作用域的活动状态。
`MemoryAddress` 的作用变得更加简单，因为 `MemoryAddress` 现在变成了 `long` 的一个简单包装器，
用于对本机指针进行建模（话句话说，不再允许从堆上的段中获取 `MemoryAddress`）。
最后，默认情况下，将作用域和 `Cleaner` 关联可以大大简化 API，并防止意外的内存泄露。

[这里](http://cr.openjdk.java.net/~mcimadamore/panama/foreign-finalize-javadoc/javadoc/jdk/incubator/foreign/package-summary.html)可以找到一份 javadoc，
它总结了计划中的 API 更改；相应的代码更改可以在[这个实验分支](https://github.com/mcimadamore/panama-foreign/tree/foreign-finalize%2Bjextract)中找到，
它还包含了 `jextract` 工具使用新 API 所需的调整。

[^1]: 类似的惯用法也可以用来增强大内存操作的易用性与静态安全性（该处未展示）
[^2]: 我们可能会提供重载的作用域工厂方法，允许用户选择不使用 Cleaner，应对作用域分配性能至关重要的情况。这应该是一个高级选项，我们希望大多数用户对简单的工厂方法提供的默认值满意。
[^3]: 我们可能会决定将功能拆分到不同的包中——例如外部内存访问 API 使用 `java.lang.foreign`，外部链接器 API 使用 `java.lang.foreign.invoke`。