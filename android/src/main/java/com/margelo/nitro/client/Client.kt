package com.margelo.nitro.client

import android.content.Intent
import android.os.Build
import android.util.Log
import com.margelo.nitro.NitroModules
import com.margelo.nitro.core.Promise
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class HybridClient : HybridClientSpec() {

    override val documentDirectoryPath: String
        get() = NitroModules.applicationContext!!.filesDir.absolutePath

    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    private val progressExecutor = Executors.newSingleThreadExecutor()

    override fun downloadFile(config: DownloadConfig): Promise<DownloadResult> {
        return Promise.async {
            val context = NitroModules.applicationContext!!
            val serviceIntent = Intent(context, DownloadService::class.java)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(serviceIntent)
            } else {
                context.startService(serviceIntent)
            }

            try {
                val maxRetries = 3
                val file = File(config.toFile)
                file.parentFile?.mkdirs()

                var bytesWritten = 0L
                var totalLength = -1L
                var lastProgressTime = 0L
                var lastStatusCode = 0

                for (attempt in 0 until maxRetries) {
                    if (attempt > 0) {
                        val backoffMs = (1000L shl (attempt - 1)) // 1s, 2s, 4s
                        Log.d("HybridClient", "Retry #$attempt after ${backoffMs}ms, resuming from $bytesWritten bytes")
                        Thread.sleep(backoffMs)
                        bytesWritten = file.length()
                    }

                    val requestBuilder = Request.Builder().url(config.fromUrl)
                    if (bytesWritten > 0) {
                        requestBuilder.header("Range", "bytes=$bytesWritten-")
                    }

                    val response = try {
                        httpClient.newCall(requestBuilder.build()).execute()
                    } catch (e: IOException) {
                        if (attempt < maxRetries - 1) continue else throw e
                    }

                    lastStatusCode = response.code
                    val body = response.body ?: throw Exception("Empty response body")

                    when (response.code) {
                        206 -> {
                            // Server supports Range — append to existing file
                            val chunkLength = body.contentLength()
                            if (totalLength <= 0 && chunkLength > 0) {
                                totalLength = bytesWritten + chunkLength
                            }
                            Log.d("HybridClient", "Resuming: bytesWritten=$bytesWritten, chunkLength=$chunkLength, totalLength=$totalLength")
                        }
                        416 -> {
                            // Range not satisfiable — file may have changed, start over
                            body.close()
                            bytesWritten = 0L
                            lastProgressTime = 0L
                            file.delete()
                            continue
                        }
                        else -> {
                            // 200 or other success — server doesn't support Range, start over
                            bytesWritten = 0L
                            lastProgressTime = 0L
                            totalLength = body.contentLength()
                            Log.d("HybridClient", "Full download: contentLength=$totalLength")
                        }
                    }

                    val append = response.code == 206
                    try {
                        FileOutputStream(file, append).use { output ->
                            body.byteStream().use { input ->
                                val buffer = ByteArray(64 * 1024)
                                var bytes: Int
                                while (input.read(buffer).also { bytes = it } != -1) {
                                    output.write(buffer, 0, bytes)
                                    bytesWritten += bytes
                                    if (totalLength > 0) {
                                        val now = System.currentTimeMillis()
                                        if (now - lastProgressTime >= 150) {
                                            lastProgressTime = now
                                            val bw = bytesWritten
                                            val tl = totalLength
                                            progressExecutor.execute {
                                                config.onProgress?.invoke(bw.toDouble(), tl.toDouble())
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        // Download completed successfully
                        break
                    } catch (e: IOException) {
                        if (attempt < maxRetries - 1) continue else throw e
                    }
                }

                DownloadResult(
                    statusCode = lastStatusCode.toDouble(),
                    bytesWritten = bytesWritten.toDouble(),
                )
            } finally {
                context.stopService(serviceIntent)
            }
        }
    }
}
