package nl.prezent.transcriptstudio.ui.admin

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import nl.prezent.transcriptstudio.data.model.AdminSettings
import nl.prezent.transcriptstudio.data.model.AdminUser
import nl.prezent.transcriptstudio.data.model.ErrorLog
import nl.prezent.transcriptstudio.data.model.Feedback
import nl.prezent.transcriptstudio.data.model.InviteCode
import nl.prezent.transcriptstudio.data.model.SystemStats
import nl.prezent.transcriptstudio.data.repository.AdminRepository
import javax.inject.Inject

private const val TAG = "AdminViewModel"

@HiltViewModel
class AdminViewModel @Inject constructor(
    private val adminRepository: AdminRepository,
) : ViewModel() {

    data class UiState(
        // Tab selection
        val selectedTab: Int = 0,

        // Dashboard
        val stats: SystemStats? = null,
        val statsLoading: Boolean = false,

        // Users
        val users: List<AdminUser> = emptyList(),
        val usersLoading: Boolean = false,

        // Invite codes
        val inviteCodes: List<InviteCode> = emptyList(),
        val inviteCodesLoading: Boolean = false,

        // Feedback
        val feedbackItems: List<Feedback> = emptyList(),
        val feedbackLoading: Boolean = false,

        // Error logs
        val errorLogs: List<ErrorLog> = emptyList(),
        val errorLogsLoading: Boolean = false,
        val errorSeverityFilter: String? = null,

        // Settings
        val settings: AdminSettings? = null,
        val settingsLoading: Boolean = false,
        val settingsSaving: Boolean = false,

        // Global
        val error: String? = null,
        val successMessage: String? = null,

        // Track which tabs have been loaded
        val loadedTabs: Set<Int> = emptySet(),
    )

    private val _uiState = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()

    init {
        loadDashboard()
    }

    fun selectTab(tab: Int) {
        _uiState.update { it.copy(selectedTab = tab, error = null, successMessage = null) }
        if (tab !in _uiState.value.loadedTabs) {
            loadTabData(tab)
        }
    }

    private fun loadTabData(tab: Int) {
        when (tab) {
            0 -> loadDashboard()
            1 -> loadUsers()
            2 -> loadInviteCodes()
            3 -> loadFeedback()
            4 -> loadErrorLogs()
            5 -> loadSettings()
        }
    }

    fun refreshCurrentTab() {
        loadTabData(_uiState.value.selectedTab)
    }

    fun clearMessages() {
        _uiState.update { it.copy(error = null, successMessage = null) }
    }

    // ── Dashboard ───────────────────────────────────────────────────────

    private fun loadDashboard() {
        viewModelScope.launch {
            _uiState.update { it.copy(statsLoading = true, error = null) }
            try {
                val stats = adminRepository.getDashboardMetrics(days = 7)
                _uiState.update {
                    it.copy(
                        stats = stats,
                        statsLoading = false,
                        loadedTabs = it.loadedTabs + 0,
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load dashboard", e)
                _uiState.update {
                    it.copy(
                        statsLoading = false,
                        error = "Kan dashboard niet laden: ${e.localizedMessage}",
                    )
                }
            }
        }
    }

    // ── Users ───────────────────────────────────────────────────────────

    private fun loadUsers() {
        viewModelScope.launch {
            _uiState.update { it.copy(usersLoading = true, error = null) }
            try {
                val users = adminRepository.getUsers()
                _uiState.update {
                    it.copy(
                        users = users,
                        usersLoading = false,
                        loadedTabs = it.loadedTabs + 1,
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load users", e)
                _uiState.update {
                    it.copy(
                        usersLoading = false,
                        error = "Kan gebruikers niet laden: ${e.localizedMessage}",
                    )
                }
            }
        }
    }

    fun createUser(username: String, password: String, name: String?, role: String) {
        viewModelScope.launch {
            try {
                adminRepository.createUser(username, password, name, role)
                _uiState.update { it.copy(successMessage = "Gebruiker aangemaakt") }
                loadUsers()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to create user", e)
                _uiState.update {
                    it.copy(error = "Kan gebruiker niet aanmaken: ${e.localizedMessage}")
                }
            }
        }
    }

    fun resetUserPassword(userId: String, newPassword: String) {
        viewModelScope.launch {
            try {
                adminRepository.resetUserPassword(userId, newPassword)
                _uiState.update { it.copy(successMessage = "Wachtwoord gereset") }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to reset password", e)
                _uiState.update {
                    it.copy(error = "Kan wachtwoord niet resetten: ${e.localizedMessage}")
                }
            }
        }
    }

    fun resetUser2FA(userId: String) {
        viewModelScope.launch {
            try {
                adminRepository.resetUser2FA(userId)
                _uiState.update { it.copy(successMessage = "2FA gereset") }
                loadUsers()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to reset 2FA", e)
                _uiState.update {
                    it.copy(error = "Kan 2FA niet resetten: ${e.localizedMessage}")
                }
            }
        }
    }

    fun deleteUser(userId: String) {
        viewModelScope.launch {
            try {
                adminRepository.deleteUser(userId)
                _uiState.update {
                    it.copy(
                        users = it.users.filter { u -> u.id != userId },
                        successMessage = "Gebruiker verwijderd",
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to delete user", e)
                _uiState.update {
                    it.copy(error = "Kan gebruiker niet verwijderen: ${e.localizedMessage}")
                }
            }
        }
    }

    // ── Invite Codes ────────────────────────────────────────────────────

    private fun loadInviteCodes() {
        viewModelScope.launch {
            _uiState.update { it.copy(inviteCodesLoading = true, error = null) }
            try {
                val codes = adminRepository.getInviteCodes()
                _uiState.update {
                    it.copy(
                        inviteCodes = codes,
                        inviteCodesLoading = false,
                        loadedTabs = it.loadedTabs + 2,
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load invite codes", e)
                _uiState.update {
                    it.copy(
                        inviteCodesLoading = false,
                        error = "Kan uitnodigingscodes niet laden: ${e.localizedMessage}",
                    )
                }
            }
        }
    }

    fun createInviteCode(maxUses: Int, expiresHours: Int) {
        viewModelScope.launch {
            try {
                adminRepository.createInviteCode(maxUses, expiresHours)
                _uiState.update { it.copy(successMessage = "Uitnodigingscode aangemaakt") }
                loadInviteCodes()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to create invite code", e)
                _uiState.update {
                    it.copy(error = "Kan code niet aanmaken: ${e.localizedMessage}")
                }
            }
        }
    }

    fun deleteInviteCode(code: String) {
        viewModelScope.launch {
            try {
                adminRepository.deleteInviteCode(code)
                _uiState.update {
                    it.copy(
                        inviteCodes = it.inviteCodes.filter { c -> c.code != code },
                        successMessage = "Code verwijderd",
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to delete invite code", e)
                _uiState.update {
                    it.copy(error = "Kan code niet verwijderen: ${e.localizedMessage}")
                }
            }
        }
    }

    // ── Feedback ────────────────────────────────────────────────────────

    private fun loadFeedback() {
        viewModelScope.launch {
            _uiState.update { it.copy(feedbackLoading = true, error = null) }
            try {
                val feedback = adminRepository.getFeedback()
                _uiState.update {
                    it.copy(
                        feedbackItems = feedback,
                        feedbackLoading = false,
                        loadedTabs = it.loadedTabs + 3,
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load feedback", e)
                _uiState.update {
                    it.copy(
                        feedbackLoading = false,
                        error = "Kan feedback niet laden: ${e.localizedMessage}",
                    )
                }
            }
        }
    }

    fun updateFeedbackStatus(feedbackId: Int, status: String) {
        viewModelScope.launch {
            try {
                val updated = adminRepository.updateFeedback(feedbackId, status = status)
                _uiState.update { state ->
                    state.copy(
                        feedbackItems = state.feedbackItems.map { f ->
                            if (f.id == feedbackId) updated else f
                        },
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to update feedback", e)
                _uiState.update {
                    it.copy(error = "Kan feedback niet bijwerken: ${e.localizedMessage}")
                }
            }
        }
    }

    fun updateFeedbackResponse(feedbackId: Int, adminResponse: String) {
        viewModelScope.launch {
            try {
                val updated = adminRepository.updateFeedback(feedbackId, adminResponse = adminResponse)
                _uiState.update { state ->
                    state.copy(
                        feedbackItems = state.feedbackItems.map { f ->
                            if (f.id == feedbackId) updated else f
                        },
                        successMessage = "Reactie opgeslagen",
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to update feedback response", e)
                _uiState.update {
                    it.copy(error = "Kan reactie niet opslaan: ${e.localizedMessage}")
                }
            }
        }
    }

    fun deleteFeedback(feedbackId: Int) {
        viewModelScope.launch {
            try {
                adminRepository.deleteFeedback(feedbackId)
                _uiState.update {
                    it.copy(
                        feedbackItems = it.feedbackItems.filter { f -> f.id != feedbackId },
                        successMessage = "Feedback verwijderd",
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to delete feedback", e)
                _uiState.update {
                    it.copy(error = "Kan feedback niet verwijderen: ${e.localizedMessage}")
                }
            }
        }
    }

    // ── Error Logs ──────────────────────────────────────────────────────

    private fun loadErrorLogs() {
        viewModelScope.launch {
            val severity = _uiState.value.errorSeverityFilter
            _uiState.update { it.copy(errorLogsLoading = true, error = null) }
            try {
                val logs = adminRepository.getErrorLogs(limit = 100, severity = severity)
                _uiState.update {
                    it.copy(
                        errorLogs = logs,
                        errorLogsLoading = false,
                        loadedTabs = it.loadedTabs + 4,
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load error logs", e)
                _uiState.update {
                    it.copy(
                        errorLogsLoading = false,
                        error = "Kan logs niet laden: ${e.localizedMessage}",
                    )
                }
            }
        }
    }

    fun setErrorSeverityFilter(severity: String?) {
        _uiState.update { it.copy(errorSeverityFilter = severity) }
        loadErrorLogs()
    }

    // ── Settings ────────────────────────────────────────────────────────

    private fun loadSettings() {
        viewModelScope.launch {
            _uiState.update { it.copy(settingsLoading = true, error = null) }
            try {
                val settings = adminRepository.getSettings()
                _uiState.update {
                    it.copy(
                        settings = settings,
                        settingsLoading = false,
                        loadedTabs = it.loadedTabs + 5,
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load settings", e)
                _uiState.update {
                    it.copy(
                        settingsLoading = false,
                        error = "Kan instellingen niet laden: ${e.localizedMessage}",
                    )
                }
            }
        }
    }

    fun updateSettings(settings: AdminSettings) {
        viewModelScope.launch {
            _uiState.update { it.copy(settingsSaving = true, error = null) }
            try {
                val updated = adminRepository.updateSettings(settings)
                _uiState.update {
                    it.copy(
                        settings = updated,
                        settingsSaving = false,
                        successMessage = "Instellingen opgeslagen",
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to update settings", e)
                _uiState.update {
                    it.copy(
                        settingsSaving = false,
                        error = "Kan instellingen niet opslaan: ${e.localizedMessage}",
                    )
                }
            }
        }
    }
}
