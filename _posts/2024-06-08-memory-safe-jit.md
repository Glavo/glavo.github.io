---
title: '[翻译] 内存安全的 JIT 编译器'
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
但幸运的是，实际并不需要这样，因为基于 Truffle 的语言运行时可以用 Graal 编译器 AOT 编译为机器码，并作为[本机可执行文件](https://www.graalvm.org/latest/reference-manual/native-image/)分发。

因此，在用户程序启动时，他们的 JavaScript 程序会被一个解释器所解释执行，这个解释器本身是一个普通的二进制可执行文件或者动态库，但仍然能受益于 Java 的安全特性。
很快，一些方法会变的“热”起来，这时候一些不寻常的事情发生了：Truffle 框架会自动追踪热点函数，并决定安排 JIT 编译编译它们。
与传统的虚拟机设计不同，你无需编写自己的 JIT 编译器，通用的 Graal 编译器不仅用于将你的解释器转换为机器码，它也会自动将你的用户的代码转换为机器码，
之后的运行过程里程序会在解释器和编译后的机器码之间来回跳转。
这要归功于一种叫做部分求值（Partial Evaluation）或*第一类二村映射*的特殊技术。

---

你可能以前没有接触过二村映射或部分求值，这个听起来很奇怪的东西到底是什么呢？

它核心思想是自动将解释器的代码转换为 JIT 编译器，用以编译用户方法。
这样语言运行时的开发者无需在两个地方（解释器和手工编写的 JIT）仔细的实现语言语义，只需要实现一个解释器就够了。
由于解释器是内存安全的，并且在被转换成 JIT 编译器时也保留了解释器语义，因此用户代码被 JIT 后的行为一定能与解释器的行为一致，
自然而然也是内存安全的。这使得虚拟机很难再出现可被利用的漏洞。

有几个技巧使这成为可能，其中最重要的是一种新的常量形式，它被通过注解引入 Java 中。
在常规编程中，变量要么是可变的，要么是不可变的。不可变变量用特殊关键字（如 `final` 或 `const`）标记，并且只能在声明处赋值一次。
常量对编译器来说非常友好，因为它们可以被折叠，这意味着对它们的引用可以直接替换为它们的值。
考虑以下代码：

```java
class Example {
    private static final int A = 1;
    private static final int B = 2;

    static int answer() {
        return A - B;
    }

    static String doSomething() {
        if (answer() < 0) 
            return "OK" 
        else 
            throw new IllegalStateException();
    }
}
```

很容易看出 `answer()` 方法将始终返回相同的数字。
一个优秀的编译器会把 `1` 和 `2` 带入到表达式中得到 `return 1 -2`，然后提前计算表达式的结果。
随后，编译器会内联对 `answer` 的所有调用（也就是把它的实现复制粘贴到所有调用处），
用 `-1` 替换所有调用，从而消除调用方法的开销。
这又可能触发更多常量折叠，比如对于 `doSomething()` 方法，编译器会证明它永远不会抛出异常，并将 `else` 分支完全删除。
在完成这步后，对 `doSomething` 的调用也可以简单地被替换为 `"OK"`，以此类推。

这很巧妙，但每个编译器都能做到这点……只要在编译时知道常量值即可。
Truffle 通过引入被称为编译时不可变（compilation final）的第三类常量来改变限制。
如果像下面这样在解释器中声明一个变量：

```java
@CompilationFinal private int a = 1;
```

根据访问的时机不同，它的常量性会发生改变。
对于解释器内部而言，它是可变的。你可以使用此类变量实现解释器。
你可以在加载用户程序时设置它们，也可以在程序运行时设置它们。
一旦用户脚本中的函数变“热”，Truffle 将与 Graal 编译器一起重新编译与用户代码相对应的解释器部分，此时 `a` 将被视为常量，即等价于字面量 `1`。

这适用于任何类型的数据，包括复杂的对象。考虑以下经过高度简化的伪代码：

```java
import com.oracle.truffle.api.nodes.Node;

class JavaScriptFunction extends Node {
    @CompilationFinal Node[] statements;

    Object execute() {
        for (var statement : statements) statement.execute();
    } 
}
```

这种类经常出现在经典的 AST 解释器中。其中 `statements` 数组被标记为编译时不可变。
首次加载程序时，我们可以用一些代表用户 JavaScript 函数中语句的对象初始化该数组，因为这个数组是可变的。
当这个对象所表示的函数变“热”了，Truffle 将启动对 `execute()` 方法的特殊编译，其中 Graal 会隐式地将 `this` 视为编译时不可变的。
由于该对象被视为常量，因此 `this.statements` 也可以被视为常量，它将被替换为解释器堆上特定 `JavaScriptFunction` 对象中字段的实际内容，
从而使编译器能够把 `execute` 内的循环展开成这样：


```java
Object execute() {
    this.statements[0].execute();
    this.statements[1].execute();
    this.statements[2].execute();
}
```

这里 `Node` 是一个超类，`execute()` 是虚函数，但这并不重要。
由于 `statements` 是编译时不可变的，其中的各个对象也会被常量折叠，因此可以对 `Node` 的 `execute` 方法进行去虚化（将其解析为实际的具体类型），然后它们也可以继续内联。

我们就这样继续下去。最后，编译器会生成一个与用户的 JavaScript（也可以 Python、C++，或者我们正在实现的任意语言）的语义相匹配的本机函数。
当特定的 `JavaScriptFunction.execute()` 经过编译后，在解释器调用它时，程序会从解释器转移至本机代码再返回。
如果您的解释器需要更改一个 `@CompilationFinal` 字段（可能因为程序更改了它的行为导致你所做的乐观假设失效），那么这绝对没问题。
Truffle 允许你这样做，它会将程序“去优化”（deoptimize）回解释器。
去优化（[相关技术讨论](https://www.youtube.com/watch?v=pksRrON5XfU&t=3259s)）是一种高级技术，通常很难安全地实现，
因为它需要将 CPU 状态映射回解释器状态，而且任何错误都可能被利用（你可以在这看到相关主题）。
但是你不必动手实现这些，这一切都是由 Truffle 为你完成的。

---

## 为什么它会起作用？

部分求值会让事情更快的原因可能不太明显。


解释器之所以很慢，是因为它们必须做出很多决定。用户的程序可以做任何事情，因此解释器必须不断检查许多可能性，以找出程序在确切的时刻试图做什么。
因为分支和内存读取对于 CPU 来说很难快速执行，因此整个程序最终会变得很慢。
这种通过增强的常量折叠编译解释器的技术消除了分支和内存读取。
在此基础上，Truffle 构建了一套 API，可以轻松地为 JavaScript 或任何有解释器的语言实现高级功能和优化。
例如，它提供了一个利用假设的简单 API —— 通过生成不处理边缘情况的代码来提升 JIT 编译和执行速度。
当遇到边缘情况时，它会丢弃生成的代码并重新生成包含处理此情况的代码。

---

## 重编译

上面我们简单提到了“重新编译”，但却忽略了它是如何实现的。我们说过解释器只是本机代码，对吧？

当解释器通过 native-image 进行 AOT 编译以准备分发给用户时，Graal 编译器会识别出自己正在编译使用 Truffle 的程序。
Graal 和 Truffle 是一同开发的，尽管他们可以各自独立使用，但将它们一同使用时它们会互相识别并协同工作。

当 Graal 注意到自己正在 AOT 编译 Truffle 语言时，它会以几种方式改变行为。
首先，它将把自己拷贝至输出的程序中。
然后它会对程序进行静态分析来找到解释器方法，然后存储两个版本的解释器至可执行文件中。
其中一个版本是可以直接执行的机器码，这是常规的通用解释器；
另一个版本是经过精心编码的 Graal 的中间表示（IR）。
IR 介于你编写的源代码与最终执行的机器代码之间（Graal 的 IR 是一个对象图）。
Graal 还会编译一个 GC，这个 GC 可能是先进成熟的 G1 GC（如果使用 Oracle GraalVM），
也可能是用[纯 Java 编写的更简单的 GC](https://github.com/oracle/graal/tree/master/substratevm/src/com.oracle.svm.core.genscavenge/src/com/oracle/svm/core/genscavenge)（如果使用 GraalVM CE）。

当用户函数变“热”时，Truffle 会在嵌入的 IR 中查找“执行用户函数”节点，并对其进行部分求值。
求值与解析图 IR 交织在一起，以确保过程尽可能高效——如果某些部分因为不断折叠已经证明其因无法到达而不会被执行，编译器甚至不会对它进行解码或查看。
这也确保了编译过程中的内存使用率保持在较低水平。

## My only friend, the end

就是这样！这就是 GraalJS 消除这一整类微妙的安全漏洞的方法：因为语言的语义是由内存安全的解释器所定义的，然后再对其进行部分求值，
所以最后生成的机器码在构造上也是内存安全的。

那么原始博客文章中所提到的 V8 沙盒呢？将指针表示为堆基址的偏移量是一个好主意，[它已经在 GraalVM 本机编译的二进制文件中被使用](https://medium.com/graalvm/isolates-and-compressed-references-more-flexible-and-efficient-memory-management-for-graalvm-a044cc50b67e)。
然而，这样做是为了提高性能，因为其他内存安全机制意味着无需缓解堆覆盖。

以上内容都不是 JavaScript 独有的，Truffle 的优势也不仅限于安全性和性能。
事实上，Truffle 会自动为你的语言添加很多功能，
例如调试（通过 Chrome 调试器的 wire 协议）、与 Java/Kotlin/所有 Truffle 语言互操作、快速的正则表达式引擎、快速的外部函数接口、profiling 工具、堆快照等等。
Truffle 已经被用于为数十种语言构建三十多个语言虚拟机，其中包含你意想不到的功能的语言，比如 [Apple 最近推出的 Pkl 配置语言](https://pkl-lang.org/index.html)。

如果本文让你产生了了解更多信息的兴趣，请看看[文档](https://www.graalvm.org/latest/graalvm-as-a-platform/language-implementation-framework/)和这篇关于它如何工作的[技术讲座](https://www.youtube.com/watch?v=pksRrON5XfU)。
