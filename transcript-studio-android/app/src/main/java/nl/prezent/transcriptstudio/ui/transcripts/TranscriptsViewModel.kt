package nl.prezent.transcriptstudio.ui.transcripts

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import nl.prezent.transcriptstudio.data.model.Transcript
import nl.prezent.transcriptstudio.data.repository.TranscriptRepository
import javax.inject.Inject

@OptIn(FlowPreview::class, ExperimentalCoroutinesApi::class)
@HiltViewModel
class TranscriptsViewModel @Inject constructor(
    private val transcriptRepository: TranscriptRepository,
) : ViewModel() {

    data class UiState(
        val transcripts: List<Transcript> = emptyList(),
        val isLoading: Boolean = false,
        val isRefreshing: Boolean = false,
        val searchQuery: String = "",
        val error: String? = null,
    )

    private val _uiState = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()

    private val _searchQuery = MutableStateFlow("")

    init {
        loadTranscripts()
        viewModelScope.launch {
            _searchQuery.debounce(300).collectLatest { query ->
                _uiState.update { it.copy(searchQuery = query) }
                loadTranscripts(search = query)
            }
        }
    }

    fun loadTranscripts(search: String? = null) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = it.transcripts.isEmpty()) }
            try {
                val response = transcriptRepository.getTranscripts(
                    search = search?.takeIf { it.isNotBlank() },
                )
                _uiState.update {
                    it.copy(
                        transcripts = response.items,
                        isLoading = false,
                        isRefreshing = false,
                        error = null,
                    )
                }
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(
                        isLoading = false,
                        isRefreshing = false,
                        error = "Kan transcripties niet laden: ${e.localizedMessage}",
                    )
                }
            }
        }
    }

    fun refresh() {
        _uiState.update { it.copy(isRefreshing = true) }
        loadTranscripts(search = _uiState.value.searchQuery)
    }

    fun updateSearch(query: String) {
        _uiState.update { it.copy(searchQuery = query) }
        _searchQuery.value = query
    }

    fun deleteTranscript(id: String) {
        viewModelScope.launch {
            try {
                transcriptRepository.deleteTranscript(id)
                _uiState.update { state ->
                    state.copy(
                        transcripts = state.transcripts.filter { it.effectiveId != id },
                    )
                }
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(error = "Kan transcriptie niet verwijderen: ${e.localizedMessage}")
                }
            }
        }
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }
}
