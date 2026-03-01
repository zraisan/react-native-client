package com.margelo.nitro.client

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.TimeUnit

class DownloadWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val url = inputData.getString("fromUrl") ?: return Result.failure()
        val toFile = inputData.getString("toFile") ?: return Result.failure()

        return try {
            val client = OkHttpClient.Builder()
                .connectTimeout(30, TimeUnit.SECONDS)
                .readTimeout(30, TimeUnit.SECONDS)
                .build()

            val request = Request.Builder().url(url).build()
            val response = client.newCall(request).execute()
            val body = response.body ?: return Result.failure()

            val file = File(toFile)
            file.parentFile?.mkdirs()

            FileOutputStream(file).use { output ->
                body.byteStream().use { input ->
                    val buffer = ByteArray(8 * 1024)
                    var bytes: Int
                    while (input.read(buffer).also { bytes = it } != -1) {
                        output.write(buffer, 0, bytes)
                    }
                }
            }

            Result.success()
        } catch (e: Exception) {
            Result.failure()
        }
    }
}
