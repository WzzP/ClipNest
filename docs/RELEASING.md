# 发布 ClipNest

版本由仓库根目录 `VERSION` 管理，当前为 `0.1.1`，对应 Git tag `v0.1.1`。Release 是否标记为正式版，与是否通过 Apple 签名/公证是两个不同维度；未公证包必须明确披露。

## 1. 发布前验证

```sh
./scripts/test.sh
./scripts/test-sandbox.sh
```

还应在实际使用的 Mac 上检查安装、首次打开、读取剪贴板、输入法搜索、重启恢复、自动粘贴、登录启动。通用二进制不等于两个架构都做过实机验证。

不要将历史数据、证书、私钥、应用专用密码或公证凭据提交到仓库。

默认构建已启用 App Sandbox；应用与 ZIP 名称仍为 ClipNest。发布前核对包内沙盒权限及数据迁移说明。

## 2. 当前可用：无 Developer ID 的发布包

无需 Apple Developer Program 即可生成：

```sh
./scripts/package-release.sh local
```

输出：

```text
.build/releases/0.1.1/local/
├── ClipNest.app
├── ClipNest-0.1.1-universal-unsigned.zip
└── SHA256SUMS.txt
```

名称中的 `unsigned` 指没有 Developer ID 发布签名；二进制仍包含 Apple Silicon 本地运行所需的 ad-hoc 签名。该包没有 Apple 公证票据，首次打开可能被 Gatekeeper 拦截。

仅向用户提供 [Apple 官方的逐应用打开说明](https://support.apple.com/guide/mac-help/mh40616/mac)，不要要求关闭 Gatekeeper 或系统完整性保护。受管理设备可能禁止打开未认证开发者的软件。

## 3. 后续：Developer ID 签名与公证

### 证书准备

加入 Apple Developer Program 后，通过 Xcode → Settings → Accounts → Manage Certificates，或开发者账户的证书页面创建 **Developer ID Application** 证书。需与相应私钥一起安装在本机钥匙串。已有团队的证书也可由有权限的成员导出后导入。

检查可用身份：

```sh
security find-identity -v -p codesigning
```

Apple Development、Apple Distribution、Mac App Distribution 与 Developer ID Application 用途不同；这里需要 **Developer ID Application**。

### 公证凭据准备

在自己的终端交互式保存公证凭据，不要把密码发到聊天或提交到脚本：

```sh
xcrun notarytool store-credentials ClipNest-Notary
```

按提示配置开发者账户、Team ID 和应用专用密码。也可按 [Apple 公证文档](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)配置 App Store Connect API 凭据。

### 一次执行签名、公证与打包

```sh
CLIPNEST_SIGN_IDENTITY="Developer ID Application: 你的名称 (TEAMID)" \
CLIPNEST_NOTARY_PROFILE="ClipNest-Notary" \
./scripts/package-release.sh notarized
```

脚本按以下顺序执行：

1. 分别构建 arm64、x86_64，合并为 Universal 二进制。
2. 使用 Developer ID Application 签名，开启 Hardened Runtime 并添加安全时间戳。
3. 上传 ZIP 到 Apple 公证服务，等待 `Accepted`。
4. 将公证票据附加到 `.app`，验证票据、代码签名和 Gatekeeper。
5. 重新打包最终 ZIP，并生成 SHA-256 校验值。

结果位于 `.build/releases/0.1.1/notarized/`。只上传最终 `ClipNest-0.1.1-universal.zip` 与 `SHA256SUMS.txt`；不要上传中间的 `notary-upload.zip` 或公证日志。签名、公证任何一步失败，脚本都会停止。

## 4. 创建 GitHub Release

确认构建对应的源码已经提交并推送，再创建 tag：

```sh
git tag -a v0.1.1 -m "ClipNest 0.1.1"
git push origin v0.1.1
```

在 GitHub 仓库 **Releases → Draft a new release** 中：

- 选择 `v0.1.1`，标题使用 `ClipNest 0.1.1`。
- 说明使用 `docs/releases/v0.1.1.md`。
- 上传 ZIP 与 `SHA256SUMS.txt`。
- 作为正式 0.1.1 版本发布时，不勾选 Pre-release。
- 如果将来上传已公证包，先同步修改 Release 说明中的签名状态和文件名。

若已安装并登录 GitHub CLI，也可以创建草稿：

```sh
gh release create v0.1.1 \
  .build/releases/0.1.1/local/ClipNest-0.1.1-universal-unsigned.zip \
  .build/releases/0.1.1/local/SHA256SUMS.txt \
  --repo WzzP/ClipNest --verify-tag --draft \
  --title "ClipNest 0.1.1" --notes-file docs/releases/v0.1.1.md
```

草稿核对后再点击 Publish release。不要覆盖已发布 tag；后续修复使用新版本号。
