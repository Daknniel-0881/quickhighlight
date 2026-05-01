using System.ComponentModel;
using System.IO;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Windows.Input;

namespace QuickHighlight.Settings;

public enum MagnifierShape
{
    Circle,
    RoundedRect
}

public sealed class SettingsStore : INotifyPropertyChanged
{
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };

    private string _activationKey = "LeftAlt";
    private MagnifierShape _shape = MagnifierShape.Circle;
    private double _radius = 150;
    private double _rectWidth = 360;
    private double _rectHeight = 220;
    private double _zoom = 1.5;
    private double _dimAlpha = 0.6;
    private bool _showRing = true;
    private bool _showZoomLabel;
    private bool _sharpenEnabled = true;
    private ChordGesture _toggleShapeGesture = new(Key.S, ModifierKeys.Control | ModifierKeys.Alt);

    public event PropertyChangedEventHandler? PropertyChanged;

    public string ActivationKey
    {
        get => _activationKey;
        set => SetField(ref _activationKey, value);
    }

    public MagnifierShape Shape
    {
        get => _shape;
        set => SetField(ref _shape, value);
    }

    public double Radius
    {
        get => _radius;
        set => SetField(ref _radius, Math.Clamp(value, 50, 400));
    }

    public double RectWidth
    {
        get => _rectWidth;
        set => SetField(ref _rectWidth, Math.Clamp(value, 100, 800));
    }

    public double RectHeight
    {
        get => _rectHeight;
        set => SetField(ref _rectHeight, Math.Clamp(value, 30, 600));
    }

    public double Zoom
    {
        get => _zoom;
        set => SetField(ref _zoom, Math.Clamp(value, 1.0, 6.0));
    }

    public double DimAlpha
    {
        get => _dimAlpha;
        set => SetField(ref _dimAlpha, Math.Clamp(value, 0, 0.9));
    }

    public bool ShowRing
    {
        get => _showRing;
        set => SetField(ref _showRing, value);
    }

    public bool ShowZoomLabel
    {
        get => _showZoomLabel;
        set => SetField(ref _showZoomLabel, value);
    }

    public bool SharpenEnabled
    {
        get => _sharpenEnabled;
        set => SetField(ref _sharpenEnabled, value);
    }

    public ChordGesture ToggleShapeGesture
    {
        get => _toggleShapeGesture;
        set => SetField(ref _toggleShapeGesture, value);
    }

    public double InnerWidth => Shape == MagnifierShape.Circle ? Radius * 2 : RectWidth;
    public double InnerHeight => Shape == MagnifierShape.Circle ? Radius * 2 : RectHeight;

    public static string SettingsPath
    {
        get
        {
            var dir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                "QuickHighlight");
            Directory.CreateDirectory(dir);
            return Path.Combine(dir, "settings.json");
        }
    }

    public static SettingsStore Load()
    {
        try
        {
            if (File.Exists(SettingsPath))
            {
                return JsonSerializer.Deserialize<SettingsStore>(
                    File.ReadAllText(SettingsPath),
                    JsonOptions) ?? new SettingsStore();
            }
        }
        catch
        {
            // Broken settings should never block the overlay. Fall back silently.
        }

        return new SettingsStore();
    }

    public void Save()
    {
        File.WriteAllText(SettingsPath, JsonSerializer.Serialize(this, JsonOptions));
    }

    public void ResetMagnifier()
    {
        Radius = 150;
        RectWidth = 360;
        RectHeight = 220;
        Zoom = 1.5;
        DimAlpha = 0.6;
        ShowRing = true;
        Shape = MagnifierShape.Circle;
        Save();
    }

    private void SetField<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return;
        field = value;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        if (propertyName is nameof(Radius) or nameof(RectWidth) or nameof(RectHeight) or nameof(Shape))
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(InnerWidth)));
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(InnerHeight)));
        }
    }
}

public readonly record struct ChordGesture(Key Key, ModifierKeys Modifiers)
{
    public override string ToString()
    {
        var parts = new List<string>();
        if (Modifiers.HasFlag(ModifierKeys.Control)) parts.Add("Ctrl");
        if (Modifiers.HasFlag(ModifierKeys.Alt)) parts.Add("Alt");
        if (Modifiers.HasFlag(ModifierKeys.Shift)) parts.Add("Shift");
        if (Modifiers.HasFlag(ModifierKeys.Windows)) parts.Add("Win");
        parts.Add(Key.ToString());
        return string.Join("+", parts);
    }
}
