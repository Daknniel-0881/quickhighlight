enum CaptureRecoveryAction {
    case startCapture
    case probePermission
    case stop
}

enum CaptureRecoveryPolicy {
    static func action(
        hasReceivedFrameSinceLaunch: Bool,
        preflightGranted: Bool,
        restartAttempts: Int,
        maxRestartAttempts: Int
    ) -> CaptureRecoveryAction {
        if preflightGranted || hasReceivedFrameSinceLaunch {
            return restartAttempts >= maxRestartAttempts ? .stop : .startCapture
        }
        return .probePermission
    }
}
