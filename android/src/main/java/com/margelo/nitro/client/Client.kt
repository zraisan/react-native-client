package com.margelo.nitro.client

import com.margelo.nitro.core.Promise
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.TimeUnit

class HybridClient : HybridClientSpec() {

    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    override fun downloadFile(config: DownloadConfig): Promise<DownloadResult> {
        return Promise.async {
            val request = Request.Builder()
                .url(config.fromUrl)
                .build()

            val response = httpClient.newCall(request).execute()
            val body = response.body ?: throw Exception("Empty response body")

            val file = File(config.toFile)
            file.parentFile?.mkdirs()

            var bytesWritten = 0L
            FileOutputStream(file).use { output ->
                body.byteStream().use { input ->
                    val buffer = ByteArray(8 * 1024)
                    var bytes: Int
                    while (input.read(buffer).also { bytes = it } != -1) {
                        output.write(buffer, 0, bytes)
                        bytesWritten += bytes
                    }
                }
            }

            DownloadResult(
                statusCode = response.code.toDouble(),
                bytesWritten = bytesWritten.toDouble(),
            )
        }
    }
}
