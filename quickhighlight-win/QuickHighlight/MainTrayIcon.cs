using System.Drawing;
using System.Windows.Forms;
using QuickHighlight.Capture;
using QuickHighlight.Settings;

namespace QuickHighlight;

public sealed class MainTrayIcon : IDisposable
{
    private readonly NotifyIcon _notifyIcon;
    private readonly ScreenCapturer _capturer;

    public MainTrayIcon(
        SettingsStore settings,
        ScreenCapturer capturer,
        Action openSettings,
        Action quit)
    {
        _capturer = capturer;
        _notifyIcon = new NotifyIcon
        {
            Text = "快捷高光",
            Icon = SystemIcons.Information,
            Visible = true,
            ContextMenuStrip = new ContextMenuStrip()
        };

        _notifyIcon.ContextMenuStrip.Items.Add("偏好设置...", null, (_, _) => openSettings());
        _notifyIcon.ContextMenuStrip.Items.Add("重新连接屏幕抓帧", null, async (_, _) =>
        {
            _notifyIcon.Text = "快捷高光（正在重连屏幕抓帧...）";
            await _capturer.RestartNowAsync();
        });
        _notifyIcon.ContextMenuStrip.Items.Add(new ToolStripSeparator());
        _notifyIcon.ContextMenuStrip.Items.Add("退出 快捷高光", null, (_, _) => quit());
        _notifyIcon.DoubleClick += (_, _) => openSettings();

        SetCaptureHealthy(true);
    }

    public void SetCaptureHealthy(bool healthy)
    {
        _notifyIcon.Icon = healthy ? SystemIcons.Information : SystemIcons.Warning;
        _notifyIcon.Text = healthy
            ? "快捷高光"
            : "快捷高光（屏幕抓帧暂时不可用，正在静默重连）";
    }

    public void Dispose()
    {
        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
    }
}
