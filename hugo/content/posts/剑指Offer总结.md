---
categories:
  - Java
date: "2012-04-06"
description: ""
# slug: 
tags:
  - Java
  - Async
categories:
  - java
title: Java中的异步Http请求：HttpClient分析与使用优化事项
draft: true
---

JDK11提供的HttpClient是一个很好的异步Http请求工具。有了它，我们可以像其他拥有协程语言一样，以少量线程，完成更多并发请求，但是如何才能更好的、正确的利用线程资源呢？（本篇皆以OpenJDK11为基础。）
<!--more-->