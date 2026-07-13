---
title: 'Gradle Wrapper Neo: 更好的 Gradle Wrapper'
date: 2026-07-14 05:00:00 +0800
tags:
  - JVM
categories: blog
description: 'Gradle Wrapper Neo 简介'
---

# Gradle Wrapper Neo: 更好的 Gradle Wrapper

在 Gradle 生态中，Gradle Wrapper 早已是不可或缺的工具，现在几乎所有 Gradle 项目都会附带 Gradle Wrapper。

但是，Gradle Wrapper 有两个明显的缺陷让我很不满意：

1. Gradle Wrapper 需要在项目中嵌入一个 `gradle-wrapper.jar` 二进制文件，并提交到 Git 仓库中。
   在项目中管理二进制文件违反了很多最佳实践，也会让项目体积膨胀（虽然通常影响不大）。

2. Gradle Wrapper 在中国大陆下载 Gradle 速度非常缓慢。尤其是 Java 默认不走系统代理，导致 Gradle Wrapper 下载十几分钟甚至下载失败的情况时有发生。

   更难绷的是，Gradle Wrapper 下载 Gradle 的缓存路径是根据 `gradle-wrapper.properties` 中的 `distributionUrl` 来决定的，
   只要 `distributionUrl` 变化就会导致 Gradle Wrapper 重新下载 Gradle，无法使用缓存。
   
   所以 `distributionUrl` 为 `https://services.gradle.org/distributions/gradle-9.6.1-bin.zip` 的项目和
   `distributionUrl` 为 `https://mirrors.cloud.tencent.com/gradle/gradle-9.6.1-bin.zip` 的项目无法共享 Gradle 缓存，
   不能临时把项目中 的 `distributionUrl` 改为国内镜像来改善下载速度，下载完再改回去。

为了解决这个问题，我开发了一个项目：[Gradle Wrapper Neo](https://github.com/Glavo/gradle-wrapper-neo)。

这个项目是 Gradle Wrapper 的直接替代品。
只需要把项目中的 `gradlew`、`gradlew.bat` 替换为 Gradle Wrapper Neo 的版本，
并把 `gradle/wrapper/gradle-wrapper.jar` 替换为 Gradle Wrapper Neo 的 `GradleWrapperNeo.java`，
就可以完成替换。

Gradle Wrapper Neo 把所有功能打包成单个 Java 源文件 `GradleWrapperNeo.java`，在执行 `gradlew` 的时候才编译成 jar 并缓存到项目的 `.gradle` 目录下，
所以只需要在项目中提交一个 Java 源文件，而不再需要提交二进制文件。


Gradle Wrapper Neo 还支持了 Gradle 镜像源，允许把特定的 `distributionUrl` 替换成镜像源的 URL，
并且不改变缓存路径，这样就可以在中国大陆快速下载 Gradle，还能和常规的 Gradle Wrapper 共享缓存。

Gradle Wrapper Neo 的配置文件路径为 `$GRADLE_USER_HOME/gradle-wrapper-neo.json`，你可以创建这样的 JSON 文件来使用腾讯云的 Gradle 镜像：

```json
{
  "version": 1,
  "mirrors": [
    {
      "pattern": "^https://services\\.gradle\\.org/distributions/(.+)$",
      "replacement": "https://mirrors.cloud.tencent.com/gradle/$1",
      "requireChecksum": false
    }
  ]
}
```

想快速创建这样的文件可以把以下 Shell 命令复制到终端并执行：

Linux/macOS/FreeBSD (Bash):

```bash
gradle_user_home=${GRADLE_USER_HOME:-"$HOME/.gradle"}
config_file=$gradle_user_home/gradle-wrapper-neo.json

mkdir -p "$gradle_user_home"
cat > "$config_file" <<'EOF'
{
  "version": 1,
  "mirrors": [
    {
      "pattern": "^https://services\\.gradle\\.org/distributions/(.+)$",
      "replacement": "https://mirrors.cloud.tencent.com/gradle/$1",
      "requireChecksum": false
    }
  ]
}
EOF
```

Windows (PowerShell):

```powershell
if ([string]::IsNullOrEmpty($env:GRADLE_USER_HOME)) {
    $gradleUserHome = Join-Path $HOME '.gradle'
} else {
    $gradleUserHome = $env:GRADLE_USER_HOME
}
$configFile = Join-Path $gradleUserHome 'gradle-wrapper-neo.json'

$json = @'
{
  "version": 1,
  "mirrors": [
    {
      "pattern": "^https://services\\.gradle\\.org/distributions/(.+)$",
      "replacement": "https://mirrors.cloud.tencent.com/gradle/$1",
      "requireChecksum": false
    }
  ]
}
'@

New-Item -ItemType Directory -Force -Path $gradleUserHome | Out-Null
$utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($configFile, $json, $utf8WithoutBom)
```

更多使用说明请参考项目 GitHub 仓库: [Glavo/gradle-wrapper-neo](https://github.com/Glavo/gradle-wrapper-neo)。
