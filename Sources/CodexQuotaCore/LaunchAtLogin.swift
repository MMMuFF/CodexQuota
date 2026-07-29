public enum LaunchAtLoginStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case unavailable
}

public protocol LaunchAtLoginService: AnyObject {
    var status: LaunchAtLoginStatus { get }
    func register() throws
}

public enum LaunchAtLoginOutcome: Equatable, Sendable {
    case alreadyEnabled
    case registrationRequested
    case requiresApproval
    case unavailable
    case failed
    case alreadyHandled
}

public final class LaunchAtLoginCoordinator {
    private var didEnsure = false

    public init() {}

    public func ensureEnabled(
        using service: LaunchAtLoginService
    ) -> LaunchAtLoginOutcome {
        guard !didEnsure else { return .alreadyHandled }
        didEnsure = true

        switch service.status {
        case .enabled:
            return .alreadyEnabled
        case .requiresApproval:
            return .requiresApproval
        case .unavailable:
            return .unavailable
        case .notRegistered:
            do {
                try service.register()
                return .registrationRequested
            } catch {
                return .failed
            }
        }
    }
}
