# Agent Drop

[English](README.md)

Agent Drop 面向一个常见的远程 agent 开发场景：你在 Mac 上工作，通过 SSH 进入远程开发机，并在远程机器上运行 Codex、Claude Code 或其他 coding agent。

当远程 agent 需要读取 Mac 本地的截图、PDF、需求文档、测试 fixture 或整个文件夹时，Agent Drop 会把这些素材发送到 SSH 机器，并给出可以直接粘贴到现有终端会话里的稳定远程路径。

![Agent Drop 工作流](docs/assets/agent-drop-workflow.png)

第一个工作流是把本地文件和文件夹发送到远程 inbox：

```text
在 Finder 中右键选择文件或文件夹
  Agent Drop
    devbox
    gpu-box
    work-ubuntu
```

选择目标后，Agent Drop 会把选中的文件和文件夹上传到远程机器，并把最终远程路径复制到 Mac 剪贴板。

```text
~/.agent-inbox/2026-06-15/demo.png
~/.agent-inbox/2026-06-15/spec-2.pdf
~/.agent-inbox/2026-06-15/project-folder
```

然后你可以把这些路径直接粘贴到正在运行 Codex、Claude Code 或其他 coding agent 的 SSH 终端里。

Agent Drop 也可以把已知的远程文件或文件夹拉回 Mac。使用
`Agent Drop -> Pull from...` 或 CLI，粘贴 `~/runs/output.png`、
`/tmp/build-artifacts`、`devbox:~/runs/output.png` 这样的路径，下载内容会进入
`~/Downloads/Agent Drop/`。成功后，最终本地路径会复制到 Mac 剪贴板。

## 截图

带共享 Hosts、Drop/Pull 模式和全局状态栏的 Transfer 窗口：

![Agent Drop Transfer 窗口](docs/assets/agent-drop-app.png)

## V1 功能

- 运行在 macOS。
- 支持从 Finder 右键菜单发送选中的文件和文件夹。
- 在 `Agent Drop` 子菜单下显示发现到的 SSH 目标。
- 从 `~/.ssh/config` 和当前活跃 SSH 连接里发现目标。
- 使用标准 `ssh` 和 `rsync` 上传。
- 把上传内容放到远程 inbox 根目录 `~/.agent-inbox`。
- 按日期分组：`~/.agent-inbox/YYYY-MM-DD/`。
- 支持把远程文件和文件夹拉回 `~/Downloads/Agent Drop/`。
- 遇到重名时自动改名，例如 `demo-2.png` 或 `build-artifacts-2`。
- 把最终远程路径复制到 Mac 剪贴板，路径包含文件名或文件夹名。
- pull 成功后，把最终本地路径复制到 Mac 剪贴板。
- 在 Finder 上传和 App pull 前检查本地依赖，缺失时给出反馈，但不会自动安装。
- 在 App 里显示传输历史、Finder 上传实时进度、最后刷新时间和版本号/build。

文件夹上传会在远端保留同名目录，并把选中文件夹里的内容同步到这个远程目录里。

## 命令行用法

Agent Drop 包含一个 CLI，可以检查依赖、列出 SSH 目标、发送文件或文件夹，以及把远程路径拉回 Mac：

```bash
agent-drop targets
agent-drop doctor
agent-drop send --target <target> <paths...>
agent-drop pull --target <target> <remote-paths...>
```

示例：

```bash
agent-drop send --target devbox ./demo.png ./project-folder
agent-drop pull --target devbox ~/runs/output.png /tmp/build-artifacts
agent-drop pull --target devbox devbox:~/runs/output.png
```

CLI 不提供交互式目标选择器。如果只发现一个 SSH 目标，`send` 和 `pull`
可以在省略 `--target` 时使用它。

`doctor`、Finder 上传和 App pull 都会检查 `ssh`、`rsync`、`tar`、`pbcopy`
等本地工具。Agent Drop 会明确提示缺失依赖，但不会自动安装。

## V1 不包含

- 不生成 prompt。
- 不做持续双向同步。
- 不和远程项目目录自动绑定。
- 不上传剪贴板图片或剪贴板文本。
- 不提供 Raycast、Alfred、iOS 分享或菜单栏工作流。

## 设计文档

当前 V1 设计记录在：

[docs/superpowers/specs/2026-06-15-agent-drop-design.md](docs/superpowers/specs/2026-06-15-agent-drop-design.md)

pull 工作流设计记录在：

[docs/superpowers/specs/2026-06-26-agent-drop-pull-design.md](docs/superpowers/specs/2026-06-26-agent-drop-pull-design.md)

Transfer 导航设计记录在：

[docs/superpowers/specs/2026-06-27-agent-drop-transfer-navigation-design.md](docs/superpowers/specs/2026-06-27-agent-drop-transfer-navigation-design.md)

Finder 上传实时状态设计记录在：

[docs/superpowers/specs/2026-06-29-agent-drop-finder-upload-live-status-design.md](docs/superpowers/specs/2026-06-29-agent-drop-finder-upload-live-status-design.md)

## 开发

运行核心测试：

```bash
swift test
```

生成 Xcode project：

```bash
xcodegen generate
```

在不检查签名的情况下构建 App 和 Finder Sync 扩展：

```bash
xcodebuild -project AgentDrop.xcodeproj -scheme AgentDrop -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

本地测试 Finder Sync 时，使用 Xcode 自动签名和 Apple Development 证书。App target 和 Finder Sync extension target 应使用同一个 Team。仓库里的 `project.yml` 已包含当前本地流程使用的 development team 和 entitlements。

构建签名的 Debug App：

```bash
xcodebuild -project AgentDrop.xcodeproj -scheme AgentDrop -configuration Debug build
```

打包开发者 DMG，用于 release 测试：

```bash
scripts/package_developer_dmg.sh
```

生成的文件是 `dist/AgentDrop-developer.dmg`。双击打开 DMG，然后把
`Agent Drop.app` 拖到 `Applications`。

这是 developer build，不是 notarized 的正式公众发布版。首次打开时，macOS
可能需要你在 Privacy & Security 里允许打开。Finder extension 仍然需要在
System Settings > Login Items & Extensions > Extensions 里启用；如果右键菜单
没有出现，启用后重启 Finder。

安装本地签名 App：

```bash
APP_SRC="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path "*/AgentDrop-*/Build/Products/Debug/AgentDrop.app" -type d | sort | tail -n 1)"
APP_DEST="$HOME/Applications/Agent Drop.app"

test -n "$APP_SRC"
pkill -x AgentDrop || true
pkill -x AgentDropFinderSync || true
rm -rf "$APP_DEST"
/usr/bin/ditto "$APP_SRC" "$APP_DEST"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R -trusted "$APP_DEST"
xcrun pluginkit -a "$APP_DEST/Contents/PlugIns/AgentDropFinderSync.appex" || true
xcrun pluginkit -e use -i ai.shili.AgentDrop.FinderSync || true
open -n "$APP_DEST"
killall Finder
```

如果右键菜单里看不到 Agent Drop，打开 System Settings > Login Items & Extensions > Extensions，启用 Agent Drop Finder extension。改完扩展状态后重启 Finder。

开发时运行 CLI：

```bash
swift run agent-drop doctor
swift run agent-drop targets
swift run agent-drop send --target devbox ./demo.png ./project-folder
swift run agent-drop pull --target devbox ~/runs/output.png
```

Agent Drop 使用 UTC `YYYY-MM-DD` 作为上传日期目录。

文件夹上传会在远端保留同名目录，并把选中文件夹里的内容同步到这个远程目录里。Pull 会把文件和文件夹放到 `~/Downloads/Agent Drop/`，保留目录内容；如果本地目标已存在，会选择带后缀的新名称。

## Finder 扩展说明

- Finder 菜单里的 `Agent Drop -> <SSH target>` 用于上传。
- `Agent Drop -> Pull from...` 会通过 `agentdrop://pull` 打开 App 的
  `Transfer` 区域，并切到 Pull 模式。
- 根菜单项带一个小的 template upload 图标。
- 上传成功或失败后，Finder 会短暂给选中的文件加 badge。
- Finder 上传过程中，扩展会写入一条实时历史记录；App 无论停在哪个区域，
  全局状态栏都可以显示当前上传状态。
- 扩展诊断日志写入：
  `~/Library/Containers/ai.shili.AgentDrop.FinderSync/Data/Library/Logs/AgentDropFinderSync.log`。
- Finder Sync 发出的 macOS 通知是 best-effort。App 里的 `History` 区域才是可靠的反馈和历史记录界面。

## 传输历史

Agent Drop 会把最近的上传和下载记录写到 Finder 扩展容器里：

    ~/Library/Containers/ai.shili.AgentDrop.FinderSync/Data/Library/Application Support/Agent Drop/upload-history.json

App 会读取这个文件并显示 `History`。选择成功的上传记录后，可以再次复制远程路径；选择成功的下载记录后，可以再次复制本地路径。失败记录会显示短错误信息，且没有可复制 payload。Finder 上传会先显示为 `Uploading` 记录，然后原地更新为成功或失败；如果 App 发现很久没有完成的旧上传，会把这条记录显示为状态未知，而不是让状态栏一直保持上传中。窗口底部状态栏会显示刷新状态点、最后刷新时间，以及 App 版本号/build。JSON 文件名为了兼容旧版本仍保留为 `upload-history.json`，但现在会存储两个传输方向。

当前 developer build 路径下，主 App 有意保持 unsandboxed，这样它可以读取 Finder 扩展的历史文件，而不需要 Apple Developer Program App Group。以后如果做签名和 notarized release，可以迁移到 App Group container。

手动 Finder smoke test：

```bash
TEST_FILE="$HOME/Downloads/agent-drop-ui-test.png"
printf 'Agent Drop Finder smoke test\n' > "$TEST_FILE"
printf 'AGENT_DROP_PENDING' | pbcopy
open -R "$TEST_FILE"
```

然后在 Finder 里右键文件或测试文件夹，选择 `Agent Drop -> x570 config` 或另一个已配置目标，并验证：

```bash
pbpaste
ssh x570 'd="$HOME/.agent-inbox/$(date +%F)"; ls -l "$d"/agent-drop-ui-test*; wc -c "$d"/agent-drop-ui-test*'
tail -n 80 "$HOME/Library/Containers/ai.shili.AgentDrop.FinderSync/Data/Library/Logs/AgentDropFinderSync.log"
```

预期结果：`pbpaste` 包含最终远程路径，远程文件或文件夹存在，文件夹上传保留内容，诊断日志记录 `upload success`。如果上传时 `Agent Drop.app` 已打开，全局状态栏会在任意区域显示当前上传状态，`History` 会显示一条 `Uploading` 记录，并在结束后更新为成功或失败。

Finder 上传后，确认历史文件已写入：

    HISTORY="$HOME/Library/Containers/ai.shili.AgentDrop.FinderSync/Data/Library/Application Support/Agent Drop/upload-history.json"
    test -f "$HISTORY"
    python3 -m json.tool "$HISTORY" | sed -n '1,80p'

打开 `Agent Drop.app`，确认上传记录出现在 `History`。选择上传记录，重置剪贴板，点击 `Copy Paths`，再确认 `pbpaste` 不再是占位内容，而是远程路径：

    printf 'APP_COPY_PENDING' | pbcopy
    pbpaste

使用 `x570` 做手动 pull smoke test：

```bash
TEST_FILE="$TMPDIR/agent-drop-e2e-$(date -u +%Y%m%dT%H%M%SZ).txt"
printf 'Agent Drop x570 pull smoke test\n' > "$TEST_FILE"
REMOTE_PATH="$(swift run agent-drop send --target x570 "$TEST_FILE" | tail -n 1)"
LOCAL_PATH="$(swift run agent-drop pull --target x570 "$REMOTE_PATH" | tail -n 1)"
test -f "$LOCAL_PATH"
cmp "$TEST_FILE" "$LOCAL_PATH"
test "$(pbpaste)" = "$LOCAL_PATH"
```

文件夹往返可以发送并拉回一个小目录，再比较其中的文件：

```bash
TEST_DIR="$TMPDIR/agent-drop-e2e-dir-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$TEST_DIR/nested"
printf 'root\n' > "$TEST_DIR/root.txt"
printf 'nested\n' > "$TEST_DIR/nested/child.txt"
REMOTE_DIR="$(swift run agent-drop send --target x570 "$TEST_DIR" | tail -n 1)"
LOCAL_DIR="$(swift run agent-drop pull --target x570 "$REMOTE_DIR" | tail -n 1)"
cmp "$TEST_DIR/root.txt" "$LOCAL_DIR/root.txt"
cmp "$TEST_DIR/nested/child.txt" "$LOCAL_DIR/nested/child.txt"
```

重复执行同一个 pull 命令，可以确认本地重名时使用 `-2` 后缀。测试 App 路由时，复制
`x570:$REMOTE_PATH`，在 Finder 里选择 `Agent Drop -> Pull from...`，确认 `Transfer`
区域会切到 Pull 模式，预选 `x570`，并填入带 host 前缀的远程路径。

## 状态

Agent Drop V1 已实现。仓库包含 Swift package/core、CLI、macOS App、Finder Sync extension、上传和 pull 工作流、核心测试、XcodeGen project 配置，以及本地测试/构建文档。
