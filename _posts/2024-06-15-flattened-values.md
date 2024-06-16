---
title: 'Java 值对象的内存布局'
date: 2024-06-15 10:37:14
tags:
  - JVM
  - Valhalla
categories: blog
description: 'Java 值对象的内存布局'
---

OpenJDK 的 Project Valhalla 正在将值类型引入 Java，通过允许用户声明值类（value class），使 JVM 能够更自由的排布对象。这篇文章将会介绍值对象的内存布局的可选方案。

## 值类

在介绍值对象的布局之前，先让我快速介绍一下 Valhalla 中的值类。如果你对 Valhalla 已经有所了解，可以跳过这一小节。

Valhalla 中的值类是以 `value` 这个上下文关键字所修饰的类：

```java
public value class MyClass {
  // ...
}
```

值类的实例就是值对象，它们的主要特点在于：

* 所有字段都必须是 `final` 的；
* 不支持通过 `synchronized` 对值对象进行加锁；
* `==` 对于值对象来说不再是比较引用，而是递归的对于所有字段应用 `==`；
* `System.identityHashCode` 对于值对象会基于它的字段进行计算，字段值完全相同的值对象的 `identityHashCode` 也完全一致；
* 无法对它们使用 `java.lang.ref` 包中的工具（比如 `WeakReference`）。

因为这些特点，JVM 能够更自由的排布对象，减少装箱，从而优化性能内存占用。

## 主要问题

在 JVM 为值对象优化内存布局时，有两个问题我们需要特别考虑：一致性和空引用（`null`）。

### 一致性

看看这段代码：

```java
record Pair(long v0, long v1) {}

class MyClass {
    Pair pair = new Pair(0L, 0L);
}

var c = new MyClass();
new Thread(() -> c.pair = new Pair(10L, 20L)).start();
System.out.println("c.pair = " + c.pair);

```

上面的代码中，`Pair` 拥有两个字段，但即便是在另一个线程中修改 `MyClass.pair` 这个字段，我们也能保证它要么是 `[0, 0]`，要么是 `[10, 20]`。

对于引用类型来说，这是自然而然的，毕竟 `MyClass.pair` 这个字段只是一个引用，或者说是一个指针。我们先在线程本地构造了一个包含新值的对象，这一步不涉及多线程，非常安全；随后我们去更新 `MyClass.pair` 这个字段中存储的指针值，这个过程是原子的，另一个线程中观察到的要么是旧对象的地址，要么是新对象的地址，不可能出现一个损坏的对象，所以也很安全。

但是如果 `Pair` 是一个值类型，那么这件事就不这么简单了。

如果 `Pair` 是值类型，那么我们可能会期望上面的代码被优化成这样：

```java
class MyClass {
    long pair$v0 = 0L;
    long pair$v1 = 0L;
}

var c = new MyClass();
new Thread(() -> { 
    c.pair$v0 = 10L;
    c.pair$v1 = 10L;
}).start();
System.out.println("c.pair = " + c.pair);
```

但如果真的这样实现那问题就来了，因为给 `c.pair$v0` 和 `c.pair$v1` 的赋值变成了两步。假如我们刚好在 `c.pair$v0 = 10L` 与 `c.pair$v1 = 10L` 这两句之间去观察 `c.pair`，那么它的值就可能是 `[10, 0]`，这里就发生了字段撕裂，破坏了一致性。

这乍一看不是什么大问题，但仔细一想，我们从没有调用过 `new Pair(10, 0)`，这个 `[10, 0]` 是绕过构造函数凭空被创造而出的，这就是个大问题了。如果我们在构造函数里对参数值进行检查以保证安全，那么字段撕裂就可能绕过安全检查构造出非法值，这是无法接受的。

对于 Valhalla 的值类型，JVM 默认也会通过一些额外的手段维护一致性，同时它允许你标注特定类型放弃一致性，从而让 JVM 能够进一步优化它。

### 空引用

Java 目前所有引用类型的变量/字段/数组元素都支持空引用（`null`）。

Valhalla 的值类型支持空引用，原有的使用了 `null` 的代码不需任何更改也能享受到值类型的改进，JVM 通过**空通道（null channel）**来支持此这种功能；Valhalla 也允许将值类型标记为不可空类型，此时 JVM 无需考虑 `null`，能够更自由地处理值类型。

## 布局方案

值对象可能是另一个对象的字段成员，也可能是数组中的元素，我们需要考虑如何“展平”它，把它嵌入它的父级（也就是包含值对象字段的对象，或者元素是值对象的数组）中。

这一节会简单介绍值对象的布局方案，而后面几节会阐述它们如何支持 `null`、如何维护一致性等高级细节。

### 无头对象

对于这样一个普通的 Java 类：

```java
class MyClass {
    private T0 field0;
    private T1 field1;
    private T2 field2;
    
    // ...
}
```

它的实例的内存布局类似这样：

```cpp
struct MyClass {
    ObjectHeader header;
    
    struct Body { 
        T0 field0;
        T1 field1;
        T2 field2;
    
        // ...
    } body;
};
```

可以看到，Java 每个堆上对象的起始位置都有一个对象头，用于存储对象的类型、GC 辅助信息、锁相关信息等等，通常占 4~16 字节，随后便是它的字段。

对于值对象，如果我们想把他嵌入另一个对象中，我们可以选择直接将对象头删掉，直接把 `MyClass::Body` 这个结构体嵌入进来：。

比如对于这样一个类：

```java
class OtherClass {
    int intField;
    String stringField;
    MyClass myClassField;
}
```

如果 `MyClass` 成为值类，那么它的内存布局可以优化成这样：

```cpp
struct OtherClass {
    ObjectHeader header;
    
    jint intField;
    jobject stringField;
    MyClass::Body myClassField;
}
```

这种布局很容易实现，而且这种实现方式下，`MyClass` 不管是真正在堆上分配，还是被嵌入到其他对象内部，它的成员布局还是一致的，访问成员时只需要调整基址即可，生成的代码都能被复用。

### 熔化重组字段

直接去除对象头是一种简单的实现方式，但并不总是最高效的。JVM 可以选择将一个对象中包含的值对象的成员全部“熔化”，拆散成一个个的字段，然后再重新组织它们。

比如对于这样的代码：

```java
value record R0(String strValue, byte byteValue) {}
value record R1(Object objValue, short shortValue, R0 r0) {}
record R2(boolean boolValue, R1 r1) {}
```

对于上面的 `R2`，如果以无头对象的方式实现和 `R0` 和 `R1` ，它的布局可能是这样的：

```cpp
// 直接把 R0 和 R1 的布局嵌入进来
struct R2 {
    ObjectHeader header;
    
    jboolean boolValue;
    struct {
        jobject objValue;
        jshort shortValue;
    
        struct {
            jobject strValue;
            jbyte byteValue;
        } r0;
    } r1;
};
```

这种实现方式直截了当，但是有一些问题。为了让程序在现代计算机上更高效，结构体的字段并不是紧凑排列的，而是会填充一些空位来对齐它们。

假设我们正在使用 64 位计算机，对象头的大小是 8 字节，Java 对象引用大小是 4 字节（得益于压缩指针技术，64 位 JVM 中的对象引用通常会被压缩到 32 位），那么它的实际布局会像这样：

```cpp
struct R2 {
    ObjectHeader header;        // 8 bytes
    
    jboolean boolValue;         // 1 byte
    // padding                  // 7 bytes
    jobject objValue;           // 4 bytes
    jshort shortValue;          // 2 bytes
    // padding                  // 2 bytes
    jobject strValue;           // 4 bytes
    jbyte byteValue;            // 1 byte
    // padding                  // 3 bytes
};
```

那么一个 `R2` 对象的大小将为 32 字节。

而 JVM 可以选择另一种实现嵌入值对象的方式：把这些嵌套的值对象的字段全部拆散（熔化），由 JVM 自动重新排序它们，最后其布局可能会是这样：

```cpp
struct R2 {
    ObjectHeader header;        // 8 bytes
    
    jobject objValue;           // 4 bytes
    jobject strValue;           // 4 bytes
    jboolean boolValue;         // 1 byte
    jbyte byteValue;            // 1 byte
    jshort shortValue;          // 2 bytes
    // padding                  // 4 bytes
};
```

这样的排序下，`R2` 对象的大小只有 24 字节。

这种实现方式具有两个优点：

1. 通过重排字段能够减少对齐填充，从而使对象结构更紧凑，减小内存占用，也能减轻 CPU 缓存压力，提升性能；
2. 重排字段时能够将 Java 对象引用排列在一起，使 GC 能更快的找到所有引用类型的字段。

### 交替分块数组

上面所有举的例子都使用普通的对象作为容器，没有提到数组。

对于数组来说，实现无头对象很容易，而想对值类型成员实现熔化重组，就要使用一种叫做**交替分块数组（alternating blocked array，简称 ABA）**的技术。

简而言之，我们可以把连续的几个值对象放在一起重排它们的字段。 

比如对于这样一个类：

```java
value record ObjAndLong(Object obj, long l) {}
```

我们可以把连续的四个 `ObjAndLong` 的实例放在一起组成一个块，并对它们的字段进行重排：

```cpp
struct ObjAndLong$Block4 {
    jobject obj[4];
    jlong l[4];
}
```

这样原本每个 `ObjAndLong` 实例在数组中的大小是 16 字节（4 字节引用 + 4 字节对齐填充 + 8 字节 `long`），四个就要占用 64 字节，但像上面这样重排后就只需要 48 字节。

交替分块数组除了更紧凑（对于一些支持 `null` 元素的数组来说尤为重要）外，它还能把相关的数据排布到一起，这能够使一些处理数组成员的某个字段的代码更快速（可以看看[这个示例](https://cr.openjdk.org/~jrose/values/ab_array_code.txt)）。

### 堆上分配

除了上面所说的这些方案，值对象还有有一种非常简单的实现方案：像普通对象一样直接在堆上分配它，所有该类型的字段全部保存对这个堆上对象的引用（指针）。

由于值对象只是一种受到的约束更严格、功能更少的对象，直接在堆上分配它没有任何问题。

当然，采用这种方案的时候，我们享受不了多少值类型的优点，但这种实现方案很简单，不需要额外手段来支持 `null` 和维护一致性，对于现有代码不会发生意料之外的性能变化，这是一个缓慢但是有效的后备方案。JVM 解释器模式下可能会默认选择此方案，而 JIT 模式下对于一些过于庞大到拷贝和维护一致性的开销非常昂贵的值对象也会考虑在堆上进行分配。

## 空通道

Valhalla 的值类型方案也支持在展平值对象的同时支持 `null`，比如下面这个例子：

```java
value record NameAndValue(String name, long value) {}

class NullChannelExample {
    R field; // OK!
}

var example = new NullChannelExample();
assert example.field == null;
example.field = new NameAndValue("name", 10L); // OK
example.field = null; // OK
```

在这个例子中，`NullChannelExample` 中的字段 `field` 完全可以被展平，同时它也可以被赋值为 `null`！JVM 是通过**空通道（null channel）**实现这种功能的。

上面的例子中，`NullChannelExample` 的实际布局可能是下面这样：

```cpp
struct NullChannelExample {
    ObjectHeader header;
    
    struct NameAndValue {
        jobject name;
        jbyte null_channel;   // <- null channel 
        // padding: 3 bytes
        jlong value;
    } field;
};
```

可以看到，JVM 在展平 `field` 时可以自动在其中插入一个 `null_channel` 字段，这个字段就是空通道。

`field.null_channel` 为 `0` 时，`field` 的其他字段都会被忽略，它的值在 Java 中等于 `null`。

由于 Java 对象/数组在初始化时会清零整个对象体，空通道自然会被填充为 `0`，这样以来对象在初始状态下 `field` 的值就刚好是 `null`，保持了与引用字段一样的语义，就不需要再付出任何额外开销来将其初始化为 `null`。

JVM 也不是随意插入的空通道。你可能注意到了，上面 JVM 插入空通道的位置刚好是对齐填充的位置，所以增加这个字段没有任何额外的空间开销。这不是巧合，而是 JVM 刻意为之，JVM 会利用这些**裕量（slack）**，在尽可能不增加空间开销的情况下实现空通道。

### 裕量

所谓**裕量（slack）**是一些被浪费的空间，这些空间可以被 JVM 所利用来实现空通道。

Java 对象中经常会有一些裕量：

* `boolean` 字段通常存储为 1 字节（8 位）的整数，支持表示 256 个状态，但 `boolean` 实际只有 2 个状态，因此存在 254 个状态的裕量。
* 对象的引用通常存储为 32 位或 64 位的整数，但并不是每个整数都指向一个合法的对象，其中可以找出难以计数的大量裕量。
  比如我们可以保留一百个低位地址，在这些地址上永远不会分配真正的对象，那么我们可以把这些地址称为**准空（quasinull）地址**，指向这些地址的引用就可以用来表示一些其他状态。
* 一些字段的值存在逻辑上的限制，一些值永远不会出现，从而产生了裕量。
  比如一个 `int` 字段的值可能永远为非负数，所以所有负数的状态都是裕量，它存在 2^31 个裕量。 
* 对象的字段之间可能会有一些对齐填充，所有对齐填充都是可利用的裕量。

前面已经举过了一个利用对齐填充实现空通道的例子。除了对齐填充，JVM 也会经常利用 `boolean` 字段的裕量实现空通道，比如下面这个例子：

```java
value record BoolAndByte(boolean boolValue, byte byteValue) {}

class BoolNullChannelExample {
    BoolAndByte value;
}
```

其中 `BoolNullChannelExample` 的内存布局类似这样：

```cpp
struct BoolNullChannelExample {
    ObjectHeader header;
    
    struct BoolAndByte {
        jbyte boolValue;
        jbyte byteValue;
    } field;
};
```

可以看到，虽然 `field` 内部没有任何对齐填充，但 `boolValue` 会被实现为一个 8 位的整数。此时 `boolValue` 字段的语义不再是 `0` 为 `false`、`1` 为 `true`，它的含义被 JVM 重新解释。假设 `byteValue` 字段的值为 `1`，那么

* 当 `boolValue` 为 `0`，则 `field` 的值为 `null`；
* 当 `boolValue` 为 `1`，则 `field` 的值为 `[false, 1]`；
* 当 `boolValue` 为 `2`，则 `field` 的值为 `[true, 1]`。

这里 JVM 就充分利用了 `boolean` 字段的裕量来实现空通道。 

除此之外，JVM 还有一些潜在的手段能够制造裕量。比如对于一个 `long` 类型的字段，JVM 可以随机生成一个概率上几乎不可能被用到的数 `x`，并通过位运算（比如用 `x ^ 1` 翻转最低位）生成另一个相应的数 `x'`，然后让 `x` 和 `x'` 具有同样的二进制表示，并通过一张全局的表存储它究竟是 `x` 还是 `x'`，这样就能挤出一个裕量用于实现空通道。

### 内部空通道和外部空通道

如果一个值对象的内部包含裕量，那么我们可以简单地在展平它的时候，利用它内部的裕量实现空通道，比如这一节前面例子中的 `NameAndValue` 就是利用内部的对齐填充实现空通道，前面的 `BoolAndByte` 是利用内部 `boolean` 字段的裕量实现空通道。

但有些时候，一个值对象内部并没有裕量，比如即将成为值类的 `java.lang.Long`：

```java
public value class Long {
    private final long value;
}
```

它只有一个 `value` 字段，没有对齐填充，而 `long` 所有可能的值都是 `value` 的合法值，所以我们在它内部找不到任何裕量。对于这种情况，JVM 会尝试在它周围“窃取”裕量实现空通道，这就是**外部空通道（external null channel）**。

比如对于下面的例子：

```java
class ExternalNullChannelExample {
    byte tag;
    Long value;
}
```

`tag` 与 `value` 之间存在 7 字节的对齐填充，`value` 在被展平的时候就会利用这里的裕量实现空通道：

```cpp
struct ExternalNullChannelExample {
    ObjectHeader header;
    
    struct {
        jbyte tag;
        jbyte value$null_channel;   // <- null channel
        // padding: 6 bytes
        jlong value;    
    } body;
};
```

和内部空通道一样，当外部空通道 `value$null_channel` 为 `0` 时，`value` 的值为 `null`。

如果周围也没有可以裕量可以利用，那么 JVM 会直接插入新的字段来实现空通道，此时就做不到零空间开销了。

### 准空地址

在裕量这一小节我说过通过保留一些低位地址作为**准空（quasinull）地址**，我们可以从对象引用中得到裕量。

假如我们拥有 `quasinull0`、`quasinull1` 等一系列的准空地址，那么我们可以直接利用对象引用的裕量实现空通道：

```java
value record StringBox(String value) {}

class QuasiNullExample {
    StringBox box;  // 这个字段会被展平成一个 String 字段，我们叫它 box$value
}

var example = new QuasiNullExample();
example.box = null;                 // box$value 的实际值为 null
example.box = new StringBox(null);  // box$value 的实际值为 quasinull0
example.box = new StringBox("str"); // box$value 的实际值为 "str"
```

可以看到，由于我们拥有 `quasinull0` 这个特殊的准空地址，我们可以用一个字段区分开 `null` 和 `StringBox[null]`。

实际我们拥有的准空地址不止一个，所以我们可以用一个引用表示嵌套的值类型。比如我们又有这样一个值类：

```java
value record Box<T>(T value) {}
```

像 `Box<Box<String>> box`，它也能被展平为一个引用字段，这个字段的实际值可能为：

* `null`：代表 `null`；
* `quasinull0`：代表 `Box[null]`；
* `quasinull1`：代表 `Box[Box[null]]`；
* `"str"`：代表 `Box[Box["str"]]`。

JVM 会提供 N 个准空地址，这会让引用拥有 N 个裕量。如果嵌套层数超过了 N，那么 JVM 可以回退到装箱的实现，继续进行嵌套。 

### 数组中的空通道

如果值对象支持内部空通道，实现它的数组并不困难；但如果不支持内部空通道（比如 `Long` 这样的对象），那么 JVM 有几种选择可以提供外部空通道。

首先，JVM 在数组可以在头部或者尾部提供空通道，布局结构类似这样：

```cpp
struct LongArray {
    ObjectHeader header;
    jint length;
    jbyte null_channels[length];
    jlong elements[length];
};
```

但这样的实现中，如果数组的 `length` 很大，空通道与对应的元素值距离会很远，一个 cache line 可能无法同时容纳它们，这会影响操作数组的性能。

另一种选择是将空通道与元素放在一起：

```cpp
struct LongArray {
    ObjectHeader header;
    jint length;
    struct {
        jbyte null_channel;
        jlong element;
    } elements[length];
};
```

这种做法缩短了空通道与元素的距离，但它让数组元素的大小加倍，每个元素浪费了 7 字节。增

最后的选择是采用前面所述的交替分块数组（ABA）：

```cpp
struct LongArray {
    ObjectHeader header;
    jint length;
    struct {
        jbyte null_channels[4];
        jlong elements[4];
    } blocks[(length + 3) / 4];
};
```

由于 ABA 可以将多个元素的空通道放在一起，减少中间的填充浪费，这里平均每个元素浪费的空间减少到了 1 个字节。

### 不可空类型

从前面几小节中我们可以看到 JVM 为支持 `null` 做了很多努力，尽可能的减少了开销。

但无论如何，只要值类型的变量支持 `null`，那 JVM 就需要付出开销来兼容 `null`。为了不付出这些开销，Valhalla 支持标注值类型为不可空，比如值类型 `Long` 对应的不可空版本是 `Long!`。

不可空值类型可以用在局部变量、字段、数组成员上：

```java
class NullRestrictedExample {
    Long! value; // -> 0L
    
    void fun(Long! arg) {
        var a1 = new Long![10];
        assert a1[0] == 0L;
        a1[0] = arg;
        
        Long[] a2 = a1;
        a2[0] = null; // ArrayStoreException
    }
}

```

对于不可空类型，JVM 不需要维护空通道，所以 `Long![]` 通常能够具有和 `long[]` 一样紧凑的布局。

## 维护一致性

接下来要说的是值对象展平时的另一个难题：JVM 如何保证出现竞态条件条件时不会发生字段撕裂，维护一致性。

### `final` 字段

维护一致性最简单的方法就是把值类型的字段声明为 `final` 的。

由于 `final` 字段无法被修改，它永远不会出现一致性问题，JVM 不需要做任何额外措施。

### 原子操作

对于小于 64 位的结构，我们可以考虑把它对齐到 1/2/4/8 字节，在寄存器中将它组装/拆解，并原子地读写它，从而维护一致性。

部分平台支持对更大（128 位甚至更大）数据的原子读写，而 JVM 在这些平台上可能会为更大的结构体通过原子读写保证一致性。

### 使用锁

使用锁是实现一致性的一种方案。

通常来说，使用锁可能难以保证高性能，但有时候它相比其他方案更可取。

一个锁可以由几个值对象成员共享。对于 ABA 数组，可以考虑每个块共享一个锁。

### 外部空通道的一致性

通过外部空通道实现的可空值类型存在一致性问题。

这里有一个特别值得注意的问题：值类型字段被设置为 `null` 时，JVM 为了性能可以只更新空通道，不清空值对象的其他字段，后续可以由 GC 对其中的引用进行清扫；但如果随后重新将此字段设置为非空值，那么一定要注意对值的更新顺序以及插入屏障，保证原本被 `null` 所覆盖的值不可能“复活”。

### `LooselyConsistentValue`

由于维护一致性的代价可能过于高昂。有些类并不需要维护如此强的一致性，它们可以通过实现 `LooselyConsistentValue` 接口，主动声明放弃一致性，此时 JVM 会不再用昂贵的手段维护此类型实例的一致性。

## 结语

如果你想了解 Valhalla 的更多信息，可以看看这些资料：

* 本文主要参考的资料来源：[encodings for flattened heap values - John Rose & Valhalla team](https://cr.openjdk.org/~jrose/values/flattened-values.html)
* 更多关于准空值的信息：[JDK-8326861: quasinulls: sentinel values that encode null-adjacent Valhalla value states](https://bugs.openjdk.org/browse/JDK-8326861)
* 更多关于一致性的讨论：[loose consistency - John Rose & Valhalla team](https://cr.openjdk.org/~jrose/values/loose-consistency.html)
* 值类型的 JEP 草案：[JEP 401: Value Classes and Objects (Preview)](https://openjdk.org/jeps/401)
* 不可空值类型的 JEP 草案：[JEP draft: Null-Restricted Value Class Types (Preview)](https://openjdk.org/jeps/8316779)
