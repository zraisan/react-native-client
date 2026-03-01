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
        return Promise.async { resolve, reject in
            guard let url = URL(string: config.fromUrl) else {
                reject(RuntimeError.error(withMessage: "Invalid URL: \(config.fromUrl)"))
                return
            }

            var request = URLRequest(url: url)
            if let connectionTimeout = config.connectionTimeout {
                request.timeoutInterval = connectionTimeout / 1000.0
            }

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    reject(RuntimeError.error(withMessage: error.localizedDescription))
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    reject(RuntimeError.error(withMessage: "Invalid response"))
                    return
                }

                guard let data = data else {
                    reject(RuntimeError.error(withMessage: "Empty response body"))
                    return
                }

                let fileURL = URL(fileURLWithPath: config.toFile)
                let directory = fileURL.deletingLastPathComponent()

                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try data.write(to: fileURL)
                } catch {
                    reject(RuntimeError.error(withMessage: error.localizedDescription))
                    return
                }

                let result = DownloadResult(
                    statusCode: Double(httpResponse.statusCode),
                    bytesWritten: Double(data.count)
                )
                resolve(result)
            }

            task.resume()
        }
    }
}
