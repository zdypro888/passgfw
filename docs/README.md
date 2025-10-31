# PassGFW 文档索引

本目录包含 PassGFW 项目的所有文档。

---

## 📚 用户文档

### 核心文档

- **[安全性与权限说明](./SECURITY_AND_PERMISSIONS.md)** - 详细的权限需求、安全特性和最佳实践
- **[v2.0 升级指南](./UPGRADE_GUIDE_V2.md)** - 从 v1.0 升级到 v2.0 的完整指南
- **[URL 列表格式示例](./list_format_examples.md)** - 动态 URL 列表的格式说明

### 平台文档

- **[iOS/macOS 使用指南](../clients/ios-macos/README.md)**
- **[Android 使用指南](../clients/android/README.md)**
- **[HarmonyOS 使用指南](../clients/harmony/README.md)**
- **[测试指南](../clients/TESTING_GUIDE.md)**

### 服务器文档

- **[服务器部署指南](../server/README.md)**

---

## 🔧 开发文档

### 技术文档（开发者参考）

- **[存储系统分析报告](./dev/STORAGE_ANALYSIS.md)** - 详细的技术分析
- **[改进总结](./dev/IMPROVEMENTS_SUMMARY.md)** - v2.0 改进详情

---

## 🗂️ 文档分类

### 按主题分类

| 主题 | 文档 | 说明 |
|------|------|------|
| **安全** | SECURITY_AND_PERMISSIONS.md | 权限、加密、最佳实践 |
| **升级** | UPGRADE_GUIDE_V2.md | v1.0 → v2.0 升级步骤 |
| **格式** | list_format_examples.md | URL 列表格式 |
| **测试** | clients/TESTING_GUIDE.md | 测试指南 |
| **开发** | dev/*.md | 技术分析和开发记录 |

### 按平台分类

| 平台 | 文档位置 |
|------|---------|
| iOS/macOS | clients/ios-macos/README.md |
| Android | clients/android/README.md |
| HarmonyOS | clients/harmony/README.md |
| Server | server/README.md |

---

## 📖 快速导航

### 新用户

1. 阅读 [主 README](../README.md) 了解项目概述
2. 查看 [平台文档](#平台文档) 选择你的平台
3. 参考 [安全说明](./SECURITY_AND_PERMISSIONS.md) 了解权限需求

### 升级用户

1. 查看 [升级指南](./UPGRADE_GUIDE_V2.md)
2. 了解 [安全改进](./SECURITY_AND_PERMISSIONS.md)
3. 参考平台文档的变更说明

### 开发者

1. 阅读 [存储系统分析](./dev/STORAGE_ANALYSIS.md) 了解技术细节
2. 查看 [改进总结](./dev/IMPROVEMENTS_SUMMARY.md) 了解变更
3. 参考各平台源码

---

## 📝 文档维护

- 文档采用 Markdown 格式
- 所有用户文档放在 `docs/` 目录
- 开发文档放在 `docs/dev/` 目录
- 保持文档与代码同步更新

---

**最后更新**: 2025-11-01
**维护者**: PassGFW Team
