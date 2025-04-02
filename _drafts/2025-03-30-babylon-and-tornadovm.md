---
title: 'Babylon OpenJDK: 初学者指南以及与 TornadoVM 的比较'
date: 2024-06-12 16:59:24
tags:
  - JVM
  - OpenJDK
categories: translate
description: 'Babylon OpenJDK: A Guide for Beginners and Comparison with TornadoVM'
---

原文链接：[Babylon OpenJDK: A Guide for Beginners and Comparison with TornadoVM](https://jjfumero.github.io/posts/2025/02/07/babylon-and-tornadovm)


## 简介

[Babylon](https://github.com/openjdk/babylon) 是一个新的 OpenJDK 项目，旨在增强 Java 平台的代码反射功能，
让反射不仅能查询类和字段，还能获取方法体和 lambda 表达式内的代码结构。
这个项目的最终目标是让用户能在不使用任何第三方库的情况下执行代码转换。

*这在实践中意味着什么？*经过增强的代码反射可用于表示不同类型的计算，例如自动微分[2]、LINQ 表达式[3]，甚至 GPU offload（也是本文的重点）。
我们在本文中将会介绍 Babylon 如何帮助开发人员在 Java 中定义 GPU 编程的并行框架，以及它与 TornadoVM 等现有的解决方案的不同之处。

在深入了解 Babylon 中调用 GPU 的流程之前，我们先来定义一个关键术语--**代码模型（Code Model）**。
在 Babylon 的语境里，代码模型是程序代码的一种表示形式，包含类型和控制流等信息，
由 `javac` 编译器生成并存储于类文件中。

经过 Babylon 增强的反射 API 使开发者能够在运行时访问和操作这些代码模型，从而直接在 Java 中实现元编程。
使用它可以动态生成和操作 Java 程序，比如可以为 Intel/NVIDIA GPU 等各种硬件加速器生成定制的 GPU 代码。
事实上，这正是 Babylon 的子项目 [HAT](https://github.com/openjdk/babylon/tree/code-reflection/hat)（异构加速器工具包，Heterogeneous Accelerator Toolkit）的目的，
它基于 Babylon 为 Java 平台提供了 GPU 后端。

本文中将探讨开发人员该如何使用 HAT 调用 GPU 进行硬件加速。
我们将会深入探讨支持这一功能的关键 API，并解释代码是如何执行的。
然后我还会对比 HAT 与 [TornadoVM](https://github.com/beehive-lab/TornadoVM)。
TornadoVM 是一个 Java 并行编程框架，可以让 Java 透明地调用 GPU 等现代硬件实现数据并行加速处理。

**利益相关** ：我（本文原作者 Juan Fumero）是 TornadoVM 项目的架构师和首席开发者之一。
虽然如此，但我对于 HAT 的探索完全是出于对这一新兴技术的好奇和探索欲。
我的目标是对这两个项目进行客观的比较，在比较中我会尽力做到公平公正，
如果你觉得有任何偏颇的地方，欢迎进行反馈和讨论。

说完这些，让我们开始吧！

## HAT: 异构加速器工具包

本博文反映的是 Babylon 项目截至 2025 年 2 月的状态。
由于该项目正在快速发展，某些示例在未来的版本中可能无法正确编译或运行。
不过，本文介绍的核心概念和基本理解对读者来说仍有价值。

HAT 提供了不同的接口来构建针对 GPU 执行而定制的应用程序。HAT 接口分为三类：

* 帮助开发人员表达并行 Kernel 的 `NDRange` Kernel API。
* 用于在 Java 和硬件加速器之间映射内存的 Java 接口（它们被称为 `iFaceMapper`）。
* 用于识别需要在 GPU 上加速的方法的 API。

让我们简要了解一下这些组件。

### NDRange API

HAT 基于 SIMT（单指令、多线程）模型，而 NDRange API 是用于让 Java 开发者针对此模型创建并行 Kernel 的接口。
在 SIMT 模型中，一条指令同时在多个线程上运行，其中每个线程可以访问不同的数据。
这种 SIMT 模型也是其他 GPU 编程接口和语言（如 CUDA、OpenCL 和 SYCL）的基础。

在 HAT 中，Java 开发人员使用 NDRange API 来定义 Kernel（将要 offload 到 GPU 上的方法）。
Kernel 封装了每个线程要完成的工作，而 NDRange 则定义了将要运行的线程数量。
这种编程模型中，代码与 GPU 实际的核心数无关，所以有很好的可扩展性。

让我们写一个简单的例子：向量加法。在 Java 中，向量加法可以这样实现：

```java
public void vectorAddition(float[] a, float[] b, float[] c) {
    for (int i = 0; i < a.length; i++) {
        c[i] = a[i] + b[i];
    }
}
```

为了清楚起见，我们做两个假设：所有向量都不是空的，并且具有相同的大小。
这些假设简化了问题，让我们能专注于核心概念。
下面是 Babylon/HAT 代码：

```java
@CodeReflection
public void vectorAddition(F32Array a, F32Array b, F32Array c, KernelContext context) {
      int idx = context.x;
      float sum = a.array(idx) + b.array(idx);
      c.array(idx, sum );
}
```

这个例子演示了一个显式并行 Kernel。

相较于上个例子，这个例子中有几个关键的变化值得注意：

* 注解：需要一个新注解（`@CodeRefection`）来指示 javac 编译器生成代表整个方法的代码模型。
* 类型变化：参数类型从 `float[]` 变为 `F32Array`。
  `F32Array` 是 HAT 提供的类型，用于表示与 GPU 兼容的数据结构。
  我们将在下一节深入探讨 HAT 的类型系统和内存管理。
* `KernelContext`：引入了一个新参数--`KernelContext`。
  这个特殊对象用于访问 GPU 内置的 intrinsic，包括线程 ID 和像线程的最大数量这样的 GPU 执行参数。
* 基于线程执行：不再需要 for 循环，取而代之的是使用从 kernel context 中获取的线程 ID 来访问数据。
  这是一种标准的 GPU 编程模式：启动的线程数通常与输入数组的大小相对应。

熟悉 CUDA、OpenCL 或 oneAPI 的人会发现这种代码结构非常熟悉。
在比较 HAT 和 TornadoVM 时，我将再次讨论这种相似性。

### 内存映射

这是 HAT 项目中我最喜欢的部分之一。HAT 定义了一个名为 `iFaceMapper` 的接口来表示数据。
数据实际上通过 Panama Memory Segments API 存储在堆外，以便于 GPU 计算。

在我看来，对于 Java 等托管语言的 GPU 编程来说，因为 GC 会在需要时移动对象，与 GPU 的要求相冲突，
所以设计数据的表示方式是一大挑战，需要在性能、可移植性和易用性之间进行权衡。

为了解决这个问题，HAT 定义了一个能够访问和操作 Panama Segment 中数据的基本接口。
该接口可以扩展，使开发人员能够创建与 GPU 或其他硬件加速器兼容的自定义数据对象。

TODO
这个接口有很大的潜在价值。它不仅适用于 Babylon 和 HAT，还适用于 TornadoVM 等项目。
虽然 TornadoVM 目前提供了丰富的硬件加速器兼容数据类型，但缺少让用户自定义数据存储和表示方式的功能。
这个接口提供一种非常有前景的集成方法，具有很大的灵活性和控制性，可以用来进一步改进 TornadoVM。

举个例子，我们可以这样在 HAT 中创建一个自定义数据对象来存储基于 Memory Segment 的数组：

```java
public interface MyCustomArray extends Buffer {
   int length();

   @BoundBy("length")
   float data(long idx);
   void data(long idx, float f);

   // Define the schema
   Schema<MyCustomArray> schema = Schema.of(MyCustomArray.class,
           array -> array
           .arrayLen("length")
           .array("data"));

   static MyCustomArray create(Accelerator accelerator, int length) {
       return schema.allocate(accelerator, length);
   }
}
```
然后，HAT OpenCL 编译器会生成如下的 C 结构：

```c
typedef struct MyCustomArray_s {
    int length;
    float data[1];
} MyCustomArray_t;
```

虽然还需要写一些模板代码，但它可以用来定义与 GPU 兼容的自定义数据类型。这是不是很酷？

### Accelerator 和 Compute Context

现在让我们来看看 API 的最后一部分，即 `Accelerator` 和 `ComputeContext`。
这两个对象用于定义要使用的后端（如 OpenCL、CUDA 等），以及我们要 offload 的 kernel 列表。

```java
var accelerator = new Accelerator(lookup, Backend.FIRST);
accelerator.compute(cc ->
       MyClass.methodToOffload(cc, matrixA, matrixB, matrixC, size)
);
```

然后：

```java
@CodeReflection
public static void methodToOffload(ComputeContext cc, MyCustomArray matrixA) {
   cc.dispatchKernel(size, kc -> myGPUKernel(kc, data));
}
```

这里要注意，传递给 `dispatchKernel` 方法的第一个参数（本例中为 `size`）是要在 GPU 上部署的线程数。

## 示例：GPU 并行矩阵乘法

让我们将这些概念付诸实践，用 HAT 实现矩阵乘法。
矩阵乘法是现代计算负载（如深度学习、人工智能和 LLM 等）中使用的核心算法之一。
此外，这也是非常适合在 GPU 上进行加速的应用场景。

让我们从矩阵乘法的 Java 顺序实现开始：

```java
private static void runSequential(F32Array matrixA, F32Array matrixB, F32Array matrixC, final int size) {
   for (int i = 0; i < size; i++) {
       for (int j = 0; j < size; j++) {
           float sum = 0;
           for (int k = 0; k < size; k++) {
               float a = matrixA.array((long) i * size + k);
               float b = matrixB.array((long) k * size + j);
               sum += a * b;
           }
           matrixC.array((long) i * size + j, sum);
       }
   }
}
```

这展示了最标准的矩阵乘法（三层嵌套循环）。在 Babylon/HAT 中，我们可以这样将最外层的循环进行并行化处理：

```java
@CodeReflection
public static void matrixMultiplyKernel(KernelContext kc, F32Array matrixA, F32Array matrixB, F32Array matrixC, int size) {
   if (kc.x < kc.maxX) {
       for (int j = 0; j < size; j++) {
           float acc = 0;
           for (int k = 0; k < size; k++) {
               acc += (matrixA.array(kc.x * size + k) * matrixB.array(k * size + j));
           }
           matrixC.array(kc.x * size + j, acc);
       }
   }
}
```

这意味着，我们将在目标设备上部署与矩阵行数相等的线程数，使第一个循环并行运行。
每个线程将执行第二层和第三层循环（归约操作），对每列的值进行累加求和。

接下来，我们需要调度 kernel。

```java
@CodeReflection
public static void matrixMultiply(ComputeContext cc, F32Array matrixA, F32Array matrixB, F32Array matrixC, int size) {
   cc.dispatchKernel(size,
           kc -> matrixMultiplyKernel(kc, matrixA, matrixB, matrixC, size)
   );
}
```

需要注意的是，该方法虽然不会在设备（GPU）上运行，但也包含 `@CodeReflection` 注解。
这是因为 HAT 可以在编译代码之前获取数据并推断类型，同时获取将要 offload 到设备上的方法的代码模型。
因此，该注解可以帮助 HAT 编译器和运行时处理数据，并生成正确的 OpenCL 和 CUDA PTX 代码。

您可以在此处查看完整示例：https://github.com/openjdk/babylon/pull/276。
请注意，唯一将 offload 到 GPU 的方法是 `matrixMultiplyKernel`，
其余代码均在主机端（Java 平台）运行。
那么编译过程是如何完成的？哪些部分被 offload？最终代码是什么样的？让我们深入探究这些问题。

## Babylon/HAT 在内部是如何运行 GPU 的？

截至 2025 年 2 月，HAT 支持 OpenCL 和 CUDA 后端。SPIR-V 后端也正在开发中（有趣的是，SPIR-V 代码生成库实际上是我们龙卷风虚拟机团队为龙卷风虚拟机开发的，所以我很高兴看到这样一个库在学术界之外得到应用）。

HAT 采用两阶段编译流程来获取 GPU 源代码（如 OpenCL C 或 SPIR-V），然后由相应的 GPU 驱动程序执行另一个编译阶段，以获得最终的 GPU 二进制代码。
我们先来讨论一下两阶段编译过程。

下图抽象地展示了不同编译阶段的工作流程，最终得到巴比伦的 GPU 代码。首先，正如我们在前面的示例中看到的，开发人员使用 NDRange API 和加速器工具包来注释和识别要卸载的代码。由于方法使用了 @CodeReflection 注解，因此 javac 编译器会生成一个代码模型，并存储在类文件中。

![](https://raw.githubusercontent.com/jjfumero/jjfumero.github.io/refs/heads/master/files/blog/25-02-07-babylon/babylonCompilation.png)

该代码模型与 AST（抽象语法树）以及类型和控制流信息非常接近。此时，HAT 会执行降级阶段（实际上是调用代码反射 API 的降级阶段），将原始代码模型转换为低级表示法。这种表示法类似于 LLVM IR。

根据该代码表示法，HAT 生成相应的 OpenCL C 代码（也可以生成 CUDA PTX（CUDA 程序的汇编代码）或 SPIR-V）。生成 GPU 代码后，我们需要另一个编译器将生成的源代码转换为 GPU 二进制代码。这需要调用每个驱动程序的相应函数。例如，对于 OpenCL，函数 clBuildProgram 就能完成这项工作。

请注意，我们可以从代码模型本身生成 GPU 代码，而无需下调。因此，根据目标代码的不同，这可能是一个更简单的选择。不过，对于 SPIR-V 或 CUDA PTX 而言，我认为降级阶段是卸载代码的一个更合适的层次。

更多详情：链接

好了，废话少说，让我们来看看实际操作！

## 安装和配置用于 GPU 的 Babylon

### Install prerequisites

For Fedora (Checked on Fedora 41)

```bash
sudo dnf install autoconf alsa-lib-devel cups-devel libXtst-devel libXt-devel libXrender-devel libXrandr-devel libXi-devel
```

for Ubuntu (Checked on Ubuntu 22.04.5 LTS):

```bash
sudo apt-get install autoconf libasound2-dev libcups2-dev libfontconfig1-dev libx11-dev libxext-dev libxrender-dev libxrandr-dev libxtst-dev libxt-dev
```

### Installation of Babylon Code-Reflection with OpenJDK 24

Babylon and HAT are in continuous development. Thus, build instructions may change in the future, The following instructions are based on Babylon (commit ee3da03).

```bash
# as in February 2025

sdk install java 23-open
sdk use java 23-open
```

### Configure Babylon (Java JDK with Babylon Port)

First, we are going to configure Babylon by building JVM from the source code. Then, we are going to use the resulting JVM to compile and run HAT programs on GPUs.

```bash
cd workdir 
ROOT_BABYLON=`pwd`
git clone https://github.com/openjdk/babylon.git
bash configure  --with-boot-jdk=${JAVA_HOME}
make images
```

Now we get a new OpenJDK version:

```
export JAVA_HOME=$ROOT_BABYLON/babylon/build/linux-x86_64-server-release/jdk
export PATH=$JAVA_HOME/bin:$PATH
```

### Configure HAT

```bash
cd $ROOT_BABYLON/hat 
source env.bash 
java @bldr/args bld
```

### Run Examples on GPUs

E.g., Mandelbrot with the OpenCL backed:

```bash
java @bldr/hatrun ffi-opencl mandel
```

Mandelbrot with the CUDA PTX backed:

```bash
java @bldr/hatrun ffi-ptx mandel
```

Cool, isn’t it? Let’s now run a benchmark and compare it with Java and TornadoVM.

## Performance Evaluation of Matrix Multiplication on GPUs

In this section, we are going to evaluate the performance of the Matrix Multiplication on GPUs using Babylon, and compare it against TornadoVM. The following table shows the system CPU, GPU and the software used.


* CPU: 13th Gen Intel(R) Core(TM) i9-13900K
* GPU: RTX 4090
* NVIDIA-DRIVER: 550.107.02
* OS: Ubuntu 22.04.5 LTS
* Kernel: Linux 6.8.0-47
* RAM: 64GB
* CUDA: 12.1.r12.1
* GCC: 11.4.0
* TornadoVM: 1.0.10-dev (5da9549d1)
* JDK for TornadoVM: OpenJDK “21.0.4” 2024-07-16 LTS
* Babylon: cd3c7ce9c8a
* JDK for Babylon: openjdk 23.0.1

### Examples

Let’s run the Matrix Multiplication explained in the previous section and compare it with TornadoVM. The full example in Babylon can be found in the following link:

https://github.com/jjfumero/babylon/tree/dev/examples/hat/examples/matmul

The TornadoVM version can be found here:https://github.com/jjfumero/tornadovm-examples.

In this post I am not explaining how to program with TornadoVM. If you are interested, I recommend a previous article in which I go into the details about how TornadoVM is used to accelerate different workloads: https://jjfumero.github.io/posts/2024/23/tornadovm-programming-model.

### Backends

Let’s evaluate the OpenCL C and the PTX backends. For the OpenCL C, I use the Intel Integrated Graphics. Although on my system I could have used the RTX 4090 for OpenCL, at the time of writing this post, Babylon does not support multiple devices or device switching. Thus, to make a fair comparison, I also chose the integrated GPU in TornadoVM.

Compared with TormadoVM, an interesting feature is when multiple GPUs are available, the TornadoVM runtime system automatically reorders the devices and selects the best based on compute capability and number of threads to be deployed. Thus, in my system, the default choice for TornadoVM was the 4090, which in my opinion, is what we want by default.

### How to reproduce?

Babylon (OpenCL):

```java
java @bldr/hatrun ffi-opencl matmul
```

Babylon (PTX):

```java
java @bldr/hatrun ffi-ptx matmul
```

TornadoVM:

The experiment is taken from the tornadovm-examples project.

Note that we can increment the number of runs to make it match with the Babylon experiment, and remove the 2D level of parallelization, to make it equivalent to the HAT/Babylon example:

```diff
git diff
diff --git a/src/main/java/io/github/jjfumero/MatrixMultiplication.java b/src/main/java/io/github/jjfumero/MatrixMultiplication.java
index 81bf05c..13c5bb1 100644
--- a/src/main/java/io/github/jjfumero/MatrixMultiplication.java
+++ b/src/main/java/io/github/jjfumero/MatrixMultiplication.java
@@ -253,7 +253,7 @@ public class MatrixMultiplication {
          */
         private static void mxmTornadoVM(Matrix2DFloat a, Matrix2DFloat b, Matrix2DFloat c, final int size) {
             for (@Parallel int i = 0; i < size; i++) {
-                for (@Parallel int j = 0; j < size; j++) {
+                for (int j = 0; j < size; j++) {
                     float sum = 0.0f;
                     for (int k = 0; k < size; k++) {
                         sum += a.get(i, k) * b.get(k, j);
@@ -277,7 +277,7 @@ public class MatrixMultiplication {
 
         private static TornadoExecutionPlan createTornadoVMPlan(Matrix2DFloat a, Matrix2DFloat b, Matrix2DFloat c) {
             TaskGraph taskGraph = new TaskGraph("mxm");
-            taskGraph.transferToDevice(DataTransferMode.FIRST_EXECUTION, a, b) //
+            taskGraph.transferToDevice(DataTransferMode.EVERY_EXECUTION, a, b) //
                     .task("mxm", Multiplication::mxmTornadoVM, a, b, c, a.getNumRows()) //
                     .transferToHost(DataTransferMode.EVERY_EXECUTION, c);
             TornadoExecutionPlan executionPlan = new TornadoExecutionPlan(taskGraph.snapshot());
@@ -455,7 +455,7 @@ public class MatrixMultiplication {
         matrixA.initRandom();
         matrixB.initRandom();
 
-        final int RUNS = 10;
+        final int RUNS = 100;
 
         // 6 implementations to compare
         ArrayList<ArrayList<Long>> timers = IntStream.range(0, 6) //
```

To run:

```bash
tornado -cp target/tornadovm-examples-1.0-SNAPSHOT.jar io.github.jjfumero.MatrixMultiplication onlyTornadoVM
```

If we have multiple devices/backends installed with TornadoVM, we can change the device and the runtime by using the flag -Dmxm.mxm.device=X:Y. X and Y are the required device indices. You can check all devices available with TornadoVM with the following command:

```bash
tornado --devices
```

### Performance Evaluation

#### OpenCL C on Intel Integrated Graphics

下面的性能图显示了所有评估版本在 100 次运行中的运行时间分布：a) 使用 OpenCL 后端的 TornadoVM；b) 通过 OpenCL 后端调度 SPIR-V 代码的 TornadoVM；c) 通过零级应用程序接口调度 SPIR-V 代码的 TornadoVM。最后一个条形图显示了巴比伦的运行时分布。所有这些版本都在英特尔集成显卡上运行。y 轴以纳秒为单位显示总运行时间（端到端）。因此，时间越短越好。每个版本的首次运行时间都包括 JIT 编译时间。

![](https://raw.githubusercontent.com/jjfumero/jjfumero.github.io/refs/heads/master/files/blog/25-02-07-babylon/plotBabylonVSTornadoVM-iGPU-streaming.png)

我们可以看到，TornadoVM 的性能始终优于 Babylon，即使在 JIT 编译的情况下也是如此。TornadoVM 的性能也更加稳定，执行时间紧紧围绕平均值。在相同的英特尔集成 GPU 上，Babylon 的性能差异更大，尽管其最小执行时间和最大执行时间之间的总差异仅约为 93 毫秒。

现在让我们来看看全貌。让我们将上述每种方法与使用 Java Streams（CPU 上最快的 Java）运行的 Java 和 Java Vector API 进行比较。下面的性能图显示了在峰值性能（预热后）下与 Java 连续运行相比的速度提升，并与 a) CPU 上的 Java 并行矢量 API；b) Intel 集成 GPU 上使用 OpenCL C 的 TornadoVM（2D 内核）；c) 使用 OpenCL C 的 TornadoVM（1D 内核）；d) Babylon/HAT。

![](https://raw.githubusercontent.com/jjfumero/jjfumero.github.io/refs/heads/master/files/blog/25-02-07-babylon/speedupBabylonAndTornadoVM-igpu.png)

我们看到，对于此应用程序，在集成 GPU 上运行的 MxM 并不比在 CPU 上运行的并行 Java Vector API 更好。
记住！除非您拥有强大的加速器，否则不要低估 CPU 的性能！

如果我们包括 NVIDIA 4090 GPU，那么 TornadoVM 的性能比 OpenCL 后端的 Java 高出 2500 倍，正如我在最近的一篇技术文章中详细介绍的那样！

#### CUDA PTX Backend

那么在 NVIDIA 4090 GPU 上运行的 PTX 后端又如何呢？下面的性能图显示了 Java 连续版本、并行 Java Vector API 版本、带有 PTX 后端的 TornadoVM 1D、TornadoVM 2D 版本和 Babylon 的 100 次运行时间分布（越低越好）。

![](https://raw.githubusercontent.com/jjfumero/jjfumero.github.io/refs/heads/master/files/blog/25-02-07-babylon/plotPerformancePTX.png)

圆点表示第一次执行，其中 TornadoVM 和 Babylon 执行 JIT 编译。我们可以看到，TornadoVM 的运行速度比 Babylon 快，包括涉及 JIT 编译和执行的第一次运行（与 Babylon 相比，TornadoVM 1D 版本快 2.3 倍，2D 版本快 9.3 倍）。

当我们将 Babylon 和 TornadoVM 1D 与并行的 Java 向量应用程序接口（Java Vector API）进行比较时，我们发现它们的运行速度比并行的 CPU 实现要慢。在离散 GPU 上运行时，我们必须考虑卸载的成本，其中我们需要考虑主 CPU 和 GPU 之间的数据传输，以及我们将在设备上执行的并发/并行操作的数量。对于 MxM 这一特殊应用，当我们以一维方式运行时，硬件的利用率很低。

如果您想深入了解 Java 向量应用程序接口与 TornadoVM 的对比分析，我推荐您阅读以下文章: https://jjfumero.github.io/posts/2024/12/17/tornadovm-vs-opencl.

通过观察 PTX 后端与 Java 相比的速度：

![](https://raw.githubusercontent.com/jjfumero/jjfumero.github.io/refs/heads/master/files/blog/25-02-07-babylon/speedupBabylonAndTornadoVM-ptx.png)

我们可以看到，在相同的 GPU 下，TornadoVM 的速度是 Java 的 1700 倍，是 CPU 执行速度的 11 倍，是 Babylon/HAT 的 346 倍。

这是否意味着 TornadoVM 总是比 Babylon/HAT 快？不一定。对于某些应用来说，TornadoVM 可能更快，而其他应用则可能更慢。正如我在下一节详细介绍的那样，TornadoVM 有一个 JIT 编译器和优化器，可以为某些应用程序带来优势。

## HAT vs TornadoVM: Differences and Limitations

让我们来谈谈 Babylon 和 TornadoVM 目前的局限性。请记住，这两个项目都在积极开发中，我今天（2025 年 2 月）所描述的局限性可能会在不久的将来得到解决/克服。

### Current Limitations of Babylon/Hat vs TornadoVM

Babylon 和 HAT 显然专注于提供一个接口来方便 Java 代码的操作和转换。因此，主要关注点是编译和运行代码所需的最低运行时支持（例如，数据处理和数据表示）。

相反，TornadoVM 提供了更完整的解决方案，可以在现代硬件加速器上运行，而不仅仅是在 GPU 上运行。因此，TornadoVM 提供了一个更复杂的工程框架来解决每个架构的自适应编译器优化、专门的代码优化器和针对不同架构和供应商的优化运行时系统。让我们来分析一下：

#### Runtime Limitations

Babylon HAT 的运行时功能目前有限。与 TornadoVM 相比，HAT 缺乏动态多设备选择（例如多个 GPU）和动态任务迁移。相反，设备始终是静态分配的，这降低了对不断变化的系统条件的适应性。此外，它不支持数据范围的复制操作，从而限制了自动数据管理功能（例如自动批处理）。

#### Hardware Support and Code Generation

Babylon HAT 目前缺少针对除 GPU 之外的其他设备的代码生成和运行时编排器。与支持来自多家供应商（英特尔、NVIDIA 和 AMD）的 GPU、CPU、FPGA 甚至 RISC-V 加速器的 TornadoVM 相比，Babylon 的硬件支持范围要窄得多。虽然未来可能会扩展，但目前的限制限制了它的适用性。缺少代码优化器可能会影响专用硬件加速器的性能潜力 [4]。

#### Compiler Optimizations

Babylon 至少目前不包含优化器编译器。相比之下，TornadoVM 扩展了最先进的开源 Graal JIT 编译器，其中包含针对 GPU、FPGA 和多核 CPU 的新编译器优化管道、调整循环顺序、自动使用快速内在函数、自动使用本地/共享内存等。

#### Parallelism and API Complexity

Babylon HAT 缺乏对二维和三维并行（或二维和三维范围）的本地支持。虽然这似乎是未来实现的一个相对简单的功能，但目前的缺失限制了多维问题的高效并行化。HAT API 及其 Range 编程模型要求开发人员具备 GPU 编程模型（如 CUDA、OpenCL 或 oneAPI）方面的专业知识。虽然有这方面背景的开发人员可以很快提高工作效率，但没有这方面背景的开发人员可能会面临陡峭的学习曲线。

这与 TornadoVM 的双 API 方法形成了鲜明对比：针对新手的基于注释的高级系统和针对专业开发人员的低级内核 API（类似于 Babylon 的 Range API）。我认为这种双重方法可以聚集更多的开发人员。

### Current Limitations in TornadoVM vs Babylon/HAT

TornadoVM 绝不是完美无缺的。它还在持续开发中，每个新版本都在不断改进。

#### Support for Custom Data Types

TornadoVM 的主要局限性在于缺乏与 Java 和硬件加速器兼容的用户数据类型定制。iFaceMapper 是一种很有前途的方法，可用于编程和处理兼容硬件加速器和 Java 运行时的高效数据结构。

#### New APIs and Data Types

这同样适用于 Babylon/HAT，但由于我更多地参与了 TornadoVM 项目，因此可以在此参考。提供 API 和新类型虽然对实现性能至关重要，但代价是开发人员必须学习新的 API。在我看来，如果这些新接口是 JDK 的一部分，那么采用这些类型的技术将更加容易。

#### Code Generation of Structure Programming Languages

TornadoVM 的代码生成非常棘手，尤其是 OpenCL C 后端。从底层细节来看，TornadoVM 从 Graal IR 中的低层生成代码，这是一种非结构化流 IR [5]。这里的挑战是从非结构化流图生成结构化 OpenCL C 内核。因此，有时很难生成正确的代码。对于 TornadoVM 而言，更好也更容易的目标是 CUDA PTX 和 SPIR-V，而不是 OpenCL C。由于 Babylon 以接近于 AST 的形式生成 OpenCL C 代码，因此生成正确的 OpenCL C 代码将更加容易。

#### Maintenance Support

事实上，TornadoVM 提供了更多的后端并支持更多的设备，这也带来了维护成本。对于像 TornadoVM 这样的小团队来说，总是要在提供新功能和保持 TornadoVM 适用于所有可能的设备、架构和操作系统之间进行权衡。这一限制虽然不在设计之列，但不容忽视。

我希望这是一个积极的讨论。您还知道/看到其他限制吗？请在评论中告诉我。

## Conclusions and Final Thoughts

巴比伦（Babylon）通过其增强的反射应用程序接口（reflection API）和 HAT 子项目，为 Java 中的 GPU 编程提供了一种非常有趣的方法。通过在运行时直接操作代码模型，它有助于动态生成 GPU 代码。

本文将简要介绍巴比伦和通过 HAT 项目进行的 GPU 编程，以及当前的性能、与 TornadoVM 的异同。在过去的 12 多年里，我一直直接参与 Java GPU 编程工作（时间过得真快！）。

我希望将 HAT 看作未来增强 Java 平台的孵化器 OpenJDK 项目，让 Java 开发人员不仅能在现代 GPU 上运行，还能在即将推出的新加速器（如新的人工智能加速器）上运行。在我看来，Babylon/HAT 是统一和整合 API 和接口的一个步骤，有助于供应商和实施者（如 TornadoVM）在提供高性能的同时尽可能接近 Java。

在这方面，我认为 HAT 借鉴了 TornadoVM、Aparapi 等项目的想法和研究成果。例如，正如 Gary Frost（HAT 项目的主要软件架构师和 Aparapi 的创建者）所承认的，HAT Accelerator 和 Compute-Context API 受到了 TornadoVM API 的启发。此外，我还看到从 Aparapi 项目借鉴的一些想法。

正如我简要提到的，TorandoVM 不仅是一个范例，也是一个技术推动者，它允许 HAT 开发人员使用我们为在 TornadoVM 中启用 SPIR-V 后端而实施的 Java 框架编写 SPIR-V 后端。

## Discussions

If you are interested, let’s keep the discussions active:

https://github.com/jjfumero/jjfumero.github.io/discussions/14

## Links

[1] https://mail.openjdk.org/pipermail/discuss/2023-September/006226.html

[2] https://openjdk.org/projects/babylon/articles/code-models

[3] https://openjdk.org/projects/babylon/articles/linq

[4] https://jjfumero.github.io/posts/2024/12/17/tornadovm-vs-opencl

[5] https://dl.acm.org/doi/pdf/10.1145/2816707.2816715