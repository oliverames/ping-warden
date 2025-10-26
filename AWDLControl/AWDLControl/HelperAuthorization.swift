//
//  HelperAuthorization.swift
//  AWDLControl
//
//  Manages the privileged helper tool installation and communication.
//  Uses SMJobBless for one-time installation, then XPC for all operations.
//

import Foundation
import ServiceManagement
import Security

class HelperAuthorization {
    static let shared = HelperAuthorization()

    private let helperLabel = "com.awdlcontrol.helper"
    private var helperConnection: NSXPCConnection?

    private init() {}

    /// Install the privileged helper tool (prompts for password once)
    func installHelper() throws {
        var authRef: AuthorizationRef?
        var authItem = kSMRightBlessPrivilegedHelper.withCString { authorizationString in
            AuthorizationItem(name: authorizationString, valueLength: 0, value: nil, flags: 0)
        }

        var authRights = withUnsafeMutablePointer(to: &authItem) { pointer in
            AuthorizationRights(count: 1, items: pointer)
        }

        let authFlags: AuthorizationFlags = [.interactionAllowed, .extendRights, .preAuthorize]

        let status = AuthorizationCreate(&authRights, nil, authFlags, &authRef)
        guard status == errAuthorizationSuccess else {
            throw NSError(domain: "com.awdlcontrol.helper", code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Failed to create authorization reference"
            ])
        }

        defer {
            if let authRef = authRef {
                AuthorizationFree(authRef, [])
            }
        }

        // Bless the helper tool
        var error: Unmanaged<CFError>?
        let success = SMJobBless(kSMDomainSystemLaunchd, helperLabel as CFString, authRef, &error)

        if !success {
            if let err = error?.takeRetainedValue() {
                throw err
            } else {
                throw NSError(domain: "com.awdlcontrol.helper", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to install helper tool"
                ])
            }
        }

        print("HelperAuthorization: Helper tool installed successfully")
    }

    /// Check if helper is installed and running
    func isHelperInstalled() -> Bool {
        // Try to connect to the helper
        guard let connection = getHelperConnection() else {
            return false
        }

        var installed = false
        let semaphore = DispatchSemaphore(value: 0)

        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            print("HelperAuthorization: Error connecting to helper: \(error)")
            semaphore.signal()
        } as? AWDLHelperProtocol

        proxy?.getVersion { version in
            print("HelperAuthorization: Helper version: \(version)")
            installed = true
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 2.0)
        return installed
    }

    /// Get connection to the helper (creates if needed)
    private func getHelperConnection() -> NSXPCConnection? {
        if let existing = helperConnection {
            return existing
        }

        let connection = NSXPCConnection(machServiceName: helperLabel, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: AWDLHelperProtocol.self)

        connection.invalidationHandler = {
            print("HelperAuthorization: Helper connection invalidated")
            self.helperConnection = nil
        }

        connection.interruptionHandler = {
            print("HelperAuthorization: Helper connection interrupted")
        }

        connection.resume()
        helperConnection = connection
        return connection
    }

    /// Load the AWDL monitoring daemon via helper
    func loadDaemon() throws {
        guard let connection = getHelperConnection() else {
            throw NSError(domain: "com.awdlcontrol.helper", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Helper not installed"
            ])
        }

        var loadError: Error?
        let semaphore = DispatchSemaphore(value: 0)

        let proxy = connection.synchronousRemoteObjectProxyWithErrorHandler { error in
            loadError = error
            semaphore.signal()
        } as? AWDLHelperProtocol

        proxy?.loadDaemon { error in
            loadError = error
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 5.0)

        if let error = loadError {
            throw error
        }
    }

    /// Unload the AWDL monitoring daemon via helper
    func unloadDaemon() throws {
        guard let connection = getHelperConnection() else {
            throw NSError(domain: "com.awdlcontrol.helper", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Helper not installed"
            ])
        }

        var unloadError: Error?
        let semaphore = DispatchSemaphore(value: 0)

        let proxy = connection.synchronousRemoteObjectProxyWithErrorHandler { error in
            unloadError = error
            semaphore.signal()
        } as? AWDLHelperProtocol

        proxy?.unloadDaemon { error in
            unloadError = error
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 5.0)

        if let error = unloadError {
            throw error
        }
    }

    /// Check if daemon is loaded via helper
    func isDaemonLoaded() -> Bool {
        guard let connection = getHelperConnection() else {
            return false
        }

        var loaded = false
        let semaphore = DispatchSemaphore(value: 0)

        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            print("HelperAuthorization: Error checking daemon status: \(error)")
            semaphore.signal()
        } as? AWDLHelperProtocol

        proxy?.isDaemonLoaded { isLoaded in
            loaded = isLoaded
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 2.0)
        return loaded
    }
}
