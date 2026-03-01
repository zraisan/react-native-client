package com.margelo.nitro.client

import android.util.Log
import androidx.work.Data
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import com.margelo.nitro.NitroModules
import com.margelo.nitro.core.Promise
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.TimeUnit

class HybridClient : HybridClientSpec() {

    override val documentDirectoryPath: String
        get() = NitroModules.applicationContext!!.filesDir.absolutePath

    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    override fun downloadFile(config: DownloadConfig): Promise<DownloadResult> {
        return if (config.background == true) {
            enqueueBackgroundDownload(config)
        } else {
            foregroundDownload(config)
        }
    }

    private fun enqueueBackgroundDownload(config: DownloadConfig): Promise<DownloadResult> {
        return Promise.async {
            val data = Data.Builder()
                .putString("fromUrl", config.fromUrl)
                .putString("toFile", config.toFile)
                .build()

            val request = OneTimeWorkRequestBuilder<DownloadWorker>()
                .setInputData(data)
                .build()

            WorkManager.getInstance(NitroModules.applicationContext!!)
                .enqueue(request)

            DownloadResult(statusCode = 0.0, bytesWritten = 0.0)
        }
    }

    private fun foregroundDownload(config: DownloadConfig): Promise<DownloadResult> {
        return Promise.async {
            val request = Request.Builder()
                .url(config.fromUrl)
                .build()

            val response = httpClient.newCall(request).execute()
            val body = response.body ?: throw Exception("Empty response body")
            val contentLength = body.contentLength()
            Log.d("HybridClient", "contentLength: $contentLength")

            val file = File(config.toFile)
            file.parentFile?.mkdirs()

            var bytesWritten = 0L
            var lastPercent = 0L
            FileOutputStream(file).use { output ->
                body.byteStream().use { input ->
                    val buffer = ByteArray(8 * 1024)
                    var bytes: Int
                    while (input.read(buffer).also { bytes = it } != -1) {
                        output.write(buffer, 0, bytes)
                        bytesWritten += bytes
                        if (contentLength > 0) {
                            val percent = bytesWritten * 100 / contentLength
                            if (percent > lastPercent) {
                                config.onProgress?.invoke(bytesWritten.toDouble(), contentLength.toDouble())
                                lastPercent = percent
                            }
                        }
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
