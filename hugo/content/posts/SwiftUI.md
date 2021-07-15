---
categories:
  - SwiftUI
  - Swift
date: "2021-07-15"
description: ""
# slug: 
tags:
  - SwiftUI
  - Swift
  - iOS
  - macOS
categories:
  - Java
title: 我的第二个SwiftUI项目——xZip 上线中遇到的问题(一)
draft: false
---
## 一、背景
最近几年有兴趣做独立开发，偶尔会写一些简单的App上架到App Store，恰巧19年时Apple发布了SwiftUI框架，便开始以新框架为主进行开发了。  
个人使用时遇到了一些问题，其中不得不说SwiftUI尚未成熟。
- iOS13的初期几个小版本，SwiftUI项目运行时都有明显问题，List、Button、NaviationLink等许多地方和预期不一致。
- iOS14中List虽补充了很多功能，但是同样缺少很多API。如：List无法消除分割线、箭头符号，无法定制左滑删除时的Delect文案等等。
- DocumentBased-App许多功能无法定制，如：隐藏创建按钮。  
- iOS13和iOS14中List的样式差距很大，如果用了一些workaround方法，会导致失效或者变得巨丑无比。

第一次用SwiftUI是一个推荐文章、项目的App，主要想试一试，当然做出来的成品也上架了，但是emmmm自己并不懂得运营随后便下架了。  
这次就做一个简单的解压缩软件。目前已经上架（纯免费啦），来记录一下开发到上架过程中遇到的问题。（其中包含一些iOS/macOS小白问题）

## 二、SwiftUI中遇到的问题
### 1. macOS
#### a. 沙盒模式文件权限（小白）
问题：App Store需要开启沙盒模式，文件权限如何获取  
解决方法：
- 解压软件一般是用户主动选择需要解压的文件和解压到的地址，即"App Sandbox"中开启 __User Selected File: Read/Write__
- 选择文件/地址
  - SwiftUI中没有相关组件，需要用AppKit，__NSOpenPanel__
- 拖入文件
  - SwiftUI的 __onDrop__ 函数

#### b. SwiftUI无法灵活改变Window大小
需求：进入某一个视图的时候希望窗口大小大一些。  
问题：SwiftUI可以通过frame(width:heigth:)以及frame(minWidth:idealWidth:...)定义window大小。但是无法通过onAppear等函数动态调整当前窗口大小。  
解决方法：
- onAppear通过NSApplication.shared.windows获取window对象，进而改变大小
```swift
static func getFirstWindowFrame() -> CGRect? {
    let size: CGRect? = NSApplication.shared.windows.first?.frame //多窗口需要修改哦
    return size
}
static func changeFirstWindowFrame(size: CGRect) {
    if let window = NSApplication.shared.windows.first {
        window.setFrame(size, display: true, animate: true)
    } //多窗口需要修改哦
}
```

#### c. SwiftUI Toolbar无法创建icon在上，Text在下的Label
需求：
![toolbar](/images/toolbar1.jpg)  
问题：SwiftUI并不能定制NavigationBar/Toolbar高度。
解决方法：很多macOS内置应用是纯icon或者左右排列icon和文本的Toolbar。所以SwiftUI短时间也不会支持吧。暂时没有很好的解决办法。
- 左右排列icon、文本
- 纯icon + Tooltip
  
#### d. SwiftUI Toolbar无法定制背景颜色
解决办法：SwiftUI并没有提供相关API。

#### e. SwiftUI Toolbar icon太小了
解决办法：
```swift
Image(systemName: imageName)
    .resizable()
    .scaledToFit()
    .imageScale(.large)
```

#### f. 多级嵌套List(children:)中显示高度错误问题。（iOS记得没有这个问题）
解决办法：
```swift
list.listStyle(SidebarListStyle()) // 目前DefaultListStyle等中会出现错位问题。但是SidebarListStyle没问题
```

#### g. 无法代码控制侧边栏的开关
解决办法：
```swift
NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil) // 多窗口的需要注意哦
```
也可以在创建WindowGroup时加一下快捷键
```swift
windowGroup.commands {
    SidebarCommands()
}
```

#### h. 标题栏不好控制。
解决办法：直接去掉吧。太难用。
```swift
windowGroup.windowToolbarStyle(UnifiedCompactWindowToolbarStyle(showsTitle: false)) // 根据情况选择toolbarStyle
                .windowStyle(HiddenTitleBarWindowStyle())
```
#### i. Toolbar样式，关掉侧边栏时不隐藏masterView的Toolbar
解决办法：
```swift
windowGroup.windowToolbarStyle(UnifiedCompactWindowToolbarStyle()
```

#### 结果
![xZip-preview](/images/xZip-preview.jpg)