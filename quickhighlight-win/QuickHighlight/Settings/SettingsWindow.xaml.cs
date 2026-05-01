using System.Windows;
using System.Windows.Input;
using QuickHighlight.Hotkeys;
using QuickHighlight.Overlay;

namespace QuickHighlight.Settings;

public partial class SettingsWindow : Window
{
    private readonly SettingsStore _settings;
    private readonly GlobalHotkey _hotkeys;
    private readonly OverlayWindow _overlay;

    public SettingsWindow(SettingsStore settings, GlobalHotkey hotkeys, OverlayWindow overlay)
    {
        InitializeComponent();
        _settings = settings;
        _hotkeys = hotkeys;
        _overlay = overlay;
        DataContext = settings;
        ActivationCombo.ItemsSource = new[] { "LeftAlt", "RightAlt", "LeftShift", "RightShift", "LeftCtrl", "RightCtrl" };
        ShapeCombo.ItemsSource = Enum.GetValues<MagnifierShape>();
        ChordBox.Text = settings.ToggleShapeGesture.ToString();
        settings.PropertyChanged += (_, _) =>
        {
            settings.Save();
            _overlay.InvalidateLens();
        };
    }

    private void ChordBox_OnPreviewKeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        e.Handled = true;
        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        if (key is Key.LeftCtrl or Key.RightCtrl or Key.LeftAlt or Key.RightAlt or Key.LeftShift or Key.RightShift)
        {
            return;
        }

        var mods = Keyboard.Modifiers;
        if (mods == ModifierKeys.None)
        {
            ChordBox.Text = "组合键必须包含 Ctrl / Alt / Shift / Win";
            return;
        }

        _settings.ToggleShapeGesture = new ChordGesture(key, mods);
        _settings.Save();
        ChordBox.Text = _settings.ToggleShapeGesture.ToString();
        _hotkeys.RegisterToggleHotkey();
    }

    private void Reset_OnClick(object sender, RoutedEventArgs e)
    {
        _settings.ResetMagnifier();
        _overlay.InvalidateLens();
    }
}
