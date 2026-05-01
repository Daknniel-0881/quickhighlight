# 快捷高光 Windows

Windows 版快捷高光是一个 WPF/.NET 8 托盘应用：按住激活键后显示透明全屏 overlay，鼠标周围出现放大高光 lens，松开即隐藏。

## 安装

1. 安装 Windows 10 19041+ 或 Windows 11。
2. 下载 Release 里的 `QuickHighlight-win-x64.zip`。
3. 解压后运行 `QuickHighlight.exe`。
4. 托盘图标出现后，右键可打开“偏好设置”。

## 默认快捷键

- 按住 `LeftAlt`：显示放大高光。
- `Ctrl+Alt+S`：切换圆形 / 圆角矩形。

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
- 后台自动指数退避重连屏幕抓帧，最多 5 次。
- 默认不显示调试 UI。
