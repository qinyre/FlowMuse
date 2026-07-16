# 文档受众重组 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `docs/` 重组为教师可直接浏览的项目说明、验收材料、技术设计和研发记录，同时保留 `.agent/` 作为 AI 协作规则入口。

**Architecture:** `docs/` 只保留四个面向人类的一级目录；产品需求和架构约束进入项目说明，完整 Sprint 2 文件夹进入验收材料，应用架构/API/数据模型与专题设计进入技术设计，其余计划、调研、排障、归档和许可证进入研发记录。根 `REQUIREMENTS.md` 仅保留到唯一正文的兼容链接；`AGENTS.md` 和 `.agent/` 改为引用新正文路径。

**Tech Stack:** Git 路径迁移、Markdown 相对链接、PowerShell 文件操作。

## Global Constraints

- 不新增 `docs/README.md`。
- `docs/验收材料/` 必须包含原 `docs/sprint2/` 的全部文件，包括图片、DOCX 和 XLSX。
- `.agent/` 保留为 AI 协作规则入口，不复制产品需求或技术设计正文。
- 不丢弃任何文档内容；迁移后所有 Markdown 内部路径必须可解析。
- 不修改用户已有的生成文件改动或 `requiredoc/`。

---

### Task 1: 创建教师可见的文档骨架并迁移文件

**Files:**
- Create: `docs/项目说明/`, `docs/验收材料/`, `docs/技术设计/`, `docs/研发记录/{plans,specs,research,troubleshooting,archive,third_party}/`
- Move: `REQUIREMENTS.md` → `docs/项目说明/项目需求.md`
- Move: `docs/architecture_constraints.md` → `docs/项目说明/架构约束.md`
- Move: `docs/sprint2/*` → `docs/验收材料/*`
- Move: `FlowMuse-App/docs/{architecture,api,data-model}.md` → `docs/技术设计/{前端架构,接口设计,数据模型}.md`
- Move: 当前 `deployment/`、`design/`、`features/` 文档 → `docs/技术设计/`
- Move: 当前 `research/`、`superpowers/{plans,specs}/`、`troubleshooting/`、`archive/`、`third_party/` → `docs/研发记录/`

- [ ] **Step 1: 创建八个目标目录**

Run: `New-Item -ItemType Directory -Force -Path docs/项目说明,docs/验收材料,docs/技术设计,docs/研发记录/plans,docs/研发记录/specs,docs/研发记录/research,docs/研发记录/troubleshooting,docs/研发记录/archive,docs/研发记录/third_party`

Expected: 所有目标目录存在，且根 `docs/` 不出现数字前缀目录。

- [ ] **Step 2: 显式移动每个正文和目录**

Run: 使用 `Move-Item -LiteralPath` 逐项迁移；`docs/sprint2` 必须整体移动到 `docs/验收材料`，不按文件类型筛选。

Expected: `docs/验收材料` 同时拥有验收要求、质量门禁、安全报告、图片、DOCX 和 XLSX。

- [ ] **Step 3: 确认移动后的文件计数**

Run: `Get-ChildItem -LiteralPath docs/验收材料 -File | Measure-Object`

Expected: 文件数与移动前 `docs/sprint2` 相同。

### Task 2: 重建 AI 路由与兼容入口

**Files:**
- Create: `REQUIREMENTS.md`
- Modify: `AGENTS.md`, `.agent/architecture.md`, `.agent/decisions.md`
- Modify: `docs/项目说明/项目需求.md`, `docs/技术设计/前端架构.md`

- [ ] **Step 1: 写入根需求兼容入口**

Content:

```markdown
# FlowMuse 需求文档

产品需求正文已迁移至 [docs/项目说明/项目需求.md](docs/项目说明/项目需求.md)。
```

Expected: 旧计划中的 `REQUIREMENTS.md` 路径仍可打开，但唯一需求正文在 `docs/项目说明/`。

- [ ] **Step 2: 更新 AI 明确阅读路径**

Replace in `AGENTS.md` and `.agent/architecture.md`:

```text
REQUIREMENTS.md                              -> docs/项目说明/项目需求.md
docs/architecture_constraints.md             -> docs/项目说明/架构约束.md
FlowMuse-App/docs/architecture.md            -> docs/技术设计/前端架构.md
FlowMuse-App/docs/api.md                     -> docs/技术设计/接口设计.md
FlowMuse-App/docs/data-model.md              -> docs/技术设计/数据模型.md
docs/superpowers/plans/*.md                  -> docs/研发记录/plans/*.md
```

Expected: AI 仍按 `AGENTS.md` 找到唯一需求、约束、技术设计与相关计划。

- [ ] **Step 3: 更新文档内部相对引用**

Update `docs/技术设计/前端架构.md` 中的架构约束链接，`docs/技术设计/语音转文字规格.md` 中的需求路径，以及 `.agent/decisions.md` 中迁移审计和协作调研路径。

Expected: 所有这些引用均指向迁移后的目标。

### Task 3: 清理历史引用并验证

**Files:**
- Modify: 所有仍含旧 `docs/sprint2`、`docs/superpowers`、`docs/research`、`docs/third_party`、`docs/probe-to-main-migration-audit.md` 路径的 Markdown 文档

- [ ] **Step 1: 扫描旧路径**

Run: `rg -n --glob '*.md' 'docs/(sprint2|superpowers|research|third_party|archive|troubleshooting|deployment|design|features)|FlowMuse-App/docs/(architecture|api|data-model)\\.md' .`

Expected: 仅允许根需求兼容入口和已更新的迁移说明；其余结果逐条改为新路径。

- [ ] **Step 2: 检查目录与差异**

Run: `git diff --check; Get-ChildItem -LiteralPath docs -Force`

Expected: `git diff --check` 无输出；根 `docs/` 仅含 `项目说明`、`验收材料`、`技术设计`、`研发记录` 四个目录。

- [ ] **Step 3: 检查验收材料完整性**

Run: `Get-ChildItem -LiteralPath docs/验收材料 -File | Select-Object Name`

Expected: 原 Sprint 2 的全部 Markdown、PNG、DOCX、XLSX 均在该目录。
