# github-release-publish

一个 **实用工具类 skill**：把任意本地项目交付成「能下载的 GitHub 版本」。

- 本地还不是仓库、或没有 GitHub remote → 新建仓库并首次推送
- 已经有仓库 → 发布新版本，且**必须先问**用户：覆盖当前最新版本，还是发一个新版本
- 覆盖 ≠ 重写历史，按风险分三档处理（只动 tag / 重发内容 / 改分支）

## 安装

技能目录（Windows）：

```powershell
git clone https://github.com/notchzoo/github-release-publish.git "$env:USERPROFILE\.agents\skills\github-release-publish"
```

或使用 skills CLI：

```bash
npx skills add notchzoo/github-release-publish -g
```

安装后重启会话即可在技能列表里看到 `github-release-publish`。

## 内容

```text
SKILL.md                       主流程：探测 → 建仓库 / 发布 / 覆盖 → 验证回报
references/commands.md         git / gh / REST / 凭证 / 受限沙箱失败处置
references/release-notes.md    提交信息、tag 说明、CHANGELOG、Release 正文模板
scripts/detect-state.ps1       只读状态探测（A/B/C 三态 + 建议版本号）
```

## 快速开始

```powershell
# 在任意项目根目录
& "$env:USERPROFILE\.agents\skills\github-release-publish\scripts\detect-state.ps1" -Path . -CheckRemote
```

输出 `key=value`：

```text
state=C-released
branch=master
latest_tag=v0.11
suggest_patch=v0.11.1
next=ASK user: publish a new version, or overwrite the current latest version
```

`state` 取值：`A-no-repository`（建仓库）、`B-no-github-remote`（补 remote）、
`C-not-yet-released`（首次发版）、`C-released`（必须先问覆盖还是新版本）。

## 版本与分类约定

仓库用**两级 tag** 表达「分类 → 版本」：

| tag | 作用 |
| --- | --- |
| `skills/utility` | 分类标签：实用工具类 skill |
| `skills/utility-vX.Y.Z` | 该分类下的版本号（GitHub Release 挂在这里） |

> 注意：Git 不允许 `skills/utility` 与 `skills/utility/v0.1.0` 同时存在（ref 冲突），
> 所以版本号用连字符挂在分类前缀下。

## 环境

- Windows PowerShell 5.1 / PowerShell 7 均可运行脚本；`detect-state.ps1` 全 ASCII
- 非 Windows 环境见 `references/commands.md` §7 的 bash / curl 等价命令
- 凭证只通过 `git credential fill` / `gh auth` 读取，从不写入文件或日志

## 变更记录

见 [CHANGELOG.md](CHANGELOG.md)。