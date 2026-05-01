using System.Windows;
using System.Windows.Media;
using MediaBrushes = System.Windows.Media.Brushes;
using MediaColor = System.Windows.Media.Color;
using MediaPen = System.Windows.Media.Pen;
using WpfPoint = System.Windows.Point;

namespace QuickHighlight.Settings;

public sealed class MagnifierPreview : FrameworkElement
{
    protected override void OnRender(DrawingContext dc)
    {
        base.OnRender(dc);
        if (DataContext is not SettingsStore settings)
        {
            settings = SettingsStore.Load();
        }

        var bounds = new Rect(0, 0, ActualWidth, ActualHeight);
        var bg = new LinearGradientBrush(MediaColor.FromRgb(245, 246, 248), MediaColor.FromRgb(218, 222, 230), 45);
        dc.DrawRectangle(bg, null, bounds);

        for (var x = 0.0; x < ActualWidth; x += 18)
        {
            dc.DrawLine(new MediaPen(new SolidColorBrush(MediaColor.FromArgb(28, 0, 0, 0)), 0.5), new WpfPoint(x, 0), new WpfPoint(x, ActualHeight));
        }

        for (var y = 0.0; y < ActualHeight; y += 18)
        {
            dc.DrawLine(new MediaPen(new SolidColorBrush(MediaColor.FromArgb(28, 0, 0, 0)), 0.5), new WpfPoint(0, y), new WpfPoint(ActualWidth, y));
        }

        var center = new WpfPoint(ActualWidth / 2, ActualHeight / 2);
        var width = settings.Shape == MagnifierShape.Circle
            ? Math.Min(settings.Radius, Math.Min(ActualWidth, ActualHeight) / 2 - 8) * 2
            : Math.Min(settings.RectWidth * 0.45, ActualWidth - 18);
        var height = settings.Shape == MagnifierShape.Circle
            ? width
            : Math.Min(settings.RectHeight * 0.45, ActualHeight - 18);
        var lens = new Rect(center.X - width / 2, center.Y - height / 2, width, height);
        Geometry lensGeometry = settings.Shape == MagnifierShape.Circle
            ? new EllipseGeometry(lens)
            : new RectangleGeometry(lens, 8, 8);

        var donut = new GeometryGroup { FillRule = FillRule.EvenOdd };
        donut.Children.Add(new RectangleGeometry(bounds));
        donut.Children.Add(lensGeometry);
        dc.DrawGeometry(new SolidColorBrush(MediaColor.FromArgb((byte)(settings.DimAlpha * 255), 0, 0, 0)), null, donut);

        dc.PushClip(lensGeometry);
        dc.PushTransform(new ScaleTransform(settings.Zoom, settings.Zoom, center.X, center.Y));
        var text = new FormattedText(
            "快捷高光 Aa 12345",
            Thread.CurrentThread.CurrentUICulture,
            System.Windows.FlowDirection.LeftToRight,
            new Typeface("Segoe UI"),
            18,
            MediaBrushes.Black,
            VisualTreeHelper.GetDpi(this).PixelsPerDip);
        dc.DrawText(text, new WpfPoint(center.X - text.Width / 2, center.Y - text.Height / 2));
        dc.Pop();
        dc.Pop();

        if (settings.ShowRing)
        {
            dc.DrawGeometry(null, new MediaPen(MediaBrushes.White, 2), lensGeometry);
            dc.DrawGeometry(null, new MediaPen(new SolidColorBrush(MediaColor.FromArgb(90, 0, 0, 0)), 1), lensGeometry);
        }
    }
}
