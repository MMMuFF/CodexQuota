import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public final class QuotaService {
    public init() {}

    public func fetch(forceTokenRefresh: Bool) async throws -> QuotaStatus {
        let executableURL = try CodexExecutableLocator.locate()
        let messages = AppServerRequestFactory.fetchRequests(
            forceTokenRefresh: forceTokenRefresh
        )
        let output = try await AppServerClient(executableURL: executableURL).run(messages)
        let accountResult = try output.result(for: AppServerRequestFactory.accountRequestID)
        let rateLimitResult = try output.result(for: AppServerRequestFactory.operationRequestID)
        let parsed = try RateLimitParser.parse(
            accountResult: accountResult,
            rateLimitResult: rateLimitResult
        )

        // The context is short-lived and is never returned, logged, or persisted.
        let auth = AuthFileParser.loadCurrent()
        let accountFingerprint = AccountIdentityParser.fingerprint(
            authAccountID: auth.accountID
        )
        var warnings: [String] = []
        var availableCount = parsed.resetCreditsAvailableCount
        var nearestExpiration = parsed.nearestResetCreditExpiresAt

        let shouldUseHTTPSFallback = nearestExpiration == nil
            && !parsed.hasResetCreditDetails
            && availableCount != 0
        if shouldUseHTTPSFallback {
            if let accessToken = auth.accessToken, let accountID = auth.accountID {
                do {
                    let fallback = try await ResetCreditHTTPClient().fetch(
                        accessToken: accessToken,
                        accountID: accountID
                    )
                    // Keep app-server's count when it was available; it is the canonical snapshot.
                    availableCount = availableCount ?? fallback.availableCount
                    nearestExpiration = fallback.nearestExpiresAt
                    if nearestExpiration == nil {
                        if availableCount == nil {
                            warnings.append("重置券详情暂不可用")
                        } else if (availableCount ?? 0) > 0 {
                            warnings.append("重置券到期时间暂不可用")
                        }
                    }
                } catch {
                    warnings.append(
                        availableCount == nil
                            ? "重置券详情暂不可用"
                            : "重置券到期时间暂不可用"
                    )
                }
            } else {
                warnings.append(
                    availableCount == nil
                        ? "重置券详情暂不可用"
                        : "重置券到期时间暂不可用"
                )
            }
        }

        let planType = parsed.planType ?? auth.planType
        if auth.subscriptionActiveUntil == nil, planType?.lowercased() == "pro" {
            warnings.append("未读取到会员到期时间")
        }

        return QuotaStatus(
            remainingPercent: parsed.remainingPercent,
            resetsAt: parsed.resetsAt,
            windowDurationMins: parsed.windowDurationMins,
            planType: planType,
            subscriptionActiveUntil: auth.subscriptionActiveUntil,
            resetCreditsAvailableCount: availableCount,
            nearestResetCreditExpiresAt: nearestExpiration,
            fetchedAt: Date(),
            warnings: warnings,
            accountFingerprint: accountFingerprint
        )
    }

    public func consumeResetCredit(
        expectedAccountFingerprint: String,
        idempotencyKey: UUID = UUID()
    ) async throws -> ResetCreditConsumeResult {
        let executableURL = try CodexExecutableLocator.locate()
        let messages = AppServerRequestFactory.consumeRequests(
            idempotencyKey: idempotencyKey
        )
        let output = try await AppServerClient(executableURL: executableURL).run(
            messages,
            expectedAccountFingerprint: expectedAccountFingerprint
        )
        _ = try output.result(for: AppServerRequestFactory.accountRequestID)
        let consumeResult = try output.result(for: AppServerRequestFactory.operationRequestID)
        return try ResetCreditConsumeParser.parse(consumeResult)
    }
}

enum CodexExecutableLocator {
    static func locate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> URL {
        let candidates = candidatePaths(environment: environment)
        for candidate in candidates {
            if fileManager.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate, isDirectory: false)
            }
        }
        throw QuotaServiceError.codexExecutableNotFound
    }

    static func candidatePaths(environment: [String: String]) -> [String] {
        var candidates: [String] = []
        if let override = environment["CODEX_QUOTA_CODEX_PATH"], !override.isEmpty {
            candidates.append((override as NSString).expandingTildeInPath)
        }

        candidates.append("/Applications/ChatGPT.app/Contents/Resources/codex")
        return candidates
    }
}

enum AppServerRequestFactory {
    static let accountRequestID = 1
    static let operationRequestID = 2

    static func fetchRequests(forceTokenRefresh: Bool) -> [JSONDictionary] {
        baseRequests(forceTokenRefresh: forceTokenRefresh) + [
            [
                "id": operationRequestID,
                "method": "account/rateLimits/read",
                "params": JSONDictionary()
            ]
        ]
    }

    static func consumeRequests(idempotencyKey: UUID) -> [JSONDictionary] {
        baseRequests(forceTokenRefresh: true) + [
            [
                "id": operationRequestID,
                "method": "account/rateLimitResetCredit/consume",
                "params": ["idempotencyKey": idempotencyKey.uuidString]
            ]
        ]
    }

    private static func baseRequests(forceTokenRefresh: Bool) -> [JSONDictionary] {
        [
            [
                "id": 0,
                "method": "initialize",
                "params": [
                    "clientInfo": [
                        "name": "codex-quota",
                        "title": "Codex Quota",
                        "version": "1.0.0"
                    ]
                ]
            ],
            ["method": "initialized"],
            [
                "id": accountRequestID,
                "method": "account/read",
                "params": ["refreshToken": forceTokenRefresh]
            ]
        ]
    }
}

private struct AppServerClient {
    let executableURL: URL

    func run(
        _ messages: [JSONDictionary],
        expectedAccountFingerprint: String? = nil
    ) async throws -> AppServerOutput {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    continuation.resume(
                        returning: try runSynchronously(
                            messages,
                            expectedAccountFingerprint: expectedAccountFingerprint
                        )
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runSynchronously(
        _ messages: [JSONDictionary],
        expectedAccountFingerprint: String?
    ) throws -> AppServerOutput {
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw QuotaServiceError.codexLaunchFailed
        }

        let timeoutState = ProcessTimeoutState()
        let timeoutWorkItem = DispatchWorkItem {
            if process.isRunning {
                timeoutState.markTimedOut()
                process.terminate()
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + 20,
            execute: timeoutWorkItem
        )
        defer { timeoutWorkItem.cancel() }

        var reader = JSONLineReader(handle: outputPipe.fileHandleForReading)
        var envelopes: [JSONDictionary] = []
        do {
            for message in messages {
                var data = try JSONSerialization.data(withJSONObject: message)
                data.append(0x0A)
                try inputPipe.fileHandleForWriting.write(contentsOf: data)

                guard let requestID = JSONValue.int(message["id"]) else {
                    continue
                }
                let received = try reader.readEnvelopes(untilResponseFor: requestID)
                envelopes.append(contentsOf: received)

                // Validate each response before sending the next request. This is especially
                // important for consume: no mutation is sent when account/read failed.
                _ = try AppServerOutput(envelopes: received).result(
                    for: requestID
                )
                if requestID == AppServerRequestFactory.accountRequestID,
                   let expectedAccountFingerprint {
                    let currentAuth = AuthFileParser.loadCurrent()
                    let currentFingerprint = AccountIdentityParser.fingerprint(
                        authAccountID: currentAuth.accountID
                    )
                    try ResetCreditAccountGuard.validate(
                        expectedFingerprint: expectedAccountFingerprint,
                        currentFingerprint: currentFingerprint
                    )
                }
            }
            try inputPipe.fileHandleForWriting.close()
            envelopes.append(contentsOf: try reader.readRemainingEnvelopes())
        } catch {
            try? inputPipe.fileHandleForWriting.close()
            let processWasRunning = process.isRunning
            if processWasRunning {
                process.terminate()
                process.waitUntilExit()
            }
            if timeoutState.didTimeOut {
                throw QuotaServiceError.appServerTimedOut
            }
            if !processWasRunning, process.terminationStatus != 0 {
                throw QuotaServiceError.codexExited(process.terminationStatus)
            }
            throw error
        }

        process.waitUntilExit()
        if timeoutState.didTimeOut {
            throw QuotaServiceError.appServerTimedOut
        }
        guard process.terminationStatus == 0 else {
            throw QuotaServiceError.codexExited(process.terminationStatus)
        }
        return try AppServerOutput(envelopes: envelopes)
    }
}

private final class ProcessTimeoutState {
    private let lock = NSLock()
    private var value = false

    var didTimeOut: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func markTimedOut() {
        lock.lock()
        value = true
        lock.unlock()
    }
}

struct AppServerOutput {
    private let envelopes: [JSONDictionary]

    init(data: Data) throws {
        guard let text = String(data: data, encoding: .utf8) else {
            throw QuotaServiceError.malformedAppServerResponse
        }
        try self.init(envelopes: text.split(whereSeparator: \Character.isNewline).compactMap { line in
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else {
                return nil
            }
            return JSONValue.dictionary(object)
        })
    }

    init(envelopes: [JSONDictionary]) throws {
        if envelopes.isEmpty {
            throw QuotaServiceError.malformedAppServerResponse
        }
        self.envelopes = envelopes
    }

    func result(for requestID: Int) throws -> Any {
        guard let envelope = envelopes.first(where: {
            JSONValue.int($0["id"]) == requestID
        }) else {
            throw QuotaServiceError.malformedAppServerResponse
        }
        if let error = JSONValue.dictionary(envelope["error"]) {
            let code = JSONValue.int(error["code"])
            let suffix = code.map { "（\($0)）" } ?? ""
            throw QuotaServiceError.appServerRequestFailed("请求被拒绝\(suffix)")
        }
        guard let result = envelope["result"] else {
            throw QuotaServiceError.malformedAppServerResponse
        }
        return result
    }
}

struct JSONLineReader {
    let handle: FileHandle
    private var buffer = Data()

    mutating func readEnvelopes(untilResponseFor requestID: Int) throws -> [JSONDictionary] {
        var received: [JSONDictionary] = []
        while let envelope = try readEnvelope() {
            received.append(envelope)
            if JSONValue.int(envelope["id"]) == requestID,
               envelope["result"] != nil || envelope["error"] != nil {
                return received
            }
        }
        throw QuotaServiceError.malformedAppServerResponse
    }

    mutating func readRemainingEnvelopes() throws -> [JSONDictionary] {
        var received: [JSONDictionary] = []
        while let envelope = try readEnvelope() {
            received.append(envelope)
        }
        return received
    }

    private mutating func readEnvelope() throws -> JSONDictionary? {
        while let line = try readLine() {
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: line),
                  let envelope = JSONValue.dictionary(object) else {
                continue
            }
            return envelope
        }
        return nil
    }

    private mutating func readLine() throws -> Data? {
        while true {
            if let newlineIndex = buffer.firstIndex(of: 0x0A) {
                var line = Data(buffer[..<newlineIndex])
                buffer.removeSubrange(...newlineIndex)
                if line.last == 0x0D {
                    line.removeLast()
                }
                return line
            }

            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                guard !buffer.isEmpty else {
                    return nil
                }
                let finalLine = buffer
                buffer.removeAll(keepingCapacity: false)
                return finalLine
            }
            buffer.append(chunk)
        }
    }
}

struct EphemeralAuthContext {
    let accessToken: String?
    let accountID: String?
    let subscriptionActiveUntil: Date?
    let planType: String?

    static let empty = EphemeralAuthContext(
        accessToken: nil,
        accountID: nil,
        subscriptionActiveUntil: nil,
        planType: nil
    )
}

enum AuthFileParser {
    static func loadCurrent(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> EphemeralAuthContext {
        let authURL: URL
        if let codexHome = environment["CODEX_HOME"], !codexHome.isEmpty {
            authURL = URL(fileURLWithPath: (codexHome as NSString).expandingTildeInPath)
                .appendingPathComponent("auth.json")
        } else {
            authURL = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
                .appendingPathComponent("auth.json")
        }
        guard let data = try? Data(contentsOf: authURL) else {
            return .empty
        }
        return parse(data) ?? .empty
    }

    static func parse(_ data: Data) -> EphemeralAuthContext? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? JSONDictionary,
              let tokens = JSONValue.dictionary(root["tokens"]) else {
            return nil
        }

        let accessToken = JSONValue.string(
            JSONValue.value(in: tokens, keys: ["access_token", "accessToken"])
        )
        let idToken = JSONValue.string(
            JSONValue.value(in: tokens, keys: ["id_token", "idToken"])
        )
        let accountID = JSONValue.string(
            JSONValue.value(in: tokens, keys: ["account_id", "accountId"])
        ) ?? accessToken.flatMap(JWTClaimParser.accountID)
            ?? idToken.flatMap(JWTClaimParser.accountID)

        return EphemeralAuthContext(
            accessToken: accessToken,
            accountID: accountID,
            subscriptionActiveUntil: idToken.flatMap(JWTClaimParser.subscriptionActiveUntil),
            planType: idToken.flatMap(JWTClaimParser.planType)
                ?? accessToken.flatMap(JWTClaimParser.planType)
        )
    }
}

private struct ResetCreditHTTPClient {
    private let endpoint = URL(
        string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits"
    )!

    func fetch(
        accessToken: String,
        accountID: String
    ) async throws -> ParsedResetCreditSummary {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15

        let delegate = ResetCreditURLSessionDelegate()
        let session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.url?.scheme?.lowercased() == "https",
              httpResponse.url?.host?.lowercased() == "chatgpt.com",
              (200..<300).contains(httpResponse.statusCode) else {
            throw QuotaServiceError.malformedAppServerResponse
        }
        return try ResetCreditParser.parseHTTPResponse(data)
    }
}

private final class ResetCreditURLSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(ResetCreditRedirectPolicy.redirectedRequest(request))
    }
}
