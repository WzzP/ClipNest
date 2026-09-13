# Mac App Store 上架检查

检查日期：2026-09-13。基线：`6ca7f02`（0.1.0）。

结论：当前 GitHub 发布包不能直接提交 Mac App Store。应先制作独立沙盒构建，验证自动粘贴和文件历史，再准备商店发行。中美区上架不是两套代码的问题；沙盒适配是主要技术门槛。

本次检查包括源代码、构建脚本和本地 0.1.0 发布产物的签名权限；未运行沙盒版、未上传 App Store Connect，也不代表 Apple 审核结论。没有修改应用行为或历史数据。

## 已确认的缺项

| 优先级 | 项目 | 代码证据及处理 |
| --- | --- | --- |
| P0 | 未启用 App Sandbox | `scripts/build-app.sh:49–55` 签名没有 entitlements；本地产物 `codesign -d --entitlements :-` 未输出权限。新增商店构建配置与最小沙盒权限，验证最终产物。Apple 审核规则 2.4.5(i) 要求沙盒。[审核指南](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility) |
| P0 | 没有商店签名与提交流程 | 当前脚本支持 ad-hoc 或 Developer ID Application，并输出 ZIP。后者用于商店外发行，不能直接充当商店提交流程。需要开发者会员、注册 Bundle ID、商店分发签名及适用的 provisioning profile，使用 Xcode 分发流程验证并上传。不能把现有公证流程当作商店审核。 |
| P1 | 隐私政策缺失 | 源码设置页面没有政策入口，仓库没有政策文档。需要公开政策 URL、应用内入口，并准确说明记录内容、用途、本地保存、暂停及删除方式。规则 5.1.1(i) 要求应用内和商店元数据均提供政策链接。[审核指南](https://developer.apple.com/app-store/review/guidelines/#privacy) |
| P1 | 缺少隐私清单 | `HistoryStore.swift:59–75` 使用 UserDefaults 保存自身设置；没有 `PrivacyInfo.xcprivacy`。应声明对应 API 类别，当前自身设置用途匹配 CA92.1，并确保清单进入最终包。[UserDefaults 文档](https://developer.apple.com/documentation/foundation/userdefaults)、[允许的理由](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype) |
| P1 | 商店元数据未准备 | 生成的 Info.plist 没有 `LSApplicationCategoryType`；需要准备类别、介绍、截图、支持及隐私 URL、年龄分级和审核说明。当前 Bundle ID `com.clipnest.app` 尚未在开发者账户验证可注册性。 |

## 必须先验证的功能风险

### 自动粘贴：最高优先级

`AppDelegate.swift:110–143` 检查 `AXIsProcessTrusted()`，切回目标应用，再通过 `CGEvent.post(.cghidEventTap)` 模拟 ⌘V。Apple 将辅助应用使用 Accessibility API 列为沙盒不兼容活动；因此不能把当前授权成功视为沙盒版也能工作。[App Sandbox 限制](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)

这里没有实测沙盒下的具体 CGEvent 路径，不能仅凭文档把整个产品判定为无法上架。先用最小沙盒原型验证授权前后、重启后、多个目标应用中的行为，并确认实现符合公开 API 和审核要求。如果无法保留，商店版先采用“复制后用户按 ⌘V”，明确呈现交互差异；不要依赖关闭沙盒或外置绕过限制的辅助程序。

### 文件历史：路径持久化不等于权限持久化

`HistoryStore.swift:20、166、284` 仅保存文件 URL，再通过 fileExists 检查并写回剪贴板，没有 security-scoped bookmark。沙盒内重启后能否访问原文件、接收应用能否读取，需要单独验证。Apple 为跨启动文件访问提供安全作用域书签及成对的访问开始/结束调用。[沙盒文件访问](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)

需验证 Finder 复制文件时获得的实际访问能力；合法取得权限后保存书签，处理过期书签、撤销权限及原文件移动。不能假定把任意 URL 转成书签就自动获得访问权。

### 旧历史迁移

`HistoryStore.swift:72` 使用系统 Application Support URL；沙盒后它会指向容器内位置。当前文本和图片可继续采用容器内存储，但不能假定直接读取商店外版本的旧目录。应提供用户选择的导入流程或经验证的迁移方式；测试导入后两次重启，确认元数据与附件均保留。[沙盒数据目录](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)

### 记录告知与删除语义

`AppDelegate.swift:24` 启动即监听。建议首次启动明确说明后台记录和本地保存，再让用户开始记录。已有暂停和排除应用设置。`HistoryStore.swift:274` 的清空保留收藏，因此政策不能把它描述成“删除全部数据”；应明确说明并提供易发现的完整删除入口。

源码检查没有发现剪贴板上传或分析 SDK；商店隐私问卷仍需按最终构建实际行为填写，不能用“纯本地”代替政策与清单。

## 可沿用，但仍需沙盒回归

- `LoginItemSettings.swift` 使用 SMAppService，由用户切换后注册；保留此方式，验证注册、撤销和登录后的表现。
- 文本、图片历史使用本地 JSON 和图片附件，迁入容器后验证读写与清理。
- 搜索、收藏、底部面板和快捷键没有在本次静态检查中发现明确上架阻断项；验证焦点、中文输入法、全屏、多屏和滚动行为。
- 当前界面主要是中文，建议补英文界面和美区介绍；不能仅因此认定无法在美区上架。

## 中国大陆与美国

同一 app 可配置不同销售地区；地区设置不消除各地材料要求。Apple 对中国大陆说明部分 app 需要 ICP 备案等材料。本次没有证实此纯本地 macOS 工具的具体适用情况，不能承诺免备案，也不能断言一定需要。建立 macOS 商店记录后，结合 App Store Connect 实际要求向 Apple 确认。[地区资料要求](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)

## 建议执行顺序

1. 独立沙盒原型：先验证自动粘贴、文件访问及重启，决定商店版交互边界。
2. 完成容器迁移、隐私说明和清单、必要的中英本地化。
3. 加入开发者计划，注册标识并完成商店签名、上传验证和测试分发。
4. 用测试数据完成全流程回归，准备中美区材料，再提交审核。

现有非沙盒集成测试通过不代表商店兼容；本次未重跑这些测试，因为没有修改运行代码，它们也无法验证上述沙盒限制。
