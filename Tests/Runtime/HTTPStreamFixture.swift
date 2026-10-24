import Foundation

struct StreamFixturePlan {
    var status = 200
    var chunks: [(delay: TimeInterval, body: String)]
}

final class StreamFixtureStore: @unchecked Sendable {
    struct Observation {
        var url: String
        var authorization: String?
        var body: Data
    }

    private let lock = NSLock()
    private var plans: [StreamFixturePlan] = []
    private var observations: [Observation] = []

    func reset(_ responses: [(status: Int, body: String)]) {
        resetPlans(responses.map { StreamFixturePlan(status: $0.status, chunks: [(0, $0.body)]) })
    }

    func resetPlans(_ plans: [StreamFixturePlan]) {
        lock.lock()
        defer { lock.unlock() }
        self.plans = plans
        observations = []
    }

    func response(for request: URLRequest) -> StreamFixturePlan {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4_096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        lock.lock()
        defer { lock.unlock() }
        observations.append(Observation(url: request.url?.absoluteString ?? "",
                                        authorization: request.value(forHTTPHeaderField: "Authorization"),
                                        body: body))
        return plans.isEmpty ? StreamFixturePlan(status: 500, chunks: [(0, "Unexpected fixture request")]) : plans.removeFirst()
    }

    func requests() -> [Observation] {
        lock.lock()
        defer { lock.unlock() }
        return observations
    }
}

final class StreamFixtureProtocol: URLProtocol {
    static let store = StreamFixtureStore()
    private let deliveryQueue = DispatchQueue(label: "com.snapai.runtime-http-fixture")
    private let lock = NSLock()
    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let fixture = Self.store.response(for: request)
        let response = HTTPURLResponse(url: request.url!, statusCode: fixture.status,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let start = DispatchTime.now()
        for (index, chunk) in fixture.chunks.enumerated() {
            deliveryQueue.asyncAfter(deadline: start + chunk.delay) { [weak self] in
                guard let self else { return }
                self.lock.lock()
                let stopped = self.stopped
                self.lock.unlock()
                guard !stopped else { return }
                self.client?.urlProtocol(self, didLoad: Data(chunk.body.utf8))
                if index == fixture.chunks.count - 1 { self.client?.urlProtocolDidFinishLoading(self) }
            }
        }
    }

    override func stopLoading() {
        lock.lock()
        stopped = true
        lock.unlock()
    }
}
