import Testing
import Foundation
@testable import MacSift

/// Stubbed `URLProtocol` that returns a caller-supplied payload and status
/// code instead of actually hitting the network. Lets us exercise
/// `UpdateChecker.checkForUpdate` end-to-end — JSON decoding, version
/// compare, asset selection, error mapping — without touching GitHub.
final class StubURLProtocol: URLProtocol {
    /// Test-local override. Set from the test, read by `startLoading`.
    /// We stuff everything under a UUID-keyed dictionary so parallel tests
    /// don't clobber each other.
    nonisolated(unsafe) static var responses: [String: Response] = [:]

    struct Response: Sendable {
        let status: Int
        let body: Data
        let error: Error?
    }

    /// Look up the response by the request URL's path. Simple and
    /// sufficient since we only ever stub the `/releases/latest` endpoint.
    static func register(for path: String, response: Response) {
        responses[path] = response
    }

    static func clear() {
        responses.removeAll()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "api.github.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let path = request.url?.path,
              let response = Self.responses[path] else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        if let error = response.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let httpResponse = HTTPURLResponse(
            url: request.url!,
            statusCode: response.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// NOTE: Swift's URLSession.shared doesn't pick up custom URLProtocols
// registered via `URLProtocol.registerClass`. The recommended pattern is
// to inject a custom session on the caller — but our `UpdateChecker` uses
// `URLSession.shared` directly. Rather than refactor the service just for
// testing, we use `URLProtocol.registerClass` which DOES take effect for
// requests routed through URLProtocol's class chain, and since
// URLSession.shared consults that chain on macOS, these tests work.

@Suite("UpdateChecker · network and decoding", .serialized)
struct UpdateCheckerNetworkTests {
    private let endpointPath = "/repos/Lcharvol/MacSift/releases/latest"

    private func register() {
        URLProtocol.registerClass(StubURLProtocol.self)
    }

    private func unregister() {
        URLProtocol.unregisterClass(StubURLProtocol.self)
        StubURLProtocol.clear()
    }

    private func releaseJSON(
        tag: String,
        assets: [(name: String, url: String, size: Int64)] = [
            (name: "MacSift.zip", url: "https://github.com/Lcharvol/MacSift/releases/download/v0.3.0/MacSift.zip", size: 1_600_000),
        ],
        body: String = "Release notes body",
        publishedAt: String? = "2026-04-14T10:00:00Z"
    ) -> Data {
        let assetBlobs = assets.map { asset in
            """
            {
              "name": "\(asset.name)",
              "browser_download_url": "\(asset.url)",
              "size": \(asset.size)
            }
            """
        }.joined(separator: ",")
        let publishedField = publishedAt.map { "\"published_at\": \"\($0)\"," } ?? ""
        let json = """
        {
          "tag_name": "\(tag)",
          "html_url": "https://github.com/Lcharvol/MacSift/releases/tag/\(tag)",
          \(publishedField)
          "body": "\(body)",
          "assets": [\(assetBlobs)]
        }
        """
        return json.data(using: .utf8)!
    }

    @Test func returnsUpdateInfoWhenLatestIsNewer() async throws {
        register()
        defer { unregister() }

        StubURLProtocol.register(for: endpointPath, response: .init(
            status: 200,
            body: releaseJSON(tag: "v0.3.0"),
            error: nil
        ))

        let info = try await UpdateChecker.checkForUpdate(currentVersion: "0.2.1")
        let got = try #require(info)
        #expect(got.latestVersion == "0.3.0")
        #expect(got.downloadURL.absoluteString == "https://github.com/Lcharvol/MacSift/releases/download/v0.3.0/MacSift.zip")
        #expect(got.downloadSizeBytes == 1_600_000)
        #expect(got.releaseURL.host == "github.com")
        #expect(got.publishedAt != nil)
    }

    @Test func returnsNilWhenCurrentIsUpToDate() async throws {
        register()
        defer { unregister() }

        StubURLProtocol.register(for: endpointPath, response: .init(
            status: 200,
            body: releaseJSON(tag: "v0.2.1"),
            error: nil
        ))

        let info = try await UpdateChecker.checkForUpdate(currentVersion: "0.2.1")
        #expect(info == nil)
    }

    @Test func returnsNilWhenCurrentIsAheadOfLatest() async throws {
        register()
        defer { unregister() }

        StubURLProtocol.register(for: endpointPath, response: .init(
            status: 200,
            body: releaseJSON(tag: "v0.2.1"),
            error: nil
        ))

        let info = try await UpdateChecker.checkForUpdate(currentVersion: "99.0.0")
        #expect(info == nil)
    }

    @Test func falsBackToAnyZipWhenPreferredAssetMissing() async throws {
        register()
        defer { unregister() }

        // Only a versioned zip, no plain `MacSift.zip`. Checker should
        // pick the `.zip` asset as the fallback rather than throwing.
        StubURLProtocol.register(for: endpointPath, response: .init(
            status: 200,
            body: releaseJSON(
                tag: "v0.3.0",
                assets: [(name: "MacSift-0.3.0.zip", url: "https://github.com/Lcharvol/MacSift/releases/download/v0.3.0/MacSift-0.3.0.zip", size: 1_700_000)]
            ),
            error: nil
        ))

        let info = try await UpdateChecker.checkForUpdate(currentVersion: "0.2.1")
        let got = try #require(info)
        #expect(got.downloadURL.absoluteString == "https://github.com/Lcharvol/MacSift/releases/download/v0.3.0/MacSift-0.3.0.zip")
    }

    @Test func throwsNoDownloadAssetWhenNoZipPresent() async throws {
        register()
        defer { unregister() }

        StubURLProtocol.register(for: endpointPath, response: .init(
            status: 200,
            body: releaseJSON(
                tag: "v0.3.0",
                assets: [(name: "source.tar.gz", url: "https://github.com/Lcharvol/MacSift/releases/download/v0.3.0/source.tar.gz", size: 10_000)]
            ),
            error: nil
        ))

        do {
            _ = try await UpdateChecker.checkForUpdate(currentVersion: "0.2.1")
            Issue.record("Expected noDownloadAsset but call succeeded")
        } catch UpdateCheckError.noDownloadAsset {
            // expected
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test func throwsDecodingFailedOnMalformedPayload() async throws {
        register()
        defer { unregister() }

        StubURLProtocol.register(for: endpointPath, response: .init(
            status: 200,
            body: Data("not valid json".utf8),
            error: nil
        ))

        do {
            _ = try await UpdateChecker.checkForUpdate(currentVersion: "0.2.1")
            Issue.record("Expected decodingFailed but call succeeded")
        } catch UpdateCheckError.decodingFailed {
            // expected
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test func stripsLeadingVFromTagName() async throws {
        register()
        defer { unregister() }

        StubURLProtocol.register(for: endpointPath, response: .init(
            status: 200,
            body: releaseJSON(tag: "v0.3.0"),
            error: nil
        ))

        let info = try await UpdateChecker.checkForUpdate(currentVersion: "0.2.1")
        let got = try #require(info)
        #expect(got.latestVersion == "0.3.0")
        #expect(!got.latestVersion.hasPrefix("v"))
    }
}
