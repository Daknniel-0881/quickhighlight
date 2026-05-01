using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Forms;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using QuickHighlight.Capture;
using QuickHighlight.Settings;

namespace QuickHighlight.Overlay;

public partial class OverlayWindow : Window
{
    private const int GWL_EXSTYLE = -20;
    private const int WS_EX_TRANSPARENT = 0x00000020;
    private const int WS_EX_TOOLWINDOW = 0x00000080;
    private const int WS_EX_LAYERED = 0x00080000;

    private readonly DispatcherTimer _timer;

    public OverlayWindow(SettingsStore settings, ScreenCapturer capturer)
    {
        InitializeComponent();
        Surface.Configure(settings, capturer);

        var bounds = Screen.PrimaryScreen?.Bounds ?? new System.Drawing.Rectangle(0, 0, 1920, 1080);
        Left = bounds.Left;
        Top = bounds.Top;
        Width = SystemParameters.PrimaryScreenWidth;
        Height = SystemParameters.PrimaryScreenHeight;

        _timer = new DispatcherTimer(DispatcherPriority.Render)
        {
            Interval = TimeSpan.FromSeconds(1.0 / 60.0)
        };
        _timer.Tick += (_, _) => Surface.UpdateCursorAndInvalidate();
        SourceInitialized += (_, _) => MakeMouseTransparent();
        Hide();
    }

    public void ShowOverlay()
    {
        if (!IsVisible) Show();
        _timer.Start();
    }

    public void HideOverlay()
    {
        _timer.Stop();
        Hide();
    }

    public void InvalidateLens() => Surface.InvalidateVisual();

    private void MakeMouseTransparent()
    {
        var hwnd = new WindowInteropHelper(this).Handle;
        var exStyle = GetWindowLong(hwnd, GWL_EXSTYLE);
        SetWindowLong(hwnd, GWL_EXSTYLE, exStyle | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW | WS_EX_LAYERED);
    }

    [DllImport("user32.dll")]
    private static extern int GetWindowLong(nint hwnd, int index);

    [DllImport("user32.dll")]
    private static extern int SetWindowLong(nint hwnd, int index, int value);
}
