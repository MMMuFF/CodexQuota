import Foundation
import CodexQuotaCore

private final class PublicResetURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var status = 200
    private static var body = Data()
    private static var headers: [String: String] = [:]
    private static var requests: [URLRequest] = []

    static func configure(_ status: Int, body: Data = Data(), headers: [String: String] = [:]) {
        lock.withLock { self.status = status; self.body = body; self.headers = headers }
    }
    static func captured() -> [URLRequest] { lock.withLock { requests } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, body, headers) = Self.lock.withLock {
            Self.requests.append(request)
            return (Self.status, Self.body, Self.headers)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

enum PublicResetHTTPTests {
    static let fixture = Data("""
    {"data":{"latest_reset":null,"scheduled_reset":null,"active_watch":null},
    "meta":{"api_version":"v1","generated_at":"2026-09-12T08:00:00Z"}}
    """.utf8)

    static func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: message, code: 1) }
    }

    static func run() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PublicResetURLProtocol.self]
        configuration.httpAdditionalHeaders = ["Authorization": "Bearer test-only", "Cookie": "test-only=value"]
        let service = PublicResetService(configuration: configuration)
        PublicResetURLProtocol.configure(200, body: fixture, headers: ["ETag": "fixture-etag"])
        let first = try await service.fetch()
        try check(first.presentation().title == "Tibo 重置：暂无预告", "公开状态未读取")
        let request = PublicResetURLProtocol.captured().last!
        try check(request.url?.absoluteString == "https://codex-resets.com/api/v1/status" && request.httpMethod == "GET", "不是指定的只读 API")
        try check(request.value(forHTTPHeaderField: "Authorization") == nil && request.value(forHTTPHeaderField: "Cookie") == nil
            && request.httpBody == nil, "公共请求携带凭据或请求体")
        PublicResetURLProtocol.configure(304)
        let cached = try await service.fetch()
        try check(cached.presentation().title == first.presentation().title, "304 未复用已验证公告")
        try check(PublicResetURLProtocol.captured().last?.value(forHTTPHeaderField: "If-None-Match") == "fixture-etag", "未使用 ETag")
        PublicResetURLProtocol.configure(429, headers: ["Retry-After": "3600"])
        do { _ = try await service.fetch(); throw NSError(domain: "429 被当作成功", code: 1) }
        catch PublicResetError.retryLater {}
        let count = PublicResetURLProtocol.captured().count
        do { _ = try await service.fetch(); throw NSError(domain: "限流期间仍请求", code: 1) }
        catch PublicResetError.retryLater {}
        try check(PublicResetURLProtocol.captured().count == count, "未遵守限流等待")
        let failing = PublicResetService(configuration: configuration)
        PublicResetURLProtocol.configure(503)
        do { _ = try await failing.fetch(); throw NSError(domain: "503 被当作暂无预告", code: 1) }
        catch PublicResetError.unavailable {}
    }
}
