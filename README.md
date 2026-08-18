# 🐋 Deepseek Harness Launcher（鲸鱼悬浮窗）

一个 Windows 桌面悬浮窗，实时反映 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 的工作状态，同时作为进入 Harness 的快捷入口。
<img width="145" height="182" alt="image" src="https://github.com/user-attachments/assets/a8c8ee4c-b96c-4295-80e5-b250a031f062" />
<img width="256" height="425" alt="image" src="https://github.com/user-attachments/assets/2ec28660-2eaf-4f77-89a3-0ecfe25e2119" />

## ✨ 功能特性

- **实时状态动画**：Harness 内**有任务在跑**时显示 `working` 动图，空闲时显示 `idle` 动图（默认每 1.5 秒检测一次，可调）
- **实时活动状态**：气泡框实时显示当前工作状态——`正在思考…` / `正在调用 pwsh` / `正在编辑文件` / `正在联网搜索` / `等待审批：xx` 等
- **一键进入**：双击悬浮窗直接用默认浏览器打开 Harness
- **状态气泡**：单击查看 Harness 运行状态（在线/离线、任务执行中/空闲、当前活动）
- **自由拖动**：按住拖动到桌面任意位置
- **更换动图**：气泡框内一键更换 working / idle 动图（仅支持 GIF 格式，自动校验文件有效性）
- **残留自动清理**：自动清除工作动图右下角抠图残留（绿幕 / 灰黑块），且只作用于原始动图，不影响用户替换后的动图
- **开机自启**：登录时自动在后台启动 Harness（`npx -y @deepseek-ai/dsh web`）并拉起悬浮窗，无需手动开 cmd

## 📋 系统要求

- Windows 10 / 11（桌面交互会话）
- PowerShell 5.1（Windows 自带）或更高
- 可选的 `npx`（Node.js）——用于开机自启时自动拉起 Harness；若你手动运行 Harness 也可

## 📁 目录结构

```
Whaleplugin/
├── README.md              # 本文档
├── LICENSE                # MIT 开源许可
├── install.ps1            # 一键注册开机自启（管理员运行可注册"登录时"任务，顺位最早）
├── uninstall.ps1          # 一键移除开机自启
└── src/                   # 运行时源码（整目录复制到任意位置即可运行）
    ├── launcher.vbs       # 隐藏启动器（无控制台窗口）
    ├── start-whale.ps1    # 启动器：静默启动 Harness → 等待端口就绪 → 拉起悬浮窗
    ├── whale-window.ps1   # 悬浮窗本体（WPF，含全部交互与状态监控）
    ├── working.gif        # "有任务运行"动图（可通过气泡框更换）
    └── idle.gif           # "空闲"动图（可通过气泡框更换）
```

> `src/` 目录是**可移动的**：所有脚本通过自身路径定位资源，复制到任意文件夹即可运行。

## 🚀 安装

### 方式一：立即使用（不需要管理员）

1. 双击 `src\launcher.vbs`（无窗口，静默后台启动 Harness + 悬浮窗）

### 方式二：注册开机自启

```powershell
# 在 Whaleplugin 目录下
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

- **普通权限**：注册 HKCU 开机自启（登录后自动启动）
- **管理员权限**（推荐）：额外注册任务计划「登录时」任务，启动顺位排在绝大多数自启软件之前

### 方式三：手动命令行

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\start-whale.ps1
```

## 🖱️ 使用说明

| 操作 | 行为 |
| --- | --- |
| 单击悬浮窗 | 弹出状态气泡：Harness 在线状态 + 任务状态 + **当前活动**（实时刷新）+ 打开/更换动图按钮 |
| 双击悬浮窗 | 直接用浏览器打开 `http://127.0.0.1:3080` |
| 按住拖动 | 移动悬浮窗到任意位置 |
| 右键 | 菜单：`打开 Harness` / `停止 Harness`（连同进程树结束）/ `退出` |
| 气泡框 → 更换工作/空闲动图 | 选择本地 GIF 替换对应动画，立即生效并持久保存 |

## 🧩 工作原理

- **状态检测**：每 1.5s 轮询 Harness API `POST /api/session.list`，任一会话 `running=true` → 显示 working 动图，否则 idle 动图
- **活动状态**：后台线程每 2s 轮询 `session.history`，从最近事件推断当前活动（`tool/call` → 工具名；`assistant/chunk` 的 `reasoning-delta` → 思考；`approval/asked` → 等待审批）
- **动图播放**：`System.Drawing` 逐帧解码 GIF（保留原始帧延迟），`DispatcherTimer` 轮播
- **残留清理**：对原始 working.gif 按帧做连通性分析 + 非蓝像素清除（右下角区域），误伤主体概率极低
- **进程生命周期**：悬浮窗由启动器托管；`停止 Harness` 通过记录的主进程 PID + 端口反查执行 `taskkill /T` 结束整棵进程树

## ⚙️ 配置

所有可调参数都在 `src\whale-window.ps1` 顶部附近：

| 参数 | 位置 | 默认 |
| --- | --- | --- |
| 轮询间隔（working/idle 切换） | `Polling timer` 的 `FromSeconds(1.5)` | 1.5s |
| 活动状态轮询间隔 | `activityScript` 的 `Start-Sleep 2` | 2s |
| 窗口尺寸 | XAML `Width/Height="180"` | 180×180 |
| 双击判定窗口 | `$global:__whaleDoubleMs` | 400ms |
| 拖动灵敏度 | `MouseMove` 中阈值 `4` | 4px |
| 残留清理区域 | `Remove-CornerArtifacts` 的 `$cx0/$cy0` | x≥254, y≥202 |

## 🗑️ 卸载

```powershell
# 1. 移除开机自启
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1

# 2. 右键悬浮窗 →「退出」关闭悬浮窗

# 3. 删除整个 Whaleplugin 文件夹
```

## ❓ 常见问题

**Q：悬浮窗没出现？**
A：确认 Harness 已在运行（`http://127.0.0.1:3080` 可访问）。`start-whale.ps1` 会等待端口最多 120s。也可查看 `src\launcher.log` 排查。

**Q：更换动图后重启又变回原图？**
A：更换的动图会复制到 `src\` 覆盖原文件并持久生效；若直接改动了 `src\working.gif`，重启后仍会使用新文件。

**Q：为什么 working 动图被自动"清理"过？**
A：原始工作动图右下角有抠图残留（绿幕/灰黑块），脚本按原图哈希识别并在加载时自动清除；**你替换的新动图不会被清理**。

**Q：双击灵敏度/拖动手感怎么调？**
A：见上表「配置」，修改 `src\whale-window.ps1` 后重启悬浮窗即可。

## 📄 开源许可

[MIT License](LICENSE)

## 🙏 致谢

- 基于 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 的公开 Web API 构建
