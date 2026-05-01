using System.Windows.Input;
using QuickHighlight.Settings;

namespace QuickHighlight.Hotkeys;

public static class ChordRecorder
{
    public static bool TryCreate(System.Windows.Input.KeyEventArgs e, out ChordGesture gesture)
    {
        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        var modifiers = Keyboard.Modifiers;
        if (key is Key.LeftAlt or Key.RightAlt or Key.LeftCtrl or Key.RightCtrl or Key.LeftShift or Key.RightShift ||
            modifiers == ModifierKeys.None)
        {
            gesture = default;
            return false;
        }

        gesture = new ChordGesture(key, modifiers);
        return true;
    }
}
