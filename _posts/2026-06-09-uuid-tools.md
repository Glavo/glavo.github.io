---
title: 'UUID Tools: 一个现代化的 Java UUID 工具库'
date: 2026-06-09 00:00:00
tags:
  - JVM
categories: blog
description: 'UUID Tools 简介与使用指南'
---

# UUID Tools: 一个现代化的 Java UUID 工具库

最近，我发现 Java 标准库的 `java.util.UUID` 提供的功能不够丰富。

`java.util.UUID` 从 Java 1.5 开始就存在，但它的 API 一直相当克制：生成方面主要提供 `randomUUID()` 和 `nameUUIDFromBytes(byte[])`，分别对应 UUID v4 和 v3；Java 26 虽然补充了 `UUID.ofEpochMillis(long)` 用于构造 UUID v7，但仍然缺少很多常见需求，例如：

- 不支持生成 UUID v1/v2/v5/v6/v8；
- `randomUUID()` 固定使用加密强随机源，吞吐与行为都不便控制；
- `UUID.fromString(String)` 只接受标准的带连字符格式；
- 只能从 v1 UUID 中提取时间戳、clock sequence 和 node，不支持 v6/v7 等新的时间有序 UUID；
- 默认的 `compareTo` 方法把两个 64 位半区当作有符号整数比较，不符合通常把 UUID 视作无符号 128 位整数的排序习惯。

虽然现在已经有 [JUG](https://github.com/cowtowncoder/java-uuid-generator) 和 [UUID Creator](https://github.com/f4b6a3/uuid-creator)，
不过它们还是略显重量级，并且 API 较为复杂。

为了满足我对 UUID 的需求，我开发了一个新的轻量级 UUID 工具库：[**UUID Tools**](https://github.com/Glavo/uuid-tools)。

## 开始使用

UUID Tools 非常轻量，用一个核心类 `org.glavo.uuid.UUIDs` 暴露了所有功能。

它提供了以下功能：

- 生成 UUID v1/v2/v3/v4/v5/v6/v7/v8，且能够很简单地自定义时间源和随机源；
- 由 UUID 各版本的字段直接构造 UUID；
- 常见 UUID 常量，例如 nil/max UUID 和 namespace UUID；
- 从时间相关 UUID 中提取时间戳、clock sequence、node 等字段；
- 解析和输出多种常见文本格式，包括标准、紧凑、URN、Windows registry、Base62 等；
- 与字节数组之间互相转换；
- 按无符号 128 位整数正确比较 UUID。

## 生成 UUID

UUID Tools 支持生成所有版本的 UUID，并且也允许用户轻松地覆盖默认的时间源和随机源。

所有生成 UUID 的方法都用 `generateV{version}` 命名，例如 `generateV1()`、`generateV4()`、`generateV7()` 等。

此外，UUID Tools 也允许你直接从 UUID 字段来构造 UUID，以便于更深度的定制。这些方法用 `v{version}` 命名，
例如 `v7(Instant timestamp, int randomHi, long randomLow)` 可以根据指定的时间戳和随机位来构造一个 UUID v7。

### 选择 UUID 版本

UUID 有一个整数版本号（比如 v4、v5、v7）。不同的版本号代表不同的含义和用途，版本号的高低不代表绝对的“新旧”或“优劣”，

在生成 UUID 前，请先根据你的用途来选择合适的 UUID 版本：

- UUID v7：基于时间戳和随机数的 UUID，排序时会根据时间顺序进行排序，适合大部分场合；
- UUID v4：完全随机的 UUID，适合不需要时间信息的场合；
- UUID v5：基于指定名称空间和字符串名称 UUID，适合需要稳定派生标识符的场合；
- UUID v8：自定义布局的 UUID，如果你有自定义 UUID 信息的需求，可以使用 v8 来实现。

此外，UUID Tools 也支持一些遗留版本的 UUID，对于新场景通常不推荐使用：

- UUID v1：基于时间戳和 MAC 地址的 UUID，默认情况下排序时不会按照时间戳排序，并且可能会暴露 MAC 地址信息，推荐使用 v7 代替；
- UUID v2：和 UUID v1 类似，但嵌入了 local domain 和 local identifier，主要用于兼容特定历史系统，推荐使用 v7 代替；
- UUID v3：基于指定名称空间和字符串名称的 MD5 哈希 UUID，安全性较弱，推荐使用基于 SHA-1 算法的 v5 代替；
- UUID v6：基于时间戳和 MAC 地址的 UUID，和 v1 类似，但是解决了 v1 的排序问题，但由于历史包袱，推荐使用 v7 代替。

### 根据时间生成 UUID（UUID v1/v2/v6/v7）

对大多数需要带时间信息的场景，优先推荐使用 UUID v7。

UUID v7 内部编码了一个时间戳，以及防止冲突的随机位。在排序时，它会根据时间戳进行排序，适合用作数据库主键、分布式 ID 等需要时间有序的场合。

你可以通过 `generateV7()` 来生成一个基于当前时间的 UUID v7：

```java
UUID _ = UUIDs.generateV7();
```

你可以通过提供自定义的 `InstantSource` 来控制时间来源，提供自定义的 `RandomGenerator` 来控制随机来源：

```java
// 使用指定的时间源生成 UUID
UUID _ = UUIDs.generateV7(Clock.fixed(...));

// 使用指定的随机源生成 UUID
UUID _ = UUIDs.generateV7(new SecureRandom());

// 同时指定时间源和随机源
UUID _ = UUIDs.generateV7(Clock.fixed(...), new SecureRandom());
```

如果你有具体的时间戳和随机位，你也可以使用 `v7` 方法直接构造一个确定的 UUID v7：

```java
UUID _ = UUIDs.v7(Instant.now(), 114514, 1919810L);
```

UUID v1/v2/v6 中同样包含时间戳信息，你可以使用类似的 `generateV1/v2/v6` 方法来生成它们，或者使用 `v1/v2/v6` 方法直接构造它们。

不过由于它们存在一些历史包袱，如果没有明确的兼容需求，建议优先使用 UUID v7。

### 生成随机 UUID（UUID v4）

UUID v4 是不包含时间信息的随机 UUID，JDK 内置的 `UUID.randomUUID()` 方法就会生成一个 UUID v4。

不过 JDK 的 `UUID.randomUUID()` 固定使用全局共享的 `SecureRandom` 作为随机源，性能较差，用户也无法控制随机源。
UUID Tools 的 `UUIDs.generateV4()` 是它的一个更灵活的替代方案。

如果你没有明确的安全性需求，可以直接使用 `UUIDs.generateV4()` 来生成一个 UUID v4：

```java
UUID _ = UUIDs.generateV4();
```

它使用了 UUID Tools 的默认随机源，对于没有加密安全需求的普通场景来说随机性已经足够，相比 `UUID.randomUUID()` 性能更好。

如果你有安全性需求，或者想要使用特定的随机源，可以显式传入自定义的 `RandomGenerator`：

```java
// 生成加密安全的 UUID v4
UUID _ = UUIDs.generateV4(new SecureRandom());

// 使用其他 RNG 生成 UUID v4
UUID _ = UUIDs.generateV4(RandomGenerator.getDefault());
```

此外，UUID Tools 允许你根据已有的随机位来确定性的构造一个 UUID v4：

```java
long randomHi = 114514L;
long randomLow = 1919810L;

// 根据指定的随机位构造 UUID v4
UUID _ = UUIDs.v4(randomHi, randomLow);
```

### UUID v3/v5：从名称稳定派生

如果你有一个字符串名称，并且希望从它派生出一个 UUID，可以使用 UUID v5。

生成 UUID v5 需要一个 UUID 作为名称空间，以及一个字符串作为 name，
`generateV5(UUID namespace, String name)` 会根据它们计算 SHA-1 哈希，并通过哈希值来构造一个 UUID v5。

给定同样的 namespace 和 name，结果永远相同；任何一个变化通常会产生完全不同的 UUID。

```java
// 基于标准的 DNS namespace 和 "glavo.site" 这个名称生成 UUID v5
UUID _ = UUIDs.generateV5(UUIDs.NAMESPACE_DNS, "glavo.site");

// 你也可以使用自定义的 UUID 作为 namespace 来生成 UUID v5
UUID myNamespace = UUIDs.generateV4();
UUID _ = UUIDs.generateV5(myNamespace, "glavo.site");
```

UUID Tools 内置了 RFC 中常见的 namespace 常量：

- `UUIDs.NAMESPACE_DNS`
- `UUIDs.NAMESPACE_URL`
- `UUIDs.NAMESPACE_OID`
- `UUIDs.NAMESPACE_X500`

如果你已经有了一个 256 位的哈希值 `byte[]`，你可以直接使用 `v5(byte[] hash)` 方法来构造一个 UUID v5：

```java
byte[] hash = new byte[32]; // 256-bit hash

// 根据指定的哈希值构造 UUID v5
UUID _ = UUIDs.v5(hash);
```

此外，UUID v3 也是基于名称派生的 UUID，UUID Tools 也提供了类似的 `generateV3` 和 `v3` 方法。
不过它使用 MD5 哈希算法，安全性较弱，现已不推荐使用。

### 自定义布局（UUID v8）

UUID v8 为应用自定义布局保留。

如果你想控制 UUID 内部的位布局，可以使用 `v8` 方法来构造一个 UUID v8：

```java
UUID uuid = UUIDs.v8(114515L, 1919810L);
```

## 解析与格式化

`UUID.toString()` 可以把 UUID 输出为类似 `550e8400-e29b-41d4-a716-446655440000` 的标准文本形式，
而 `UUID.fromString(String)` 则可以解析这种标准文本形式。

但现实中 UUID 也有字符串表示方式，所以 UUID Tools 提供了更灵活的解析和格式化方法，支持多种常见的文本格式。

| 格式 | 输出方法 | 解析方法 | 示例 |
|------|----------|----------|------|
| Standard | `UUID.toString()` | `UUIDs.parse(String)` | `550e8400-e29b-41d4-a716-446655440000` |
| Compact | `UUIDs.toCompactString(UUID)` | `UUIDs.parse(String)` | `550e8400e29b41d4a716446655440000` |
| Windows registry | / | `UUIDs.parse(String)` | `{550e8400-e29b-41d4-a716-446655440000}` |
| URN | `UUIDs.toURNString(UUID)` | `UUIDs.parse(String)` | `urn:uuid:550e8400-e29b-41d4-a716-446655440000` |
| Base62 | `UUIDs.toBase62String(UUID)` | `UUIDs.parseBase62(String)` | `2aUyqjCzEIiEcYMKj7TZtw` |

## 二进制转换

很多协议和数据库存储 UUID 的 16 字节形式，而不是一个字符串。

UUID Tools 支持把 UUID 转换为 `byte[]`，以及从 `byte[]` 解析 UUID：

```java
UUID uuid = UUIDs.generateV7();

byte[] bytes = UUIDs.toBytes(uuid);
UUID decoded = UUIDs.fromBytes(bytes);
```

## 正确比较 UUID

`java.util.UUID` 实现了 `Comparable<UUID>`，但它的 `compareTo` 按两个 `long` 字段做有符号比较，这会导致一些不符合直觉的排序结果。

UUID Tools 提供了 `UUIDs.compare(UUID, UUID)` 和 `UUIDs.comparator()`，按无符号 128 位整数比较：

```java
Instant now = Instant.now();
UUID uuid1 = UUIDs.v7(now, 0, 0L);
UUID uuid2 = UUIDs.v7(now.plusSeconds(1L), 0, 0L);

assert UUIDs.compare(uuid1, uuid2) < 0;

TreeSet<UUID> ordered = new TreeSet<>(UUIDs.comparator());
ordered.add(uuid2);
ordered.add(uuid1);
```

## 字段访问

除了 JDK 已有的 `version()` 和 `variant()`，UUID Tools 还提供了一些常用访问器。

比如你可以这样从时间相关的 UUID（v1/v2/v6/v7）中提取时间戳：

```java
UUID uuid = UUIDs.generateV7();

boolean timeBased = UUIDs.isTimeBased(uuid);
Instant instant = UUIDs.getInstant(uuid);
long epochMillis = UUIDs.getUnixTimestampMillis(uuid);
long gregorianTimestamp = UUIDs.getGregorianTimestamp(uuid);
```

## UUID v1 与 v6 互相转换

UUID v6 和 UUID v1 都是基于时间戳和 MAC 地址的 UUID，只是 UUID v6 对位布局进行了优化，使得它在排序时能够按照时间戳顺序排序。

UUID Tools 提供了 `UUIDs.convertV1ToV6(UUID)` 和 `UUIDs.convertV6ToV1(UUID)` 来实现它们之间的互相转换：

```java
UUID v1 = UUIDs.generateV1();
UUID v6 = UUIDs.convertV1ToV6(v1);
UUID v1Again = UUIDs.convertV6ToV1(v6);

assert v1.equals(v1Again);
```

## 为什么不用 UUID Creator？

[UUID Creator](https://github.com/f4b6a3/uuid-creator) 是 Java 生态中另一个流行的 UUID 库，它也支持生成多种版本的 UUID，并且提供了丰富的功能。

但是我对它的一部分细节不是特别满意：

1. UUID Creator 的 `UuidCreator` API 较为臃肿和繁杂，也使得 JAR 体积较大（约为 UUID Tools 的十倍）；
2. UUID Creator 的 `GUID` API 更现代化，更简洁，但是功能有所缺失，对生成 UUID 时的控制不够灵活，而且我对部分方法的命名也不太满意。

所以我参考了它的 `GUID` API，优化了 API 设计，添加了更丰富的功能，创建了更轻量级的 UUID Tools 库。
