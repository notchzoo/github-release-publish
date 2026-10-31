---
name: github-release-publish
description: "把本地项目发布成 GitHub 仓库与版本的标准流程：本地还不是仓库、或没有 GitHub remote 时，新建一个可直接上传的仓库并首次推送；已经有仓库时发布新版本，并且必须先询问用户是「覆盖当前最新版本」还是「发布新版本」。适用于任意语言与框架（CMake/C++、Python、Node、Go、Rust、纯文档项目），产出可下载的 tag + GitHub Release、CHANGELOG 与版本标记。触发词：上传到 GitHub、新建仓库、发布新版本、整理成 v0.x、覆盖最新版本、发版、release、tag、之前的版本下载不到。"
---

# GitHub 仓库创建与版本发布

把任意本地项目交付成「能下载的 GitHub 版本」：**没有仓库就建仓库，有仓库就发版本**，
并且**永远先问清楚**是覆盖当前最新版本，还是发布一个新版本。

## 流程总览

```text
探测状态
 ├─ A 不是 git 仓库 ─┐
 ├─ B 没有 GitHub remote ─┤→ 建仓库 → 首次提交推送 → 首次发版 → 验证回报
 └─ C 已有 GitHub 仓库
      ├─ 从未发过版 → 直接发首个版本 → 验证回报
      └─ 已有版本  → 必须询问 ─┬→ 覆盖当前最新版本 → 覆盖流程 → 验证回报
                                └→ 发布新版本      → 发版流程 → 验证回报
```

## 硬性原则

| # | 原则 | 原因 |
|---|---|---|
| 1 | 先探测、后动作 | 仓库状态、remote、已有 tag/Release 必须从真实状态读出来，绝不猜 |
| 2 | 破坏性操作先确认 | 覆盖 tag、force push、删除 Release 会毁掉别人手里的版本 |
| 3 | 已有仓库发版必须二选一 | 「覆盖当前最新版本」还是「发布新版本」，由用户决定，不由 agent 决定 |
| 4 | 先验证、后上传 | 项目自带构建/测试能跑就先跑，失败就不上传 |
| 5 | 五处一致 | tag / Release / CHANGELOG / README 或版本文件 / 提交信息，版本号必须一致 |

## 阶段 1：探测状态（只读，永远第一步）

```powershell
# 在项目根目录执行；-CheckRemote 会额外查 GitHub（需要已配置凭证）
& "<skill 目录>\scripts\detect-state.ps1" -Path . -CheckRemote
```

输出是 `key=value`，关键键：`state`（A-no-repository / B-no-github-remote /
C-not-yet-released / C-released）、`branch`、`slug`、`dirty_files`、`latest_tag`、
`suggest_patch|minor|major`、`repo_private`、`release_count`、`latest_release`。

脚本只读，从不提交/打标签/推送；Windows PowerShell 5.1 与 PowerShell 7 均可运行。
手工等价命令见 `references/commands.md` §2。

## 阶段 2：新建仓库（状态 A / B）

1. **本地建仓**（仅状态 A）：`git init -b <branch>`；按项目类型补 `.gitignore`。
2. **体检暂存内容**：`git add -A --dry-run`，排除 `build/`、`out/`、`node_modules/`、
   `.venv/`、`__pycache__/`、大二进制、`*.env`、密钥与凭据。
3. **首次提交**：`git add -A` → `git commit -m "<项目名> 初始版本"`。
4. **仓库可见性必须问**：`private`（默认建议）还是 `public`。
5. **建库并推送**（优先 gh，无 gh 用 REST API，命令见 `references/commands.md` §3）：
   ```powershell
   gh repo create <owner>/<repo> --private --source . --remote origin --push
   ```
6. 用户要的是「一个可下载的版本」时，接着做阶段 4，首个版本建议 `v0.1.0`
   （已有 0 起始编号习惯的，顺延为 `v0.0.x`）。

## 阶段 3：已有仓库时的必问项 ⚠️

当 `state=C-released`（仓库已有版本），**用提问工具问一次**（DSH 用 `ask_user_question`；
其他运行环境就直接问），选项固定三选一，推荐项放第一位：

```text
<owner/repo> 已经有版本（最新 vX.Y.Z，Release 已发布）。这次要怎么发？
  1. 发布新版本 vA.B.C（推荐）—— 旧版本原样保留，新增一个可下载的 tag + Release
  2. 覆盖当前最新版本 vX.Y.Z —— 移动 tag 并重写该 Release（已发布内容会被替换）
  3. 取消
```

同一轮可以顺带确认：

- **新版本号**：给出 `suggest_patch` / `suggest_minor` / `suggest_major` 三个建议，让用户选或自定义；
  用户指定了就照用，不擅自「纠正」。
- **是否要动分支历史**：只有「覆盖」且已发布提交与当前内容不同才可能需要 force push —— 必须单独再确认。
- **可见性变更**：用户没提就不要改。

> **用户没明确回答前，不推送任何 tag、不改任何 Release。**

## 阶段 4：发布新版本（默认路径）

1. **验证**：跑项目自带的构建/测试（见「通用性适配」）。失败就停下报告，不发布。
2. **更新版本落点**：
   - `CHANGELOG.md`：新增 `## vX.Y.Z — YYYY-MM-DD`（没有就新建，并把旧版本补一条）
   - `README.md`：顶部版本标记（没有就加一行，并链到 CHANGELOG）
   - 语言清单文件：`package.json` / `pyproject.toml` / `CMakeLists.txt` / `Cargo.toml`（存在才改）
   - 模板见 `references/release-notes.md`
3. **提交**：提交信息 `vX.Y.Z: <一句话摘要>` + 要点。中文说明用 UTF-8 文件 + `git commit -F`。
4. **附注 tag**：`git tag -a vX.Y.Z -F tag-msg.txt`。
5. **普通推送**（绝不 force）：`git push origin <branch>` → `git push origin vX.Y.Z`。
6. **建 Release**：`gh release create vX.Y.Z --title "..." --notes-file notes.md`，
   无 gh 用 REST `POST /repos/{owner}/{repo}/releases`（`make_latest` 控制谁是最新）。
7. 进入阶段 6 验证与回报。

## 阶段 5：覆盖当前最新版本（用户明确选择后才做）

覆盖 ≠ 重写历史。先分清覆盖对象：

| 覆盖对象 | 做法 | 风险 |
|---|---|---|
| 只有 tag / Release 指向错提交 | 移动 tag + PATCH Release | 低，分支历史不动 |
| 已发布内容缺文件，需要重发 | 新提交 → `git tag -f` → force push 该 tag | 中，旧 tag 对象消失 |
| 分支内容也要改 | `git push --force-with-lease` | 高，**必须再确认一次** |

```powershell
git tag -f -a vX.Y.Z <commit> -F tag-msg.txt
git push origin vX.Y.Z --force
# Release：PATCH 正文，或 delete + create（会产生短暂空窗）
```

收尾必须提示：已下载旧包的人、镜像与协作者本地副本不会自动更新；
共享分支上覆盖会影响别人。

## 阶段 6：验证与回报

```powershell
git ls-remote --tags origin     # 远端确实有这个 tag
git status --short --branch     # 工作区与远端同步
gh release view vX.Y.Z          # 或 REST GET /releases 确认非 draft
```

固定表格回报：

| 版本 | 提交 | 标签 | Release | 下载 |
|---|---|---|---|---|
| vX.Y.Z | <sha7> | vX.Y.Z | <url> | `<repo>/archive/refs/tags/vX.Y.Z.zip` |

再补一句：旧版本是否也补了 tag/Release（「只能在历史里看、下载不到」的常见诉求）。

## 通用性适配（语言无关）

| 生态 | 构建/测试（优先项目自带脚本） | 版本号常见位置 |
|---|---|---|
| CMake / C++ | `cmake --build build --config Debug`，或仓库自带 `scripts/verify_project.ps1` | `CMakeLists.txt` 的 `project(... VERSION)` |
| Node / TS | `npm test`、`npm run build` | `package.json` |
| Python | `pytest`、`python -m build` | `pyproject.toml` / `__version__` |
| Go | `go build ./...`、`go test ./...` | `git tag` |
| Rust | `cargo test`、`cargo build` | `Cargo.toml` |
| 纯文档 / 资源 | 无构建：检查链接与图片是否可打开 | `README.md` / `VERSION` |

规则：

- 优先 `Makefile` / `justfile` / `package.json scripts` / 项目自带脚本，不自己发明构建命令。
- 没有可运行的验证手段时照常发布，但回报里写明「未验证」。
- 默认分支从 `git symbolic-ref refs/remotes/origin/HEAD` 读，不要写死 `main`。
- monorepo：在子目录发版，tag 用 `<pkg>-vX.Y.Z` 前缀；多产品仓库先问发哪一个。
- 非 Windows 环境：`references/commands.md` §7 给了 bash/curl 等价命令。

## 失败处理

| 现象 | 处理 |
|---|---|
| `schannel: AcquireCredentialsHandle failed: SEC_E_NO_CREDENTIALS` | 受限沙箱/权限问题：用提权（danger-full-access）**重试同一条命令**，不要改 git 配置绕过 |
| `couldn't create signal pipe, Win32 error 5` | 沙箱禁止命名管道，git 的 credential helper 起不来；处理同上 |
| `could not read Username for 'https://github.com'` | 没有可用凭证：请用户 `gh auth login`；**不要索要明文 token** |
| `detected dubious ownership` | 目录归属与当前用户不一致：加 `safe.directory` 或修权限；`detect-state.ps1` 会在 `hint` 里提示 |
| 推送成功但 Release 失败 | 只补 Release，**不要重推 tag** |
| 构建/测试失败 | 停止发布，先修或明确告知用户 |
| 用户中途改主意 | 已推送的 tag 走阶段 5，并重新确认 |

## 红线

- 不 `push --force` 分支，除非用户明确同意，且用 `--force-with-lease`。
- 不删除 tag / Release，除非用户明确同意。
- 不提交密钥、`.env`、凭据、构建产物；不把 token 写进文件或日志（判断凭证时只看长度/用户名）。
- 不擅自把私有仓库改成公开。
- 不为「让流程通过」跳过验证、伪造版本号或改写用户历史。

## 实战样例（本仓库 cube 的两次发布）

```text
v0.10  64bcd70  初始版本（PBR 框架，无太阳图层）→ 补 tag + Release（用户抱怨旧版本下载不到时）
v0.11  bbecf2d  SunSprite 太阳图层 + 手册        → tag + Release（latest）
```

关键动作：提交前跑 `verify_project.ps1`；中文提交/版本说明写成 UTF-8 文件后 `-F` 传入；
受限沙箱里推送需提权重试；最后用 `ls-remote` + Release API 双重确认。