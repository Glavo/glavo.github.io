---
title: JEP 402：统一基本值与对象
date: 2021-03-06 18:00:00
tags:
- JEP
- Project Valhalla
categories: translate
description: JEP 402 翻译
excerpt: JEP 402：统一基本值与对象
---

**建议阅读前置提案（[JEP 草案：原始对象](https://zhuanlan.zhihu.com/p/354841176)）后阅读。**

该 JEP 还处于草案状态，后续可能发生更改，仅供参考。因为前置的 [JEP 390](https://bugs.openjdk.java.net/browse/JDK-8249100) 已经进入 Java 16，本 JEP 有望近期进入主线。

更新：

该草案今天（2021/03/18）成为正式 JEP，从 Java 17 开始 Preview 的可能性不小，敬请期待。

## 摘要

通过将基本值（`int`、`double` 等类型的值）建模为原始类（参见[JEP 草案：原始对象](https://zhuanlan.zhihu.com/p/354841176)）的实例，将基本值与对象统一。

## 目标

这个 JEP 包括以下内容：

- 库更改：将 8 个包装类（`java.lang.Integer`、`java.lang.Double` 等）迁移为偏引用原始类。
- 语言更改：将基本值视为迁移后包装类的实例，将基本类型关键字（`int`、`double` 等）视为对应原始值类型的别名；支持方法调用、原始引用转换和对应的类型协变。
- JVM 更改：将基本数组类型视为相应的原始对象数组类型。
- 核心反射更改：修改 8 个 表示基本类型的 `Class` 对象（`int.class`、`double.class` 等）的行为，对它们对应的类进行建模。

## 非目标

原始对象和原始类的核心功能在 [JEP 草案：原始对象](https://zhuanlan.zhihu.com/p/354841176) 中介绍，本 JEP 值关注将这些特性应用于 8 个基本类型。

这个 JEP 没有处理原始值类型（包括 `int`、`double` 等）与 Java 泛型的交互。独立的 JEP 将解决将原始值类型作为类型参数的需求，并优化其性能。

这个 JEP 没有析出新的数字原始类型，也没有为 Java 的一元或二元运算符提供新的功能。

## 动机

Java 是一种面向对象的编程语言，但是它的基本值——布尔值、整数和浮点数——都不是对象。在创建语言时这是一种明智的设计选择，因为每个对象都要进行间接寻址，有着大量额外开销。但是这意味着基本值不支持对象的一些有用特性，比如实例方法、子类型和泛型。

为了解决这些问题，标准库为每个基本类型提供了*包装类（wrapped class）*，每个包装类提供将对应基本类型存储在对象内的能力。Java 5 中有引入了隐式的装箱和拆箱操作，根据程序的需求，在基本值和包装类实例之间透明地相互转换。

但是包装类这个解决方案并不完善。它并没有完全隐藏转换的影响，例如将同一个值装箱两次可能产生两个彼此不 `==` 的对象。更重要的是，在很多程序中，将基本值包装在对象中会产生巨大的运行时开销，程序员必须权衡这些开销与表达能力带来的好处。

由 [JEP 草案：原始对象](https://zhuanlan.zhihu.com/p/354841176) 引入了*原始对象*特性后消除了将 identity-free 值建模为对象的开销。因此现在我们可以在所有上下文中将基本值视为第一等对象。最后，我们可以说所有值都是对象！

每个原始对象都需要一个原始类；`int` 值应该属于哪个类？很多现有代码都假定了基本类型属于其包装类的对象模型。由于不再需要*装箱*基本值，我们可以重新调整包装类的用途——将 `int` 值视为 `java.lang.Integer` 的实例，将 `boolean` 值视为 `java.lang.Boolean` 的实例等。

通过使用原始类定义基本类型，我们可以为它们提供实例方法，并将它们集成进子类型图中。原始值类型与泛型的互操作性将在一个独立的 JEP 中实现。

## 描述

### 基本原始类

8 个*基本原始类（basic primitive classes）*如下：

- `java.lang.Boolean`
- `java.lang.Character`
- `java.lang.Byte`
- `java.lang.Short`
- `java.lang.Integer`
- `java.lang.Long`
- `java.lang.Float`
- `java.lang.Double`

编译器和引导类加载器使用特殊的逻辑定位这些类文件；启用预览功能后，将会查找到这些类修改后的版本。

修改后的版本为原始类。它们属于*偏引用原始类*，这意味着名称 `Integer`、`Double` 等将继续表示引用类型。

这些类的 `public` 构造函数在 Java 16 中被弃用。为了避免一些二进制兼容问题（identity 类和原始类构造器编译后行为不一致），修改后的类的构造器是 `private` 的。

### Java 语言模型

8 个基本类型关键字（`boolean`、`char`、`byte`、`short`、`int`、`long`、`float` 和 `double`）现在是基本原始类对应的原始值类型的别名。`.ref` 语法可以用于表示相应的引用类型。

因为这些关键字是别名，所以每个原始类类型、原始值类型和原始引用类型都有两种方法表示，如下表所示：

| 原始类                 | 值类型                     | 引用类型                   |
| :--------------------- | :------------------------- | :------------------------- |
| `boolean` 或 `Boolean` | `boolean` 或 `Boolean.val` | `boolean.ref` 或 `Boolean` |
| `char` 或 `Character`  | `char` 或 `Character.val`  | `char.ref` 或 `Character`  |
| `byte` 或 `Byte`       | `byte` 或 `Byte.val`       | `byte.ref` 或 `Byte`       |
| `short` 或 `Short`     | `short` 或 `Short.val`     | `short.ref` 或 `Short`     |
| `int` 或 `Integer`     | `int` 或 `Integer.val`     | `int.ref` 或 `Integer`     |
| `long` 或 `Long`       | `long` 或 `Long.val`       | `long.ref` 或 `Long`       |
| `float` 或 `Float`     | `float` 或 `Float.val`     | `float.ref` 或 `Float`     |
| `double` 或 `Double`   | `double` 或 `Double.val`   | `double.ref` 或 `Double`   |

代码风格问题上，使用小写、以关键字为基础的表示方法是首选。

对于原始类声明的限制在基本原始类上有一个特例：允许基本原始类递归地声明一个自身类型的实例字段（例如 `int` 类有一个 `int` 类型的字段）。

Java 支持一些不同基本值类型之间的转换，例如 `int` 可以转换为 `double`；这些行为没有改变。为了清晰起见，我们现在称之为 *widening numeric conversions* 和 *narrowing numeric conversions*。引用类型（例如 `int.ref` 和 `double.ref`）之间没有类似的转换。

*装箱*和*拆箱*操作现在被原始类的*原始引用转换*和*原始值转换*取代。它们支持的类型相同，但是运行时效率更高。

Java 提供了一些一元和二元操作符操作基本值，这些操作不变。

因为基本原始值是对象，所以它们也拥有类声明中定义的那些实例方法。`23.compareTo(42)` 这样的语法现在是合法的。（TODO：这会不会引入解析问题？ `equals` 和 `compareTo` 这样的行为有意义吗？）

与其他原始值类型一样，基本原始值类型的数组是协变的：现在 `int[]` 是 `int.ref[]`、`Number[]` 等类型的子类型。

### 编译和运行时

在 JVM 中，基本原始类型与原始类类型不同：类型 `D` 表示 64 位的浮点值，占用两个栈 slot，并支持一套专用操作（`dload`、`dstore`、`dadd`、`dcmpg` 等），而类型 `Qjava/lang/Double$val;` 表示 `Double` 类型的原始对象，这些原始对象只占用单个栈 slot，并接受对象操作（`aload`、`astore`、`invokevirtual` 等）。

Java 编译器负责根据需求，通过调用类似 `Double.valueOf` 和 `Double.doubleValue` 的方法，将值在两个类型之间互相转换。生成的字节码类似装箱和拆箱操作，但是运行时开销大大减小。

为了保持一致性，字段类型和方法签名中出现的基本原始值类型总是转化为基本 JVM 类型（例如 `double` 表示为 `D` 而不是 `Qjava/lang/Double$val;`）。

对于基本原始数组，仅使用编译器转换并不充足。例如，使用 `newarray` 创建的 `[D` 类型数组可以传递给接受 `[Ljava/lang/Double;` 参数的函数；使用 `anewarray` 创建的 `[Qjava/lang/Double$val;` 可以转换为类型 `[D`。为了支持这种行为，JVM 将类型 `[D` 和 `[Qjava/lang/Double$val;` 视为彼此兼容的，可以在其中任意一个上同时使用两类操作（`daload` 和 `aaload`，`dastore` 和`aastore`），无需关心数组是如何创建的。

### 反射

对于每个基本原始类，程序员通常会遇到两个 `Class` 对象。以类 `double` 为例，它们是：

- `double.class`（等价于 `Double.val.class`），对应于 JVM 描述符类型 `D`。调用 `isPrimitive` 方法返回 `true`。启用预览功能后，为了和语言模型一致，此对象使用 `java.lang.Double$val` 类的声明响应大多数查询（`getMethods`，`getSuperclass` 等）。
- `Double.class`（等价于 `double.ref.class`），对应于 JVM 描述符类型 `Ljava/lang/Double;`。调用 `isPrimitive` 方法返回 `false`。其行为类似于标准的对原始引用类型建模的 `Class` 对象。

对基本原始对象调用 `getClass` 方法返回的 `Class` 对象属于第一种——`double.class`、`int.class` 等。与所有基本对象相同，无论是通过值类型（`(23.0).getClass()`）还是引用类型（`((Double) 23.0).getClass()`）调用 `getClass()` 都会返回相同的结果。这个行为发生了变化，可能会破坏一些程序——`val.getClass().equals(Double.class)` 不是 `val instanceof Double` 安全的替代品。

第三个 `Class` 对象存在，对应于 JVM 描述符类型 `Qjava/lang/Double$val;`，但实践中很少用到，因为 Java 编译器从不在描述符中使用这个名称。这个对象没有对应的类字面量。调用 `isPrimitive` 方法返回 `false`。其行为类似于标准的对原始值类型建模的 `Class` 对象。

## 选择

语言可以保持不变——原始对象是一个有用的功能，它不需要将基本值视为对象。但是消除基本值和对象之间差别是有用的，特别是 Java 的泛型将会被增强以处理原始对象。

可以引入新的类作为基本原始类（比如说 `java.lang.int`），将包装类作为遗留 API 放弃。但是，关于装箱行为的一些假设在代码中根深蒂固，一组新的类会破坏这些程序。

JVM 可以完全统一基本原始类型（`I`、`D` 等）与其对应的原始类类型（`Qjava/lang/Integer$val;`、`Qjava/lang/Double$val;` 等）之间的差别，但这是一个代价高昂的变化，最终几乎没有什么好处。例如，必须有一种方法来协调占用两个栈 slot 的`D` 类型与占用一个栈 slot 的 `Qjava/lang/Double$val;` 类型，可能要对类文件格式进行破坏性的更高。

## 风险和假设

删除包装类的构造函数破坏了传统 Java 程序一个重要子集的二进制兼容性。迁移到原始类也会产生一些行为变化。[JEP 390](https://openjdk.java.net/jeps/390) 以及预期中的一些后续工作缓解了这些问题，但一些调用了构造函数或依赖于装箱对象 identity 的程序会被破坏。

由于基本原始类型将会成为类类型，反射行为的一些变化可能会导致一些程序产生问题。而且对应于 `Qjava/lang/Double$val;` 的 Class 特殊类对象的存在很容易被忽略，可能会让程序员大吃一惊。

## 依赖

[原始对象 JEP](https://zhuanlan.zhihu.com/p/354841176) 是本 JEP 的前置条件。

[JEP 390](https://bugs.openjdk.java.net/browse/JDK-8249100) 向 `javac` 和 Hotspot 添加了包装类可能发生不兼容更改的警告。一些后续工作将在额外的 JEP 中进行。

我们将修改 Java 的泛型模型，使其类型参数更加*通用*——可以由所有类型实例化，包括引用类型和值类型。这将在独立的 JEP 中讨论。