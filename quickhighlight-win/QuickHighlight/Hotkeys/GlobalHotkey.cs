using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows.Input;
using System.Windows.Interop;
using QuickHighlight.Settings;

namespace QuickHighlight.Hotkeys;

public sealed class GlobalHotkey : IDisposable
{
    private const int HotkeyIdToggleShape = 0x5148;
    private const int WM_HOTKEY = 0x0312;
    private const int WH_KEYBOARD_LL = 13;
    private const int WM_KEYDOWN = 0x0100;
    private const int WM_SYSKEYDOWN = 0x0104;
    private const int WM_KEYUP = 0x0101;
    private const int WM_SYSKEYUP = 0x0105;

    private readonly SettingsStore _settings;
    private readonly HwndSource _messageWindow;
    private readonly LowLevelKeyboardProc _keyboardProc;
    private nint _hook;
    private bool _activationDown;

    public event Action<bool>? ActivationChanged;
    public event Action? ToggleShapePressed;

    public GlobalHotkey(SettingsStore settings)
    {
        _settings = settings;
        var parameters = new HwndSourceParameters("QuickHighlightHotkeySink")
        {
            Width = 0,
            Height = 0,
            WindowStyle = 0x800000
        };
        _messageWindow = new HwndSource(parameters);
        _messageWindow.AddHook(WndProc);
        _keyboardProc = KeyboardHookCallback;
    }

    public void Start()
    {
        _hook = SetWindowsHookEx(WH_KEYBOARD_LL, _keyboardProc, GetModuleHandle(null), 0);
        RegisterToggleHotkey();
    }

    public void RegisterToggleHotkey()
    {
        UnregisterHotKey(_messageWindow.Handle, HotkeyIdToggleShape);
        var modifiers = ToNativeModifiers(_settings.ToggleShapeGesture.Modifiers);
        var vk = KeyInterop.VirtualKeyFromKey(_settings.ToggleShapeGesture.Key);
        if (!RegisterHotKey(_messageWindow.Handle, HotkeyIdToggleShape, modifiers, (uint)vk))
        {
            // Do not interrupt users. The settings UI keeps the chosen gesture visible;
            // users can pick another if this one is taken by the OS or another app.
            var error = Marshal.GetLastWin32Error();
            Console.Error.WriteLine($"QuickHighlight toggle hotkey registration failed: {error}");
        }
    }

    private nint WndProc(nint hwnd, int msg, nint wParam, nint lParam, ref bool handled)
    {
        if (msg == WM_HOTKEY && wParam.ToInt32() == HotkeyIdToggleShape)
        {
            ToggleShapePressed?.Invoke();
            handled = true;
        }
        return nint.Zero;
    }

    private nint KeyboardHookCallback(int nCode, nint wParam, nint lParam)
    {
        if (nCode >= 0)
        {
            var vkCode = Marshal.ReadInt32(lParam);
            if (IsActivationKey(vkCode))
            {
                var msg = wParam.ToInt32();
                var down = msg is WM_KEYDOWN or WM_SYSKEYDOWN;
                var up = msg is WM_KEYUP or WM_SYSKEYUP;
                if ((down || up) && down != _activationDown)
                {
                    _activationDown = down;
                    ActivationChanged?.Invoke(down);
                }
            }
        }

        return CallNextHookEx(_hook, nCode, wParam, lParam);
    }

    private bool IsActivationKey(int vkCode) => _settings.ActivationKey switch
    {
        "LeftAlt" => vkCode == 0xA4,
        "RightAlt" => vkCode == 0xA5,
        "LeftShift" => vkCode == 0xA0,
        "RightShift" => vkCode == 0xA1,
        "LeftCtrl" => vkCode == 0xA2,
        "RightCtrl" => vkCode == 0xA3,
        _ => vkCode == 0xA4
    };

    private static uint ToNativeModifiers(ModifierKeys modifiers)
    {
        uint native = 0;
        if (modifiers.HasFlag(ModifierKeys.Alt)) native |= 0x0001;
        if (modifiers.HasFlag(ModifierKeys.Control)) native |= 0x0002;
        if (modifiers.HasFlag(ModifierKeys.Shift)) native |= 0x0004;
        if (modifiers.HasFlag(ModifierKeys.Windows)) native |= 0x0008;
        native |= 0x4000; // MOD_NOREPEAT
        return native;
    }

    public void Dispose()
    {
        UnregisterHotKey(_messageWindow.Handle, HotkeyIdToggleShape);
        if (_hook != nint.Zero)
        {
            UnhookWindowsHookEx(_hook);
            _hook = nint.Zero;
        }
        _messageWindow.Dispose();
    }

    private delegate nint LowLevelKeyboardProc(int nCode, nint wParam, nint lParam);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(nint hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(nint hWnd, int id);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern nint SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, nint hMod, uint dwThreadId);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnhookWindowsHookEx(nint hhk);

    [DllImport("user32.dll")]
    private static extern nint CallNextHookEx(nint hhk, int nCode, nint wParam, nint lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern nint GetModuleHandle(string? lpModuleName);
}
