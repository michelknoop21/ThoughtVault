package nl.prezent.transcriptstudio.ui.login

import androidx.fragment.app.FragmentActivity
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
import nl.prezent.transcriptstudio.data.repository.AuthRepository
import nl.prezent.transcriptstudio.service.BiometricService
import javax.inject.Inject

@HiltViewModel
class LoginViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val biometricService: BiometricService,
) : ViewModel() {

    data class UiState(
        val email: String = "",
        val password: String = "",
        val isLoading: Boolean = false,
        val error: String? = null,
        val requires2FA: Boolean = false,
        val tempToken: String = "",
        val twoFACode: String = "",
        val canUseBiometric: Boolean = false,
    )

    sealed interface Event {
        data object LoginSuccess : Event
    }

    private val _uiState = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()

    private val _events = MutableSharedFlow<Event>()
    val events: SharedFlow<Event> = _events.asSharedFlow()

    fun checkBiometric(activity: FragmentActivity) {
        // Biometric login only makes sense if the device supports it AND there's a stored token
        viewModelScope.launch {
            val canUse = biometricService.canAuthenticate(activity) && authRepository.hasStoredToken()
            _uiState.update { it.copy(canUseBiometric = canUse) }
        }
    }

    fun updateEmail(email: String) {
        _uiState.update { it.copy(email = email, error = null) }
    }

    fun updatePassword(password: String) {
        _uiState.update { it.copy(password = password, error = null) }
    }

    fun update2FACode(code: String) {
        _uiState.update { it.copy(twoFACode = code, error = null) }
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }

    fun login() {
        val state = _uiState.value
        if (state.email.isBlank() || state.password.isBlank()) {
            _uiState.update { it.copy(error = "Vul e-mailadres en wachtwoord in") }
            return
        }

        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            try {
                val response = authRepository.login(state.email.trim(), state.password)
                if (response.requires2FA) {
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            requires2FA = true,
                            tempToken = response.tempToken ?: "",
                        )
                    }
                } else {
                    _uiState.update { it.copy(isLoading = false) }
                    _events.emit(Event.LoginSuccess)
                }
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(isLoading = false, error = "Inloggen mislukt")
                }
            }
        }
    }

    fun verify2FA() {
        val state = _uiState.value
        if (state.twoFACode.isBlank()) {
            _uiState.update { it.copy(error = "Voer de verificatiecode in") }
            return
        }

        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            try {
                authRepository.verify2FA(
                    email = state.email.trim(),
                    tempToken = state.tempToken,
                    code = state.twoFACode.trim(),
                )
                _uiState.update { it.copy(isLoading = false) }
                _events.emit(Event.LoginSuccess)
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(isLoading = false, error = "Ongeldige verificatiecode")
                }
            }
        }
    }

    fun cancel2FA() {
        _uiState.update {
            it.copy(
                requires2FA = false,
                tempToken = "",
                twoFACode = "",
                error = null,
            )
        }
    }

    fun biometricLogin(activity: FragmentActivity) {
        viewModelScope.launch {
            if (!authRepository.hasStoredToken()) {
                _uiState.update { it.copy(error = "Log eerst in met e-mail en wachtwoord") }
                return@launch
            }

            _uiState.update { it.copy(isLoading = true, error = null) }
            try {
                val result = biometricService.authenticate(activity)
                if (result.isSuccess && result.getOrNull() == true) {
                    // Token exists and biometric succeeded — validate with backend
                    authRepository.getMe()
                    _uiState.update { it.copy(isLoading = false) }
                    _events.emit(Event.LoginSuccess)
                } else if (result.isFailure) {
                    _uiState.update {
                        it.copy(isLoading = false, error = "Biometrische verificatie mislukt")
                    }
                } else {
                    // User cancelled
                    _uiState.update { it.copy(isLoading = false) }
                }
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(isLoading = false, error = "Inloggen mislukt")
                }
            }
        }
    }
}
