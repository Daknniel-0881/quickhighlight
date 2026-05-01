using System.Runtime.InteropServices;
using System.Runtime.InteropServices.WindowsRuntime;
using System.Threading;
using Windows.Graphics.Capture;
using Windows.Graphics.DirectX;
using Windows.Graphics.DirectX.Direct3D11;
using Windows.Graphics.Imaging;
using Windows.Graphics;
using WinRT;
using SharpDX.Direct3D;
using SharpDX.Direct3D11;
using SharpDX.DXGI;

namespace QuickHighlight.Capture;

public sealed class ScreenCapturer : IDisposable
{
    private const int MonitorDefaultToPrimary = 1;
    private readonly object _frameLock = new();
    private readonly SemaphoreSlim _lifecycleLock = new(1, 1);

    private SharpDX.Direct3D11.Device? _d3dDevice;
    private IDirect3DDevice? _direct3DDevice;
    private GraphicsCaptureItem? _item;
    private Direct3D11CaptureFramePool? _framePool;
    private GraphicsCaptureSession? _session;
    private SoftwareBitmap? _latestFrame;
    private SizeInt32 _lastSize;
    private int _processingFrame;
    private int _restartAttempts;
    private int _restartDelayMs = 1000;
    private bool _stopping;

    public event Action<bool>? CaptureHealthChanged;

    public SoftwareBitmap? LatestFrame
    {
        get
        {
            lock (_frameLock)
            {
                return _latestFrame is null ? null : SoftwareBitmap.Copy(_latestFrame);
            }
        }
    }

    public async Task StartAsync()
    {
        await _lifecycleLock.WaitAsync();
        try
        {
            if (_session is not null || _stopping) return;
            StartCore();
            CaptureHealthChanged?.Invoke(true);
            _restartAttempts = 0;
            _restartDelayMs = 1000;
        }
        catch
        {
            CaptureHealthChanged?.Invoke(false);
            _ = ScheduleRestartAsync();
        }
        finally
        {
            _lifecycleLock.Release();
        }
    }

    public async Task StopAsync()
    {
        await _lifecycleLock.WaitAsync();
        try
        {
            _stopping = true;
            StopCore(clearFrame: true);
        }
        finally
        {
            _lifecycleLock.Release();
        }
    }

    public async Task RestartNowAsync()
    {
        await _lifecycleLock.WaitAsync();
        try
        {
            _restartAttempts = 0;
            _restartDelayMs = 1000;
            StopCore(clearFrame: true);
            _stopping = false;
            StartCore();
            CaptureHealthChanged?.Invoke(true);
        }
        catch
        {
            CaptureHealthChanged?.Invoke(false);
            _ = ScheduleRestartAsync();
        }
        finally
        {
            _lifecycleLock.Release();
        }
    }

    private void StartCore()
    {
        if (!GraphicsCaptureSession.IsSupported())
        {
            throw new NotSupportedException("Windows.Graphics.Capture is not supported on this Windows build.");
        }

        _d3dDevice = new SharpDX.Direct3D11.Device(
            DriverType.Hardware,
            DeviceCreationFlags.BgraSupport);

        using var dxgiDevice = _d3dDevice.QueryInterface<SharpDX.DXGI.Device>();
        var hr = CreateDirect3D11DeviceFromDXGIDevice(dxgiDevice.NativePointer, out var inspectable);
        Marshal.ThrowExceptionForHR(hr);
        _direct3DDevice = MarshalInterface<IDirect3DDevice>.FromAbi(inspectable);
        Marshal.Release(inspectable);

        var monitor = MonitorFromPoint(new POINT(0, 0), MonitorDefaultToPrimary);
        _item = CreateItemForMonitor(monitor);
        _item.Closed += OnCaptureItemClosed;
        _lastSize = _item.Size;

        _framePool = Direct3D11CaptureFramePool.CreateFreeThreaded(
            _direct3DDevice,
            DirectXPixelFormat.B8G8R8A8UIntNormalized,
            2,
            _lastSize);
        _framePool.FrameArrived += OnFrameArrived;

        _session = _framePool.CreateCaptureSession(_item);
        TryDisableCursorCapture(_session);
        _session.StartCapture();
    }

    private void StopCore(bool clearFrame)
    {
        if (_item is not null)
        {
            _item.Closed -= OnCaptureItemClosed;
        }

        if (_framePool is not null)
        {
            _framePool.FrameArrived -= OnFrameArrived;
        }

        _session?.Dispose();
        _framePool?.Dispose();
        _d3dDevice?.Dispose();
        _session = null;
        _framePool = null;
        _item = null;
        _direct3DDevice = null;
        _d3dDevice = null;

        if (clearFrame)
        {
            lock (_frameLock)
            {
                _latestFrame?.Dispose();
                _latestFrame = null;
            }
        }
    }

    private async void OnFrameArrived(Direct3D11CaptureFramePool sender, object args)
    {
        if (Interlocked.Exchange(ref _processingFrame, 1) == 1) return;
        try
        {
            using var frame = sender.TryGetNextFrame();
            if (frame is null) return;

            if (frame.ContentSize.Width != _lastSize.Width || frame.ContentSize.Height != _lastSize.Height)
            {
                _lastSize = frame.ContentSize;
                sender.Recreate(
                    _direct3DDevice,
                    DirectXPixelFormat.B8G8R8A8UIntNormalized,
                    2,
                    _lastSize);
            }

            using var bitmap = await SoftwareBitmap.CreateCopyFromSurfaceAsync(frame.Surface);
            var converted = SoftwareBitmap.Convert(bitmap, BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied);
            lock (_frameLock)
            {
                _latestFrame?.Dispose();
                _latestFrame = converted;
            }
            CaptureHealthChanged?.Invoke(true);
        }
        catch
        {
            CaptureHealthChanged?.Invoke(false);
            _ = ScheduleRestartAsync();
        }
        finally
        {
            Interlocked.Exchange(ref _processingFrame, 0);
        }
    }

    private void OnCaptureItemClosed(GraphicsCaptureItem sender, object args)
    {
        CaptureHealthChanged?.Invoke(false);
        _ = ScheduleRestartAsync();
    }

    private async Task ScheduleRestartAsync()
    {
        if (_stopping || _restartAttempts >= 5) return;
        var delay = _restartDelayMs;
        _restartAttempts++;
        _restartDelayMs = Math.Min(_restartDelayMs * 2, 30_000);
        await Task.Delay(delay);
        if (_stopping) return;

        await _lifecycleLock.WaitAsync();
        try
        {
            StopCore(clearFrame: true);
            StartCore();
            CaptureHealthChanged?.Invoke(true);
            _restartAttempts = 0;
            _restartDelayMs = 1000;
        }
        catch
        {
            CaptureHealthChanged?.Invoke(false);
            _ = ScheduleRestartAsync();
        }
        finally
        {
            _lifecycleLock.Release();
        }
    }

    private static GraphicsCaptureItem CreateItemForMonitor(nint monitor)
    {
        var interop = GraphicsCaptureItem.As<IGraphicsCaptureItemInterop>();
        var itemPtr = interop.CreateForMonitor(monitor, GraphicsCaptureItemGuid);
        try
        {
            return GraphicsCaptureItem.FromAbi(itemPtr);
        }
        finally
        {
            Marshal.Release(itemPtr);
        }
    }

    private static void TryDisableCursorCapture(GraphicsCaptureSession session)
    {
        try
        {
            session.IsCursorCaptureEnabled = false;
        }
        catch
        {
            // Older Windows builds may not expose the property. Capturing cursor is not fatal.
        }
    }

    public void Dispose()
    {
        _stopping = true;
        StopCore(clearFrame: true);
        _lifecycleLock.Dispose();
    }

    private static readonly Guid GraphicsCaptureItemGuid =
        new("79C3F95B-31F7-4EC2-A464-632EF5D30760");

    [DllImport("d3d11.dll", ExactSpelling = true)]
    private static extern int CreateDirect3D11DeviceFromDXGIDevice(nint dxgiDevice, out nint graphicsDevice);

    [DllImport("user32.dll")]
    private static extern nint MonitorFromPoint(POINT pt, int flags);

    [ComImport]
    [Guid("3628E81B-3CAC-4C60-B7F4-23CE0E0C3356")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    [ComVisible(true)]
    private interface IGraphicsCaptureItemInterop
    {
        nint CreateForWindow(nint window, in Guid iid);
        nint CreateForMonitor(nint monitor, in Guid iid);
    }

    [StructLayout(LayoutKind.Sequential)]
    private readonly struct POINT
    {
        public POINT(int x, int y)
        {
            X = x;
            Y = y;
        }

        public readonly int X;
        public readonly int Y;
    }
}
