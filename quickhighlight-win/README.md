# 快捷高光 Windows

Windows 版快捷高光是一个 WPF/.NET 8 托盘应用：按住激活键后显示透明全屏 overlay，鼠标周围出现放大高光 lens，松开即隐藏。交互和 macOS 版保持一致：抓不到屏幕帧时不弹窗、不在 lens 里画错误文字，只通过托盘轻提示并静默自愈。

## 安装

1. 安装 Windows 10 19041+ 或 Windows 11。
2. 下载 Release 里的 `QuickHighlight-win-x64.zip`。
3. 解压后运行 `QuickHighlight.exe`。
4. 托盘图标出现后，右键可打开“偏好设置”。

## 默认快捷键

- 按住 `LeftAlt`：显示放大高光。
- `Ctrl+Alt+S`：切换圆形 / 圆角矩形。

## 放大倍率怎么生效

Zoom 的逻辑和 macOS 版一样：

1. 用 `Windows.Graphics.Capture` 持续抓主屏帧。
2. 鼠标在哪里，就从屏幕帧里裁一小块区域。
3. 裁剪尺寸 = `lensSize / zoom`，比如 2x 就只裁 lens 一半大的源画面。
4. 再把这块小画面拉伸回完整 lens，所以你看到的就是放大后的细节。

如果托盘图标显示抓帧暂时不可用，说明当前没有拿到屏幕帧。此时不是倍率数学失效，而是没有“原材料”可以放大；lens 会保持透明高光，后台低频探测并自动恢复。

## 构建

需要 .NET 8 SDK：

```powershell
cd quickhighlight-win
.\build.ps1
```

输出文件位于：

```text
quickhighlight-win/artifacts/QuickHighlight-win-x64.zip
```

## 体验约束

- 抓帧失败不会弹窗，也不会在 lens 里画错误文字。
- 抓帧失败时 lens 内保持透明，只保留暗化 donut 和高光边框。
- 收到第一帧后才把托盘状态标记为健康，避免“看起来已连接但 Zoom 没画面”的误判。
- 后台自动指数退避重连屏幕抓帧，连续失败后进入低频探测；恢复后自动接上。
- 高 DPI 下使用物理像素计算 crop，再按 WPF DPI 转回 lens 尺寸，避免 125%/150% 缩放时倍率偏差。
- 默认不显示调试 UI。
