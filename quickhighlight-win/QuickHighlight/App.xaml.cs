using System.Windows;
using QuickHighlight.Capture;
using QuickHighlight.Hotkeys;
using QuickHighlight.Overlay;
using QuickHighlight.Settings;

namespace QuickHighlight;

public partial class App : System.Windows.Application
{
    private SettingsStore _settings = null!;
    private ScreenCapturer _capturer = null!;
    private OverlayWindow _overlay = null!;
    private GlobalHotkey _hotkeys = null!;
    private MainTrayIcon _tray = null!;

    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        _settings = SettingsStore.Load();
        _capturer = new ScreenCapturer();
        _overlay = new OverlayWindow(_settings, _capturer);
        _tray = new MainTrayIcon(_settings, _capturer, ShowSettings, Shutdown);

        _capturer.CaptureHealthChanged += healthy =>
            Dispatcher.Invoke(() => _tray.SetCaptureHealthy(healthy));

        _hotkeys = new GlobalHotkey(_settings);
        _hotkeys.ActivationChanged += isDown =>
            Dispatcher.Invoke(isDown ? _overlay.ShowOverlay : _overlay.HideOverlay);
        _hotkeys.ToggleShapePressed += () =>
            Dispatcher.Invoke(() =>
            {
                _settings.Shape = _settings.Shape == MagnifierShape.Circle
                    ? MagnifierShape.RoundedRect
                    : MagnifierShape.Circle;
                _settings.Save();
                _overlay.InvalidateLens();
            });
        _hotkeys.Start();

        await _capturer.StartAsync();

        if (e.Args.Contains("--settings", StringComparer.OrdinalIgnoreCase))
        {
            ShowSettings();
        }
    }

    private void ShowSettings()
    {
        var window = new SettingsWindow(_settings, _hotkeys, _overlay);
        window.Owner = _overlay.IsVisible ? _overlay : null;
        window.Show();
        window.Activate();
    }

    protected override async void OnExit(ExitEventArgs e)
    {
        _hotkeys.Dispose();
        _tray.Dispose();
        _overlay.Close();
        await _capturer.StopAsync();
        _capturer.Dispose();
        base.OnExit(e);
    }
}
