//
//  GeForceNOWDiscovery.swift
//  PingWarden
//
//  Asynchronously discovers GeForce NOW datacenter zones from the public
//  status API and returns them as PingTarget entries the dashboard can probe.
//

import Foundation

enum GeForceNOWDiscovery {
    private static let endpoint = URL(string: "https://status.geforcenow.com/api/v2/components.json")
    private static let zoneCodePattern = #"\bNP[A]?-[A-Z0-9-]+\b"#

    /// Zone codes from the last successful fetch, kept in memory for the
    /// process and in defaults across launches. `DashboardViewModel` is a
    /// `@StateObject` that is rebuilt every time the Dashboard or Targets
    /// pane appears, so without this a saved GeForce NOW target could not
    /// be matched until a fresh network round-trip finished, and the shared
    /// probe spent those seconds measuring a fallback target instead.
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var memoryCache: (codes: [String], fetchedAt: Date)?
    private static let cachedCodesKey = "DashboardGFNZoneCodes"
    private static let cachedAtKey = "DashboardGFNZoneCodesFetchedAt"
    private static let cacheRetention: TimeInterval = 30 * 24 * 3600

    /// The last successfully discovered zones, or `nil` when nothing has
    /// been fetched yet on this Mac (or the persisted copy is too old to
    /// trust). Cheap and synchronous, so a fresh view model can build its
    /// full target list before it registers a probe demand.
    static func cachedTargets(userDefaults: UserDefaults = .standard) -> (targets: [PingTarget], fetchedAt: Date)? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let memoryCache {
            return (makeTargets(fromCodes: memoryCache.codes), memoryCache.fetchedAt)
        }
        guard let codes = userDefaults.stringArray(forKey: cachedCodesKey), !codes.isEmpty else {
            return nil
        }
        let fetchedAt = Date(timeIntervalSince1970: userDefaults.double(forKey: cachedAtKey))
        guard Date().timeIntervalSince(fetchedAt) < cacheRetention else { return nil }
        let validCodes = codes.filter { !extractZoneCodes(from: [$0]).isEmpty }
        guard !validCodes.isEmpty else { return nil }
        memoryCache = (validCodes, fetchedAt)
        return (makeTargets(fromCodes: validCodes), fetchedAt)
    }

    private static func storeCache(codes: [String], fetchedAt: Date, userDefaults: UserDefaults = .standard) {
        cacheLock.lock()
        memoryCache = (codes, fetchedAt)
        cacheLock.unlock()
        userDefaults.set(codes, forKey: cachedCodesKey)
        userDefaults.set(fetchedAt.timeIntervalSince1970, forKey: cachedAtKey)
    }

    /// Remove both cache tiers. Used by the removal flow.
    static func clearCache(userDefaults: UserDefaults = .standard) {
        cacheLock.lock()
        memoryCache = nil
        cacheLock.unlock()
        userDefaults.removeObject(forKey: cachedCodesKey)
        userDefaults.removeObject(forKey: cachedAtKey)
    }

    private static func makeTargets(fromCodes codes: [String]) -> [PingTarget] {
        codes.sorted().map { code in
            PingTarget(
                displayName: "GeForce NOW (\(code))",
                host: "\(code.lowercased()).cloudmatchbeta.nvidiagrid.net",
                port: 443,
                source: .geforceNow
            )
        }
    }

    private struct ComponentsResponse: Decodable {
        let components: [Component]
    }

    private struct Component: Decodable {
        let name: String
    }

    /// Returns the discovered zone targets, or `nil` when the fetch failed
    /// (network error, non-2xx, decode failure). `nil` is distinct from a
    /// successful-but-empty response so callers can keep previously
    /// discovered zones on a transient failure instead of wiping them —
    /// which would silently reset the user's selected GFN target.
    static func fetchTargets() async -> [PingTarget]? {
        guard let endpoint else { return nil }

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 8

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            let payload = try JSONDecoder().decode(ComponentsResponse.self, from: data)
            let codes = Array(extractZoneCodes(from: payload.components.map(\.name))).sorted()
            // An empty list is a successful answer that says "no zones";
            // keep the previous cache rather than persisting nothing.
            if !codes.isEmpty {
                storeCache(codes: codes, fetchedAt: Date())
            }
            return makeTargets(fromCodes: codes)
        } catch {
            return nil
        }
    }

    private static func extractZoneCodes(from componentNames: [String]) -> Set<String> {
        guard let regex = try? NSRegularExpression(pattern: zoneCodePattern) else {
            return []
        }

        var codes = Set<String>()

        for name in componentNames {
            let uppercasedName = name.uppercased()
            let nameNSString = uppercasedName as NSString
            let range = NSRange(location: 0, length: nameNSString.length)
            let matches = regex.matches(in: uppercasedName, range: range)

            for match in matches {
                codes.insert(nameNSString.substring(with: match.range))
            }
        }

        return codes
    }
}
