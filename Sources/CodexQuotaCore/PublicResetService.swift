import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol PublicResetServicing {
    func fetch() async throws -> PublicResetStatus
}

public actor PublicResetService: PublicResetServicing {
    private let session: URLSession
    private var cached: PublicResetStatus?
    private var etag: String?
    private var retryAt = Date.distantPast

    public init(configuration: URLSessionConfiguration = .ephemeral) {
        let configuration = configuration.copy() as! URLSessionConfiguration
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        session = URLSession(configuration: configuration, delegate: PublicResetSessionDelegate(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    public func fetch() async throws -> PublicResetStatus {
        guard Date() >= retryAt else { throw PublicResetError.retryLater }
        var request = URLRequest(url: URL(string: "https://codex-resets.com/api/v1/status")!)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw PublicResetError.invalidResponse }
        if response.statusCode == 429 {
            let value = response.value(forHTTPHeaderField: "Retry-After") ?? "300"
            let seconds: TimeInterval
            if let parsed = Double(value), parsed.isFinite {
                seconds = max(60, parsed)
            } else {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = .gmt
                formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                seconds = max(60, formatter.date(from: value)?.timeIntervalSinceNow ?? 300)
            }
            retryAt = Date().addingTimeInterval(seconds)
            throw PublicResetError.retryLater
        }
        if response.statusCode == 304, let cached { return cached }
        guard response.statusCode == 200 else { throw PublicResetError.unavailable }
        let status = try PublicResetStatus.parse(data)
        cached = status
        let newTag = response.value(forHTTPHeaderField: "ETag")
        etag = newTag.flatMap { $0.count <= 512 && !$0.contains("\r") && !$0.contains("\n") ? $0 : nil }
        return status
    }
}

private final class PublicResetSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
