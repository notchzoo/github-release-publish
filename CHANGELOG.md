# 变更记录

## v0.1.0 — 2026-10-31

首个版本。

### 新增

- `SKILL.md`：探测 → 新建仓库 → 发布新版本 → 覆盖版本 → 验证回报的完整流程，
  含「已有仓库必须先问覆盖还是新版本」的硬性要求和语言无关的适配矩阵
- `references/commands.md`：git / gh / GitHub REST 命令、凭证读取、受限沙箱
  （`SEC_E_NO_CREDENTIALS`、命名管道失败、`dubious ownership`）处置
- `references/release-notes.md`：提交信息、tag 说明、CHANGELOG、Release 正文模板与版本号选择
- `scripts/detect-state.ps1`：只读状态探测，输出 A/B/C 三态、标签、脏文件、
  `owner/repo`、建议的 patch/minor/major 版本号

### 验证

- 在真实项目（私有仓库、已有 v0.10/v0.11 两个 Release）上实测三种状态：
  非仓库目录 → `A-no-repository`；本地有 tag 无 remote → `B-no-github-remote`；
  完整仓库 → `C-released` + 远端 Release 列表