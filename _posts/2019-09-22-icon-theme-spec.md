---
title: (翻译) freedesktop.org 图标主题规范
date: 2019-09-22 16:00:00
tags:
- freedesktop.org
categories: 文档翻译
description: 图标主题是一组拥有共同观感的图标。用户可以选择希望使用的主题，并让所有应用使用该主题内的图标
---
原文：[freedesktop.org Icon Theme Specification](https://standards.freedesktop.org/icon-theme-spec/icon-theme-spec-latest.html#)



## 概述

图标主题是一组拥有共同观感的图标。用户可以选择希望使用的主题，并让所有应用使用该主题内的图标。图标主题最开始是桌面文件规范中的 `icon` 字段，不过未来它可以有其他的用处（例如 mimetype 图标）。

对于开发者来说，图标主题只是一个映射。给定一组用于查找图标的目录和一个主题名称，它能够从图标名称及大小映射至对应的图标文件。



## 定义

*  **图标主题**

  图标主题是一组被命名的图标，它用于从图标名以及大小映射到图标文件。一个图标主题可以通过继承自另一个主题拓展它。

* **图标文件**

  图标文件是可以被加载作为图标使用的图像文件，目前支持的文件格式有 PNG、XPM 以及 SVG。PNG 是位图文件的推荐格式，而 SVG 为矢量图标。XPM 格式仅为了向后兼容，不建议新主题采用 XPM 格式。对 SVG 格式的支持是可选的。

* **基目录**

  图标和主题会在一组名为基目录的目录中搜索，主题会存储在基目录的子目录中。

* **图标比例系数**

  通常在高 dpi 屏幕上会缩放界面避免 UI 太小难以辨识。为了支持缩放，图标可以拥有一个目标比例系数，用以描述设计上的比例因子。

  For instance, an icon with a directory size of 48 but scale 2x would be 96x96 pixels, but designed to have the same level of detail as a 48x48 icon at scale 1x. This can be used on high density displays where a 48x48 icon would be too small (or ugly upscaled) and a normal 96x96 icon would have a lot of detail that is hard to see.



## 目录布局

图标和主题会在一组目录（基目录）下被查找。默认情况下，应用会在 `$HOME/.icons` （为了向后兼容）、`$XDG_DATA_DIRS/icons` 和 `/usr/share/pixmaps` 中查找（按照列出的顺序），应用可以自己扩展或更改列表。主题作为子目录存储在这些目录中，同时一个主题可以通过子目录名相同分布在多个多个基目录下，由此用户可以扩展或覆盖系统主题。

为了有一个位置安装第三方应用的图标，一个名为 hicolor [^1]的主题应该总是存在，可以从[该处](http://www.freedesktop.org/software/icon-theme/)下载有关 hicolor 主题的数据。实现需要在当无法在当前主题查找到某个图标时到 hicolor 主题中去寻找。

每个主题都存储为基目录的子目录。主题的内部名称为子目录的名称，但主题指定的用户可见名称可能不同。主题名称区分大小写，要求由 ASCII 字符构成，并不能包含逗号或空格。

主题的所有目录中至少有一个要包含名为 `index.theme` 的主题描述文件，当存在多个描述文件时，选择按顺序搜索基目录时第一个查找到的文件。该文件描述了主题的常规属性。

在主题目录中还有一组包含图像文件的子目录，每个目录都包含 `index.theme`  所描述的针对某些图标大小和比例所设计的图标。子目录允许深入几个级别，例如主题 hicolor 的子目录 `48x48/apps` 具体路径类似 `$basedir/hicolor/48x48/apps`。

图标文件类型必须为 PNG、XPM 或者 SVG，扩展名必须是 `.png`、`.xpm` 或者 `.svg` （小写）。对 SVG 格式的支持是可选的，不支持 SVG 的实现应该忽略所有 `.svg` 文件。除此之外，每个图标文件都可能附带一个包含额外图像数据的附加文件，文件名应与对应的图标文件相同，扩展名应为 `.icon`，例如文件名为 `mime_source_c.png` 的图标文件对应的附加文件名应为 `mime_source_c.icon`。



## 文件格式

如桌面文件规范中所述，图标主题描述文件和图标数据文件都是 ini 格式的文本文件。它们不包含编码字段，始终以 UTF-8 编码存储。

`index.theme` 文件必须以名为 *Icon Theme* 的部分开头，其内容参见表1，所有列表均以逗号分隔。

表1. 标准键

| 键                | 描述                                                         | 值类型       | 必要 |
| ----------------- | ------------------------------------------------------------ | ------------ | ---- |
| Name              | 图标主题的短名称，used in e.g. lists when selecting themes.  | localestring | YES  |
| Comment           | 主题的较长描述                                               | localestring | YES  |
| Inherits          | 继承的主题。当图标在主题中查找不到时会继续在该主题中寻找（并在所有继承的主题中递归寻找）。若未指定主题，实现需要将 hicolor 添加至继承树。实现可以选择将其他默认主题添加至最后描述的主题与 hicolor 之间。 | strings      | NO   |
| Directories       | 主题的子目录。每一个子目录都需要在 `index.theme` 中有对应的描述部分。 | strings      | YES  |
| ScaledDirectories | 除 `Directories` 列出的目录外的其他子目录。These directories should only be read by implementations supporting scaled directories and was added to keep compatibility with old implementations that don't support these. | strings      | NO   |
| Hidden            | 是否在用户选择主题界面中隐藏该主题。这用于 fallback 主题等应对用户隐藏的主题。 | boolean      | NO   |
| Example           | 一个图标的名称，用作展示该主题观感的例子。                   | string       | NO   |



`Directories` 中指定的每一个子目录都应该有一个与目录名相同的对应部分，这些部分的内容在下面表2中列出。

表2. 每个目录键

| 键        | 描述 | 值类型  | 必要 | 类型      |
| --------- | ---- | ------- | ---- | --------- |
| Size      |      | integer | YES  |           |
| Scale     |      | integer | NO   |           |
| Context   |      | string  | NO   |           |
| Type      |      | string  | NO   |           |
| MaxSize   |      | integer | NO   | Scalable  |
| MinSize   |      | integer | NO   | Scalable  |
| Threshold |      | integer | NO   | Threshold |



[^1]: 选择该名称是为了和 KDE 旧的默认主题兼容

