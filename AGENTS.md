# Repository Guidelines 仓库贡献指南

## 项目结构与模块划分
- 目录约定：`core/`（入口场景、Autoload 单例）、`features/`（玩家、战斗、UI 等功能模块）、`data/`（物品、技能等 `.tres` 资源）、`assets/`（贴图、模型、音频）、`docs/`（设计文档）、`tests/`（自动化测试预留）、`tools/`（导入器与脚本）。
- Godot 的导入缓存位于 `.godot/`，不要手动修改或依赖其中生成文件的内容。
- 新的玩法或系统优先放在 `features/<domain>/` 下，使场景与脚本尽量解耦、可复用。

## 构建、运行与开发命令
- 使用 Godot 4.5（Forward+）打开工程：`godot4 --path .`，或在编辑器中打开后按 `F5` 运行。
- 运行指定场景示例：`godot4 --path . --scene core/main.tscn`（根据实际场景路径调整）。
- 导出配置在 Godot 编辑器中维护并保存到 `export_presets.cfg`；如非必要，请勿手动编辑。

## 代码风格与命名规范
- GDScript 使用 4 空格缩进、UTF-8 编码，尽量使用类型标注（typed GDScript）。
- 命名约定：场景 `PascalCase.tscn`，类名 `PascalCase`，脚本 `snake_case.gd`，信号 `something_happened`，常量/枚举 `SCREAMING_SNAKE_CASE`。
- 节点名使用 `PascalCase`，清晰表达角色（如 `Player`、`HitboxArea`、`HealthBar`）。一个主要场景与一个同名脚本成对放在同一目录下。

## 测试与验证
- `tests/` 目录预留给 GUT / WAT 等测试框架；当前阶段，推荐在对应 `features/` 子目录下添加简短示例场景进行手动验证。
- 提交代码前至少在编辑器中运行主流程场景（如 `core/main.tscn`），确认输入映射以及新功能流程可用。
- 优先编写数据驱动、可预测的逻辑，为后续自动化测试打基础。

## Commit 与 Pull Request 规范
- 推荐轻量约定式提交信息，例如：`feat(player): 支持点击移动`、`fix(combat): 修正暴击计算`；可参考当前 `git log` 风格。
- 单次提交尽量聚焦一个改动点，不要将大规模重构与行为变更混在同一提交中。
- PR 描述应包含：变更概述、关键实现思路、测试方式（例：“在 Godot 4.5 中运行 `core/main.tscn` 手动验证”），以及可见改动时的截图或 GIF。

## 面向智能代理的说明
- 优先修改 `core/`、`features/` 中的脚本及 `data/` 中的数据资源；除非用户明确要求，请避免改动 `.godot/` 缓存或大体积二进制资源。
- 保持改动最小化并遵循本文件与 `README.md` 中既有架构与约定，避免无关重构。
