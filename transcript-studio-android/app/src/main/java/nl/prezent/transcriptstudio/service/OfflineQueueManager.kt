package nl.prezent.transcriptstudio.service

import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import nl.prezent.transcriptstudio.data.local.QueuedUpload
import nl.prezent.transcriptstudio.data.local.QueuedUploadDao
import nl.prezent.transcriptstudio.data.remote.ApiService
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.math.min

private const val TAG = "OfflineQueueManager"
private const val MAX_RETRIES = 5

/**
 * Manages the offline upload queue. Observes network state and drains
 * the queue when connectivity is restored.
 */
@Singleton
class OfflineQueueManager @Inject constructor(
    private val queuedUploadDao: QueuedUploadDao,
    private val apiService: ApiService,
    private val networkMonitor: NetworkMonitor,
) {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var isDraining = false

    init {
        // Observe connectivity changes and drain queue when online
        scope.launch {
            networkMonitor.isOnline
                .collectLatest { online ->
                    if (online) {
                        drainQueue()
                    }
                }
        }
    }

    /**
     * Enqueue a file for upload when the network becomes available.
     */
    suspend fun enqueue(filePath: String, profileId: String, type: String = "audio") {
        queuedUploadDao.insert(
            QueuedUpload(
                type = type,
                filePath = filePath,
                profileId = profileId,
            )
        )
        Log.d(TAG, "Enqueued upload: $filePath (type=$type)")

        // Try to drain immediately if online
        if (networkMonitor.isOnline.value) {
            scope.launch { drainQueue() }
        }
    }

    private suspend fun drainQueue() {
        if (isDraining) return
        isDraining = true

        try {
            // Clean up items that have exceeded max retries
            queuedUploadDao.deleteExhausted(MAX_RETRIES)

            val items = queuedUploadDao.getAllOnce()
            if (items.isEmpty()) return

            Log.d(TAG, "Draining queue: ${items.size} items")

            for (item in items) {
                if (!networkMonitor.isOnline.value) {
                    Log.d(TAG, "Lost connectivity, stopping drain")
                    break
                }

                try {
                    uploadItem(item)
                    queuedUploadDao.delete(item.id)
                    Log.d(TAG, "Successfully uploaded queued item ${item.id}")
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to upload queued item ${item.id} (retry ${item.retryCount})", e)
                    queuedUploadDao.incrementRetryCount(item.id)

                    // Exponential backoff between retries
                    val backoffMs = min(1000L * (1L shl item.retryCount), 30_000L)
                    delay(backoffMs)
                }
            }
        } finally {
            isDraining = false
        }
    }

    private suspend fun uploadItem(item: QueuedUpload) {
        when (item.type) {
            "audio" -> {
                val file = File(item.filePath)
                if (!file.exists()) {
                    Log.w(TAG, "Audio file no longer exists: ${item.filePath}")
                    return
                }
                val requestFile = file.asRequestBody("audio/wav".toMediaType())
                val filePart = MultipartBody.Part.createFormData("file", file.name, requestFile)
                val profileIdBody = item.profileId.toString()
                    .toRequestBody("text/plain".toMediaType())
                apiService.transcribe(filePart, profileIdBody)
            }
            "text" -> {
                // For text uploads, the filePath contains the transcription text
                val body = mapOf(
                    "transcription" to item.filePath,
                    "profile_id" to item.profileId.toString(),
                )
                apiService.transcribeText(body)
            }
        }
    }
}
