# ClipNest · 剪贴巢

面向个人使用的原生 macOS 剪贴板管理工具。使用 Swift、SwiftUI 和 AppKit，数据计划仅保存在本机。

## 当前状态

已建立 Swift Package 和菜单栏应用入口。当前只是可编译的应用骨架，尚未读取或保存剪贴板。

## 第一版范围

- 文本剪贴板历史、去重和本地持久化
- 历史搜索、再次复制、删除及清空
- 保存数量上限、暂停记录
- 全局快捷键唤出历史面板
- 随后增加图片记录和收藏

后续探索底部卡片面板、分组和自动粘贴。自动粘贴需按实际实现申请系统授权。记录逻辑应尊重敏感剪贴板标记，并支持排除应用。

## 开发

最低系统目标：macOS 14。当前项目使用 Swift Package Manager，可用命令行工具构建，也可以用 Xcode 打开 Package.swift。

```sh
swift build
swift run ClipNest
```

当前命令运行的是开发用可执行程序；标准 .app 打包、应用图标及分发设置后续添加。本机开发无需付费 Apple Developer Program 会员。
