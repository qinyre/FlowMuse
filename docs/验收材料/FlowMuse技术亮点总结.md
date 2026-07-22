# FlowMuse 技术亮点总结

> **面向评委的一页纸技术说明**
> **项目定位**：端到端加密的跨平台协同白板应用

---

## 🎯 核心创新点

### 1. 自研 Markdraw 白板内核

**技术亮点**：
- **30,000+ 行核心代码**：完全自主研发，非第三方封装
- **不可变状态 + Result 模式**：天然支持 undo/redo，状态管理清晰
- **Excalidraw 完全兼容**：可导入/导出 .excalidraw 格式，生态互通
- **224 个单元测试**：Repository 层 100% 覆盖，核心模块 80%+ 覆盖

**架构优势**：
```
Element (不可变) → ToolResult (sealed class) → EditorState.applyResult()
```
- 所有编辑操作返回 Result 对象，状态折叠统一处理
- 双序列化格式：.markdraw（人类可读）+ .excalidraw（协作载体）
- 元素内置版本控制：version + versionNonce + fractional index

---

### 2. 零知识端到端加密协作

**隐私保护**：
- **AES-GCM-128 加密**：所有协作内容在本地加密后传输
- **服务端盲转发**：服务端只见密文，永远看不到明文画板内容
- **乐观锁冲突解决**：baseSceneVersion + SHA256 哈希校验

**技术流程**：
```
客户端A → 加密(roomKey) → Socket.IO → 服务端转发(密文) → 客户端B → 解密(roomKey)
```

**安全边界**：
- 协作密钥：本地生成，secure storage 存储
- 服务端职责：房间管理、消息转发、快照存储（密文）
- 隐私保障：即使服务端被攻破，攻击者也无法解密历史内容

---

### 3. 六平台统一代码库

**跨平台能力**：
- **95% 代码复用率**：一份 Dart 代码，6 端一致体验
- **平台差异收敛**：仅在适配层处理平台特性，共享代码禁止 `Platform.is*` 判断

**支持平台**：
| 平台 | 状态 | 特殊适配 |
|------|------|---------|
| Android | ✅ | 标准 Flutter |
| iOS | ✅ | 标准 Flutter |
| macOS | ✅ | 标准 Flutter |
| Windows | ✅ | 标准 Flutter |
| Web | ✅ | 标准 Flutter |
| **HarmonyOS** | ✅ | **7 个原生 Platform Channel** |

---

### 4. 鸿蒙深度适配（7 个原生能力）

#### 4.1 Pen Kit - 手写笔生态
- **压感识别**：`PointerEvent.pressure` 驱动笔迹粗细
- **全局取色器**：`imageFeaturePicker.pickForResult()` 系统级取色
- **OneEuro 滤波**：平滑笔迹，低延迟抗抖动

#### 4.2 Core Speech Kit - 语音识别
- **实时预览**：中间结果仅本地展示，不修改白板
- **生命周期安全**：取消/退后台立即释放麦克风
- **普通话优化**：针对中文场景调优

#### 4.3 PDFKit - 原生 PDF 渲染
- **逐页渲染**：PDF 页面转为图片嵌入白板
- **Platform Channel**：绕过 Flutter PDF 插件限制

#### 4.4 DocumentViewPicker - 文件管理
- **文件选择**：原生文件选择器，替代未适配的 file_picker
- **文件保存**：直存 Downloads 目录，用户可见

#### 4.5 @ohos.net.http - 原生 HTTP
- **绕过限制**：解决 dart:io socket 缺陷
- **手写识别**：HTTP POST 请求服务端识别接口

#### 4.6 FormExtensionAbility - 服务卡片
- **桌面快速入口**：显示最近白板缩略图
- **一键恢复**：点击卡片直达白板编辑

#### 4.7 Network Config - 网络安全
- **Cleartext HTTP**：开发环境允许 HTTP 流量
- **生产环境**：HTTPS 强制加密

**技术架构图**：
```
Flutter Dart 层
    ↓ MethodChannel
ArkTS Platform Channel 层
    ↓ Native API
鸿蒙系统能力 (Pen Kit / Core Speech Kit / PDFKit / ...)
```

---

### 5. AI 驱动的智能笔记

#### 5.1 手写识别
- **自动识别**：手写完成后 1 秒去抖延迟自动调度
- **手动转换**：框选笔迹手动触发，支持 text/shape/formula/drawing
- **服务端识别**：HTTP POST 向 MyScript 发送笔迹数据

#### 5.2 AI 笔记助手
- **受限操作**：仅允许重命名笔记、插入文本、生成思维导图
- **预览确认**：AI 返回动作后先预览，用户确认后才应用
- **OpenAI 兼容**：用户自备模型，支持任意兼容 API
- **隐私友好**：API Key 本地 secure storage，客户端直接调用

#### 5.3 语音转文字
- **跨平台**：Android SpeechRecognizer / 鸿蒙 Core Speech Kit / Web Speech API
- **标准文本**：最终结果创建普通 TextElement，复用撤销/保存/协作

---

## 📊 技术指标

| 指标 | 数值 | 说明 |
|------|------|------|
| **笔迹延迟** | <16ms | 60fps 流畅手写 |
| **协作同步** | <200ms | 局域网 4 设备验证 |
| **代码规模** | 67,846 行 | Dart 代码总量 |
| **核心内核** | 30,000+ 行 | Markdraw 白板内核 |
| **测试覆盖** | 224 个 | 单元测试数量 |
| **文档规模** | 32,000+ 行 | Markdown 文档 |
| **代码复用率** | 95% | 跨 6 平台 |
| **鸿蒙特性** | 7 个 | Platform Channel |

---

## 🏗️ 架构设计

### 前端分层架构
```
展示层 (views/)          - 页面与组件
    ↓
状态层 (view_models/)    - Riverpod Notifier
    ↓
应用层 (app/)            - 路由与主题
    ↓
领域层 (models/)         - 不可变值对象
    ↓
数据层 (repositories/)   - SQLite / HTTP / Socket.IO
```

### 编辑器内核架构
```
EditorState (不可变)
    ↓
Tool (画笔/形状/文本/...)
    ↓
ToolResult (sealed class)
    ↓
applyResult() → 新 EditorState
    ↓
HistoryManager (双栈 undo/redo)
```

### 协作加密流程
```
本地编辑 → Scene 序列化 → AES-GCM 加密 → Socket.IO 发送
                                              ↓
服务端盲转发(密文) → Socket.IO 接收 → AES-GCM 解密 → Scene 合并
```

---

## 🎨 工程质量

### 代码规范
- **Lint 规则**：flutter_lints strict 模式
- **命名约定**：驼峰命名 + Provider 后缀
- **架构约束**：Feature-First 四层架构，documented in `.agent/conventions.md`

### 测试策略
- **单元测试**：Repository 层 100% 覆盖
- **集成测试**：协作同步、AI 助手、语音识别
- **真机验证**：4 设备（鸿蒙平板/手机 + Android + PC）协作压测

### 文档体系
- **79 个 Markdown 文档**：项目说明、技术设计、研发记录、验收材料
- **AGENTS.md**：449 行 AI 协作规范
- **ADR 决策记录**：`.agent/decisions.md` 记录关键架构决策

---

## 🔒 安全边界

| 维度 | 设计 |
|------|------|
| **传输加密** | 协作消息 + 快照全程 AES-GCM-128 |
| **身份认证** | Bearer token，secure storage 存储 |
| **乐观锁** | baseSceneVersion + baseSceneHash，409 触发 reconcile |
| **软删除** | 笔记默认软删除，可恢复 |
| **零知识** | 服务端只见密文，不解密 |

---

## 🚀 差异化竞争优势

### vs Excalidraw
- ✅ **端到端加密**（Excalidraw 无加密）
- ✅ **鸿蒙深度适配**（Excalidraw 不支持鸿蒙）
- ✅ **手写笔压感**（Excalidraw 无压感）
- ✅ **离线优先**（Excalidraw 需联网）

### vs Miro
- ✅ **隐私优先**（Miro 云端明文存储）
- ✅ **自研内核**（Miro 闭源）
- ✅ **跨平台统一**（Miro 移动端功能受限）
- ✅ **开源潜力**（Miro 纯商业）

### vs OneNote
- ✅ **实时协作**（OneNote 刷新同步）
- ✅ **端到端加密**（OneNote 无端到端加密）
- ✅ **自研内核**（OneNote 闭源）
- ✅ **鸿蒙原生**（OneNote 基础适配）

---

## 📈 社会价值

### 教育赋能
- 远程授课：教师平板手写，学生实时跟进
- 课堂互动：多人协作标注，提升参与度
- 公式推导：手写识别转 LaTeX，可编辑可导出

### 隐私保护
- 端到端加密：保护知识产权和敏感数据
- 零知识协作：服务端无法窃取用户内容
- 本地优先：离线可用，数据自主可控

### 技术开源
- 32,000 行文档：贡献社区最佳实践
- Platform Channel 参考：鸿蒙适配范例
- Markdraw 内核：可剥离为独立库开源

---

## 🎯 竞赛评分对照

| 评分维度 | 满分 | 对应亮点 |
|---------|------|---------|
| **创新性** | 50 | 自研内核 + 零知识加密 + 鸿蒙深度适配 |
| **完备度** | 20 | 224 测试 + 6 平台验证 + Docker 部署 |
| **前景评估** | 20 | 教育场景刚需 + 隐私差异化 + 生态贡献 |
| **规范性** | 10 | 79 文档 + Lint strict + ADR 记录 |
| **附加分** | 20 | 7 鸿蒙特性 + AI 融合 + 社会价值 |

---

**项目地址**：[待补充]
**演示视频**：[待补充]
**联系方式**：[待补充]
