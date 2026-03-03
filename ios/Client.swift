import Foundation
import NitroModules

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

            let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw RuntimeError.error(withMessage: "Invalid response")
            }

            let statusCode = httpResponse.statusCode

            switch statusCode {
            case 206:
                let contentLength = httpResponse.expectedContentLength
                let totalLength: Int64 = contentLength > 0
                    ? existingBytes + Int64(contentLength)
                    : -1

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
                    config: config
                )
                return DownloadResult(
                    statusCode: Double(statusCode),
                    bytesWritten: Double(bytesWritten)
                )

            case 416:
                try? fileManager.removeItem(at: fileURL)

                var freshRequest = URLRequest(url: url)
                if let connectionTimeout = config.connectionTimeout {
                    freshRequest.timeoutInterval = connectionTimeout / 1000.0
                }
                let (freshBytes, freshResponse) = try await URLSession.shared.bytes(for: freshRequest)
                guard let freshHttpResponse = freshResponse as? HTTPURLResponse else {
                    throw RuntimeError.error(withMessage: "Invalid response on fresh request")
                }

                let totalLength = Int64(freshHttpResponse.expectedContentLength)
                config.begin?(Double(freshHttpResponse.statusCode), Double(totalLength))
                let bytesWritten = try await self.streamToFile(
                    fileURL: fileURL,
                    asyncBytes: freshBytes,
                    totalLength: totalLength,
                    config: config
                )
                return DownloadResult(
                    statusCode: Double(freshHttpResponse.statusCode),
                    bytesWritten: Double(bytesWritten)
                )

            case 200:
                let totalLength = Int64(httpResponse.expectedContentLength)
                config.begin?(Double(statusCode), Double(totalLength))
                let bytesWritten = try await self.streamToFile(
                    fileURL: fileURL,
                    asyncBytes: asyncBytes,
                    totalLength: totalLength,
                    config: config
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

    private func streamToFile(
        fileURL: URL,
        asyncBytes: URLSession.AsyncBytes,
        totalLength: Int64,
        config: DownloadConfig
    ) async throws -> Int64 {
        let fileManager = FileManager.default
        let append = config.resumable == true

        if !append {
            fileManager.createFile(atPath: fileURL.path, contents: nil)
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
