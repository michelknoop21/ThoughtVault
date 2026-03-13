package nl.prezent.transcriptstudio.ui.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import nl.prezent.transcriptstudio.data.model.FeedbackRequest
import nl.prezent.transcriptstudio.data.remote.ApiService
import nl.prezent.transcriptstudio.data.repository.AuthRepository
import nl.prezent.transcriptstudio.service.SecureTokenStore
import nl.prezent.transcriptstudio.service.SettingsRepository
import javax.inject.Inject

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val settingsRepository: SettingsRepository,
    private val authRepository: AuthRepository,
    private val secureTokenStore: SecureTokenStore,
    private val apiService: ApiService,
) : ViewModel() {

    data class UiState(
        // Server
        val baseUrl: String = SettingsRepository.DEFAULT_BASE_URL,
        val apiPrefix: String = SettingsRepository.DEFAULT_API_PREFIX,
        val serverSaving: Boolean = false,
        val connectionStatus: ConnectionStatus = ConnectionStatus.Unknown,

        // Account
        val userName: String = "",
        val userEmail: String = "",
        val userRole: String = "user",

        // Password change
        val currentPassword: String = "",
        val newPassword: String = "",
        val confirmPassword: String = "",
        val passwordChanging: Boolean = false,
        val passwordError: String? = null,
        val passwordSuccess: Boolean = false,

        // Feedback
        val feedbackCategory: String = "Bug",
        val feedbackTitle: String = "",
        val feedbackDescription: String = "",
        val feedbackSubmitting: Boolean = false,
        val feedbackSuccess: Boolean = false,

        // General
        val isAdmin: Boolean = false,
    )

    enum class ConnectionStatus {
        Unknown, Checking, Connected, Error
    }

    sealed interface Event {
        data object Logout : Event
        data object NavigateToAdmin : Event
    }

    private val _uiState = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()

    private val _events = MutableSharedFlow<Event>()
    val events: SharedFlow<Event> = _events.asSharedFlow()

    init {
        loadSettings()
    }

    private fun loadSettings() {
        viewModelScope.launch {
            val baseUrl = settingsRepository.baseUrl.first()
            val apiPrefix = settingsRepository.apiPrefix.first()
            val userName = secureTokenStore.getUserName() ?: ""
            val userEmail = secureTokenStore.getUserEmail() ?: ""
            val userRole = secureTokenStore.getUserRole() ?: "user"

            _uiState.update {
                it.copy(
                    baseUrl = baseUrl,
                    apiPrefix = apiPrefix,
                    userName = userName,
                    userEmail = userEmail,
                    userRole = userRole,
                    isAdmin = userRole == "admin",
                )
            }

            checkConnection()
        }
    }

    // ── Server ──────────────────────────────────────────────────────────

    fun updateBaseUrl(url: String) {
        _uiState.update { it.copy(baseUrl = url) }
    }

    fun updateApiPrefix(prefix: String) {
        _uiState.update { it.copy(apiPrefix = prefix) }
    }

    fun saveServerSettings() {
        viewModelScope.launch {
            _uiState.update { it.copy(serverSaving = true) }
            settingsRepository.setBaseUrl(_uiState.value.baseUrl.trim())
            settingsRepository.setApiPrefix(_uiState.value.apiPrefix.trim())
            _uiState.update { it.copy(serverSaving = false) }
            checkConnection()
        }
    }

    fun checkConnection() {
        viewModelScope.launch {
            _uiState.update { it.copy(connectionStatus = ConnectionStatus.Checking) }
            try {
                apiService.health()
                _uiState.update { it.copy(connectionStatus = ConnectionStatus.Connected) }
            } catch (_: Exception) {
                _uiState.update { it.copy(connectionStatus = ConnectionStatus.Error) }
            }
        }
    }

    // ── Password ────────────────────────────────────────────────────────

    fun updateCurrentPassword(value: String) {
        _uiState.update { it.copy(currentPassword = value, passwordError = null, passwordSuccess = false) }
    }

    fun updateNewPassword(value: String) {
        _uiState.update { it.copy(newPassword = value, passwordError = null, passwordSuccess = false) }
    }

    fun updateConfirmPassword(value: String) {
        _uiState.update { it.copy(confirmPassword = value, passwordError = null, passwordSuccess = false) }
    }

    fun changePassword() {
        val state = _uiState.value
        if (state.currentPassword.isBlank() || state.newPassword.isBlank()) {
            _uiState.update { it.copy(passwordError = "Vul alle velden in") }
            return
        }
        if (state.newPassword != state.confirmPassword) {
            _uiState.update { it.copy(passwordError = "Wachtwoorden komen niet overeen") }
            return
        }
        if (state.newPassword.length < 8) {
            _uiState.update { it.copy(passwordError = "Wachtwoord moet minimaal 8 tekens zijn") }
            return
        }

        viewModelScope.launch {
            _uiState.update { it.copy(passwordChanging = true, passwordError = null) }
            try {
                authRepository.changePassword(state.currentPassword, state.newPassword)
                _uiState.update {
                    it.copy(
                        passwordChanging = false,
                        passwordSuccess = true,
                        currentPassword = "",
                        newPassword = "",
                        confirmPassword = "",
                    )
                }
            } catch (_: Exception) {
                _uiState.update {
                    it.copy(
                        passwordChanging = false,
                        passwordError = "Wachtwoord wijzigen mislukt",
                    )
                }
            }
        }
    }

    // ── Feedback ────────────────────────────────────────────────────────

    fun updateFeedbackCategory(category: String) {
        _uiState.update { it.copy(feedbackCategory = category) }
    }

    fun updateFeedbackTitle(title: String) {
        _uiState.update { it.copy(feedbackTitle = title) }
    }

    fun updateFeedbackDescription(description: String) {
        _uiState.update { it.copy(feedbackDescription = description) }
    }

    fun submitFeedback() {
        val state = _uiState.value
        if (state.feedbackTitle.isBlank() || state.feedbackDescription.isBlank()) return

        viewModelScope.launch {
            _uiState.update { it.copy(feedbackSubmitting = true) }
            try {
                apiService.submitFeedback(
                    FeedbackRequest(
                        category = state.feedbackCategory.lowercase(),
                        title = state.feedbackTitle,
                        description = state.feedbackDescription,
                    )
                )
                _uiState.update {
                    it.copy(
                        feedbackSubmitting = false,
                        feedbackSuccess = true,
                        feedbackTitle = "",
                        feedbackDescription = "",
                    )
                }
            } catch (_: Exception) {
                _uiState.update { it.copy(feedbackSubmitting = false) }
            }
        }
    }

    fun clearFeedbackSuccess() {
        _uiState.update { it.copy(feedbackSuccess = false) }
    }

    // ── Account actions ─────────────────────────────────────────────────

    fun logout() {
        viewModelScope.launch {
            authRepository.logout()
            _events.emit(Event.Logout)
        }
    }

    fun navigateToAdmin() {
        viewModelScope.launch {
            _events.emit(Event.NavigateToAdmin)
        }
    }
}
