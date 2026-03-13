package nl.prezent.transcriptstudio.ui.home

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import nl.prezent.transcriptstudio.data.model.Transcript
import nl.prezent.transcriptstudio.data.model.TranscriptTask
import nl.prezent.transcriptstudio.data.repository.TaskRepository
import nl.prezent.transcriptstudio.data.repository.TranscriptRepository
import nl.prezent.transcriptstudio.service.SecureTokenStore
import java.util.Calendar
import javax.inject.Inject

private const val TAG = "HomeViewModel"
private const val RECENT_TRANSCRIPTS_LIMIT = 5

@HiltViewModel
class HomeViewModel @Inject constructor(
    private val taskRepository: TaskRepository,
    private val transcriptRepository: TranscriptRepository,
    private val secureTokenStore: SecureTokenStore,
) : ViewModel() {

    data class UiState(
        val userName: String? = null,
        val greetingType: GreetingType = GreetingType.fromCurrentTime(),
        val activeTasks: List<TranscriptTask> = emptyList(),
        val recentTranscripts: List<Transcript> = emptyList(),
        val isLoading: Boolean = true,
        val isRefreshing: Boolean = false,
        val error: String? = null,
    )

    enum class GreetingType {
        MORNING,
        AFTERNOON,
        EVENING;

        companion object {
            fun fromCurrentTime(): GreetingType {
                val hour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
                return when {
                    hour < 12 -> MORNING
                    hour < 18 -> AFTERNOON
                    else -> EVENING
                }
            }
        }
    }

    private val _uiState = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()

    init {
        loadUserName()
        loadData()
    }

    private fun loadUserName() {
        viewModelScope.launch {
            val name = secureTokenStore.getUserName()
            _uiState.update { it.copy(userName = name) }
        }
    }

    fun loadData() {
        viewModelScope.launch {
            _uiState.update {
                it.copy(
                    isLoading = it.activeTasks.isEmpty() && it.recentTranscripts.isEmpty(),
                    error = null,
                    greetingType = GreetingType.fromCurrentTime(),
                )
            }

            try {
                val tasks = taskRepository.getActiveTasks()
                val transcripts = transcriptRepository.getTranscripts()
                val recent = transcripts.items.take(RECENT_TRANSCRIPTS_LIMIT)

                _uiState.update {
                    it.copy(
                        activeTasks = tasks,
                        recentTranscripts = recent,
                        isLoading = false,
                        error = null,
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load home data", e)
                _uiState.update {
                    it.copy(
                        isLoading = false,
                        error = "Kan gegevens niet laden. Probeer het opnieuw.",
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
                val transcripts = transcriptRepository.getTranscripts()
                val recent = transcripts.items.take(RECENT_TRANSCRIPTS_LIMIT)

                _uiState.update {
                    it.copy(
                        activeTasks = tasks,
                        recentTranscripts = recent,
                        isRefreshing = false,
                        error = null,
                        greetingType = GreetingType.fromCurrentTime(),
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to refresh home data", e)
                _uiState.update {
                    it.copy(
                        isRefreshing = false,
                        error = "Kan gegevens niet laden. Probeer het opnieuw.",
                    )
                }
            }
        }
    }
}
