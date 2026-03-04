package com.margelo.nitro.client

import android.content.Intent
import android.os.Build
import android.util.Log
import com.margelo.nitro.NitroModules
import com.margelo.nitro.core.Promise
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.ResponseBody
import java.io.File
import java.io.FileOutputStream
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
            val useBackground = config.background == true
            var serviceIntent: Intent? = null

            if (useBackground) {
                serviceIntent = Intent(context, DownloadService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(serviceIntent)
                } else {
                    context.startService(serviceIntent)
                }
            }

            try {
                val file = File(config.toFile)
                file.parentFile?.mkdirs()

                val client = httpClient.newBuilder().apply {
                    config.connectionTimeout?.let { connectTimeout(it.toLong(), TimeUnit.MILLISECONDS) }
                    config.readTimeout?.let { readTimeout(it.toLong(), TimeUnit.MILLISECONDS) }
                }.build()

                // Check existing partial file if resumable
                var existingBytes = 0L
                if (config.resumable == true && file.exists()) {
                    existingBytes = file.length()
                }

                val requestBuilder = Request.Builder().url(config.fromUrl)
                if (existingBytes > 0) {
                    requestBuilder.header("Range", "bytes=$existingBytes-")
                }

                val response = client.newCall(requestBuilder.build()).execute()
                val statusCode = response.code
                val body = response.body ?: throw Exception("Empty response body")

                when (statusCode) {
                    206 -> {
                        val chunkLength = body.contentLength()
                        val totalLength = if (chunkLength > 0) existingBytes + chunkLength else -1L

                        if (totalLength > 0 && existingBytes >= totalLength) {
                            body.close()
                            progressExecutor.execute {
                                config.begin?.invoke(statusCode.toDouble(), totalLength.toDouble())
                                config.onProgress?.invoke(existingBytes.toDouble(), totalLength.toDouble())
                            }
                            return@async DownloadResult(
                                statusCode = statusCode.toDouble(),
                                bytesWritten = existingBytes.toDouble()
                            )
                        }

                        Log.d("HybridClient", "Resuming: existingBytes=$existingBytes, chunkLength=$chunkLength, totalLength=$totalLength")
                        progressExecutor.execute {
                            config.begin?.invoke(statusCode.toDouble(), totalLength.toDouble())
                        }
                        val bytesWritten = streamToFile(file, body, totalLength, config)
                        DownloadResult(
                            statusCode = statusCode.toDouble(),
                            bytesWritten = bytesWritten.toDouble()
                        )
                    }
                    416 -> {
                        body.close()
                        file.delete()
                        Log.d("HybridClient", "416 received, deleting file and restarting")

                        val freshRequest = Request.Builder().url(config.fromUrl).build()
                        val freshResponse = client.newCall(freshRequest).execute()
                        val freshBody = freshResponse.body ?: throw Exception("Empty response body on fresh request")
                        val totalLength = freshBody.contentLength()

                        Log.d("HybridClient", "Restarting download: totalLength=$totalLength")
                        progressExecutor.execute {
                            config.begin?.invoke(freshResponse.code.toDouble(), totalLength.toDouble())
                        }
                        val bytesWritten = streamToFile(file, freshBody, totalLength, config)
                        DownloadResult(
                            statusCode = freshResponse.code.toDouble(),
                            bytesWritten = bytesWritten.toDouble()
                        )
                    }
                    200 -> {
                        val totalLength = body.contentLength()
                        Log.d("HybridClient", "Full download (200): totalLength=$totalLength")
                        progressExecutor.execute {
                            config.begin?.invoke(statusCode.toDouble(), totalLength.toDouble())
                        }
                        val bytesWritten = streamToFile(file, body, totalLength, config)
                        DownloadResult(
                            statusCode = statusCode.toDouble(),
                            bytesWritten = bytesWritten.toDouble()
                        )
                    }
                    else -> {
                        body.close()
                        progressExecutor.execute {
                            config.begin?.invoke(statusCode.toDouble(), 0.0)
                        }
                        DownloadResult(
                            statusCode = statusCode.toDouble(),
                            bytesWritten = 0.0
                        )
                    }
                }
            } finally {
                if (useBackground && serviceIntent != null) {
                    context.stopService(serviceIntent)
                }
            }
        }
    }

    private fun streamToFile(
        file: File,
        body: ResponseBody,
        totalLength: Long,
        config: DownloadConfig
    ): Long {
        val append = config.resumable == true
        var bytesWritten = if (append) file.length() else 0L
        var lastProgressTime = 0L

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

        if (totalLength > 0) {
            val bw = bytesWritten
            val tl = totalLength
            progressExecutor.execute {
                config.onProgress?.invoke(bw.toDouble(), tl.toDouble())
            }
        }

        return bytesWritten
    }
}
