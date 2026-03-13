package nl.prezent.transcriptstudio.ui.tasks

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import nl.prezent.transcriptstudio.data.model.TaskStatus
import nl.prezent.transcriptstudio.data.model.TranscriptTask
import nl.prezent.transcriptstudio.data.repository.TaskRepository
import javax.inject.Inject

private const val TAG = "TasksViewModel"
private const val AUTO_REFRESH_INTERVAL_MS = 30_000L

@HiltViewModel
class TasksViewModel @Inject constructor(
    private val taskRepository: TaskRepository,
) : ViewModel() {

    data class UiState(
        val tasks: List<TranscriptTask> = emptyList(),
        val isLoading: Boolean = false,
        val isRefreshing: Boolean = false,
        val error: String? = null,
    )

    sealed interface Event {
        data class NavigateToTranscript(val id: String) : Event
    }

    private val _uiState = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()

    private val _events = MutableSharedFlow<Event>()
    val events: SharedFlow<Event> = _events.asSharedFlow()

    private val sseJobs = mutableMapOf<String, Job>()

    init {
        loadTasks()
        startAutoRefresh()
    }

    fun loadTasks() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = it.tasks.isEmpty(), error = null) }
            try {
                val tasks = taskRepository.getActiveTasks()
                _uiState.update { it.copy(tasks = tasks, isLoading = false, error = null) }

                // Start SSE for each active task
                tasks.filter { it.status.isActive }.forEach { task ->
                    startSSE(task.effectiveId)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load tasks", e)
                _uiState.update {
                    it.copy(
                        isLoading = false,
                        error = "Kan taken niet laden. Probeer het opnieuw.",
                    )
                }
            }
        }
    }

    fun refresh() {
        viewModelScope.launch {
            _uiState.update { it.copy(isRefreshing = true, error = null) }
            try {
                val tasks = taskRepository.getActiveTasks()
                _uiState.update { it.copy(tasks = tasks, isRefreshing = false, error = null) }

                // Restart SSE for active tasks
                tasks.filter { it.status.isActive }.forEach { task ->
                    startSSE(task.effectiveId)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to refresh tasks", e)
                _uiState.update {
                    it.copy(
                        isRefreshing = false,
                        error = "Kan taken niet vernieuwen. Probeer het opnieuw.",
                    )
                }
            }
        }
    }

    fun cancelTask(taskId: String) {
        viewModelScope.launch {
            try {
                taskRepository.cancelTask(taskId)
                // Cancel SSE job for this task
                sseJobs.remove(taskId)?.cancel()
                // Remove from list
                _uiState.update { state ->
                    state.copy(tasks = state.tasks.filter { it.effectiveId != taskId })
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to cancel task $taskId", e)
                _uiState.update {
                    it.copy(error = "Kan taak niet annuleren. Probeer het opnieuw.")
                }
            }
        }
    }

    private fun startSSE(taskId: String) {
        // Cancel previous SSE job for same taskId
        sseJobs.remove(taskId)?.cancel()

        sseJobs[taskId] = viewModelScope.launch {
            try {
                taskRepository.observeTask(taskId).collect { update ->
                    _uiState.update { state ->
                        state.copy(
                            tasks = state.tasks.map { task ->
                                if (task.effectiveId == taskId) {
                                    task.copy(
                                        status = update.status ?: task.status,
                                        progress = update.progress ?: task.progress,
                                        message = update.message ?: task.message,
                                        notuleHtml = update.notuleHtml ?: task.notuleHtml,
                                        rawTranscription = update.rawTranscription ?: task.rawTranscription,
                                        errorMessage = update.errorMessage ?: task.errorMessage,
                                    )
                                } else {
                                    task
                                }
                            },
                        )
                    }

                    // Navigate when completed
                    if (update.status == TaskStatus.COMPLETED) {
                        _events.emit(Event.NavigateToTranscript(taskId))
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "SSE stream ended for task $taskId", e)
            } finally {
                sseJobs.remove(taskId)
            }
        }
    }

    private fun startAutoRefresh() {
        viewModelScope.launch {
            while (true) {
                delay(AUTO_REFRESH_INTERVAL_MS)
                // Only auto-refresh if not already loading
                val state = _uiState.value
                if (!state.isLoading && !state.isRefreshing) {
                    try {
                        val tasks = taskRepository.getActiveTasks()
                        _uiState.update { it.copy(tasks = tasks, error = null) }
                    } catch (e: Exception) {
                        Log.w(TAG, "Auto-refresh failed", e)
                    }
                }
            }
        }
    }

    override fun onCleared() {
        super.onCleared()
        sseJobs.values.forEach { it.cancel() }
        sseJobs.clear()
    }
}
