package nl.prezent.transcriptstudio.data.remote

import android.util.Log
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.retry
import kotlinx.serialization.json.Json
import nl.prezent.transcriptstudio.data.model.TaskStatusUpdate
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.sse.EventSource
import okhttp3.sse.EventSourceListener
import okhttp3.sse.EventSources
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.math.min

private const val TAG = "SSEClient"
private const val MAX_RECONNECT_DELAY_MS = 30_000L

@Singleton
class SSEClient @Inject constructor(
    private val okHttpClient: OkHttpClient,
    private val json: Json,
) {

    /**
     * Observe real-time status updates for a task via Server-Sent Events.
     *
     * The SSE endpoint is `{baseUrl}/task/{taskId}/stream` with the token
     * passed as a query parameter (since SSE does not support custom headers
     * in the browser EventSource API, the backend also accepts `?token=`).
     *
     * The returned flow retries up to 5 times with exponential backoff
     * (1s, 2s, 4s, 8s, 16s capped at 30s).
     */
    fun observeTask(taskId: String, baseUrl: String, token: String): Flow<TaskStatusUpdate> =
        callbackFlow {
            val url = "${baseUrl.trimEnd('/')}/task/$taskId/stream?token=$token"
            val request = Request.Builder()
                .url(url)
                .header("Accept", "text/event-stream")
                .build()

            val factory = EventSources.createFactory(okHttpClient)

            val listener = object : EventSourceListener() {
                override fun onEvent(
                    eventSource: EventSource,
                    id: String?,
                    type: String?,
                    data: String,
                ) {
                    try {
                        val update = json.decodeFromString<TaskStatusUpdate>(data)
                        trySend(update)

                        // Close the flow on terminal events
                        if (type in listOf("done", "completed") ||
                            update.status?.isTerminal == true
                        ) {
                            close()
                        }
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to parse SSE event: $data", e)
                    }
                }

                override fun onFailure(
                    eventSource: EventSource,
                    t: Throwable?,
                    response: Response?,
                ) {
                    val statusCode = response?.code
                    Log.w(TAG, "SSE failure for task $taskId (HTTP $statusCode)", t)
                    close(t ?: Exception("SSE connection failed (HTTP $statusCode)"))
                }

                override fun onClosed(eventSource: EventSource) {
                    close()
                }
            }

            val eventSource = factory.newEventSource(request, listener)

            awaitClose {
                eventSource.cancel()
            }
        }.let { flow ->
            // Retry with exponential backoff: 1s, 2s, 4s, 8s, 16s (capped at 30s)
            var attempt = 0
            flow.retry(5) { cause ->
                val delayMs = min(1000L * (1L shl attempt), MAX_RECONNECT_DELAY_MS)
                Log.d(TAG, "Retrying SSE connection in ${delayMs}ms (attempt ${attempt + 1})", cause)
                delay(delayMs)
                attempt++
                true
            }
        }
}
