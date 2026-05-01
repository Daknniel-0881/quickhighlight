namespace QuickHighlight.Capture;

internal enum CaptureRecoveryAction
{
    StartCapture,
    ProbeAvailability,
    Stop
}

internal static class CaptureRecoveryPolicy
{
    public static CaptureRecoveryAction Decide(
        bool captureSupported,
        bool hasReceivedFrame,
        int restartAttempts,
        int maxRestartAttempts)
    {
        if (!captureSupported)
        {
            return CaptureRecoveryAction.ProbeAvailability;
        }

        if (!hasReceivedFrame && restartAttempts >= maxRestartAttempts)
        {
            return CaptureRecoveryAction.ProbeAvailability;
        }

        return CaptureRecoveryAction.StartCapture;
    }
}
