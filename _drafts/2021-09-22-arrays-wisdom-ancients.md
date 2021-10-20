---
title: Arrays of Wisdom of the Ancients
date: 2021-09-22 22:25:00
tags:
- JVM
categories: translate
description: Arrays of Wisdom of the Ancients 翻译
---

原文链接：[Arrays of Wisdom of the Ancients](https://shipilev.net/blog/2016/arrays-wisdom-ancients/#_new_reflective_array)

Aleksey Shipilёv, [@shipilev](http://twitter.com/shipilev), [aleksey@shipilev.net](aleksey@shipilev.net)

## 简介

Java 语言和 JDK 类库有两种不同但相关的方式对元素进行分组：数组和集合。
使用其中任意一个都有利有弊，因此在实际程序中都很普遍。
为了帮助在两者之间进行转换，有一些标准方法可以引用数组让其表现为集合（例如 `Arrays.asList`），
以及从集合复制到数组（例如几个 `Collection.toArray` 方法）。
在这篇文章中，我们将尝试回答一个有争议的问题：哪种 `toArray` 转换模式更快？

这篇文章使用 [JMH](http://openjdk.java.net/projects/code-tools/jmh/) 作为研究坩埚。
如果您还没有了解过它，并且还没有浏览过 [JMH 的示例](http://hg.openjdk.java.net/code-tools/jmh/file/tip/jmh-samples/src/main/java/org/openjdk/jmh/samples/)，
我建议您在阅读本文的其余部分之前先了解它，以获得最佳体验。
一些 x86 汇编知识也很有用，虽然这些不是必要的。

## API 设计

在集合上盲目地调用 `toArray` 和遵循通过工具或疯狂在互联网上搜索找到的建议似乎是很自然的。
但是，如果我们查看 `Collection.toArray` 的一系列方法，我们可以看到两种不同的方法：

```java
public interface Collection<E> extends Iterable<E> {

    /**
     * Returns an array containing all of the elements in this collection.
     *
     * ...
     *
     * @return an array containing all of the elements in this collection
     */
    Object[] toArray();

    /**
     * Returns an array containing all of the elements in this collection;
     * the runtime type of the returned array is that of the specified array.
     * If the collection fits in the specified array, it is returned therein.
     * Otherwise, a new array is allocated with the runtime type of the
     * specified array and the size of this collection.
     *
     * ...
     *
     * @param <T> the runtime type of the array to contain the collection
     * @param a the array into which the elements of this collection are to be
     *        stored, if it is big enough; otherwise, a new array of the same
     *        runtime type is allocated for this purpose.
     * @return an array containing all of the elements in this collection
     * @throws ArrayStoreException if the runtime type of the specified array
     *         is not a supertype of the runtime type of every element in
     *         this collection
     */
    <T> T[] toArray(T[] a);
```

这些方法表现出微妙的不同，这是有原因的。泛型的类型擦除带来的阻抗迫使我们要使用实际参数精准地拼写出目标数组类型。
请注意，简单地将 `toArray()` 返回的 `Object[]` 强制转换为 `ConcreteType[]` 是不可行的，因为运行时必须保持类型安全——尝试这样转换数组会导致 `ClassCastException`。

接受数组的方法还可以通过预分配的数组防止结果。事实上，前辈的经验可能会告诉我们，为了得到最佳性能，我们最好提供预先确定好长度的数组（甚至可能长度为零！）。
IntelliJ IDEA 15 建议我们传递预先确定好长度的数组，而不是懒惰地传递传递长度为零的数组。
它接着解释说，库必须通过反射调用来分配给定运行时类型的数组，这会付出一定的开销。

![图一：IntelliJ IDEA 15 试图帮助我们](https://z3.ax1x.com/2021/09/22/4aZ7b4.png)

PMD 的 OptimizableToArrayCall 规则告诉我们同样的事情，但似乎还暗示了新分配的“空”数组将被丢弃，我们应该通过传递预先确定好长度的数组来避免这种情况。

![图二：PMD 5.4.1 试图帮助我们](https://z3.ax1x.com/2021/09/22/4aedZ4.png)

前辈们到底有多聪明？

## 性能运行

### 实验装置

在我们进行实验前，我们需要了解它的自由度。至少有三个方面需要考虑：

1. **集合的大小。**PMD 的规则表明，分配将被丢弃的数组是徒劳的。这意味着我们希望涵盖一些小的集合，以了解“无意义”的数组实例化的开销。
   我们还希望看到复制元素的成本为主的大型集合的性能如何。当然，为了避免“最佳性能点”，我们还会增加大小介于两者之间的集合测试。

2. **toArray() 参数的形状。**当然，我们想测试 `toArray` 调用的所有变体。其中特别令人感兴趣的是使用零长数组和预确定长度的数组的调用，
   但非类型化的 `toArray` 作为参考也非常有趣。

3. **集合中 toArray() 的实现。**IDEA 的建议说明了存在可能会降低性能的反射数组实例化。我们需要调查实际使用的集合。
   大多数集合的行为与 `AbstractCollection` 相同：
   分配 `Object[]` 或 `T[]` 数组——在后一种情况下使用了 `java.lang.reflect.Array::newInstance` 分配 `T[]` 数组——然后使用迭代器将元素逐一复制到目标数组中。

    ```java
    public abstract class AbstractCollection {
        public <T> T[] toArray(T[] a) {
            int size = size();
            T[] r = (a.length >= size) ?
                     a : (T[])Array.newInstance(a.getClass().getComponentType(), size);
            Iterator<E> it = iterator();
            for (int i = 0; i < r.length; i++) {
                ...
                r[i] = (T)it.next();
            }
            return ... r;
        }
    }
   ```

   某些集合（特别是 `ArrayList`）只需将它背后存储用的数组元素复制到目标数组中：
    
    ```java
    public class ArrayList {
        public <T> T[] toArray(T[] a) {
            if (a.length < size) {
                // Arrays.copyOf would do the Array.newInstance
                return (T[]) Arrays.copyOf(elementData, size, a.getClass());
            }
            System.arraycopy(elementData, 0, a, 0, size);
            if (a.length > size) {
                a[size] = null;
            }
            return a;
        }
    }
    ```
   
   `ArrayList` 是最常用的集合类之一，因此我们希望了同时了解*普遍的* `ArrayList`，以及*通用的*基于 `AbstractCollection` 的集合（像 `HashSet`）的性能。


### 基准

通过以上观察，我们可以构建出以下 JMH 基准：

```java
@Warmup(iterations = 5, time = 1, timeUnit = TimeUnit.SECONDS)
@Measurement(iterations = 5, time = 1, timeUnit = TimeUnit.SECONDS)
@Fork(value = 3, jvmArgsAppend = {"-XX:+UseParallelGC", "-Xms1g", "-Xmx1g"})
@BenchmarkMode(Mode.AverageTime)
@OutputTimeUnit(TimeUnit.NANOSECONDS)
@State(Scope.Benchmark)
public class ToArrayBench {

    @Param({"0", "1", "10", "100", "1000"})
    int size;

    @Param({"arraylist", "hashset"})
    String type;

    Collection<Foo> coll;

    @Setup
    public void setup() {
        if (type.equals("arraylist")) {
            coll = new ArrayList<Foo>();
        } else if (type.equals("hashset")) {
            coll = new HashSet<Foo>();
        } else {
            throw new IllegalStateException();
        }
        for (int i = 0; i < size; i++) {
            coll.add(new Foo(i));
        }
    }

    @Benchmark
    public Object[] simple() {
        return coll.toArray();
    }

    @Benchmark
    public Foo[] zero() {
        return coll.toArray(new Foo[0]);
    }

    @Benchmark
    public Foo[] sized() {
        return coll.toArray(new Foo[coll.size()]);
    }

    public static class Foo {
        private int i;

        public Foo(int i) {
            this.i = i;
        }

        @Override
        public boolean equals(Object o) {
            if (this == o) return true;
            if (o == null || getClass() != o.getClass()) return false;
            Foo foo = (Foo) o;
            return i == foo.i;
        }

        @Override
        public int hashCode() {
            return i;
        }
    }
}
```

> 由于此基准是 GC 密集型的，因此固定 GC 算法和堆大小很重要，这样可以避免启发式算法带来的意外的行为改变。 

### 性能数据

在相当大的 i7-4790K、4.0 GHz、Linux x86_64、JDK 9b99 EA 上运行，将产生（平均执行时间，越低越好）：

```
Benchmark            (size)     (type)  Mode  Cnt      Score    Error  Units

# ---------------------------------------------------------------------------

ToArrayBench.simple       0  arraylist  avgt   30    19.445 ±   0.152  ns/op
ToArrayBench.sized        0  arraylist  avgt   30    19.009 ±   0.252  ns/op
ToArrayBench.zero         0  arraylist  avgt   30     4.590 ±   0.023  ns/op

ToArrayBench.simple       1  arraylist  avgt   30     7.906 ±   0.024  ns/op
ToArrayBench.sized        1  arraylist  avgt   30    18.972 ±   0.357  ns/op
ToArrayBench.zero         1  arraylist  avgt   30    10.472 ±   0.038  ns/op

ToArrayBench.simple      10  arraylist  avgt   30     8.499 ±   0.049  ns/op
ToArrayBench.sized       10  arraylist  avgt   30    24.637 ±   0.128  ns/op
ToArrayBench.zero        10  arraylist  avgt   30    15.845 ±   0.075  ns/op

ToArrayBench.simple     100  arraylist  avgt   30    40.874 ±   0.352  ns/op
ToArrayBench.sized      100  arraylist  avgt   30    93.170 ±   0.379  ns/op
ToArrayBench.zero       100  arraylist  avgt   30    80.966 ±   0.347  ns/op

ToArrayBench.simple    1000  arraylist  avgt   30   400.130 ±   2.261  ns/op
ToArrayBench.sized     1000  arraylist  avgt   30   908.007 ±   5.869  ns/op
ToArrayBench.zero      1000  arraylist  avgt   30   673.682 ±   3.586  ns/op

# ---------------------------------------------------------------------------

ToArrayBench.simple       0    hashset  avgt   30    21.270 ±   0.424  ns/op
ToArrayBench.sized        0    hashset  avgt   30    20.815 ±   0.400  ns/op
ToArrayBench.zero         0    hashset  avgt   30     4.354 ±   0.014  ns/op

ToArrayBench.simple       1    hashset  avgt   30    22.969 ±   0.221  ns/op
ToArrayBench.sized        1    hashset  avgt   30    23.752 ±   0.503  ns/op
ToArrayBench.zero         1    hashset  avgt   30    23.732 ±   0.076  ns/op

ToArrayBench.simple      10    hashset  avgt   30    39.630 ±   0.613  ns/op
ToArrayBench.sized       10    hashset  avgt   30    43.808 ±   0.629  ns/op
ToArrayBench.zero        10    hashset  avgt   30    44.192 ±   0.823  ns/op

ToArrayBench.simple     100    hashset  avgt   30   298.032 ±   3.925  ns/op
ToArrayBench.sized      100    hashset  avgt   30   316.250 ±   9.614  ns/op
ToArrayBench.zero       100    hashset  avgt   30   284.431 ±   6.201  ns/op

ToArrayBench.simple    1000    hashset  avgt   30  4227.564 ±  84.983  ns/op
ToArrayBench.sized     1000    hashset  avgt   30  4539.614 ± 135.379  ns/op
ToArrayBench.zero      1000    hashset  avgt   30  4428.601 ± 205.191  ns/op

# --------------------------------------------------------------------------- 
```

好吧，看起来 `simple` 转换胜过其他的一切，并且与直觉相反，`zero` 转换胜过了 `sized` 转换。

> 这这一点上，大多数人犯了一个重大错误：他们采用了这些数字，就像它们是真的一样。但这些数字只是数据，除非我们从中提炼出要点，否则它们没有任何意义。要做到这一点，我们需要了解为什么数字是这样的。

仔细查看数据，我们希望得到两个主要问题的答案：

1. 为什么 `simple` 似乎比 `zero` 和 `sized` 更快？
2. 为什么 `zero` 似乎比 `sized` 更快？

回答这些问题是理解正在发生的事情的途径。

> 任何优秀的性能工程师，在开始调查前尝试猜测答案以找出实际答案是一种训练直觉的联系。花几分钟时间对这些问题做出合理的假设性回答。你需要做什么实验来证实这些假设？什么样的实验可以证伪它们？

### 不是分配压力

我想抛出一个简单的假设：分配压力。人们可能会猜测，不同的分配压力可以解释性能的差异。事实上许多 GC 密集型负载也是与 GC 绑定的，这意味着基准性能与 GC 性能紧密相连。

通常来说，把很多基准转换为与 GC 绑定的基准很容易。在我们的例子中，我们使用单个线程允许基准代码，这使得 GC 线程可以自由地在不同的核心上运行，
并使用多个 GC 线程收集单个基准线程的垃圾。添加更多基准线程将使他们：a) 与 GC 线程争夺 CPU 时间，从而隐式地计算 GC 时间；
b) 产生更多垃圾，从而使每个应用程序线程的有效 GC 线程数下降，从而增加内存管理成本。

> 这就是为什么您通常希望同时在单线程和多线程（饱和）模式下运行基准测试的原因之一。在饱和模式下运行能够捕获系统正在执行的任何“隐秘”的卸载活动。

但是在我们的例子中，我们可以走捷径估测分配压力。为此，JMH 有一个 `-prof gc` 分析器，它监听 GC 事件，将它们相加，
并将分配/流失率标准化为 benchmark ops 的数量，威宁提供每个 `@Benchmark` 调用的分配压力。

*分配压力（该表仅展示“gc.alloc.rate.norm”指标）*

```
Benchmark           (size)     (type)  Mode  Cnt    Score    Error  Units

# ------------------------------------------------------------------------

ToArrayBench.simple      0  arraylist  avgt   30    16.000 ± 0.001  B/op
ToArrayBench.sized       0  arraylist  avgt   30    16.000 ± 0.001  B/op
ToArrayBench.zero        0  arraylist  avgt   30    16.000 ± 0.001  B/op

ToArrayBench.simple      1  arraylist  avgt   30    24.000 ± 0.001  B/op
ToArrayBench.sized       1  arraylist  avgt   30    24.000 ± 0.001  B/op
ToArrayBench.zero        1  arraylist  avgt   30    40.000 ± 0.001  B/op

ToArrayBench.simple     10  arraylist  avgt   30    56.000 ± 0.001  B/op
ToArrayBench.sized      10  arraylist  avgt   30    56.000 ± 0.001  B/op
ToArrayBench.zero       10  arraylist  avgt   30    72.000 ± 0.001  B/op

ToArrayBench.simple    100  arraylist  avgt   30   416.000 ± 0.001  B/op
ToArrayBench.sized     100  arraylist  avgt   30   416.000 ± 0.001  B/op
ToArrayBench.zero      100  arraylist  avgt   30   432.000 ± 0.001  B/op

ToArrayBench.simple   1000  arraylist  avgt   30  4016.001 ± 0.001  B/op
ToArrayBench.sized    1000  arraylist  avgt   30  4016.001 ± 0.002  B/op
ToArrayBench.zero     1000  arraylist  avgt   30  4032.001 ± 0.001  B/op

# ------------------------------------------------------------------------

ToArrayBench.simple      0    hashset  avgt   30    16.000 ± 0.001  B/op
ToArrayBench.sized       0    hashset  avgt   30    16.000 ± 0.001  B/op
ToArrayBench.zero        0    hashset  avgt   30    16.000 ± 0.001  B/op

ToArrayBench.simple      1    hashset  avgt   30    24.000 ± 0.001  B/op
ToArrayBench.sized       1    hashset  avgt   30    24.000 ± 0.001  B/op
ToArrayBench.zero        1    hashset  avgt   30    24.000 ± 0.001  B/op

ToArrayBench.simple     10    hashset  avgt   30    56.000 ± 0.001  B/op
ToArrayBench.sized      10    hashset  avgt   30    56.000 ± 0.001  B/op
ToArrayBench.zero       10    hashset  avgt   30    56.000 ± 0.001  B/op

ToArrayBench.simple    100    hashset  avgt   30   416.000 ± 0.001  B/op
ToArrayBench.sized     100    hashset  avgt   30   416.001 ± 0.001  B/op
ToArrayBench.zero      100    hashset  avgt   30   416.001 ± 0.001  B/op

ToArrayBench.simple   1000    hashset  avgt   30  4056.006 ± 0.009  B/op
ToArrayBench.sized    1000    hashset  avgt   30  4056.007 ± 0.010  B/op
ToArrayBench.zero     1000    hashset  avgt   30  4056.006 ± 0.009  B/op

# ------------------------------------------------------------------------
```

数据确实表明，在相同大小下分配压力基本相同。在某些情况下，`zero` 测试会多分配 16 字节——这是“冗余”数组分配的成本。
（读者练习：为什么 `zero` 在 HashSet 的情况下相同？）。但是，我们上面的吞吐量基准表明 `zero` 的情况更快，
而不是像分配压力假设所预测的那样更慢。因此，分配压力不能解释我们所看到的现象。

## 性能分析

在我们的领域，我们可以跳过假设的建立，直接使用强大的工具戳破这些东西。如果我们做一会事后诸葛亮，直接得出结论，这一部分可能更短。
但是这篇文章的要点之一是展示分析这些基准的方法。

### 认识 VisualVM（和其他仅限于 Java 的分析器）

最显然的方法是将 Java 分析器附加到基准 JVM 上，然后查看那里发生了什么。在不失通用性的情况下，让我们使用 JDK 本身附带的 VisualVM 分析器，
它可以在大多数安装中直接使用。

使用它非常容易：启动应用程序，启动 VisualVM（如果 JDK 在你的 PATH 中，直接执行 `jvisualvm` 就可以了），
从列表中选择一个目标 VM，从下拉列表或选项卡中选择 **“Sample”**，点击 **“CPU Sampling”**，然后享受结果。
让我们做一个测试，看看它显示了什么：


![图三：“ToArrayBench.simple”情况下 ArrayList 大小为 1000 时的 VisualVM 分析器截图](https://shipilev.net/blog/2016/arrays-wisdom-ancients/visualvm-sample-simple.png)

呃……信息量很大。

大多数 Java 分析器是有固有偏差的，因为它们要么插入代码，所以会导致真实结果偏差，要么[在代码中的指定位置（例如安全点）采样](http://jeremymanson.blogspot.co.uk/2010/07/why-many-profilers-have-serious.html)，
这也会扭曲结果。在我们上面的例子中，虽然大部分工作是在 `simple()` 方法中完成的，但是分析器错误的将工作归因于保存基准循环的 `…_jmhStub` 方法。

但这不是这里的核心问题。对我们来说，最大的问题是缺少任何可以帮我们回答性能问题的低级细节。你能在上面的分析截图中看到任何可以验证我们的例子中任何合理假设的东西吗？
不能，因为数据太粗糙了。请注意，对于更大的工作负载来说这不是一个问题，因为性能现象展现在更大、更分散的调用树中。在这些工作负载中，偏差的影响被平摊了。

### 认识 JMH -prof perfasm

需要探索微基准的底层细节，这就是为什么好的微基准测试工具提供了一种清晰的方式剖解、分析和内省小的工作负载。
对于 JMH，我们有一个内置的 **“perfasm”** 分析器，它从 VM 中转储 [PrintAssembly](https://wiki.openjdk.java.net/display/HotSpot/PrintAssembly) 的输出，
用 [perf_events](http://www.brendangregg.com/perf.html) 计数器对其进行注释，并打印出最热点的部分。
perf_events 使用硬件计数器提供非侵入式采样分析，这是我们想要的细粒度性能工程。

以下是其中一项测试的示例输出：

```
$ java -jar target/benchmarks.jar zero -f 1 -p size=1000 -p type=arraylist -prof perfasm
....[Hottest Region 1].......................................................................
 [0x7fc4c180916e:0x7fc4c180920c] in StubRoutines::checkcast_arraycopy

StubRoutines::checkcast_arraycopy [0x00007fc4c18091a0, 0x00007fc4c180926b]
  0.04%                  0x00007fc4c18091a0: push   %rbp
  0.06%    0.01%         0x00007fc4c18091a1: mov    %rsp,%rbp
  0.01%                  0x00007fc4c18091a4: sub    $0x10,%rsp
  0.02%    0.01%         0x00007fc4c18091a8: mov    %r13,(%rsp)
  0.14%    0.02%         0x00007fc4c18091ac: mov    %r14,0x8(%rsp)
  0.07%    0.02%         0x00007fc4c18091b1: lea    (%rdi,%rdx,4),%rdi
  0.01%                  0x00007fc4c18091b5: lea    (%rsi,%rdx,4),%r13
                         0x00007fc4c18091b9: mov    %rdx,%r14
  0.02%                  0x00007fc4c18091bc: neg    %rdx
  0.01%    0.01%   ╭     0x00007fc4c18091bf: jne    0x00007fc4c18091de
                   │     0x00007fc4c18091c5: xor    %rax,%rax
                   │     0x00007fc4c18091c8: jmpq   0x00007fc4c1809260
                   │     0x00007fc4c18091cd: data16 xchg %ax,%ax
 19.30%   19.73%   │↗↗↗  0x00007fc4c18091d0: mov    %eax,0x0(%r13,%rdx,4)
  5.96%    6.89%   ││││  0x00007fc4c18091d5: inc    %rdx
                   ││││  0x00007fc4c18091d8: je     0x00007fc4c1809233
  3.84%    4.92%   ↘│││  0x00007fc4c18091de: mov    (%rdi,%rdx,4),%eax
  5.83%    6.56%    │││  0x00007fc4c18091e1: test   %rax,%rax
                    ╰││  0x00007fc4c18091e4: je     0x00007fc4c18091d0
 14.88%   20.52%     ││  0x00007fc4c18091e6: mov    0x8(%rax),%r11d
 15.11%   19.60%     ││  0x00007fc4c18091ea: shl    $0x3,%r11
 10.65%   11.80%     ││  0x00007fc4c18091ee: cmp    %r8,%r11
  0.01%              ╰│  0x00007fc4c18091f1: je     0x00007fc4c18091d0
                      │  0x00007fc4c18091f3: cmp    (%r11,%rcx,1),%r8
                      ╰  0x00007fc4c18091f7: je     0x00007fc4c18091d0
                         0x00007fc4c18091f9: cmp    $0x18,%ecx
                         0x00007fc4c18091fc: jne    0x00007fc4c1809223
                         0x00007fc4c1809202: push   %rax
                         0x00007fc4c1809203: mov    %r8,%rax
                         0x00007fc4c1809206: push   %rcx
                         0x00007fc4c1809207: push   %rdi
                         0x00007fc4c1809208: mov    0x20(%r11),%rdi
                         0x00007fc4c180920c: mov    (%rdi),%ecx
.............................................................................................
 75.96%   90.09%  <total for region 1>
 ```

