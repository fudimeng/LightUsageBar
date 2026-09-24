import Foundation

/// Reads Claude Code's OAuth login from the Keychain and renews the access token when it expires.
///
/// Claude Code only renews this token when its CLI makes a request, and the desktop app keeps
/// its own login elsewhere, so without renewal the token here goes stale within hours.
/// The renewed token is written back to the same Keychain item exactly as Claude Code does,
/// so the CLI keeps working with it.
enum ClaudeCredentials {
    private static let service = "Claude Code-credentials"
    // Values used by Claude Code itself (TOKEN_URL and CLIENT_ID in its OAuth config).
    private static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    /// Renew slightly early so a request never starts with a token about to lapse.
    private static let renewalMargin: TimeInterval = 5 * 60

    struct Login {
        let token: String
        let plan: String?
    }

    static func login(forceRefresh: Bool = false) async throws -> Login {
        let stored = try readKeychain()
        let oauth = try loginSection(stored)
        guard let access = oauth["accessToken"] as? String else { throw UsageError.unavailable(L10n.signIn) }
        let plan = PlanName.claude(oauth["subscriptionType"] as? String)
        if !forceRefresh, isFresh(oauth) { return Login(token: access, plan: plan) }
        return Login(token: try await renew(previousAccess: access), plan: plan)
    }

    static func renewForDiagnostics() async throws -> String {
        _ = try await login(forceRefresh: true)
        let oauth = try loginSection(try readKeychain())
        let expiry = Date(timeIntervalSince1970: ((oauth["expiresAt"] as? Double) ?? 0) / 1000)
        return expiry.formatted(date: .abbreviated, time: .shortened)
    }

    private static func renew(previousAccess: String) async throws -> String {
        // The server rotates the refresh token on every renewal, so two clients renewing at once
        // could strand one of them. Take the same lock Claude Code takes, then re-check.
        let lock = try await ClaudeRefreshLock.acquire()
        defer { lock.release() }

        var current = try readKeychain()
        var currentOAuth = try loginSection(current)
        if let currentAccess = currentOAuth["accessToken"] as? String, currentAccess != previousAccess, isFresh(currentOAuth) {
            return currentAccess
        }
        guard let refreshToken = currentOAuth["refreshToken"] as? String else { throw UsageError.unavailable(L10n.loginInvalid) }
        var body: [String: Any] = ["grant_type": "refresh_token", "refresh_token": refreshToken, "client_id": clientID]
        if let scopes = currentOAuth["scopes"] as? [String], !scopes.isEmpty { body["scope"] = scopes.joined(separator: " ") }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Stay well inside the lock's 60-second stale window.
        request.timeoutInterval = 20
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200: break
        // invalid_grant and friends: the refresh token itself is no longer valid.
        case 400, 401, 403: throw UsageError.unavailable(L10n.loginInvalid)
        default: throw UsageError.unavailable("\(L10n.renewFailed) (HTTP \(status))")
        }
        guard let reply = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newAccess = reply["access_token"] as? String,
              let expiresIn = reply["expires_in"] as? Double else {
            throw UsageError.unavailable(L10n.renewFailed)
        }

        let now = Date().timeIntervalSince1970
        currentOAuth["accessToken"] = newAccess
        currentOAuth["expiresAt"] = Int64((now + expiresIn) * 1000)
        // Like Claude Code: keep the old refresh token when the server does not issue a new one.
        currentOAuth["refreshToken"] = (reply["refresh_token"] as? String) ?? refreshToken
        if let refreshExpiresIn = reply["refresh_token_expires_in"] as? Double {
            currentOAuth["refreshTokenExpiresAt"] = Int64((now + refreshExpiresIn) * 1000)
        }
        if let scope = reply["scope"] as? String, !scope.isEmpty {
            currentOAuth["scopes"] = scope.split(separator: " ").map(String.init)
        }
        current["claudeAiOauth"] = currentOAuth
        try writeKeychain(current)
        return newAccess
    }

    private static func isFresh(_ oauth: [String: Any]) -> Bool {
        guard let expiresAt = oauth["expiresAt"] as? Double else { return false }
        return expiresAt / 1000 - renewalMargin > Date().timeIntervalSince1970
    }

    private static func loginSection(_ stored: [String: Any]) throws -> [String: Any] {
        guard let oauth = stored["claudeAiOauth"] as? [String: Any] else { throw UsageError.unavailable(L10n.signIn) }
        return oauth
    }

    private static func readKeychain() throws -> [String: Any] {
        let value: String
        switch ProcessRunner.run("/usr/bin/security", ["find-generic-password", "-s", service, "-w"], timeout: 60) {
        case .success(let output): value = output
        case .timedOut: throw UsageError.unavailable(L10n.keychainPending)
        // errSecItemNotFound: Claude Code has never stored a login on this Mac.
        case .failed(let status) where status == 44: throw UsageError.unavailable(L10n.signIn)
        case .failed, .launchFailed: throw UsageError.unavailable(L10n.keychainDenied)
        }
        guard let data = value.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageError.unavailable(L10n.signIn)
        }
        return json
    }

    /// Mirrors Claude Code's own write: update the item in place with a hex-encoded payload.
    private static func writeKeychain(_ json: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: json, options: .withoutEscapingSlashes)
        let hex = data.map { String(format: "%02x", $0) }.joined()
        let arguments = ["add-generic-password", "-U", "-a", NSUserName(), "-s", service, "-X", hex]
        guard case .success = ProcessRunner.run("/usr/bin/security", arguments, timeout: 20) else {
            throw UsageError.unavailable(L10n.writeBackFailed)
        }
    }
}

/// The cross-process lock Claude Code holds while renewing its token.
///
/// Claude Code uses proper-lockfile: a lock is a directory created atomically with mkdir,
/// considered stale once its modification time is older than 60 seconds. It takes a current
/// lock inside the config directory and a legacy lock beside it; this holds both the same way.
struct ClaudeRefreshLock {
    private static let staleAfter: TimeInterval = 60
    private let held: [String]

    static func acquire() async throws -> ClaudeRefreshLock {
        let configDirectory = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude")
        let paths = [
            configDirectory.appendingPathComponent(".oauth_refresh.lock").path,
            configDirectory.resolvingSymlinksInPath().path + ".lock",
        ]
        // Claude Code retries five times with a one-to-two second pause; match that patience.
        for attempt in 0..<6 {
            var held: [String] = []
            for path in paths {
                guard lockDirectory(path) else { break }
                held.append(path)
            }
            if held.count == paths.count { return ClaudeRefreshLock(held: held) }
            held.reversed().forEach { rmdir($0) }
            if attempt < 5 { try await Task.sleep(for: .milliseconds(1000 + Int.random(in: 0..<1000))) }
        }
        throw UsageError.unavailable(L10n.renewBusy)
    }

    func release() { held.reversed().forEach { rmdir($0) } }

    /// Creates the lock directory, reclaiming it first if its holder stopped updating it.
    private static func lockDirectory(_ path: String) -> Bool {
        if mkdir(path, 0o755) == 0 { return true }
        guard errno == EEXIST,
              let modified = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) > staleAfter else { return false }
        rmdir(path)
        return mkdir(path, 0o755) == 0
    }
}
