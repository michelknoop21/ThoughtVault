package nl.prezent.transcriptstudio.ui.recording

import android.content.Context
import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import nl.prezent.transcriptstudio.data.model.Profile
import nl.prezent.transcriptstudio.data.model.TranscribeResponse
import nl.prezent.transcriptstudio.data.remote.ApiService
import nl.prezent.transcriptstudio.data.repository.ProfileRepository
import nl.prezent.transcriptstudio.service.AudioRecorderService
import nl.prezent.transcriptstudio.service.NetworkMonitor
import nl.prezent.transcriptstudio.service.OfflineQueueManager
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import javax.inject.Inject

private const val TAG = "RecordingViewModel"

@HiltViewModel
class RecordingViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    private val audioRecorderService: AudioRecorderService,
    private val profileRepository: ProfileRepository,
    private val apiService: ApiService,
    private val networkMonitor: NetworkMonitor,
    private val offlineQueueManager: OfflineQueueManager,
) : ViewModel() {

    data class UiState(
        val recordingState: AudioRecorderService.State = AudioRecorderService.State.IDLE,
        val audioLevel: Float = 0f,
        val elapsedMs: Long = 0L,
        val profiles: List<Profile> = emptyList(),
        val selectedProfile: Profile? = null,
        val isLoadingProfiles: Boolean = true,
        val isUploading: Boolean = false,
        val error: String? = null,
    ) {
        val isIdle: Boolean get() = recordingState == AudioRecorderService.State.IDLE
        val isRecording: Boolean get() = recordingState == AudioRecorderService.State.RECORDING
        val isPaused: Boolean get() = recordingState == AudioRecorderService.State.PAUSED

        val elapsedFormatted: String get() {
            val totalSeconds = elapsedMs / 1000
            val minutes = totalSeconds / 60
            val seconds = totalSeconds % 60
            return "%02d:%02d".format(minutes, seconds)
        }
    }

    sealed interface Event {
        data class ShowMessage(val message: String) : Event
        data object StartForegroundService : Event
        data object StopForegroundService : Event
    }

    private val _uiState = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()

    private val _events = MutableSharedFlow<Event>()
    val events: SharedFlow<Event> = _events.asSharedFlow()

    private var recordingFile: File? = null
    private var readJob: Job? = null

    init {
        loadProfiles()
        observeRecorderState()
    }

    private fun loadProfiles() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoadingProfiles = true) }
            try {
                val profiles = profileRepository.getAccessibleProfiles()
                val defaultProfile = profiles.firstOrNull { it.isDefault } ?: profiles.firstOrNull()
                _uiState.update {
                    it.copy(
                        profiles = profiles,
                        selectedProfile = it.selectedProfile ?: defaultProfile,
                        isLoadingProfiles = false,
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load profiles", e)
                _uiState.update {
                    it.copy(
                        isLoadingProfiles = false,
                        error = "Kan profielen niet laden",
                    )
                }
            }
        }
    }

    private fun observeRecorderState() {
        viewModelScope.launch {
            audioRecorderService.state.collect { state ->
                _uiState.update { it.copy(recordingState = state) }
            }
        }
        viewModelScope.launch {
            audioRecorderService.audioLevel.collect { level ->
                _uiState.update { it.copy(audioLevel = level) }
            }
        }
        viewModelScope.launch {
            audioRecorderService.elapsedMs.collect { ms ->
                _uiState.update { it.copy(elapsedMs = ms) }
            }
        }
    }

    fun selectProfile(profile: Profile) {
        _uiState.update { it.copy(selectedProfile = profile) }
    }

    fun startRecording() {
        if (!_uiState.value.isIdle) return

        viewModelScope.launch {
            try {
                _uiState.update { it.copy(error = null) }

                val outputDir = File(context.filesDir, "recordings").also { it.mkdirs() }
                recordingFile = audioRecorderService.start(outputDir)

                // Start reading audio data on IO dispatcher
                readJob = viewModelScope.launch(Dispatchers.IO) {
                    audioRecorderService.readLoop()
                }

                _events.emit(Event.StartForegroundService)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start recording", e)
                _uiState.update { it.copy(error = "Kan opname niet starten: ${e.message}") }
            }
        }
    }

    fun pauseRecording() {
        audioRecorderService.pause()
    }

    fun resumeRecording() {
        audioRecorderService.resume()
    }

    fun stopRecording() {
        viewModelScope.launch {
            _events.emit(Event.StopForegroundService)

            readJob?.cancel()
            readJob = null

            val file = audioRecorderService.stop() ?: return@launch
            recordingFile = file

            uploadRecording(file)
        }
    }

    fun cancelRecording() {
        viewModelScope.launch {
            _events.emit(Event.StopForegroundService)

            readJob?.cancel()
            readJob = null

            audioRecorderService.cancel()
            recordingFile = null
        }
    }

    fun dismissError() {
        _uiState.update { it.copy(error = null) }
    }

    private fun uploadRecording(file: File) {
        val profileId = _uiState.value.selectedProfile?.id ?: return

        viewModelScope.launch {
            _uiState.update { it.copy(isUploading = true, error = null) }

            if (!networkMonitor.isOnline.value) {
                // Queue for later upload
                try {
                    offlineQueueManager.enqueue(
                        filePath = file.absolutePath,
                        profileId = profileId.toIntOrNull() ?: 0,
                        type = "audio",
                    )
                    _uiState.update { it.copy(isUploading = false) }
                    _events.emit(Event.ShowMessage("Opname in wachtrij (geen verbinding)"))
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to queue recording", e)
                    _uiState.update {
                        it.copy(
                            isUploading = false,
                            error = "Kan opname niet in wachtrij plaatsen",
                        )
                    }
                }
                return@launch
            }

            try {
                val requestFile = file.asRequestBody("audio/wav".toMediaType())
                val filePart = MultipartBody.Part.createFormData("file", file.name, requestFile)
                val profileIdBody = profileId.toRequestBody("text/plain".toMediaType())

                val response: TranscribeResponse = apiService.transcribe(filePart, profileIdBody)

                _uiState.update { it.copy(isUploading = false) }
                _events.emit(Event.ShowMessage("Opname verzonden voor verwerking"))
                Log.d(TAG, "Upload successful: task_id=${response.taskId}")
            } catch (e: Exception) {
                Log.e(TAG, "Upload failed, queueing for retry", e)

                // Fall back to offline queue
                try {
                    offlineQueueManager.enqueue(
                        filePath = file.absolutePath,
                        profileId = profileId.toIntOrNull() ?: 0,
                        type = "audio",
                    )
                    _uiState.update { it.copy(isUploading = false) }
                    _events.emit(Event.ShowMessage("Upload mislukt, opname in wachtrij geplaatst"))
                } catch (queueError: Exception) {
                    Log.e(TAG, "Failed to queue recording after upload failure", queueError)
                    _uiState.update {
                        it.copy(
                            isUploading = false,
                            error = "Upload mislukt: ${e.message}",
                        )
                    }
                }
            }
        }
    }

    override fun onCleared() {
        super.onCleared()
        // If still recording when ViewModel is cleared, stop gracefully
        if (_uiState.value.recordingState != AudioRecorderService.State.IDLE) {
            readJob?.cancel()
            audioRecorderService.cancel()
        }
    }
}
