---
categories:
  - Java
date: "2019-12-30"
description: ""
# slug: 
tags:
  - Java
  - Async
categories:
  - java
title: Java中的异步Http请求：HttpClient分析与使用优化事项
draft: false
---

JDK11提供的HttpClient是一个很好的异步Http请求工具。有了它，我们可以像其他拥有协程语言一样，以少量线程，完成更多并发请求，但是如何才能更好的、正确的利用线程资源呢？（本篇皆以OpenJDK11为基础。）
<!--more-->
## 一、简单使用
```java
var client = HttpClient.newHttpClient();
var request = HttpRequest.newBuilder()
                .uri(URI.create("http://..."))
                .GET()
                .build();
client.sendAsync(request, HttpResponse.BodyHandlers.ofString())
  .thenAccept(System.out::println)
```
但是当我们阅读了HttpClient源码后，会发现这种使用方式，会有很多问题。

## 二、异步相关的核心类
JDK9以后提供的类都已经按照Java Module使用模式进行模块化划分。java.net.http模块中以HttpClient是核心抽象类，他的实现类和相关工具都无法直接调用。

### 1、HttpClientImpl
HttpClient实现类，在读java.net.http源码时，你会发现HttpClientImpl的引用无处不在......
- HttpClient默认构造的线程池是通过Executors.newCachedThreadPool构造的，其线程数最大值为Integer.MAX_VALUE，核心线程数为0。这意味着如果我们 __短时间内发送大量请求时，会创建过多的线程__ ，影响性能。我们应当根据情况适当优化线程池配置。线程池构造源码如下：
  ```java       
  Executor ex = builder.executor;
  if (ex == null) {
      ex = Executors.newCachedThreadPool(new DefaultThreadFactory(id));
      isDefaultExecutor = true;
  } else {
      isDefaultExecutor = false;
  }
  ```         
- 通过上述源码，我们也可以发现，如果我们 __多次构造HttpClient实例__ 时不指定Executor实例，__会重复创建多个线程池实例__。（核心线程数为0）

### 2、SelectorManager
SelectorMangager顾名思义，管理Selector操作，用于事件监听，是HttpClient的Socket管理核心类。
- 继承Thread，且是一个守护线程
- 当HttpClient实例创建完成后，SelectorManager实例便start运行
- 每当HttpClientImpl创建时，便会启动SelectorManager线程，__多HttpClient实例多SelectorManager线程__

<!-- ### 3、DelegatingExecutor
线程池的封装类型
- 当由SelectorManager线程调用execute()方法时，会启用线程池；反之则线性执行。
  ```java
  @Override
  public void execute(Runnable command) {
      if (isInSelectorThread.getAsBoolean()) {
          delegate.execute(command);
      } else {
          command.run();
      }
  }
  ```
  -->
### 3、SocketTube
实现Java9 Flow API中Publisher和Subscriber接口，为HttpClient提供响应式、异步处理Socket事件操作。

## 三、HttpClient线程测试分析

### 测试方式
- HttpClient提供了debug模式，我们可以通过设置参数开启。debug会展示线程名称，线程ID（自增），以及消耗时间。由自增ID我们可以推断大致产生多少线程。
  ```java
  System.setProperty("jdk.internal.httpclient.debug", "true");
  ```
- 由于线程数目差距比较明显，没有使用jvm调试工具，而是运行结束前通过Thread.currentThread().getThreadGroup()获取线程组信息。（并不是运行期间产生的总线程数）
- 服务端提供简单Http接口，__接口需要1秒钟后再写Response__ 。（Thread.sleep）
- 客户端分三种方式，每种方式都是并发100次请求。
  - 每次请求均创建一个HttpClient实例。
  - 共用一个HttpClient，HttpClient使用默认构造方式。
  - 共用一个HttpClient，且共用一个自定义线程池，优化线程池配置。

### 测试代码
```java
public class TestHttpClient {
    private int times;
    private HttpClient client;
    private Supplier<HttpClient> clientSupplier;

    public TestHttpClient(int times, Supplier<HttpClient> client) {
        this.times = times;
        this.clientSupplier = client;
    }

    public TestHttpClient(int times, Optional<Executor> executor) {
        this.times = times;
        this.client = executor.map(ex -> HttpClient.newBuilder().executor(ex).build())
                .orElse(HttpClient.newHttpClient());
    }

    public void start() {
        if (times <= 0 || (clientSupplier == null && client == null)) {
            return;
        }
        if (client != null) {
            this.startWithClient();
        } else {
            this.startWithSupplier();
        }
    }

    private void startWithSupplier() {
        var list = new ArrayList<CompletableFuture<HttpResponse<String>>>();
        for (var i = 0; i < times; i++) {
            list.add(this.get(this.clientSupplier.get(), URL));
        }
        CompletableFuture.allOf(list.toArray(new CompletableFuture[0]))
                .thenAccept(s -> showAllThread(Thread.currentThread())).join();
    }

    private void startWithClient() {
        var list = new ArrayList<CompletableFuture<HttpResponse<String>>>();
        for (var i = 0; i < times; i++) {
            list.add(this.get(this.client, URL));
        }
        CompletableFuture.allOf(list.toArray(new CompletableFuture[0]))
                .thenAccept(s -> showAllThread(Thread.currentThread())).join();
    }

    private CompletableFuture<HttpResponse<String>> get(HttpClient client, String urlString) {
        var req = HttpRequest.newBuilder()
                .uri(URI.create(urlString))
                .GET()
                .build();
        return client.sendAsync(req, HttpResponse.BodyHandlers.ofString());
    }

    private void showAllThread(Thread thread) {
        System.out.println("Current Thread: " + thread.getName() + " active count:" + thread.getThreadGroup().activeCount());
        ThreadGroup currentGroup =
                Thread.currentThread().getThreadGroup();
        int noThreads = currentGroup.activeCount();
        Thread[] lstThreads = new Thread[noThreads];
        currentGroup.enumerate(lstThreads);
        for (int i = 0; i < noThreads; i++)
            System.out.println("i：" + i + " = " + lstThreads[i].getName());
    }
}
```

### 测试分析
#### 测试1：每个请求都创建一个HttpClient
```java
var times = 100;
var defaultClient = new TestHttpClient(times, HttpClient::newHttpClient);
defaultClient.start();
```

```text
...
DEBUG: [HttpClient-100-SelectorManager] [2s 471ms] Http1AsyncReceiver(SocketTube(100)) Http1TubeSubscriber: dropSubscription
...
DEBUG: [HttpClient-100-Worker-2] [2s 500ms] Http1AsyncReceiver(SocketTube(100)) Got 0 bytes for delegate null
...
DEBUG: [HttpClient-81-SelectorManager] [2s 562ms] SocketTube(81) write: starting subscription
DEBUG: [HttpClient-76-Worker-1] [2s 562ms] SocketTube(76) leaving requestMore:  Reading: [ops=1, demand=1, stopped=false], Writing: [ops=0, demand=1]
DEBUG: [HttpClient-81-SelectorManager] [2s 562ms] SocketTube(81) write: offloading requestMore
DEBUG: [HttpClient-9-SelectorManager] [2s 562ms] SocketTube(20) Read scheduler stopped
DEBUG: [HttpClient-9-SelectorManager] [2s 562ms] Http2ClientImpl stopping
DEBUG: [HttpClient-81-Worker-0] [2s 562ms] SocketTube(81) write: requesting more...
DEBUG: [HttpClient-81-Worker-0] [2s 562ms] SocketTube(81) leaving requestMore:  Reading: [ops=1, demand=1, stopped=false], Writing: [ops=0, demand=1]

Current Thread: ForkJoinPool.commonPool-worker-7 active count:329
...
```
分析：由debug日志提供的线程ID数目，可以看出会创建 __100个SelectorManager线程__ ，线程池内线程数也十分多，结束前线程组仍包含了 __329个线程__ ，最终使用 __2s 562ms__。

#### 测试2：100次请求共用一个HttpClient，HttpClient使用默认构造方式。
```java
var defaultClient = new TestHttpClient(times, Optional.empty());
defaultClient.start();
```
```text
...
DEBUG: [HttpClient-1-SelectorManager] [2s 75ms] SocketTube(23) write: offloading requestMore
DEBUG: [HttpClient-1-Worker-18] [2s 75ms] SocketTube(23) write: requesting more...
DEBUG: [HttpClient-1-Worker-18] [2s 75ms] SocketTube(23) leaving requestMore:  Reading: [ops=1, demand=1, stopped=false], Writing: [ops=0, demand=1]
DEBUG: [HttpClient-1-Worker-66] [2s 75ms] SocketTube(50) write: requesting more...
DEBUG: [HttpClient-1-Worker-66] [2s 76ms] SocketTube(50) leaving requestMore:  Reading: [ops=1, demand=1, stopped=false], Writing: [ops=0, demand=1]
...
Current Thread: ForkJoinPool.commonPool-worker-11 active count:98
...
```
仅拥有一个SelectorManager线程，但可以看出线程ID已经自增到了 __80+__ ，结束前线程仍有 __98个__ ，时间消耗了 __2s 76ms__

#### 测试3：优化线程池配置
```java
var executor = new ThreadPoolExecutor(0, 1,
        1, TimeUnit.SECONDS,
        new LinkedBlockingQueue<>());
var customExecutorClient = new TestHttpClient(times, Optional.of(executor);
customExecutorClient.start();
```
这个线程池核心数为0，最大线程池为1，保证程序能够在所有线程工作完成后1s自动退出，且减少创建销毁线程的开销。
```text
...
DEBUG: [pool-1-thread-1] [2s 9ms] SocketTube(99) leaving requestMore:  Reading: [ops=1, demand=1, stopped=false], Writing: [ops=0, demand=1]
DEBUG: [pool-1-thread-1] [2s 9ms] SocketTube(100) write: requesting more...
DEBUG: [pool-1-thread-1] [2s 9ms] SocketTube(100) leaving requestMore:  Reading: [ops=1, demand=1, stopped=false], Writing: [ops=0, demand=1]
DEBUG: [pool-1-thread-1] [2s 9ms] SocketTube(98) write: requesting more...
DEBUG: [pool-1-thread-1] [2s 9ms] SocketTube(98) leaving requestMore:  Reading: [ops=1, demand=1, stopped=false], Writing: [ops=0, demand=1]
Current Thread: ForkJoinPool.commonPool-worker-3 active count:5
i：0 = main
i：1 = Monitor Ctrl-Break
i：2 = HttpClient-1-SelectorManager
i：3 = pool-1-thread-1
i：4 = ForkJoinPool.commonPool-worker-3
```
结束前 __线程数仅为5，耗时仅为2s9ms__ 便完成了100个请求。 （这5个线程并不是在期间总产生数量，而是运行结束前的数量）
这5个线程中包含主线程(Main)，信号检测线程(Monitor Ctrl-Break)，SelectorManager，我们定义的线程池，还有ForkJoinPool的线程（CompletableFuture默认使用，可以看出ID已经增长到了3）。其他使用情况均创建大量线程，且并没有提高并发能力。

## 四、总结
我们使用HttpClient + CompletableFuture，即NIO + 任务调度，同样可以做到其他语言中协程并发请求的效果。但是为了达到更高时间和空间效率，我们应当注意几点：
1. 不要重复创建多余的HttpClient实例
2. 自定义线程池，否则默认提供的线程池会创建大量线程，且线程利用率很低。

由于线程数目差距比较明显，没有使用jvm调试工具，有兴趣的小伙伴可以使用工具，查看具体产生了多少线程。
