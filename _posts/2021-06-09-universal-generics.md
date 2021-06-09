---
title: JEP 草案：通用泛型
date: 2021-06-09 17:30:00
tags:
- JEP
- Project Valhalla
categories: translate
description: 通用泛型 JEP 草案翻译
---

原文链接：[JEP draft: Universal Generics (Preview)](https://openjdk.java.net/jeps/8261529)

## 摘要

允许 Java 类型变量覆盖引用类型和原始类型。当类型变量或原始值类型的值可能被赋值为 `null` 时发出警告。
这是一个[预览语言功能](https://openjdk.java.net/jeps/12)。

## 非目标

[JEP 401](https://openjdk.java.net/jeps/401) 引入了核心功能*原始值类型（primitive value type）*。
本 JEP 仅关注于支持将原始值类型作为类型参数传递。

未来我们希望 JVM 能够在 Java 编译器的帮助下优化原始值类型参数化的性能。但是就目前而言，泛型继续通过擦除实现。

为了响应这些语言变化，预计未来将会对标准库泛型代码进行重大调整，但这些调整将在单独的 JEP 中进行。
未来还可能会重构当前为原始类型手工特化代码的实现。

## 动机

一个常见的编程任务是采用解决特定类型值问题的代码，并扩展它以处理其他类型值。
Java 开发者可以使用三种不同的策略执行此任务：

- *手工特化代码*。多次重复写一段代码（可能会用复制粘贴实现），每次使用不同的类型。
- *子类型多态*。将解决方案中的类型修改为所有预期操作数的类型的公共超类型。
- *参数化多态*。用类型变量替代解决方案中的类型，由调用者用他们需要操作的任意类型实例化。

方法 `java.util.Arrays.binarySearch` 很好地展示了这三种策略：

```java
static int binarySearch(Object[] a, Object key)
static <T> int binarySearch(T[] a, T key, Comparator<? super T> c)
static int binarySearch(char[] a, char key)
static int binarySearch(byte[] a, byte key)
static int binarySearch(short[] a, short key)
static int binarySearch(int[] a, int key)
static int binarySearch(long[] a, long key)
static int binarySearch(float[] a, float key)
static int binarySearch(double[] a, double key)
```

第一个变体使用了子类型多态。它适用于所有共享了公共超类型 `Object[]` 的引用类型数组。
类似地，搜索的键可以是任何对象。方法的行为取决于参数的动态属性——运行时数组成员和键是否支持互相比较？

第二个变体使用了参数化多态。它也适用于所有引用类型的数组，但要求调用者提供一个比较函数。
参数化方法签名确保编译时在每个调用点，数组成员和键是所提供的比较函数支持的类型。

其他变体使用手工特化。这些函数用于基本原始类型的数组，这些数组类型没有有意义的公共超类型。
不幸的是，这意味着一个几乎相同的方法有 7 个不同的部分，这给 API 规范添加了很多噪声，违反了 [DRY 原则](https://en.wikipedia.org/wiki/Don't_repeat_yourself)

[JEP 401](https://openjdk.java.net/jeps/401) 中引入的原始值类型是一类新的类型，允许开发者对自定义的原始值进行操作。
原始值具有到引用类型的轻量级转换，然后可以参与子类型关系。原始值数组也支持这些转换（例如，值的数组可以被视为 `Object[]`）。
因此，原始值类型可以直接使用依赖子类型多态性的 API，比如说 `binarySearch` 的 `Object[]` 变体。

不幸的是，Java 的参数化多态方法只针对引用类型设计。因此，原始值类型和基本原始类型（`int`、`double` 等）一样不能为类型参数。
假设有一个原始值类型 `Point`，则尝试使用比较函数对 `Point` 数组进行排序需要选择一个引用类型作为 `T` 的实例，
然后提供一个对所有该引用类型的值都有效的比较函数。原始值类型确实附带了一个明确的伴随引用类型——在本例中为 `Point.ref`——
但是使用 `Point.ref` 作为类型参数会导致一些问题：

- 为 `Point` 编写比较函数最自然的方式是使用 `Point` 类型的参数。
  但为了使用泛型 `Comparator` 接口，lambda 表达式需要声明 `Point.ref` 类型的参数。
  （类似地，如果要把这个 `Comparator` 存储到局部变量中，那么变量的类型将为 `Comparator<Point.ref>`。）
- 参数类型 `Point.ref` 增加了输入值为 `null` 的可能性，函数需要适当地相应这些输入（可能使用[非空断言](https://docs.oracle.com/en/java/javase/15/docs/api/java.base/java/util/Objects.html#requireNonNull(T))）。
- 更重要的是，未来我们希望直接在寄存器中传递*展平的（flattened）* `Point` 值以优化对比较函数的调用。但是引用类型 `Point.ref` 会影响展平值。

因为这些原因，如果大多数泛型 API 除了支持引用类型，还能支持原始值类型，那会很有用。
语言可以通过放宽类型参数必须是引用类型的要求，并相应地调整类型变量、边界和推断的处理来实现这一点。

开发人员需要考虑的一个重要影响是，通用类型变量现在可能表示不允许为 `null` 的类型。
Java 编译器可以产生警告，就像 Java 5 中引入的 unchecked 警告一样，以提醒开发人员注意这种可能。
语言可以提供一些新功能来解决这些警告。

回到基本原始类型手工特化的问题，在 [JEP 402](https://openjdk.java.net/jeps/402) 中，
语言会被更新，将基本原始类型视为原始值类型。到那时，基本原始值可以同时利用子类型多态和参数化多态，
未来的 API 将不再需要为每个基本原始类型生成手工特化代码。类型变量将覆盖所有 Java 类型。

## 描述

下面描述的功能是预览功能，需要在编译时和运行时使用 `--enable-preview` 标识启用。

### 类型变量和边界

以前 Java 的类型变量边界是根据语言的子类型关系解释的。
现在，如果以下任意条件之一成立，则我们称类型 `S` 以 `T` 为界：

- *S* 是 *T* 的子类型（其中每个类型都是其自身的子类型，引用类型根据其类声明和其他子类型规则，是很多其他类型的子类型）
- *S* 是原始值类型，其对应的引用类型以 *T* 为界
- *S* 是类型变量，其上界以 *T* 为界；或者 *T* 是具有下界的类型变量，并且 *S* 以 *T* 的下界为界

通常，类型变量会带有上界，而那些没有声明边界（`<T>`）的类型变量隐式地距又上界 `Object`（`<T extends Object>`）。
任何类型都可以作为上界，任何类型都可以作为实例化类型变量的参数提供，只要类型参数以类型变量的上界为界。

> 如果 `Point` 是一个原始值类型，则类型 `List<Point>` 有效，因为 `Point` 以 `Object` 为界。

因此类型变量几乎可以覆盖任何类型，不再被假定为表示引用类型。

通配符也有边界，也可以是任何类型。当测试一种参数化类型是另一种参数化类型的子类型时，会执行类似的边界检查。

> 如果原始类 `Point` 实现接口 `Shape`，则类型 `List<Point>` 是 `List<? extends Shape>` 的子类型，并且类型 `List<Shape>` 是 `List<? super Point>` 的子类型，因为 `Point` 以 `Shape` 为界。

类型参数推断被增强，以支持推断原始类型。因为在*有界*图中，原始值类型比引用类型“低”，
所以当推断变量没有相等边界时，推断会倾向于原始值下界。

> 调用 `List.of(new Point(3.0, -1.0))` 通常会被推断出类型 `List<Point>`；如果它出现于赋值上下文中，并且目标类型为 `Collection<Point.ref>`，则它会被推断为类型 `List<Point.ref>`。

对于类型变量、边界检查和推断的更改被自动应用。很多泛型 API 将顺利地处理原始值类型，无需 API 作者的干预。

（TODO：与 [JEP 402](https://openjdk.java.net/jeps/402) 结合使用时，由于类型推断在现有代码中倾向于 `int` 而非 `Integer`，所以存在一些源代码兼容风险。偏引用原始类的用户迁移时也可能会遇到意外的 `.val` 类型。需要进一步探索。）

### 空污染和空警告

引用可以为 `null`，但原始值类型不是引用类型，所以 [JEP 401](https://openjdk.java.net/jeps/401) 禁止将 `null` 赋值给原始值类型。

```java
Point p = null; // error
```

当我们允许类型变量覆盖更广泛的类型集时，我们必须要求开发人员对类型变量的实例做出更少假设。
具体来说，给一个类型变量类型的变量赋值为 `null` 通常是不合适的，因为该类型变量可能会被原始值类型实例化。

```java
class C<T> { T x = null; /* shouldn't do this */ }
C<Point> c = new C<Point>();
Point p = c.x; // error
```

本例中，字段 `x` 的类型被擦除为 `Object`，因此运行时 `C<Point>` 会愉快地存储 `null`，尽管这违反了编译时类型的期望。
这个场景是一个*空污染（null pollution）*的例子，一种新的堆污染。
与其他形式的堆污染一样，当程序试图不支持的值为擦除后类型的变量赋值时（本例中为对 `p` 的赋值），会在运行时检测到该问题。

对于其他形式的堆污染，编译器会生成*空警告（null warning）*以阻止空污染：

- 向类型变量类型赋值 `null` 字面量时会发出警告。
- 如果构造函数未初始化具有类型变量类型的非 `final` 字段，则会发出警告。

（对于某些值转换也会有空警告，这将在后面的部分中讨论。）

```java
class Box<T> {

    T x;
    
    public Box() {} // warning: uninitialized field
    
    T get() {
        return x;
    }
    
    void set(T newX) {
        x = newX;
    }
    
    void clear() {
        x = null; // warning: null assignment
    }
    
    T swap(T oldX, T newX) {
        T currentX = x;
        if (currentX != oldX)
            return null; // warning: null assignment
        x = newX;
        return oldX;
    }
    
}
```

现有泛型代码中很大一部分都会产生空警告，因为这些代码是在假设类型变量是引用类型的情况下编写的。
这会促进开发人员处理，因为他们有能力更新他们的代码以消除污染源。

编译时没有空警告的泛型代码可以安全地使用原始值类型实例化：这不会引入空污染或产生 `NullPointerException` 风险。

未来的版本中，泛型代码的物理布局会针对每个原始值类型特化。那时会更早地检测到空污染，未能解决警告的代码可能会无法使用。
解决了警告的代码做好了*被特化的准备*：未来的 JVM 增强不会破坏程序的功能。

### 引用类型类型变量

当泛型代码*需要*使用 `null` 时，语言提供了一些特殊功能，以确保类型变量类型是（`null` 友好的）引用类型。

- 以 `IdentityObject` 为界（直接界定或使用 identity 类界定）的类型变量始终是引用类型。

  ```java
  class C<T extends Reader> { T x = null; /* ok */ }
  
  FileReader r = new C<FileReader>().x;
  ```

- 由上下文关键字 `ref` 修饰的类型变量禁止非引用类型的参数，因此始终是引用类型。

  ```java
  class C<ref T> { T x = null; /* ok */ }
  
  FileReader r = new C<FileReader>().x;
  Point.ref p = new C<Point.ref>().x;
  ```

- 类型变量可以*使用* `.ref` 语法修饰，该语法表示从实例化类型到其最严格的边界引用类型的映射（例如，从 `Point` 映射至 `Point.ref`，从 `FileReader` 映射至 `FileReader`）。

  ```java
  class C<T> { T.ref x = null; /* ok */ }
  
  FileReader r = new C<FileReader>().x;
  Point.ref p = new C<Point.ref>().x;
  Point.ref p2 = new C<Point>().x;
  ```

（以上新语法可能会变化。）

最后一种情况下，`T` 和 `T.ref` 是两种不同的类型变量类型。允许以引用转换或值转换的形式在两种类型之间互相赋值。

```java
class C<T> {
    T.ref x = null;
    void set(T arg) { x = arg; /* ok */ }
}
```

以 `IdentityObject` 为界或者用 `ref` 修饰符声明的类型变量是*引用类型变量（reference type variable）*。
所有其他的类型变量被称为*通用类型变量（universal type variable）*。

类似地，引用类型变量或具有 `T.ref` 形式的类型变量的类型被称为*引用类型变量类型（reference type variable type）*，
而不带 `.ref` 的通用类型变量的类型被称为*通用类型变量类型（universal type variable type）*。

### 值转换警告

原始值转换允许将原始引用类型转换为原始值类型，从而将对象引用映射至对象本身。
根据 [JEP 401](https://openjdk.java.net/jeps/401)，如果引用为 `null`，则转换在运行时失败。

```java
Point.ref pr = null;
Point p = pr; // NullPointerException
```

当值转换应用于类型变量类型时，没有运行时检查，但转换可能是空污染的来源。

```java
T.ref tr = null;
T t = tr; // t is polluted
```

为了避免 `NullPointerException` 和空污染，值转换会产生空警告，除非编译器能够证明正在转换的引用是非 `null` 的。

```java
class C<T> {
    T.ref x = null;
    T get() { return x; } // warning: possible null value conversion
    T.ref getRef() { return x; }
}

C<Point> c = new C<>();
Point p1 = c.get();
Point p2 = c.getRef(); // warning: possible null value conversion
```

如果参数、局部变量或 `final` 字段是引用类型变量类型的，编译器可以在某些用法下证明该变量的值是非空的。
这种情况下，值转换可以在没有空警告的情况下发生。该证明类似于确定变量是否在使用前初始化的控制流分析。

```java
<T> T deref(T.ref val, T alternate) {
    if (val == null) return alternate;
    return val; // no warning
}
```

### 参数化类型转换

未受检转换传统上允许将 raw 类型转换为同一个类的参数化。这些转换是 unsound 的，所以会伴随未受检警告。

随着开发者的一些修改，例如对某些类型变量应用 `.ref`，他们可能会在 API 签名中使用与其他代码不同步的参数化类型（例如 `List<T.ref>`）。
为了顺利迁移，允许的未受检转换被扩展，包含以下参数化至参数化的转换：

- 将参数化类型的类型参数从通用类型变量（`T`）更改为其引用类型（`T.ref`），反之亦然

  ```java
  List<T.ref> newList() { return Arrays.asList(null, null); }
  List<T> list = newList(); // unchecked warning
  ```

- 将参数化类型的类型参数从原始值类型（`Point`、`LocalDate.val`）更改为其引用类型（`Point.ref`、`LocalDate`），反之亦然

  ```java
  void plot(Function<Point.ref, Color> f) { ... }
  Function<Point, Color> gradient = p -> Color.gray(p.x());
  plot(gradient); // unchecked warning
  ```

- 将参数化类型中的类型通配符边界从通用类型变量（`T`）或原始值类型（`Point`、`LocalDate.val`）更改为其引用类型（`T.ref`、`Point.ref`、`LocalDate`），反之亦然（其子类型尚不允许转换）

  ```java
  Supplier<? extends T.ref> nullFactory() { return () -> null; }
  Supplier<? extends T> factory = nullFactory(); // unchecked warning
  ```

- 递归地将未受检转换应用于参数化类型的任何类型参数或通配符边界

  ```java
  Set<Map.Entry<String, T>> allEntries() { ... }
  Set<Map.Entry<String, T.ref>> entries = allEntries(); // unchecked warning
  ```

这些未受检的转换在小代码段中似乎很容易避免，但它们提供的灵活性将大大简化迁移，因为不同的程序组件和库可能在不同时间采用通用泛型。

除了未受限的赋值外，这些转换还可以用于未受检的强制转换和方法覆盖。

```java
interface Calendar<T> {
    Set<T> get(Set<LocalDate> dates);
}

class CalendarImpl<T> implements Calendar<T> {
    Set<T.ref> get(Set<LocalDate.val> dates) { ... } // unchecked warning
}
```

### 编译至 `class` 文件

泛型类和方法将继续通过擦除实现：生成的字节码用其擦除后的边界替换类型变量。因此，在泛型 API 中，原始对象通常作为引用进行操作。

检测堆污染的常规规则为：在某些程序点插入强制转换，以断言值具有预期的运行时类型。对于原始值类型，这些检查包括检查值是否是非 `null` 的。

`Signature` 属性被扩展，以支持编码其他形式的编译时类型信息：

- 声明为 `ref T` 的类型变量
- 使用 `T.ref` 形式的类型变量
- 原始值类型作为类型参数和类型变量/通配符的边界出现

## 备选方案

我们可以要求开发者在使用泛型 API 时始终使用原始引用类型。这不是一个好的解决方案，正如*动机*一节中所说的那样。

我们还可以要求 API 作者*选择*通用类型变量，而不是默认让类型变量通用。
但我们的目标是让通用泛型称为规范，在实践中，大多数类型变量没有理由不能通用。
选择加入会带来太多摩擦，导致 Java 生态系统支离破碎。

如前所述，基于擦除的编译策略不允许我们期望在原始对象上使用泛型 API 获得性能。未来我们希望增强 JVM，编译生成特化于不同类型参数的异构类。
但是这个 JEP 中优先考虑语言更改，开发人员现在可以编写更具表现力的代码，并让他们的泛型 API 做好通用化的准备，同时预测未来的性能改进。

我们可以避免引入新的警告，接受空污染是使用原始值类型编程的常规事实。这将提供“更干净”的编译体验，但是通用 API 在运行时的不可预测性不会让人愉快。
最后，我们希望在泛型 API 中使用 `null` 的开发者注意并仔细考虑他们的用法如何与原始值类型交互。

在另一个极端，我们可以将部分或全部警告视为错误。但我们不想引入源代码迁移时的不兼容性——遗留代码和遗留 API 的用户应该仍然能成功编译，即使会有新的警告。

## 风险和假设

这些功能的成功取决于 Java 开发者学习并采用新的模型来处理类型变量与 `null` 的交互。
新的警告非常明显，它们需要被理解和欣赏，而非被忽视，才能起到预期的效果。

在特化泛型前提供这些功能带来了一些挑战。一些开发者可能对性能不满意（例如将 `ArrayList<Point>` 和 `Point[]` 做对比），
并对将泛型用于原始值类型的成本产生错误的长期直觉。其他开发者在应用 `.ref` 时可能会做出不太理想的选择，
在代码更改很久后，直到在支持特化的 VM 上运行时才注意到不良影响。

## 依赖

[JEP 401](https://openjdk.java.net/jeps/401)，原始对象， 是前置条件。

后续 JEP 将更新标准库，解决空警告并做好特化准备。

另一个后续 JEP 将在 JVM 中引入泛型 API 的运行时特化。
