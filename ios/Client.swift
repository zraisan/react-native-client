import Foundation
import NitroModules

private struct ContentRange {
    let start: Int64
    let end: Int64
    let total: Int64?
}

private func parseContentRange(_ header: String?) -> ContentRange? {
    guard let header = header else { return nil }

    let parts = header
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)

    guard parts.count == 2, parts[0].lowercased() == "bytes" else {
        return nil
    }

    let rangeParts = parts[1].split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
    guard rangeParts.count == 2 else { return nil }

    let bounds = rangeParts[0].split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
    guard bounds.count == 2,
          let start = Int64(String(bounds[0])),
          let end = Int64(String(bounds[1])) else {
        return nil
    }

    let totalPart = String(rangeParts[1])
    let total = totalPart == "*" ? nil : Int64(totalPart)
    if totalPart != "*" && total == nil {
        return nil
    }

    return ContentRange(start: start, end: end, total: total)
}

private func isValidResumeResponse(
    contentRange: ContentRange?,
    existingBytes: Int64,
    contentLength: Int64
) -> Bool {
    if existingBytes <= 0 { return true }
    guard let contentRange = contentRange else { return false }
    guard contentRange.start == existingBytes else { return false }
    guard contentRange.end >= contentRange.start else { return false }
    if let total = contentRange.total, contentRange.end >= total {
        return false
    }

    let rangeLength = contentRange.end - contentRange.start + 1
    if contentLength > 0 && contentLength != rangeLength {
        return false
    }

    return true
}

class BackgroundDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let destinationURL: URL
    var existingBytes: Int64
    let config: DownloadConfig
    let continuation: CheckedContinuation<DownloadResult, Error>

    init(
        destinationURL: URL,
        existingBytes: Int64,
        config: DownloadConfig,
        continuation: CheckedContinuation<DownloadResult, Error>
    ) {
        self.destinationURL = destinationURL
        self.existingBytes = existingBytes
        self.config = config
        self.continuation = continuation
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let totalWritten = existingBytes + totalBytesWritten
        let totalExpected = existingBytes + totalBytesExpectedToWrite
        config.onProgress?(Double(totalWritten), Double(totalExpected))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let fileManager = FileManager.default
        let httpResponse = downloadTask.response as? HTTPURLResponse
        let statusCode = httpResponse?.statusCode ?? 200
        let contentRange = parseContentRange(httpResponse?.value(forHTTPHeaderField: "Content-Range"))
        let contentLength = downloadTask.response?.expectedContentLength ?? -1

        do {
            if statusCode == 206 && existingBytes > 0 {
                guard isValidResumeResponse(
                    contentRange: contentRange,
                    existingBytes: existingBytes,
                    contentLength: contentLength
                ) else {
                    try? fileManager.removeItem(at: destinationURL)
                    try restartFreshDownload(in: session)
                    return
                }

                // Append downloaded chunk to existing file
                try appendFileContents(from: location, to: destinationURL)
            } else {
                // Replace/move the temp file to destination
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.moveItem(at: location, to: destinationURL)
            }

            let finalSize = (try? fileManager.attributesOfItem(atPath: destinationURL.path)[.size] as? Int64) ?? 0
            continuation.resume(returning: DownloadResult(
                statusCode: Double(statusCode),
                bytesWritten: Double(finalSize)
            ))
        } catch {
            continuation.resume(throwing: error)
        }

        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            continuation.resume(throwing: error)
            session.finishTasksAndInvalidate()
        }
    }

    private func restartFreshDownload(in session: URLSession) throws {
        guard let url = URL(string: config.fromUrl) else {
            throw NSError(
                domain: "NitroClient",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid URL: \(config.fromUrl)"]
            )
        }

        var request = URLRequest(url: url)
        if let connectionTimeout = config.connectionTimeout {
            request.timeoutInterval = connectionTimeout / 1000.0
        }

        existingBytes = 0
        config.begin?(0, 0)
        session.downloadTask(with: request).resume()
    }

    private func appendFileContents(from sourceURL: URL, to destinationURL: URL) throws {
        let input = try FileHandle(forReadingFrom: sourceURL)
        defer { try? input.close() }

        let output = try FileHandle(forWritingTo: destinationURL)
        defer { try? output.close() }

        try output.seekToEnd()

        let bufferSize = 1024 * 1024
        while let chunk = try input.read(upToCount: bufferSize), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
        }
    }

}

class HybridClient: HybridClientSpec {
    var hybridContext = margelo.nitro.HybridContext()
    var memorySize: Int { return getSizeOf(self) }

    var documentDirectoryPath: String {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].path
    }

    func downloadFile(config: DownloadConfig) throws -> Promise<DownloadResult> {
        return Promise.async {
            guard let url = URL(string: config.fromUrl) else {
                throw RuntimeError.error(withMessage: "Invalid URL: \(config.fromUrl)")
            }

            let fileURL = URL(fileURLWithPath: config.toFile)
            let fileManager = FileManager.default

            let directory = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

            // Check existing partial file if resumable
            var existingBytes: Int64 = 0
            if config.resumable == true && fileManager.fileExists(atPath: config.toFile) {
                let attributes = try fileManager.attributesOfItem(atPath: config.toFile)
                existingBytes = (attributes[.size] as? Int64) ?? 0
            }

            var request = URLRequest(url: url)
            if let connectionTimeout = config.connectionTimeout {
                request.timeoutInterval = connectionTimeout / 1000.0
            }
            if existingBytes > 0 {
                request.setValue("bytes=\(existingBytes)-", forHTTPHeaderField: "Range")
            }

            if config.background == true {
                return try await self.backgroundDownload(
                    request: request,
                    fileURL: fileURL,
                    existingBytes: existingBytes,
                    config: config
                )
            }

            // Foreground download (existing behavior)
            let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw RuntimeError.error(withMessage: "Invalid response")
            }

            let statusCode = httpResponse.statusCode

            switch statusCode {
            case 206:
                let contentLength = httpResponse.expectedContentLength
                let contentRange = parseContentRange(httpResponse.value(forHTTPHeaderField: "Content-Range"))

                if !isValidResumeResponse(
                    contentRange: contentRange,
                    existingBytes: existingBytes,
                    contentLength: contentLength
                ) {
                    try? fileManager.removeItem(at: fileURL)
                    return try await self.downloadFresh(url: url, fileURL: fileURL, config: config)
                }

                let totalLength: Int64 = contentRange?.total
                    ?? (contentLength > 0 ? existingBytes + contentLength : -1)

                if totalLength > 0 && existingBytes >= totalLength {
                    config.begin?(Double(statusCode), Double(totalLength))
                    config.onProgress?(Double(existingBytes), Double(totalLength))
                    return DownloadResult(
                        statusCode: Double(statusCode),
                        bytesWritten: Double(existingBytes)
                    )
                }

                config.begin?(Double(statusCode), Double(totalLength))
                let bytesWritten = try await self.streamToFile(
                    fileURL: fileURL,
                    asyncBytes: asyncBytes,
                    totalLength: totalLength,
                    config: config,
                    append: existingBytes > 0
                )
                return DownloadResult(
                    statusCode: Double(statusCode),
                    bytesWritten: Double(bytesWritten)
                )

            case 416:
                try? fileManager.removeItem(at: fileURL)
                return try await self.downloadFresh(url: url, fileURL: fileURL, config: config)

            case 200:
                let totalLength = Int64(httpResponse.expectedContentLength)
                config.begin?(Double(statusCode), Double(totalLength))
                let bytesWritten = try await self.streamToFile(
                    fileURL: fileURL,
                    asyncBytes: asyncBytes,
                    totalLength: totalLength,
                    config: config,
                    append: false
                )
                return DownloadResult(
                    statusCode: Double(statusCode),
                    bytesWritten: Double(bytesWritten)
                )

            default:
                config.begin?(Double(statusCode), 0)
                return DownloadResult(
                    statusCode: Double(statusCode),
                    bytesWritten: 0
                )
            }
        }
    }

    private func downloadFresh(
        url: URL,
        fileURL: URL,
        config: DownloadConfig
    ) async throws -> DownloadResult {
        var request = URLRequest(url: url)
        if let connectionTimeout = config.connectionTimeout {
            request.timeoutInterval = connectionTimeout / 1000.0
        }

        let (freshBytes, freshResponse) = try await URLSession.shared.bytes(for: request)
        guard let freshHttpResponse = freshResponse as? HTTPURLResponse else {
            throw RuntimeError.error(withMessage: "Invalid response on fresh request")
        }

        let totalLength = Int64(freshHttpResponse.expectedContentLength)
        config.begin?(Double(freshHttpResponse.statusCode), Double(totalLength))
        let bytesWritten = try await self.streamToFile(
            fileURL: fileURL,
            asyncBytes: freshBytes,
            totalLength: totalLength,
            config: config,
            append: false
        )
        return DownloadResult(
            statusCode: Double(freshHttpResponse.statusCode),
            bytesWritten: Double(bytesWritten)
        )
    }

    private func backgroundDownload(
        request: URLRequest,
        fileURL: URL,
        existingBytes: Int64,
        config: DownloadConfig
    ) async throws -> DownloadResult {
        return try await withCheckedThrowingContinuation { continuation in
            let identifier = "com.margelo.nitro.client.bg.\(UUID().uuidString)"
            let sessionConfig = URLSessionConfiguration.background(withIdentifier: identifier)
            sessionConfig.isDiscretionary = config.discretionary == true

            if let connectionTimeout = config.connectionTimeout {
                sessionConfig.timeoutIntervalForRequest = connectionTimeout / 1000.0
            }

            let delegate = BackgroundDownloadDelegate(
                destinationURL: fileURL,
                existingBytes: existingBytes,
                config: config,
                continuation: continuation
            )

            let session = URLSession(configuration: sessionConfig, delegate: delegate, delegateQueue: nil)
            let task = session.downloadTask(with: request)

            config.begin?(0, 0)
            task.resume()
        }
    }

    private func streamToFile(
        fileURL: URL,
        asyncBytes: URLSession.AsyncBytes,
        totalLength: Int64,
        config: DownloadConfig,
        append: Bool
    ) async throws -> Int64 {
        let fileManager = FileManager.default

        if !append {
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
            _ = fileManager.createFile(atPath: fileURL.path, contents: nil)
        }

        let fileHandle = try FileHandle(forWritingTo: fileURL)
        var bytesWritten: Int64 = 0
        if append {
            bytesWritten = Int64(try fileHandle.seekToEnd())
        }
        var lastProgressTime = CFAbsoluteTimeGetCurrent()
        let bufferCapacity = 64 * 1024
        var buffer = Data()
        buffer.reserveCapacity(bufferCapacity)

        for try await byte in asyncBytes {
            buffer.append(byte)

            if buffer.count >= bufferCapacity {
                try fileHandle.write(contentsOf: buffer)
                bytesWritten += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)

                if totalLength > 0 {
                    let now = CFAbsoluteTimeGetCurrent()
                    if now - lastProgressTime >= 0.15 {
                        lastProgressTime = now
                        config.onProgress?(Double(bytesWritten), Double(totalLength))
                    }
                }
            }
        }

        if !buffer.isEmpty {
            try fileHandle.write(contentsOf: buffer)
            bytesWritten += Int64(buffer.count)
        }

        try fileHandle.close()

        if totalLength > 0 {
            config.onProgress?(Double(bytesWritten), Double(totalLength))
        }

        return bytesWritten
    }
}
