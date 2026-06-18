# repair-codex-computer-use-chrome

一个用于 Windows Codex Desktop 的快速修复 skill 可复用脚本，多个版本多次使用验证。

这个仓库现在内置 `scripts/install-computer-use-local.ps1` 修复引擎，不再要求用户提前安装 `codex-windows-fast-patch` skill。

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

## 前置条件

- Windows 版 Codex Desktop 已安装，并且当前 Windows 用户能访问 Codex 的本地目录。
- Chrome 浏览器已安装。
- Chrome 浏览器需要提前从 Chrome 插件商店安装并启用 Codex 扩展。脚本会修复 Native Messaging manifest、注册表项和本地 helper 路径，但不会替用户从插件商店安装扩展。
- 当前用户需要能写入 `$env:USERPROFILE\.codex`、`$env:LOCALAPPDATA\OpenAI\extension`，以及当前用户注册表 `HKCU\Software\Google\Chrome\NativeMessagingHosts` 和 `HKCU\Software\Classes\codex`。
- Codex Desktop 安装包或本地缓存里需要能找到 `openai-bundled` 插件资源。

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
- 优先使用仓库内置的 `scripts/install-computer-use-local.ps1` 修复引擎；如果这个文件缺失，才尝试回退到本机已有的 `codex-windows-fast-patch` skill。
- 先轻量稳定 Chrome Native Messaging manifest，再跑严格校验，尽量避免触发完整缓存重建。
- 每次运行前会备份相关配置到 `$env:CODEX_HOME\backups\computer-use-chrome-skill\...`。

## 仓库结构

```text
.
├── SKILL.md
├── agents/
│   └── openai.yaml
├── THIRD_PARTY_NOTICES.md
└── scripts/
    ├── install-computer-use-local.ps1
    └── repair.ps1
```

## 注意

这个 skill 面向 Windows Codex Desktop。它会修改当前用户范围内的 Codex 配置、Chrome Native Messaging 注册表项、`codex://` 协议注册表项和 Codex 插件缓存。运行前请确认你要修的是当前 Windows 用户下的 Codex 环境。

这个项目不是 OpenAI 官方项目。

## 开源与第三方代码说明

本仓库的原创包装脚本、skill 元数据和文档按仓库 `LICENSE` 中的说明发布。

`scripts/install-computer-use-local.ps1` 来自公开仓库 [chen0416ccc-cpu/codex-windows-fast-patch-skill](https://github.com/chen0416ccc-cpu/codex-windows-fast-patch-skill) 的 `scripts/install-computer-use-local.ps1`，用于让本项目具备通用的一键修复能力。导入时，上游仓库没有标准 `LICENSE` 文件，GitHub license API 也未识别到许可证。因此该第三方脚本不由本仓库重新授权；使用、分发或二次修改前，请自行确认上游项目授权状态或联系原作者。详细来源见 `THIRD_PARTY_NOTICES.md`。

## 致谢

感谢 [linux.do](https://linux.do/) 网站提供的社区讨论与教程线索。
