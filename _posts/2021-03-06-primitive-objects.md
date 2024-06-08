---
title: JEP 401：原始对象（Primitive Objects）
date: 2021-03-06 12:00:00
tags:
- JEP
- Project Valhalla
categories: translate
description: JEP 401 翻译
---

原文链接：[JEP 401: Primitive Objects (Preview)](https://openjdk.java.net/jeps/401)

这个草案今天刚刚更新，加上 [JEP 390](https://openjdk.java.net/jeps/390) 进入 Java 16，Primitive Objects 和相关 JEP 在下下个 LTS 版本之前能够正式进入 Java 规范中应该可能性极大。我这里把这篇 JEP 草案翻译了一下，虽然只是草案，但是这里描述的新的对象模型很可能近期进入 Java 主线。

相关 JEP 草案翻译：[统一基本值与对象](https://zhuanlan.zhihu.com/p/354979657)。

更新：
今天（2021/03/18）这两篇草案成为了正式 JEP，在 Java 17 之前开始 Preview 希望很大，敬请期待吧！

## 摘要

通过用户自定义原始类型增强 Java 对象模型。原始类型对象缺乏object identity，它们可以直接存储和传递，不需要对象头以及间接寻址。

## 目标

本 JEP 提案将对 Java 语言与虚拟机进行重大更改，包括：

- 允许用户声明 identity-free 的原始类（*primitive classes*），这些类的实例实例叫做原始对象（*primitive objects*），并指定了对这些无 identity 对象调用比较、synchronized 等需要依赖 identity 才能正确实现的操作会发生的行为。
- 同时允许对原始对象和原始引用（*primitive references*）进行操作，并使它们之间可以进行无缝转换。原始值类型能够不进行间接寻址直接存储和传递原始对象，原始引用可以表现出多态性（polymorphism）同时允许使用空引用（null references）。

## 非目标

这个 JEP 主要讨论用户自定义的原始类和原始类型。这里不讨论对 Java 语言的额外改进，但预期中这些功能会同时开发，具体有：

- 一个[独立的 JEP](https://zhuanlan.zhihu.com/p/354979657) 通过将目前基本类型（`int`、`boolean`等）的包装类视为原始对象增强它们。
- 一个独立的 JEP 将更新 Java 的泛型以支持原始值类型作为类型参数。

一个重要的后续工作（这些 JEP 中都没有涉及）将会增强 JVM 使其对不同的原始值类型布局特化（specialize）泛型类和字节码。

其他后续工作可能会增强现有的 API 以利用原始对象，或者基于原始对象引入新的语言特性以及 API。

## 动机

Java 程序员会使用两类值：基本类型（数字与布尔值）和对象的引用类型。

原始类型提供更高的性能，因为它们直接存储（没有对象头和指针）在堆栈里直接存储在变量中，最终可以直接存储在 CPU 寄存器中。从内存读取原始值不需要额外的间接寻址，原始数组会紧密的连续存储在内存中，原始值不需要被 GC 回收，并且原始操作直接定义在 CPU 中。

对象引用提供了更好的抽象——譬如字段、方法、访问控制、实例验证、命名类型以及子类型多态等。它们还具有 *identity*，支持修改字段以及加锁等操作。

在某些领域，程序员需要原始类型的高性能，但代价是他们必须放弃面向对象编程提供的一些有价值的抽象。这可能产生 bug，像错误的解释了无类型的数字或者错误的处理了异构数据数组。（[火星气候探测者号](https://zh.wikipedia.org/wiki/%E7%81%AB%E6%98%9F%E6%B0%A3%E5%80%99%E6%8E%A2%E6%B8%AC%E8%80%85%E8%99%9F)的失败展示了这类 bug 的潜在成本）

理想状况下，我们希望 Java 虚拟机能够以原始类型的性能运行面向对象的代码。不幸的是，虽然很多对象并不需要 identity，但 object identity 依然是这类优化的主要障碍。如果没有 identity，JVM 就可以自由地处理对象，譬如可以把对象像基本类型那样直接存储在变量中并让 CPU 直接处理。

具体的对象不需要 identity 的例子包括：

- 没有作为基本类型支持的数字类型，譬如无符号整数、128位整数以及半精度浮点数。
- 点（Point）、复数类型、颜色、向量以及其他多维数字。
- 大小、变化率、温度、货币等带单位的数字。
- 日期与时间的抽象，包括 `java.time` 中的大量类型。
- 元组、[记录](https://openjdk.java.net/jeps/395)（Record）、map entries、database rows以及多个返回值。
- 不可变的 cursors、子数组、中间流以及其他数据结构视图的抽象。

We can also expect that new programming patterns and API designs will evolve as it becomes practical for programs to operate on many more objects.

## 描述

### 原始对象和原始类

*原始对象（primitive object）*是一种没有 *identity* 的类实例。也就是说，原始对象没有固定的内存地址或其他属性能够把它们与字段中存储着相同值的同一个类的其他实例区分开。原始对象不能用 `synchronized` 加锁，它们的字段不能修改。原始对象的 `==` 操作符行为是对递归的比较字段的值。实例为原始对象的类被称为*原始类（primitive classes）*

一个 *identity 对象* 是一个有着 identity 的类实例或者数组——它们有 Java 对象的传统行为。identity 对象的字段可以被修改，它们与一个同步监视器关联。identity 对象的 `==` 操作符的行为是进行一次 identity 比较。实例为 identity 对象的类被称为 *identity 类*。

#### 原始类声明

类可以用上下文关键字（contextual keyword）`primitive`  声明为原始类。原始类被隐式声明为 `final` 的，它们不能被声明为 `abstract`  的。

如果一个类既不是 `primitive`  的也不是 `abstract` 的（不包括特殊类 `Object`），那它就是一个 identity 类。

```java
primitive class Point implements Shape {
    private double x;
    private double y;
    
    public Point(double x, double y) {
        this.x = x;
        this.y = y;
    }
    
    public double x() { return x; }
    public double y() { return y; }
    
    public Point translate(double dx, double dy) {
        return new Point(x+dx, y+dy);
    }
    
    public boolean contains(Point p) {
        return equals(p);
    }
}

interface Shape {
    boolean contains(Point p);
}
```

原始类的声明有以下限制：

- 所有字段都被隐式声明为 `final` 的，所以必须在构造器内或通过初始值进行初始化，并且不能在其他地方被重新赋值。
- 原始值类型的字段不能直接或间接的引用包含这个字段的原始类型。换句话说，除了引用类型的字段，原始类的布局必须是没有循环依赖的、flat 的、固定大小的。
- 不能直接或间接地实现 `IdentityObject` 接口（见下文）。这意味着原始类的超类必须是 `Object` 或者无状态的抽象类。
- 构造器不能使用 `super` 调用超类构造器。创建实例时不会执行任何超类的初始化代码。
- 没有被声明为 `synchronized` 的成员函数。
- （可能）不能实现 `Cloneable` 接口或声明 `clone()` 方法。
- （可能）不能声明 `finalize()` 方法。
- （可能）构造函数在函数体内为所有字段赋值（或所有字段都已经被明确赋值）前不能使用 `this`。 在大多数方面，原始类的声明与 identity 类声明相似。它们可以有超接口、类型参数、嵌套类、内部类、重载构造函数、`static` 成员，并且能够用所有的访问控制修饰符修饰成员。

#### 使用原始对象

原始对象使用普通的类实例创建表达式创建。

```java
Point p1 = new Point(1.0, -0.5);
```

原始类的实例字段和方法都能够像普通类一样访问。

```java
Point p2 = p1.translate(p1.y(), 0.0);
```

原始类可以从超类和超接口中继承方法，也可以重写它们。原始类的实例可以被赋值给超类型的变量。

```java
System.out.println(p2.toString());
Shape s = p2;
assert !s.contains(p1);
```

`==` 操作符会比较原始对象的字段值，而**不是**比较 object identity。基本类型的字段会安慰比较，其他字段会递归的通过 `==` 操作符进行比较。

```java
assert new Point(1.0, -0.5) == p1;
assert p1.translate(0.0, 0.0) == p1;
```

继承自 `Object` 的`equals`、`hashCode` 和 `toString` 方法以及 `System.identityHashCode` 行为与相等性一致。

```java
Point p3 = p1.translate(0.0, 0.0);
assert p1.equals(p3);
assert p1.hashCode() == p3.hashCode();
assert System.identityHashCode(p1) == System.identityHashCode(p3);
assert p1.toString().equals(p3.toString());
```

尝试在原始对象上使用 `synchronized` 会抛出异常。

```java
Object obj = p1;
try { synchronized (obj) { assert false; } }
catch (RuntimeException e) { /* expected exception */ }
```

#### `PrimitiveObject` 和 `IdentityObject` 接口

两个新接口作为[必要的预览 API](https://openjdk.java.net/jeps/12) 导入：

- `java.lang.PrimitiveObject`
- `java.lang.IdentityObject`

所有原始类都隐式的实现了 `PrimitiveObject` 接口。所有的 identity 类（包括所有之前在 Java 生态系统中的类）隐式实现了 `IdentityObject` 接口。所有数组类型也是 `IdentityObject` 的子类型。

这些接口有助于从三个方面区分 identity 对象和原始对象：

- `instanceof IdentityObject` 和 `instanceof PrimitiveObject` 可以测试对象是否具有 identity（类似地，可以通过 `Class` 使用反射的方式进行测试）。
- `IdentityObject` 和 `PrimitiveObject` 类型的变量可以分别存储具有和不具有 identity 的对象。
- 类型参数边界 `extends IdentityObject` 和 `extends PrimitiveObject` 可以用于分别限制类型参数对应的值必须具有或不具有 identity。

接口可以显式继承 `IdentityObject`  或 `PrimitiveObject` 以保证所有的实现对象都具有或不具有 identity。一个类同时实现（隐式、显式或者继承其他接口）这两个接口是一个错误。默认情况下接口不继承它们中任意一个，能够同时被两种具体类实现。

类似的，抽象类也可以显式声明实现 `IdentityObject` 或者 `PrimitiveObject`；或者当抽象类声明了字段、实例初始化器、构造函数或者 `synchronized`  方法时，它会隐式实现 `IdentityObject`。其他情况下，抽象类不会实现这两个接口中任意一个，能够同时被两种具体类继承。

特殊类 `Object` 的行为类似于一个简单的抽象类：它既不实现 `IdentityObject`  也不实现 `PrimitiveObject`。对 `new Object()` 的调用会被重新解释为创造一个空的、继承 `Object` 的 identity 类（名称未定）的实例。

### 原始值和引用

原始对象可以作为*原始值（primitive value）*被直接存储进变量和进行操作，没有对象头也不进行指针操作。这些值的类型被称为*原始值类型（primitive value type*）。

原始对象也可以作为*对象引用（references to objects）*被存储与操作。对它们的引用的类型被称为*原始引用类型（primitive reference types）*。

因此，对于每个原始类，有两个不同的类型与其关联——一个值类型和一个引用类型。类的实例可以被直接或通过引用间接操作，这取决于具体使用的类型。

#### 原始值类型

原始类的名称表示了这个类对应的*原始值类型*。与传统的类类型不同，原始值类型对应的值不是对象的*引用*，而是对象本身。这有两个重要结果：

- 原始值类型的变量可以不用存储对象头与指针，直接存储原始对象的字段。
- 原始值类型的变量不能为 `null`。

原始值类型是*单态（monomorphic）*的——一个类型的所有值都是同一个类的实例，具有相同的布局。

原始类实例创建表达式的类型是原始值类型。原始类的类体中的 `this`  表达式同样为原始值类型。

如上所示，原始值类型允许访问字段和方法。它们同样支持使用 `==` 和 `!=` 操作符比较相同类型的值。

原始值类型的表达式不能用作 `synchronized`  语句的操作对象。

基本类型（`int`、`boolean`、`double`等）不受该 JEP 的影响，但它们也可以被认作另一种原始值类型。

#### 引用类型

通常来说，引用类型的变量会保存对象的引用和 `null` 其中之一。而现在，被引用的对象可以是一个 identity 对象或者一个原生对象。

原始类的类名后加上 `.ref` 后缀表示这个原始类对应的*原始引用类型（primitive reference type）*。原始引用类型的值是对对应的原始类实例的引用和 `null` 其中之一。 原始引用类型是对应原始类所有超类型的子类型。

```java
Point pi; // stores a Point object
Point.ref pr; // stores a reference to a Point
Shape s; // stores a reference to a Shape, which may be a Point
```

一个原始引用类型与对应的原始类的原始值类型有着相同的成员，并且支持引用类型的所有常规操作，（可能）除了原始引用类型的表达式用作 `synchronized` 的操作对象时错误的。

对原始对象的引用通过对原始值进行*原始引用转换（primitive reference conversions）*创建。与装箱操作类似，原始引用转换在 Java 语言中会隐式发生。因为不会引入新的 identity，所以原始引用转换是非常轻量级的。

```java
Point p1 = new Point(3.0, -2.1);
Point.ref[] prs = new Point.ref[1];
prs[0] = p1; // convert Point to Point.ref
```

与拆箱操作类似，*原始值转换（primitive value conversion）*会把一个原始引用转换为原始值。当原始引用值为 `null` 时，原始值转换会抛出 `NullPointerException`。

```java
Point p2 = prs[0]; // Convert Point.ref to Point
prs[0] = null;
p2 = prs[0]; // NullPointerException
```

方法调用可以隐式执行原始值或原始引用转换，以确保 receiver  的类型与方法声明中预期的 `this` 类型所匹配。

```java
p1.toString(); // Convert Point to Object
Shape s = p1;
s.contains(p1); // Convert Shape to Point
```

很多程序并不需要使用原始引用——原始值类型已经提供了它们所有需要的功能。原始引用在以下情况中有用：

- 需要子类型多态时。例如：需要原始类型对象充当接口的实例时。
- 需要 `null` 时。例如：算法需要 sentinel 时。
- 需要用间接寻址避免原始类的字段发生循环时。
- 使用引用有更高的性能时（见下）。

当前 Java 泛型被设计为只能工作于引用类型，但一个单独的 JEP 将会增强泛型与原始值类型的互操作性。

#### 重载解析和类型参数推断

原始引用转换和原始值转换只允许在*宽松*调用上下文中进行，不会发生于*严格*调用上下文。这将遵循装箱和拆箱操作的模式：不需要发生转换即可调用的方法重载优先于需要发生转换才能调用的转换。

```java
void m(Point p, int i) { ... }
void m(Point.ref pr, Integer i) { ... }

void test(Point.ref pr, Integer i) {
    m(pr, i); // prefers the second declaration
    m(pr, 0); // ambiguous
}
```

类型参数推断对原始引用和原始值转换的处理方式与对装箱和拆箱操作的处理方式相同。在需要推断类型的地方传递原始值会被推断为对应的原始引用类型。

```java
var list = List.of(new Point(1.0, 5.0));
// infers List<Point.ref>
```

（类型推断的行为在单独的 JEP 中会被更改为允许推断为原始值类型）

#### 数组子类型

原始类实例的数组是协变的——类型 `Point[]`  是 `Point.ref[]` 和 `Object[]` 的子类型。

向一个静态类型为 `Object[]`、运行时成员类型为 `Point` 的数组存储一个引用时，会先经过数组存储检查（检查引用的对象类型为 `Point`），然后发生原始值转换（将引用转换为原始值）后存储进数组。

类似的，如果从一个存储着原始值类型且静态类型为 `Object[]` 的数组中读取值时会发生原始引用转换。

```java
Object replace(Object[] objs, int i, Object val) {
    Object result = objs[i]; // may perform reference conversion
    objs[i] = val; // may perform value conversion
    return result;
}

Point[] ps = new Point[]{ new Point(3.0, -2.1) };
replace(ps, 0, new Point(-2.1, 3.0));
replace(ps, 0, null); // NullPointerException from value conversion
```

#### 偏引用原始类

一些类可以被声明为原始类——它们不可变而且不需要 identity——但是有很多用户希望将其作为“普通的”引用类型使用，特别是不想对缺少 `null` 进行调整。常见情况为一个类被声明为 identity 类，但是希望向下兼容地重构为原始类（标准库中的很多类被指定为[基于值的类](https://docs.oracle.com/en/java/javase/15/docs/api/java.base/java/lang/doc-files/ValueBased.html)以应对这种迁移）。

在这些情况下，类可以被声明为 `primitive` 的，但需要使用一个特殊的名称：

```java
primitive class Time.val {
    ...
}
```

这种情况下，`Time.val` 表示一个原始值类型，而 `Time` 表示对应的原始引用类型。

```java
Time[] trefs = new Time[]{ new Time(...) };
Time.val t = trefs[0]; // primitive value conversion
```

除了作为类型使用时对类型名的解释，偏引用原始类与其他原始类完全一致。

准备将现有 identity 类迁移为原始类的库作者需要注意，即使重构为偏引用原始类，用户依然会感知到一些差异：

- 调用了非私有构造函数的用户代码运行时会发生链接错误，需要重新编译（参见后文对编译的讨论）。
- 原本 `!=` 的对象之间可能会变为 `==`。
- 在对象上使用 `synchronized` 会抛出异常。
- `getClass()` 方法可能返回不同的 `Class` 对象。

#### 原始值类型的默认值

每个类型都有一个*默认值（default value）*用于初始化字段以及填充对应数组的成员。引用类型的默认值是 `null`，基本类型的默认值为 `0` 或者 `false`。原始值类型的默认值是该类的*默认实例（default instance）*，其所有字段都会被对应类型的默认值填充。

表达式 `Point.default` 引用原始类 `Point` 的默认实例。

```java
assert new Point(0.0, 0.0) == Point.default;
Point[] ps = new Point[100];
assert ps[33] == Point.default;
```

请注意，原始类的默认实例是在不调用任何构造函数和实例初始化器的情况下创建的，任何能够访问该类的用户都能使用该实例。原始类不能将默认实例定义为其他值。

#### 强制实例验证

原始类拥有构造函数，通常情况下使用构造函数初始化类的字段，并在其中验证确保字段的值是有效的。

默认情况下，有一些“后门”方式可以绕过构造函数，在不经过构造函数校验的情况下创建原始值的实例，包括：

- 自动被创建的默认实例，可以被任何能够访问该类的用户使用。

  ```java
  Point p = (new Point[1])[0]; // creates (0.0, 0.0)
  ```

  可以通过控制原始类的访问权限，只允许可信代码访问，从而防止不需要的默认实例（可信代码中可以通过总是初始化字段和数组元素或使用引用类型避免默认值出现）。

- 非原子读写。当对一个字段或数组成员同时进行读和写时可能读取到损坏的值对象（参见 [JLS 17.7](https://docs.oracle.com/javase/specs/jls/se14/html/jls-17.html#jls-17.7)）。

  ```java
  Point[] ps = new Point[]{ new Point(0.0, 1.0) };
  new Thread(() -> ps[0] = new Point(1.0, 0.0)).run();
  Point p = ps[0]; // may be (1.0, 1.0), among other possibilities
  ```

  可以通过将字段声明为 `volatile`  强制对其进行原子读写。通过将原始类的可访问性限制到可保证避免读写冲突（通过 `volatile`  字段或使用引用类型）可信代码可避免通过非原子读写创建实例。

（暂定功能）：如果实例的正确性非常重要，则可用[名称未定]关键字修饰原始类。这种情况下，编译器和 JVM 会保证在执行类的实例方法前检测和阻止“后门”实例创建。

```java
[KEYWORD TBD] primitive class DatabaseConnection {
    private Database db;
    private String user;
    
    public DatabaseConnection(Database db, String user) {
        // validation code...
        this.db = db;
        this.user = user;
    }
    
    ...
}
```

### 编译和运行时

原始类会被编译为 `class` 文件，Java 虚拟机会对其进行特殊处理。

#### `class` 文件表示&解释方式

声明在 `class` 文件中的原始类使用 `ACC_PRIMITIVE`  修饰符（`0x0100`）修饰。（表示偏引用原始类和强制实例验证类的修饰符未定）在类加载时，原始类会被认为实现了接口 `PrimitiveObject`；如果原始类不是 `final` 的，或者具有非 `final` 实例字段，或者直接或间接实现了接口 `IdentityObject`，则会产生一个错误。在准备（preparation）阶段，如果原生类的实例字段具有循环性，则会产生一个错误。

允许原始子类型的抽象类在 `class` 文件中声明此功能（详细方式待定）。在类加载阶段，如果类不是抽象的，或者声明了实例字段，或者声明了 `synchronized` 方法，或者直接或间接实现了接口 `IdentityObject`，则会产生一个错误。

在类加载阶段，如果一个类（不包括接口）不是原始类且不允许原始子类型，则它会被认为实现了接口 `IdentityObject`。所有数组类型都会被认为实现了接口 `IdentityObject`。如果任何类或接口直接或间接同时实现或继承接口 `PrimitiveObject` 和 `IdentityObject`，则会产生一个加载时错误。

原始值类型在类型描述符里使用 `Q` 作为前缀（例如 `QPoint;` 表示原始类型 `Point`）而非一般类型的 `L` 前缀。（有关限制的详细信息暂定）

验证时将 `Q` 类型视为命名类超类类型的子类型（例如 `QPoint;` 是 `Ljava/lang/Object;` 的子类型）。

方法和字段的 `Q`  描述符表示的类会在第一次访问该字段或调用该方法前加载。

一个 `CONSTANT_Class` 常量池条目也可以使用 `Q` 描述符作为“类名”描述原始值类型。

（这些关于类型编码的描述细节可能会被更改）

原始类成员方法的 `this` 参数拥有原始值验证类型。

原始值类型是栈中的“一个 slot”，即使它们的大小远远超过 32 位或 64 位。没有强制指定原始对象的编码方式，实现可以自由的在不同上下文（譬如栈与堆）中使用不同的编码方式。另一方面，对原始对象的引用应该以与传统对象引用兼容的方式编码。

引入了两条新的操作码便于创建实例：

- `defaultvalue`：带有一个 `CONSTANT_Class`  操作数，生成原始值类型的默认值。该操作码没有任何访问限制——任何能够解析对应原始类 `Class` 常量的地方都能获取它的默认值。
- `withfield`：带有一个 `CONSTANT_Fieldref` 操作数，使用现有对象作为模板替换其中一个字段的值生成新的原始对象。该操作始终有 `private` 操作权限，在原始类或其嵌套类以外地方进行 `withfield` 操作会产生一个链接错误。

对原始类使用 `new` 操作会产生一个链接错误。实例初始化方法可以在原始类中声明，但是验证阻止调用它们（Instance initialization methods can be declared in a primitive class, but verification prevents their invocation）。

新的特殊方法*工厂方法（factory method）*返回类的实例。工厂方法是名称为 `<new>` 的方法（或为返回值非 `void` 的 `<init>` 方法），且为静态方法，可以使用 `invokestatic` 调用。

`anewarray` 和 `multianewarray` 指令用于创建原始值类型的数组。

当 `defaultvalue`、`anewarray ` 和 `multianewarray` 指令与原始值类型一起使用时会触发命名原始类的初始化。在初始化期间，（不同）原始值类型的实例字段可以递归的触发该命名原始类的初始化。

`checkcast`、`instanceof` 和 `aastore`  操作支持原始值类型，在必要时执行原始值转换（包括 `null` 检查）。

`if_acmpeq`  和 `if_acmpne`  操作实现了前文所述的原始对象间的 `==` 比较。`monitorenter` 指令用于原始对象时会抛出异常。

#### Java 语言编译

`javac` 将类似 `Point.ref` 的原始引用类型编码为合成出的原始类的超类，名称类似 `Point$ref`。编译器根据需要插入类型转换以访问具体的成员。

对于偏引用原始类，简单的名称（`Time`）被赋予抽象超类，而具体子类的名称类似 `Time$val`。

原始引用转换是隐式的：`QPoint;`是 `LPoint$ref;` 的子类型。原始值转换是通过 `checkcast` 操作实现的。

原始类的构造方法被编译为工厂方法，而非实例初始化方法。构造方法体中，编译器将 `this` 视为可变的局部变量，由 `defaultvalue` 初始化，由 `withfield` 修改，最后作为返回值返回。

#### 核心反射

原始对象的 `getClass()` 方法返回一个表示对应原始类的 `java.lang.Class` 对象。此 `Class` 对象也表示对象的原始值类类型。

（暂定）对于偏引用原始类，类对象的名称形式为 `ClassName.val`。在 Java 语言中，`ClassName.val.class` 是受支持的类字面量。

一个新的反射预览 API 方法 `Class.isPrimitiveClass` 用于检测类是否为原始类（这个方法与 `isPrimitive` 不同，`isPrimitive` 用于检测 `Class` 是否表示基本类型）。

原始类对应 `Class` 对象的 `getDeclaredConstructors` 方法以及相关方法搜索工厂方法而非实例初始化方法。

（暂定）原始类的 `Class` 对象调用 `getSuperclass` 结果是用于表示原始引用类型的合成的抽象类的 `Class` 对象，其名称形式为 `ClassName.ref`。在 Java 语言中，`ClassName.ref.class` 是受支持的类字面量。

（暂定）方法 `Class.valueType` 和 `Class.referenceType` 提供原始引用类型类对象和原始值类型类对象之间映射的便捷方法。

#### 性能模型

由于原始对象缺少 identity，JVM 可以自由的复制以及重新编码它们，以优化计算速度、内存占用和 GC 性能。

在典型的用法中，程序员可以有以下预期：

In typical usage, programmers can expect the following:

- 原始值类型的字段和数组会直接而紧凑的存储值，从而减少内存占用以及增加内存局部性。
- 引用类型地字段和数组会以传统引用的方式编码值。
- 原始值类型的局部变量、方法参数和表达式结果通常不在 JVM 堆中（特别是在编译后的机器码中）；有时这些原始对象可以完全保存在寄存器中。
- 引用类型的局部变量、方法参数和表达式结果通常会以传统引用的方式编码值，但是优化可能会消除这些引用。

请注意，任何特定的优化都不一定能保证发生。譬如，当一个原始类具有大量字段时，JVM 可能会将原始值编码为堆上对象的引用。

## 替代方案

JVM 长期以来一直对 identify 对象实现逃逸分析，以识别那些不依赖 identify 且能够“扁平化”的对象。这些优化的结果某种程度上来说是不可预测的，且无法对“逃逸”出作用域的对象启用。

手工实现的优化可以优化性能，但正如[动机](#动机)一节所述，这样的方式放弃了有价值的抽象。

在建立这样的对象模型前，我们研究了许多不同的“装箱”和多态化方法。在这个模型中，原始类是第一类对象（有少量行为变化），引用类型和值类型相同对象的两种不同视图。将 identity 强加给装箱后的原始对象具有不确定性行为。Approaches that "intern" boxed primitive objects to a canonical memory location are too heavyweight。区分 identity 类和接口继承图（根为 `Object`）与原始类和接口继承树（根为一个新的类或接口）的方式阻止了与现有 Java 代码的互操作性。

C-like 语言中支持对 `strcut` 或者其他类似类的抽象扁平化存储。例如，C# 语言支持[*值类型*](https://docs.microsoft.com/en-us/dotnet/csharp/language-reference/builtin-types/value-types)。与原始对象不同，这个抽象中的值具有 identity，这意味着它们支持修改字段等操作。因此，必须小心地指定分配、调用等操作时复制的语义，这会使用户模型更加复杂，同时降低运行时实现的灵活性。我们更喜欢将这些低级细节留给 JVM 实现决定。

## 风险和假设

该特性对 Java 对象模型进行了重大修改，特别是 `Object` 的语义。程序员可能对类似 `==` 和 `synchronized` 等操作语义的变化感到惊讶，甚至发生错误。重要的时确认这种破坏性是罕见的且易处理的。

某些更改可能产生潜在的对 identity 对象性能的影响。例如 `if_acmpeq`  和 `aaload`  操作通常只会消耗一个指令周期，但是现在需要对原始对象进行额外的检测。identity 类应该作为“快速路径”进行优化，我们需要将任何性能降低最小化

`==` 操作存在间接的将 `private` 字段值暴露给任何可以创建类实例的人的安全风险。允许在构造函数以外通过默认实例和非原子读写创建实例也存在安全风险。程序员需要了解何时使用 `primitive` 类是不安全的，以及要了解我们提供的这些用于降低风险的工具。

这个 JEP 不涉及原始类与基本类型或泛型的交互，这些特性将于其他 JEP 处理（参见下面的“相关特性”一节）。但是，最终这三个 JEP 需要都完成才能提供一个整体的语言设计。

## 依赖

### 先决条件

预计在本 JEP 前需要先改进 JVM 规范（特别是对“class”文件验证的处理）和 Java 语言规范（特别是对类型的处理）、解决技术债务问题并促进新特性规范化。

[JEP 390](https://bugs.openjdk.java.net/browse/JDK-8249100) 中已经在 `javac` 和 HotSpot 中添加了可能对原始类候选进行不兼容更改的警告。

### 相关特性

在这个[独立的 JEP](https://zhuanlan.zhihu.com/p/354979657) 中，我们预计会更新基本类型（`int`、`boolean`等）使用原始类进行表示，从而允许基本值成为原始对象。现有的包装类将会调整为相应基本类型对应的偏引用原始类。

在另一个 JEP 中，我们预计会修改 Java 的泛型模型使类型参数更通用，能够被所有类型实例化，包括引用类型和值类型。

### 未来的工作

JVM 类和方法特化（[JEP 218](https://openjdk.java.net/jeps/218)）将允许在通过原始值类型实例化泛型类和方法时特化字段、数组和局部变量布局。

很多已存在语义特性和 API 可以通过原始类增强，并能够启用更多新特性。