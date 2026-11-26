# 第三方许可

本项目（夜航船，`/Users/a138/Desktop/夜航船`）以 GNU GPL v3 分发，见根目录 [LICENSE](LICENSE)。
以下第三方材料保留其原版权与适用许可。

## Aminark/legado-ios（LegadoCore）

- 项目：<https://github.com/Aminark/legado-ios>
- 许可：GNU GPL v3，完整文本见 [LICENSES/Aminark-legado-ios-LICENSE.txt](LICENSES/Aminark-legado-ios-LICENSE.txt)
- 引入位置：`Packages/LegadoCore/Sources/LegadoCore/`（58 个 Swift 文件）
- 引入版本：`v0.1.16`（2026-11-23），浅克隆自 `main` 分支
- 内容：Legado（开源阅读）3.0 书源格式的 Swift 实现，含规则引擎（CSS / JSONPath / 正则 / JavaScriptCore）、
  书源导入、HTTP 传输、搜索、详情、目录、正文加载。
- 版权归 Aminark 及其贡献者。本仓库未修改其算法实现；如需追溯上游改动，见其仓库 CHANGELOG 与 Git 历史。
- 上游自身声明：不提供、不内置、不分发任何网络书源；书源由用户自行提供。

## SwiftSoup

- 项目：<https://github.com/scinfu/SwiftSoup>，固定版本 `2.13.5`
- 用途：HTML 解析与 CSS 选择器
- 许可：MIT，完整版权及许可见 [LICENSES/SwiftSoup-LICENSE.txt](LICENSES/SwiftSoup-LICENSE.txt)

## Kanna

- 项目：<https://github.com/tid-kijyun/Kanna>，固定版本 `6.1.0`
- 用途：XPath 解析（Legado 规则里的 `@XPath:`）
- 许可：MIT，完整版权及许可见 [LICENSES/Kanna-LICENSE.txt](LICENSES/Kanna-LICENSE.txt)

## ZIPFoundation

- 项目：<https://github.com/weichsel/ZIPFoundation>，固定版本 `0.9.20`
- 用途：EPUB ZIP 容器读取（LegadoCore 的 LocalBook 模块使用）
- 许可：MIT，完整版权及许可见 [LICENSES/ZIPFoundation-LICENSE.txt](LICENSES/ZIPFoundation-LICENSE.txt)

## 系统框架

LegadoCore 另外链接 `JavaScriptCore`、`CryptoKit`、`sqlite3`、`Network`、`Security`、`Vision`、`ImageIO`、`CommonCrypto`，
均为 Apple 系统框架，不涉及单独分发许可。

## 关于应用分发

LegadoCore 通过 `JavaScriptCore` 执行书源里的 JS 规则。按 App Store 审核指南 2.5.2，
下载并执行会改变 App 功能的代码需符合相应限制；本项目定位为 TestFlight / 自签，不作为 App Store 发行。
