# 命令手册（PowerShell / Git / GitHub REST）

所有命令都在**项目根目录**执行。`<owner>/<repo>`、`<branch>`、`vX.Y.Z` 按实际情况替换。

---

## 1. 凭证与沙箱

### 1.1 检查已有凭证（不回显 token）

```powershell
$env:GIT_TERMINAL_PROMPT = "0"          # 禁止交互卡住
$out = ("protocol=https`nhost=github.com`n`n" | git credential fill 2>&1) -join "`n"
if ($out -match '(?m)^username=(.+)$') { "user: " + $Matches[1] }
if ($out -match '(?m)^password=(.+)$') { "token present, length=" + $Matches[1].Trim().Length }
```

登录名 + token 长度足够判断可用性；**永远不要打印 token 本身**。

### 1.2 常见失败与处置

| 报错 | 含义 | 处置 |
|---|---|---|
| `schannel: AcquireCredentialsHandle failed: SEC_E_NO_CREDENTIALS` | 进程拿不到系统证书句柄（沙箱/权限） | 用提权（danger-full-access）重试**同一条命令**，不要改 git 配置 |
| `couldn't create signal pipe, Win32 error 5` | 受限沙箱禁止命名管道，git 的 sh/credential helper 起不来 | 同上，提权重试 |
| `could not read Username for 'https://github.com'` | 没有可用凭证 | 让用户 `gh auth login` 或配置 credential helper；**不要索要明文 token** |
| `remote: Permission to ... denied` | token 无 `repo` 权限 | 换有权重的凭证，不要试错式重推 |

> 提权只用于**需要网络/证书/凭据进程**的那一条命令；文件读写照旧走受限模式。

### 1.3 认证方式优先级

1. `gh auth status` 可用 → 直接用 `gh`
2. `credential.helper`（GCM / store）里有凭证 → 用 git + REST API
3. 都没有 → 停下，请用户登录，不要索要明文 token

---

## 2. 探测（只读）

```powershell
git rev-parse --is-inside-work-tree        # 是否 git 仓库
git remote -v                              # 是否有 GitHub remote
git rev-parse --abbrev-ref HEAD            # 当前分支
git ls-files | Measure-Object              # 已跟踪文件数
git status --porcelain                     # 脏文件
git tag --sort=-v:refname | Select-Object -First 5
git symbolic-ref refs/remotes/origin/HEAD  # 默认分支
```

远程版本与 Release：

```powershell
git ls-remote --tags origin
gh release list --limit 5
# 无 gh：
Invoke-RestMethod "https://api.github.com/repos/<owner>/<repo>/releases" -Headers $headers
```

脚本版：`./scripts/detect-state.ps1 -Path . -CheckRemote`

---

## 3. 新建仓库（状态 A / B）

### 3.1 gh

```powershell
git init -b main
git add -A
git commit -m "<项目名> 初始版本"
gh repo create <owner>/<repo> --private --source . --remote origin --push
```

### 3.2 REST API（无 gh）

```powershell
$headers = @{ Authorization = "token $token"; Accept = "application/vnd.github+json"; "User-Agent" = "dsh" }
$body = @{ name = "<repo>"; private = $true; description = "<一句话>" } | ConvertTo-Json
Invoke-RestMethod -Uri "https://api.github.com/user/repos" -Method Post -Headers $headers `
  -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -ContentType "application/json; charset=utf-8"

git remote add origin https://github.com/<owner>/<repo>.git
git push -u origin <branch>
```

组织仓库用 `POST /orgs/<org>/repos`。

---

## 4. 发布新版本

```powershell
git add -A
git commit -F .commit-msg.txt            # 中文说明用 UTF-8 文件，避免命令行编码问题
git tag -a vX.Y.Z -F .tag-msg.txt
git push origin <branch>
git push origin vX.Y.Z
```

```powershell
# gh
gh release create vX.Y.Z --title "vX.Y.Z — <摘要>" --notes-file notes.md

# 或 API
$payload = @{ tag_name = "vX.Y.Z"; name = "vX.Y.Z — <摘要>"; body = $notes; draft = $false; prerelease = $false; make_latest = "true" } | ConvertTo-Json
Invoke-RestMethod -Uri "https://api.github.com/repos/<owner>/<repo>/releases" -Method Post -Headers $headers `
  -Body ([System.Text.Encoding]::UTF8.GetBytes($payload)) -ContentType "application/json; charset=utf-8"
```

---

## 5. 覆盖当前最新版本（需用户明确同意）

### 5.1 只移动 tag 与 Release（历史不变）

```powershell
git tag -f -a vX.Y.Z <commit> -m "vX.Y.Z 重发：<原因>"
git push origin vX.Y.Z --force
```

Release 有两种处理：

```powershell
# A. 就地改正文/标题
$rel = Invoke-RestMethod "https://api.github.com/repos/<owner>/<repo>/releases/tags/vX.Y.Z" -Headers $headers
$payload = @{ body = $notes; make_latest = "true" } | ConvertTo-Json
Invoke-RestMethod "https://api.github.com/repos/<owner>/<repo>/releases/$($rel.id)" -Method Patch -Headers $headers `
  -Body ([System.Text.Encoding]::UTF8.GetBytes($payload)) -ContentType "application/json; charset=utf-8"

# B. 删掉重建（会短暂消失）
gh release delete vX.Y.Z --yes
gh release create vX.Y.Z --notes-file notes.md
```

### 5.2 分支内容也要改（高风险，必须二次确认）

```powershell
git commit --amend        # 或新提交
git push --force-with-lease origin <branch>
```

提示用户：已下载的旧包、镜像、协作者的本地分支都不会自动更新。

---

## 6. 验证

```powershell
git ls-remote --tags origin
git status --short --branch
gh release view vX.Y.Z
```

```powershell
$rels = Invoke-RestMethod "https://api.github.com/repos/<owner>/<repo>/releases" -Headers $headers
$rels | ForEach-Object { "$($_.tag_name) draft=$($_.draft) $($_.html_url)" }
```

下载地址（私有仓库需登录）：

```text
https://github.com/<owner>/<repo>/archive/refs/tags/vX.Y.Z.zip
https://github.com/<owner>/<repo>/releases/tag/vX.Y.Z
```

---

## 7. 非 Windows / bash 等价命令

```bash
git credential fill <<< $'protocol=https\nhost=github.com\n\n'
curl -s -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/repos/<owner>/<repo>/releases
gh release create vX.Y.Z --notes-file notes.md
```