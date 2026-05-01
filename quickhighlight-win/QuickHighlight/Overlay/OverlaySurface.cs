using System.Runtime.InteropServices;
using System.Runtime.InteropServices.WindowsRuntime;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using QuickHighlight.Capture;
using QuickHighlight.Settings;
using Windows.Graphics.Imaging;
using MediaBrushes = System.Windows.Media.Brushes;
using MediaColor = System.Windows.Media.Color;
using MediaPen = System.Windows.Media.Pen;
using WinForms = System.Windows.Forms;
using WpfSize = System.Windows.Size;

namespace QuickHighlight.Overlay;

public sealed class OverlaySurface : FrameworkElement
{
    private SettingsStore? _settings;
    private ScreenCapturer? _capturer;
    private System.Windows.Point _cursor;
    private System.Drawing.Point _cursorScreenPixel;
    private bool _cursorOnPrimaryScreen = true;

    public void Configure(SettingsStore settings, ScreenCapturer capturer)
    {
        _settings = settings;
        _capturer = capturer;
    }

    public void UpdateCursorAndInvalidate()
    {
        if (GetCursorPos(out var point))
        {
            var dpi = VisualTreeHelper.GetDpi(this);
            var primaryBounds = WinForms.Screen.PrimaryScreen?.Bounds
                ?? new System.Drawing.Rectangle(0, 0, 1920, 1080);
            _cursorScreenPixel = new System.Drawing.Point(point.X, point.Y);
            _cursorOnPrimaryScreen = primaryBounds.Contains(_cursorScreenPixel);
            _cursor = new System.Windows.Point(
                (point.X - primaryBounds.Left) / dpi.DpiScaleX,
                (point.Y - primaryBounds.Top) / dpi.DpiScaleY);
        }
        InvalidateVisual();
    }

    protected override void OnRender(DrawingContext dc)
    {
        base.OnRender(dc);
        if (_settings is null || _capturer is null) return;

        var bounds = new Rect(0, 0, ActualWidth, ActualHeight);
        var inner = new WpfSize(_settings.InnerWidth, _settings.InnerHeight);
        var lens = new Rect(
            _cursor.X - inner.Width / 2,
            _cursor.Y - inner.Height / 2,
            inner.Width,
            inner.Height);
        Geometry lensGeometry = _settings.Shape == MagnifierShape.Circle
            ? new EllipseGeometry(lens)
            : new RectangleGeometry(lens, 8, 8);

        var donut = new GeometryGroup { FillRule = FillRule.EvenOdd };
        donut.Children.Add(new RectangleGeometry(bounds));
        donut.Children.Add(lensGeometry);
        dc.DrawGeometry(
            new SolidColorBrush(MediaColor.FromArgb((byte)(_settings.DimAlpha * 255), 0, 0, 0)),
            null,
            donut);

        DrawMagnifiedFrame(dc, lens, lensGeometry, _settings, _capturer);

        if (_settings.ShowRing)
        {
            dc.DrawGeometry(null, new MediaPen(new SolidColorBrush(MediaColor.FromArgb(220, 255, 255, 255)), 2), lensGeometry);
            dc.DrawGeometry(null, new MediaPen(new SolidColorBrush(MediaColor.FromArgb(90, 0, 0, 0)), 1), lensGeometry);
        }

        if (_settings.ShowZoomLabel)
        {
            var text = new FormattedText(
                $"{_settings.Zoom:F1}x",
                Thread.CurrentThread.CurrentUICulture,
                System.Windows.FlowDirection.LeftToRight,
                new Typeface("Segoe UI Semibold"),
                14,
                MediaBrushes.White,
                VisualTreeHelper.GetDpi(this).PixelsPerDip);
            dc.DrawText(text, new System.Windows.Point(_cursor.X - text.Width / 2, lens.Bottom + 6));
        }
    }

    private void DrawMagnifiedFrame(
        DrawingContext dc,
        Rect lens,
        Geometry lensGeometry,
        SettingsStore settings,
        ScreenCapturer capturer)
    {
        using var frame = capturer.LatestFrame;
        if (frame is null || !_cursorOnPrimaryScreen)
        {
            return;
        }

        try
        {
            using var converted = SoftwareBitmap.Convert(frame, BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied);
            var source = ToBitmapSource(converted);
            var dpi = VisualTreeHelper.GetDpi(this);
            var primaryBounds = WinForms.Screen.PrimaryScreen?.Bounds
                ?? new System.Drawing.Rectangle(0, 0, source.PixelWidth, source.PixelHeight);
            var scaleX = source.PixelWidth / Math.Max((double)primaryBounds.Width, 1);
            var scaleY = source.PixelHeight / Math.Max((double)primaryBounds.Height, 1);

            var cropWidthPx = Math.Max(1, (int)Math.Round((lens.Width * dpi.DpiScaleX / settings.Zoom) * scaleX));
            var cropHeightPx = Math.Max(1, (int)Math.Round((lens.Height * dpi.DpiScaleY / settings.Zoom) * scaleY));
            var cursorPxX = (int)Math.Round((_cursorScreenPixel.X - primaryBounds.Left) * scaleX);
            var cursorPxY = (int)Math.Round((_cursorScreenPixel.Y - primaryBounds.Top) * scaleY);
            var cropX = Math.Clamp(cursorPxX - cropWidthPx / 2, 0, Math.Max(0, source.PixelWidth - cropWidthPx));
            var cropY = Math.Clamp(cursorPxY - cropHeightPx / 2, 0, Math.Max(0, source.PixelHeight - cropHeightPx));
            cropWidthPx = Math.Min(cropWidthPx, source.PixelWidth - cropX);
            cropHeightPx = Math.Min(cropHeightPx, source.PixelHeight - cropY);
            if (cropWidthPx <= 0 || cropHeightPx <= 0) return;

            var cropped = new CroppedBitmap(source, new Int32Rect(cropX, cropY, cropWidthPx, cropHeightPx));
            dc.PushClip(lensGeometry);
            dc.DrawImage(cropped, lens);
            dc.Pop();
        }
        catch
        {
            // UX rule: never draw error text or warning colors inside the lens.
        }
    }

    private static BitmapSource ToBitmapSource(SoftwareBitmap bitmap)
    {
        var width = bitmap.PixelWidth;
        var height = bitmap.PixelHeight;
        var stride = width * 4;
        var bytes = new byte[stride * height];
        bitmap.CopyToBuffer(bytes.AsBuffer());
        var source = BitmapSource.Create(
            width,
            height,
            96,
            96,
            PixelFormats.Bgra32,
            null,
            bytes,
            stride);
        source.Freeze();
        return source;
    }

    [DllImport("user32.dll")]
    private static extern bool GetCursorPos(out POINT lpPoint);

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT
    {
        public int X;
        public int Y;
    }
}
