import Foundation
import Security

enum LicenseCredentialFailure: Equatable {
    case interactionNotAllowed
    case userCanceled
    case authenticationFailed
    case unavailable(OSStatus)
    case malformedValue
}

enum LicenseCredentialRead {
    /// A marker lookup deliberately requests no secret data.
    case found(Data?)
    case notFound
    case blocked(LicenseCredentialFailure)
}
