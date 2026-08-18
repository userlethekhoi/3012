import Foundation

public struct AccessRoute: Equatable, Sendable {
    public let selected: AccessProbe?
    public let probes: [AccessProbe]
    public let requiresFreshSession: Bool

    public init(selected: AccessProbe?, probes: [AccessProbe], requiresFreshSession: Bool) {
        self.selected = selected
        self.probes = probes
        self.requiresFreshSession = requiresFreshSession
    }
}

public struct AccessProviderRouter: Sendable {
    private let providers: [any DeviceAccessProvider]
    private let supportMatrix: AccessSupportMatrix

    public init(
        providers: [any DeviceAccessProvider],
        supportMatrix: AccessSupportMatrix = AccessSupportMatrix()
    ) {
        self.providers = providers
        self.supportMatrix = supportMatrix
    }

    public func route(
        context: DeviceAccessContext,
        disablePolicy: ProviderDisablePolicy = ProviderDisablePolicy()
    ) async -> AccessRoute {
        var probes: [AccessProbe] = []
        var privilegedAttemptStarted = false

        for provider in providers {
            guard supportMatrix.allows(provider.id, context: context),
                  disablePolicy.allows(provider.id, build: context.systemBuild) else {
                continue
            }
            if privilegedAttemptStarted { break }

            let probe = await provider.probe(context: context)
            probes.append(probe)
            if probe.outcome == .available {
                return AccessRoute(selected: probe, probes: probes, requiresFreshSession: false)
            }
            if probe.stage >= .privilegedAttempt {
                privilegedAttemptStarted = true
            }
        }

        return AccessRoute(
            selected: nil,
            probes: probes,
            requiresFreshSession: privilegedAttemptStarted
        )
    }
}
