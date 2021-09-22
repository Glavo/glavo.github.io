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