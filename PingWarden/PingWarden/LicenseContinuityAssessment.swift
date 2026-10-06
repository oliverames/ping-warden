import Foundation

/// Inactive diagnostics over caller-supplied values. This is not an entitlement
/// gate or a capture adapter. It opens no store and never requests verification.
/// App-target file, not Core: LicenseCredentialRead is app-local.
enum LicenseContinuityAssessment {
    struct Input {
        let cache: MigrationRead<[String: MigrationStoredValue]>
        let observedAt: Date
        let deviceIdentifier: MigrationRead<String>
        /// nil means no observation, not a missing Keychain item.
        let credential: LicenseCredentialRead?
        let grandfatherMarker: LicenseCredentialRead?
        let legacyMigrationMarker: LicenseCredentialRead?
        let helperEnabled: Bool?
        /// Already observed by the caller. Never obtained by this component.
        let verification: VerificationObservation
    }

    enum VerificationObservation: Equatable {
        case notRequested, pending, unavailable
        /// These labels describe supplied evidence, not a durable handoff proof.
        case reportedValid, reportedRevoked, reportedInvalidKey
    }

    enum CredentialObservation: Equatable {
        case notObserved, absent, malformed, exceedsAssessmentLimit
        /// Recognizable syntax does not establish purchase or destination access.
        case readableSyntaxOnly
        case blocked(LicenseCredentialFailure)
    }

    enum MarkerObservation: Equatable {
        case notObserved, present, absent
        case blocked(LicenseCredentialFailure)
    }

    enum CacheObservation: Equatable {
        case unavailable, absent, malformed, unsupportedTimestamp
        case legacyUnsealed
        case deviceIdentifierUnavailable
        case sealMismatch
        case sealMatchesSuppliedDevice
    }

    enum ClockObservation: Equatable { case notAssessed, plausible, implausible }

    /// Describes the stored claim's time window, independently of seal trust.
    /// For unsealed values this records the old policy's claim, not authorization.
    enum PaidWindow: Equatable {
        case notAssessed, noPaidClaim, missingVerificationTime
        case withinOriginalWindow, outsideOriginalWindow
    }

    enum TransitionWindow: Equatable { case notAssessed, absent, active, expired }

    enum SealedPolicyObservation: Equatable {
        case notEstablished, clockRejected, noCurrentCachedEntitlement
        case paidCacheFitsExistingPolicy, transitionOnlyFitsExistingPolicy
    }

    enum LegacyTransitionObservation: Equatable {
        case notApplicable, noOriginalDeadline, markersUnresolved
        case alreadyAttempted, helperUnobserved, originalEvidenceInsufficient
        /// Only describes the original deadline and supplied prior-use evidence.
        /// It never creates a grant, seals state, or writes a one-shot marker.
        case originalDeadlinePlausible
    }

    enum UnresolvedReason: Equatable {
        case integration(MigrationCutoverBlocker)
        case cacheUnavailable, cacheAbsent, cacheMalformed, unsupportedTimestamp
        case legacyStateRequiresPreflight, deviceBindingNotEstablished, sealMismatch
        case clockNeedsReview, noCurrentCachedEntitlement
        case credentialNeedsExplicitHandling, markerAccessUnresolved
        case verificationNotObserved, verificationPending, verificationUnavailable
        case reportedDenialNeedsHandling, reportedSuccessNeedsBoundHandoff
    }

    struct Report {
        let observedAt: Date
        let credential: CredentialObservation
        let grandfatherMarker: MarkerObservation
        let legacyMigrationMarker: MarkerObservation
        let verification: VerificationObservation
        var cache: CacheObservation
        var clock: ClockObservation = .notAssessed
        var paidWindow: PaidWindow = .notAssessed
        var lastVerifiedAt: Date?
        var originalOfflineExpiry: Date?
        var originalTransitionDeadline: Date?
        var transitionWindow: TransitionWindow = .notAssessed
        var legacyTransition: LegacyTransitionObservation = .notApplicable

        /// A local-cache characterization only. Separately reported verification
        /// outcomes are not committed here, and this never grants feature access.
        var sealedPolicy: SealedPolicyObservation {
            guard cache == .sealMatchesSuppliedDevice else { return .notEstablished }
            guard clock == .plausible else { return .clockRejected }
            if paidWindow == .withinOriginalWindow { return .paidCacheFitsExistingPolicy }
            if LicensePolicy.canEnableProtection(
                cachedLicenseValid: false, lastVerifiedAt: nil,
                now: observedAt, grandfatherDeadline: originalTransitionDeadline
            ) { return .transitionOnlyFitsExistingPolicy }
            return .noCurrentCachedEntitlement
        }

        var unresolvedReasons: [UnresolvedReason] {
            var reasons = MigrationCutoverBlocker.permanent.map { UnresolvedReason.integration($0) }
            switch cache {
            case .unavailable: reasons.append(.cacheUnavailable)
            case .absent: reasons.append(.cacheAbsent)
            case .malformed: reasons.append(.cacheMalformed)
            case .unsupportedTimestamp: reasons.append(.unsupportedTimestamp)
            case .legacyUnsealed: reasons.append(.legacyStateRequiresPreflight)
            case .deviceIdentifierUnavailable: reasons.append(.deviceBindingNotEstablished)
            case .sealMismatch: reasons.append(.sealMismatch)
            case .sealMatchesSuppliedDevice:
                if sealedPolicy == .noCurrentCachedEntitlement { reasons.append(.noCurrentCachedEntitlement) }
            }
            if clock == .implausible { reasons.append(.clockNeedsReview) }
            if credential != .readableSyntaxOnly { reasons.append(.credentialNeedsExplicitHandling) }
            if [grandfatherMarker, legacyMigrationMarker].contains(where: {
                switch $0 {
                case .notObserved, .blocked: return true
                case .present, .absent: return false
                }
            }) { reasons.append(.markerAccessUnresolved) }
            switch verification {
            case .notRequested: reasons.append(.verificationNotObserved)
            case .pending: reasons.append(.verificationPending)
            case .unavailable: reasons.append(.verificationUnavailable)
            case .reportedValid: reasons.append(.reportedSuccessNeedsBoundHandoff)
            case .reportedRevoked, .reportedInvalidKey: reasons.append(.reportedDenialNeedsHandling)
            }
            return reasons
        }

        /// There is deliberately no success or cutover-ready case.
        enum Disposition { case retainOriginalInstallation }
        var disposition: Disposition { .retainOriginalInstallation }
        /// No assessment can relax the snapshot's permanent integration gates.
        var cutoverReadiness: MigrationCutoverReadiness {
            MigrationCutoverReadiness(status: .notReady, reasons: MigrationCutoverBlocker.permanent)
        }
    }

    /// The only callback is a nonescaping, read-only seal comparison.
    /// A future caller may pass LicenseStateSeal.matches(_:payload:), which
    /// computes an HMAC without resolving a device identifier or accessing stores.
    /// Callers must not supply a matcher that performs I/O or mints persisted state.
    static func assess(
        _ input: Input,
        matchesSeal: (_ stored: String, _ payload: String) -> Bool
    ) -> Report {
        let grandfather = marker(input.grandfatherMarker)
        let migrated = marker(input.legacyMigrationMarker)
        var report = Report(
            observedAt: input.observedAt,
            credential: credential(input.credential),
            grandfatherMarker: grandfather,
            legacyMigrationMarker: migrated,
            verification: input.verification,
            cache: .unavailable
        )
        guard supportedTimestamp(input.observedAt.timeIntervalSince1970) else {
            report.cache = .unsupportedTimestamp
            return report
        }
        let values: [String: MigrationStoredValue]
        switch input.cache {
        case .unavailable: return report
        case .absent:
            report.cache = .absent
            return report
        case .available(let captured): values = captured
        }

        let format = MigrationSnapshotBuilder.classifyLicenseCache(values)
        guard format != .malformed else {
            report.cache = .malformed
            return report
        }
        guard format != .absent else {
            report.cache = .absent
            return report
        }
        for key in ["LicenseLastVerifiedAt", "LicenseGrandfatherDeadline", "LicenseLastSeenAt"] {
            if case .real(let timestamp)? = values[key], !supportedTimestamp(timestamp) {
                report.cache = .unsupportedTimestamp
                return report
            }
        }
        let paidClaim = flag("LicenseCachedValid", in: values)
        let verified = date("LicenseLastVerifiedAt", in: values)
        let deadline = date("LicenseGrandfatherDeadline", in: values)
        let lastSeen = date("LicenseLastSeenAt", in: values)
        report.lastVerifiedAt = verified
        report.originalOfflineExpiry = verified?.addingTimeInterval(LicensePolicy.offlineGraceInterval)
        report.originalTransitionDeadline = deadline
        report.clock = LicensePolicy.clockIsPlausible(
            now: input.observedAt, lastVerifiedAt: verified, lastSeenAt: lastSeen
        ) ? .plausible : .implausible
        if !paidClaim {
            report.paidWindow = .noPaidClaim
        } else if verified == nil {
            report.paidWindow = .missingVerificationTime
        } else {
            report.paidWindow = LicensePolicy.canEnableProtection(
                cachedLicenseValid: paidClaim, lastVerifiedAt: verified,
                now: input.observedAt, grandfatherDeadline: nil
            ) ? .withinOriginalWindow : .outsideOriginalWindow
        }
        report.transitionWindow = deadline.map {
            input.observedAt < $0 ? .active : .expired
        } ?? .absent

        if format == .legacyUnsealed {
            report.cache = .legacyUnsealed
            report.legacyTransition = legacyTransition(
                values: values, originalDeadline: deadline,
                grandfather: grandfather, migrated: migrated,
                helperEnabled: input.helperEnabled, now: input.observedAt
            )
            return report
        }

        guard case .available(let deviceIdentifier) = input.deviceIdentifier,
              UUID(uuidString: deviceIdentifier) != nil else {
            // The existing seal helper's fallback strings cannot establish
            // device binding. Do not silently treat them as hardware identities.
            report.cache = .deviceIdentifierUnavailable
            return report
        }
        guard case .string(let storedSeal)? = values["LicenseStateSeal"] else {
            report.cache = .malformed
            return report
        }
        let payload = LicensePolicy.sealPayload(
            cachedLicenseValid: paidClaim, lastVerifiedAt: verified,
            grandfatherDeadline: deadline, lastSeenAt: lastSeen,
            deviceIdentifier: deviceIdentifier
        )
        report.cache = matchesSeal(storedSeal, payload) ? .sealMatchesSuppliedDevice : .sealMismatch
        return report
    }

    private static func credential(_ read: LicenseCredentialRead?) -> CredentialObservation {
        guard let read else { return .notObserved }
        switch read {
        case .notFound: return .absent
        case .blocked(let failure): return .blocked(failure)
        case .found(let bytes):
            guard let bytes else { return .malformed }
            // A diagnostic bound, not a new production license-key rule.
            guard bytes.count <= 4096 else { return .exceedsAssessmentLimit }
            guard let text = String(data: bytes, encoding: .utf8),
                  LicensePolicy.normalizeKey(text) != nil else { return .malformed }
            return .readableSyntaxOnly
        }
    }

    private static func marker(_ read: LicenseCredentialRead?) -> MarkerObservation {
        guard let read else { return .notObserved }
        switch read {
        case .found: return .present // Marker lookups intentionally contain no data.
        case .notFound: return .absent
        case .blocked(let failure): return .blocked(failure)
        }
    }

    private static func legacyTransition(
        values: [String: MigrationStoredValue], originalDeadline: Date?,
        grandfather: MarkerObservation, migrated: MarkerObservation,
        helperEnabled: Bool?, now: Date
    ) -> LegacyTransitionObservation {
        guard let originalDeadline else { return .noOriginalDeadline }
        if migrated == .present { return .alreadyAttempted }
        guard migrated == .absent,
              grandfather == .present || grandfather == .absent else {
            return .markersUnresolved
        }
        guard let helperEnabled else { return .helperUnobserved }
        let plausible = LicensePolicy.legacyGrandfatherDeadline(
            timestamp: originalDeadline.timeIntervalSince1970,
            previouslyChecked: grandfather == .present || flag("LicenseGrandfatherChecked", in: values),
            helperEnabled: helperEnabled, now: now
        )
        return plausible == nil ? .originalEvidenceInsufficient : .originalDeadlinePlausible
    }

    private static func flag(_ key: String, in values: [String: MigrationStoredValue]) -> Bool {
        if case .bool(let value)? = values[key] { return value }
        return false
    }

    private static func date(_ key: String, in values: [String: MigrationStoredValue]) -> Date? {
        guard case .real(let timestamp)? = values[key], timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    private static func supportedTimestamp(_ timestamp: Double) -> Bool {
        // Reject nonfinite and extreme values before sealPayload converts to Int.
        // This bounded diagnostic profile does not change production coercions.
        timestamp.isFinite && timestamp >= 0 && timestamp <= 1_000_000_000_000
    }
}
