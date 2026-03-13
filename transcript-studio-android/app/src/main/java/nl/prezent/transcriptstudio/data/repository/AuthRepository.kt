package nl.prezent.transcriptstudio.data.repository

import nl.prezent.transcriptstudio.data.model.*
import nl.prezent.transcriptstudio.data.remote.ApiService
import nl.prezent.transcriptstudio.service.SecureTokenStore
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AuthRepository @Inject constructor(
    private val apiService: ApiService,
    private val secureTokenStore: SecureTokenStore,
) {

    /**
     * Login step 1. If 2FA is required, returns a response with [LoginResponse.requires2FA] = true
     * and a [LoginResponse.tempToken]. Otherwise, stores the token and user info.
     */
    suspend fun login(email: String, password: String): LoginResponse {
        val response = apiService.login(
            LoginRequest(username = email, password = password)
        )
        if (!response.requires2FA && response.token != null) {
            storeSession(response)
        }
        return response
    }

    /**
     * Login step 2: verify 2FA code.
     */
    suspend fun verify2FA(email: String, tempToken: String, code: String): LoginResponse {
        val response = apiService.verify2FA(
            TwoFARequest(username = email, tempToken = tempToken, code = code)
        )
        if (response.token != null) {
            storeSession(response)
        }
        return response
    }

    /**
     * Get the current user's profile from the backend.
     */
    suspend fun getMe(): MeResponse {
        val me = apiService.getMe()
        // Refresh cached user info
        secureTokenStore.storeUserInfo(
            userId = me.userId,
            userName = me.name,
            userEmail = me.username,
            userRole = me.role,
        )
        return me
    }

    /**
     * Validate the stored token against the backend.
     * Returns true if the token is still valid.
     */
    suspend fun validateToken(): Boolean {
        return try {
            val response = apiService.validateToken()
            response.isSuccessful
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Logout: invalidate server-side token and clear local storage.
     */
    suspend fun logout() {
        try {
            apiService.logout()
        } catch (_: Exception) {
            // Server-side logout is best-effort
        }
        secureTokenStore.clearAll()
    }

    /**
     * Change the current user's password.
     */
    suspend fun changePassword(currentPassword: String, newPassword: String) {
        apiService.changePassword(
            ChangePasswordRequest(currentPassword = currentPassword, newPassword = newPassword)
        )
    }

    /**
     * Request a password reset code (sent via email by the backend).
     */
    suspend fun requestPasswordReset(email: String) {
        apiService.requestPasswordReset(PasswordResetRequestBody(username = email))
    }

    /**
     * Verify a password reset code. Returns a reset token for the final step.
     */
    suspend fun verifyPasswordReset(email: String, code: String): String {
        val response = apiService.verifyPasswordReset(
            PasswordResetVerifyBody(username = email, code = code)
        )
        return response.resetToken
    }

    /**
     * Complete password reset with the reset token and new password.
     */
    suspend fun completePasswordReset(resetToken: String, newPassword: String) {
        apiService.completePasswordReset(
            PasswordResetCompleteBody(resetToken = resetToken, newPassword = newPassword)
        )
    }

    /**
     * Check if a token is stored locally.
     */
    suspend fun hasStoredToken(): Boolean = secureTokenStore.loadToken() != null

    /**
     * Get the locally stored user role.
     */
    suspend fun getUserRole(): String? = secureTokenStore.getUserRole()

    // ── Private ──────────────────────────────────────────────────────────

    private suspend fun storeSession(response: LoginResponse) {
        response.token?.let { secureTokenStore.storeToken(it) }
        secureTokenStore.storeUserInfo(
            userId = response.userId,
            userName = response.name,
            userEmail = null, // Not in login response
            userRole = response.role,
        )
    }
}
