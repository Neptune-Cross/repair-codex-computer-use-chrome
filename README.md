# repair-codex-computer-use-chrome

一个用于 Windows Codex Desktop 的快速修复 skill 可复用脚本，多个版本多次使用验证。

它主要处理这些情况：

- `computer-use@openai-bundled`、`browser@openai-bundled`、`chrome@openai-bundled` 无法安装、不可用或状态异常。
- bundled marketplace / plugin cache 指向坏掉的临时目录。
- `chrome\latest`、Chrome Native Messaging manifest、Chrome 扩展状态不一致。
- `codex://` 协议仍指向旧的 Codex AppX 包。
- Computer Use helper transport 可以导入但运行时校验失败。

## 安装

推荐直接克隆到 Codex skills 目录：

```powershell
git clone https://github.com/Neptune-Cross/repair-codex-computer-use-chrome.git "$env:USERPROFILE\.codex\skills\repair-codex-computer-use-chrome"
```

如果已经存在同名目录，可以先备份或删除旧目录后再克隆。

## 使用

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\repair-codex-computer-use-chrome\scripts\repair.ps1"
```

需要机器可读输出时：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\repair-codex-computer-use-chrome\scripts\repair.ps1" -Json
```

## 设计要点

- 不写死 Windows 用户名，优先使用 `$env:CODEX_HOME`、`$env:USERPROFILE`、`$env:LOCALAPPDATA`。
- 自动发现当前用户本地的 `OpenAI\Codex\bin\*\codex.exe`。
- 自动发现当前 `OpenAI.Codex_*` AppX 包，并同步 `codex://` 协议。
- 先轻量稳定 Chrome Native Messaging manifest，再跑严格校验，尽量避免触发完整缓存重建。
- 每次运行前会备份相关配置到 `$env:CODEX_HOME\backups\computer-use-chrome-skill\...`。

## 仓库结构

```text
.
├── SKILL.md
├── agents/
│   └── openai.yaml
└── scripts/
    └── repair.ps1
```

## 注意

这个 skill 面向 Windows Codex Desktop。它会修改当前用户范围内的 Codex 配置、Chrome Native Messaging 注册表项、`codex://` 协议注册表项和 Codex 插件缓存。运行前请确认你要修的是当前 Windows 用户下的 Codex 环境。

## 致谢

感谢 [linux.do](https://linux.do/) 网站提供的社区讨论与教程线索。
