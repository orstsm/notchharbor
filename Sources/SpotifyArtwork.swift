import AppKit
import ImageIO

enum SpotifyArtwork {
    static func safeURL(_ value: String) -> URL? {
        guard let url = URL(string: value), url.scheme == "https", url.host == "i.scdn.co",
              url.user == nil, url.password == nil, url.port == nil,
              url.query == nil, url.fragment == nil, url.path.hasPrefix("/image/") else { return nil }
        return url
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    static func load(_ url: URL) async -> NSImage? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 10
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(from: url)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                  response.expectedContentLength <= 2_000_000 else { return nil }
            var data = Data()
            for try await byte in bytes {
                if Task.isCancelled || data.count >= 2_000_000 { return nil }
                data.append(byte)
            }
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 256,
                    kCGImageSourceCreateThumbnailWithTransform: true
                  ] as CFDictionary) else { return nil }
            return NSImage(cgImage: thumbnail, size: .zero)
        } catch { return nil }
    }
}
