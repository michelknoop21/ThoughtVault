package nl.prezent.transcriptstudio.data.repository

import kotlinx.coroutines.flow.Flow
import nl.prezent.transcriptstudio.data.model.*
import nl.prezent.transcriptstudio.data.remote.ApiService
import nl.prezent.transcriptstudio.data.remote.SSEClient
import nl.prezent.transcriptstudio.service.SecureTokenStore
import nl.prezent.transcriptstudio.service.SettingsRepository
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class TaskRepository @Inject constructor(
    private val apiService: ApiService,
    private val sseClient: SSEClient,
    private val secureTokenStore: SecureTokenStore,
    private val settingsRepository: SettingsRepository,
) {

    suspend fun getActiveTasks(): List<TranscriptTask> =
        apiService.getActiveTasks().tasks

    suspend fun getTaskStatus(taskId: String): TranscriptTask =
        apiService.getTaskStatus(taskId)

    suspend fun cancelTask(taskId: String): CancelTaskResponse =
        apiService.cancelTask(taskId)

    suspend fun deleteTask(taskId: String) {
        apiService.deleteTask(taskId)
    }

    /**
     * Observe real-time task status updates via SSE.
     * Returns a Flow that emits [TaskStatusUpdate] events until the task completes.
     */
    suspend fun observeTask(taskId: String): Flow<TaskStatusUpdate> {
        val baseUrl = settingsRepository.getApiBaseUrl()
        val token = secureTokenStore.loadToken() ?: ""
        return sseClient.observeTask(taskId, baseUrl, token)
    }
}
