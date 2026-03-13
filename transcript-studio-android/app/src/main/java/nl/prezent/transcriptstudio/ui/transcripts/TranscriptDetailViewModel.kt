package nl.prezent.transcriptstudio.ui.transcripts

import android.content.Context
import android.content.Intent
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import nl.prezent.transcriptstudio.data.model.Profile
import nl.prezent.transcriptstudio.data.model.Transcript
import nl.prezent.transcriptstudio.data.repository.ProfileRepository
import nl.prezent.transcriptstudio.data.repository.TranscriptRepository
import javax.inject.Inject

@HiltViewModel
class TranscriptDetailViewModel @Inject constructor(
    private val transcriptRepository: TranscriptRepository,
    private val profileRepository: ProfileRepository,
    private val savedStateHandle: SavedStateHandle,
) : ViewModel() {

    data class UiState(
        val transcript: Transcript? = null,
        val profiles: List<Profile> = emptyList(),
        val isLoading: Boolean = true,
        val isEditing: Boolean = false,
        val editTitle: String = "",
        val error: String? = null,
        val showRegenerateDialog: Boolean = false,
        val showDeleteDialog: Boolean = false,
        val selectedTab: Int = 0, // 0 = Notulen, 1 = Transcriptie
    )

    sealed class Event {
        data object NavigateBack : Event()
    }

    private val _uiState = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()

    private val _events = MutableSharedFlow<Event>()
    val events: SharedFlow<Event> = _events.asSharedFlow()

    private val transcriptId: String
        get() = savedStateHandle.get<String>("id") ?: ""

    init {
        loadTranscript()
        loadProfiles()
    }

    fun loadTranscript() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }
            try {
                val transcript = transcriptRepository.getTranscript(transcriptId)
                _uiState.update {
                    it.copy(
                        transcript = transcript,
                        isLoading = false,
                        error = null,
                    )
                }
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(
                        isLoading = false,
                        error = "Kan transcriptie niet laden: ${e.localizedMessage}",
                    )
                }
            }
        }
    }

    private fun loadProfiles() {
        viewModelScope.launch {
            try {
                val profiles = profileRepository.getAccessibleProfiles()
                _uiState.update { it.copy(profiles = profiles) }
            } catch (_: Exception) {
                // Profiles are optional — fail silently
            }
        }
    }

    fun startEditTitle() {
        _uiState.update {
            it.copy(
                isEditing = true,
                editTitle = it.transcript?.effectiveTitle ?: "",
            )
        }
    }

    fun cancelEditTitle() {
        _uiState.update { it.copy(isEditing = false) }
    }

    fun saveTitle(newTitle: String) {
        viewModelScope.launch {
            try {
                val updated = transcriptRepository.updateTranscript(
                    taskId = transcriptId,
                    title = newTitle,
                )
                _uiState.update {
                    it.copy(
                        transcript = updated,
                        isEditing = false,
                    )
                }
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(
                        isEditing = false,
                        error = "Kan titel niet opslaan: ${e.localizedMessage}",
                    )
                }
            }
        }
    }

    fun updateEditTitle(title: String) {
        _uiState.update { it.copy(editTitle = title) }
    }

    fun showRegenerateDialog() {
        _uiState.update { it.copy(showRegenerateDialog = true) }
    }

    fun hideRegenerateDialog() {
        _uiState.update { it.copy(showRegenerateDialog = false) }
    }

    fun regenerateNotule(profileId: String?) {
        viewModelScope.launch {
            _uiState.update { it.copy(showRegenerateDialog = false) }
            try {
                transcriptRepository.regenerateNotule(
                    taskId = transcriptId,
                    profileId = profileId,
                )
                // Reload to get updated data
                loadTranscript()
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(error = "Kan notulen niet opnieuw genereren: ${e.localizedMessage}")
                }
            }
        }
    }

    fun showDeleteDialog() {
        _uiState.update { it.copy(showDeleteDialog = true) }
    }

    fun hideDeleteDialog() {
        _uiState.update { it.copy(showDeleteDialog = false) }
    }

    fun deleteTranscript() {
        viewModelScope.launch {
            _uiState.update { it.copy(showDeleteDialog = false) }
            try {
                transcriptRepository.deleteTranscript(transcriptId)
                _events.emit(Event.NavigateBack)
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(error = "Kan transcriptie niet verwijderen: ${e.localizedMessage}")
                }
            }
        }
    }

    fun selectTab(index: Int) {
        _uiState.update { it.copy(selectedTab = index) }
    }

    fun shareTranscript(context: Context) {
        val transcript = _uiState.value.transcript ?: return
        val html = transcript.effectiveNotuleHtml ?: transcript.effectiveTranscription ?: return
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/html"
            putExtra(Intent.EXTRA_SUBJECT, transcript.effectiveTitle)
            putExtra(Intent.EXTRA_HTML_TEXT, html)
            putExtra(Intent.EXTRA_TEXT, html) // Fallback for apps that don't support HTML
        }
        context.startActivity(Intent.createChooser(intent, "Delen via"))
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }
}
