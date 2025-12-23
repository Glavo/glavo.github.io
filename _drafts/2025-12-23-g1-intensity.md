---
title: '[翻译] JEP draft: Automatic Heap Sizing for G1'
date: 2025-12-23 12:00:00
tags:
  - JVM
  - GC
categories: translate
description:
---

原文链接：[JEP Draft: Automatic Heap Sizing for G1](https://openjdk.org/jeps/8359211)

---

## Summary

Automatically and dynamically adapt the maximum Java heap size according to the environment when using the G1 garbage collector (G1).

## Goals

When using G1:

* Dynamically adapt the maximum Java heap size to changes to the available memory in the environment.
* Typical performance should not change noticeably compared to when the end user manually correctly tunes Java heap size.

## Non-Goals

It is not a goal of this JEP to:

* Find a static optimal maximum Java heap size.
* Remove the existing configurability of static heap bounds using existing Java heap sizing options.
* Change existing dynamic adaption of the current Java heap size to the workload.

## Motivation

When users choose the G1 garbage collector, the maximum heap size is the only memory-related option they should need to set. Unfortunately, setting a good maximum heap size is notoriously difficult. An application's memory usage or requirements depend on the input and changes during different phases of execution, yet the user is asked to set a maximum heap size across the entire runtime of the application in advance. In addition to the Java heap memory, the JVM itself allocates a certain, non-fixed amount of memory for its own purpose that also depends on the selected maximum heap size which the user needs to consider when determining it. If the maximum Java heap size is set too low, the application can run out of memory; if set too high, the environment can run out of memory. Finding a good maximum heap size involves measuring application memory usage and throughput for different maximum Java heap sizes in an experimental setup that provides a representative workload to an application. Setting up such an environment alone is challenging for most users.

We argue that the JVM can automatically control the maximum Java heap size and balance CPU and memory consumption better than the user can manually with explicit configuration. The JVM should monitor the free memory available in the environment, and use that always current information to automatically determine a maximum heap size. Users should not need to set `-Xmx` when choosing G1. G1 should be allowed to use all the memory in the environment if needed, just as a C application does, yet timely respond to a reduction in free memory. Finally, users should be able to express a preference between less garbage collector CPU usage (but more memory use) and more garbage collector CPU usage (but less memory use) similarly to what [JEP XXX](https://openjdk.org/jeps/8329758) provides for the ZGC collector.

With automatic heap sizing, the memory consumption may further depend on how much free memory is available in the environment. The same application may consume more memory if it is not needed for other applications and less memory when other applications running in the same environment are using more memory.

## Description

G1 is being extended to automatically select a maximum Java heap size that dynamically adapts to changing circumstances in the program and the environment.

The selected heap size will lie between the minimum (`-Xms`) and maximum (`-Xmx`) heap configuration, but when one or both are not configured by the user, the default maximum and minimum heap sizes will be changed when using G1 to give the automatic heap sizing as much flexibility as possible, as follows:

* Default minimum and initial heap sizes (`-Xms`) are changed to 4 MB.
* Default maximum heap size (`-Xmx`) is changed to 100% of the available RAM of the computer or the compressed oops boundary if [compressed oops](https://wiki.openjdk.org/display/HotSpot/CompressedOops) are in use, whichever is lower (see the [Determining maximum heap size](https://openjdk.org/jeps/8359211#Determining-maximum-heap-size) section), minus a small reserve.

Within these boundaries, G1 will dynamically adapt the Java heap size, as described below:

* G1 ergonomics will [automatically and dynamically tune](https://openjdk.org/jeps/8359211#Automatic-dynamic-tuning) the maximum heap size according to changes in the availability of free memory in the environment. This [response to environment memory pressure](https://openjdk.org/jeps/8359211#Responding-to-environment-memory-pressure) will be to either decrease maximum heap size and reduce JVM memory usage by giving back memory to the operating system, or increase maximum heap size and use more memory as free memory in the environment increases to better meet G1 garbage collector goals.
* Sudden increases in application allocation requests are specifically handled, by [rapid expansion](https://openjdk.org/jeps/8359211#Rapid-expansion) of the Java heap.
* A [new method](https://openjdk.org/jeps/8359211#G1GCIntensity) (`-XX:G1GCIntensity`) to indicate the user's intent about the performance/memory footprint tradeoff for influencing this dynamic maximum heap size.

With these changes, the need for configuring the maximum heap size when using G1 should drop significantly.

This feature will be enabled by default when using the G1 garbage collector. Since the G1 garbage collector is currently the default collector, there is typically nothing to do for the end user to benefit from these changes. If there are existing minimum and maximum heap size limitations set (via `-Xms` and `-Xms`), they will set the operating limits within which these new features will apply. Users are encouraged to remove these options.

### Automatic dynamic tuning

After finding an initial maximum heap size, G1 continuously monitors the behavior of the garbage collector, the application, and the environment, adjusts the maximum heap size, and applies incremental tuning of actual heap size using existing mechanisms.

### Determining maximum heap size

G1 ergonomics determine the maximum heap size using 100% the available RAM in the environment, observing current settings for [compressed oops](https://wiki.openjdk.org/display/HotSpot/CompressedOops) minus a small reserve of free memory if the user did not set a maximum heap size.

The compressed oops boundary is approximately at 32 GB without additional options. Staying within this bound by default, keeps G1 profiting from the performance advantages compressed oops provide in the common case of applications requiring less than 32 GB. When disabling compressed oops, G1 may use all of the available memory in the environment minus the small reserve.

A reserve of system memory kept unused by the JVM is generally helpful, even in even in single-application deployments. For example, it allows for file caches to be populated, which typically improves the performance of the system. At the same time, as explained in [rapid expansion](https://openjdk.org/jeps/8359211#Rapid-expansion) this unused memory acts as a safety buffer that can be used to avoid unexpected responses by the garbage collection algorithm that manifest in whole heap collections if the application's allocation rate rises suddenly.

### Measuring CPU overhead

G1 is a generational garbage collector. Young objects are placed in a young generation, collected more frequently during young-only phases. Old objects are promoted to the old generation without collecting them at first. The old generation is collected less frequently in the space reclamation phase (which collects both generations) according to the [G1 garbage collection cycle](https://docs.oracle.com/en/java/javase/24/gctuning/garbage-first-g1-garbage-collector1.html#GUID-F1BE86FA-3EDC-4D4F-BDB4-4B044AD83180).

To decide whether to grow or shrink the heap G1 tracks garbage collector CPU usage, trying to keep the target garbage collection CPU usage derived from the current value of `-XX:GCTimeRatio`, and modified by `-XX:G1GCIntensity`, the current maximum heap size, and other existing variables. In the existing heuristics, G1 examines the overall GC CPU usage at every young collection. If a sequence of garbage collections consumes more CPU than the CPU target, then the heap expands. Conversely, if a sequence of collections consumes less CPU than that CPU target, the heap shrinks.

Garbage collection activity is not the only CPU overhead imposed by the GC. Frequent collection cycles impose other CPU penalties on the application, such as increased execution of GC barriers (instructions performed when accessing Java objects while a garbage collection cycle is in progress). The existing automatic heap resizing heuristics take this into account and expand the heap to minimize such impacts. These impacts can be larger the more CPU the application itself consumes, and this, too, is taken into consideration.

### Responding to environment memory pressure

The JVM process can automatically find an appropriate heap size for the given target garbage collector CPU usage. However, if we let the JVM use as much memory as it wants, the environment may not have enough memory available to run other processes. Therefore, in addition to monitoring the behaviour of the Java application, G1 will also continuously monitor the overall available free memory. If there is a decrease in free memory in the environment, G1 will adjust its internal target CPU usage and attempt to shrink the heap. Similarly, in response to more free memory in the environment, G1 may increase JVM memory usage to better meet garbage collector CPU usage and pause time goals to accommodate current and future predicted behaviour of the application.

This shrinking and expansion of the Java heap is done concurrently with the application; the added memory is proactively concurrently uncommitted or committed and paged to minimize any slowdowns due to OS operations.

This new maximum heap size will automatically consider the JVM's internal native memory usage: If the JVM requires more native memory, the amount of free memory in the environment adjusts, and so the automatically determined maximum heap size.

Other applications running in the same environment may also deplete the free memory in the environment, which will have the effect of increasing GC frequency, making the JVM consume less memory to shrink the heap at the cost of spending more CPU. Multiple JVMs using G1 and running in the same environment will reach an equilibrium rather than fight over memory with each other.

On MacOS or Windows with memory compression enabled, the ratio of compressed and uncompressed memory is continuously monitored. The perceived size of the memory reserve is scaled according to that compression ratio. When the OS starts compressing more memory, the GC will work harder to reclaim garbage and give memory back to the OS, relieving its compression pressure.

### Rapid expansion

Decent startup performance is an important goal for a balanced garbage collector like G1. When the JVM starts with an initial heap size of 4 MB on a large computer with many cores, it will quickly find itself in a situation where that Java heap size is not enough. The application might require a heap size of, for example, 20 GB, in which case the garbage collector will need to expand the heap and do so very quickly.

Specifically at startup, with the heap starting out small, garbage collection will likely trigger early on and frequently, as the application is likely to need more memory faster than the garbage collector can free it. To accommodate these application allocation surges, G1 will keep expanding the heap as per existing heuristics.

In addition to expanding the heap in the event of allocation surges, the garbage collector will use the recent CPU usage of the garbage collector and application activity to grow the heap as necessary. Growing the heap allows G1 to reduce the frequency of collections, which in turn reduces the garbage collector's CPU usage and so may improve the application's throughput.

### G1GCIntensity

Users may have different preferences on how to trade garbage collector CPU usage for memory footprint for different applications.

The new option `-XX:G1GCIntensity` influences this tradeoff between garbage collector CPU usage and memory footprint. It takes an integer value between 0 and 10, with a default of 5. This corresponds to a balance of garbage collector CPU usage/memory footprint provided by existing defaults. Raise it for a larger CPU usage and a smaller heap; lower it for less CPU usage and a larger heap.

The `-XX:G1GCIntensity` option is manageable, meaning it may be updated at runtime, if desired.

## Testing

This enhancement primarily affects performance metrics. Therefore, it will be thoroughly performance-tested with a wide variety of workloads. The defined success metrics will be tested on said workloads.

## Risks and Assumptions

By changing the default maximum heap size from 25% of the available memory to all available memory, there is a risk that the new heuristics use more memory than the current implementation would, and so other processes may run out of memory. However, even with a 25% default maximum heap policy there is already a risk of that happening when several JVMs using that default run in the same environment. Moreover, the dynamically updated maximum heap size is very likely to be able to throw an out-of-memory error before exceeding the environment's memory limits.
