#!/bin/bash

cd "$(dirname $0)/.."

_date=$(date '+%F')
_time=$(date '+%F %H:%M:%S')
_file_name="./_drafts/$_date-$1.md"

echo "Create file: $_file_name"

echo "---
title: '$1'
date: $_time
tags:
  - 
categories: blog
---
" > $_file_name
