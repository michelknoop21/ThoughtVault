package nl.prezent.transcriptstudio.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class LoginRequest(
    val username: String,
    val password: String,
)

@Serializable
data class LoginResponse(
    val token: String? = null,
    @SerialName("user_id") val userId: String? = null,
    val role: String? = null,
    val name: String? = null,
    @SerialName("requires_2fa") val requires2FA: Boolean = false,
    @SerialName("temp_token") val tempToken: String? = null,
    val message: String? = null,
)

@Serializable
data class TwoFARequest(
    val username: String,
    @SerialName("temp_token") val tempToken: String,
    val code: String,
)

@Serializable
data class RegisterRequest(
    val username: String,
    val password: String,
    @SerialName("invite_code") val inviteCode: String,
)

@Serializable
data class RegisterResponse(
    @SerialName("user_id") val userId: String? = null,
    val username: String? = null,
    @SerialName("qr_code") val qrCode: String? = null,
    @SerialName("totp_secret") val totpSecret: String? = null,
    @SerialName("require_2fa_setup") val require2FASetup: Boolean = false,
)

@Serializable
data class ChangePasswordRequest(
    @SerialName("current_password") val currentPassword: String,
    @SerialName("new_password") val newPassword: String,
)

@Serializable
data class PasswordResetRequestBody(
    val username: String,
)

@Serializable
data class PasswordResetVerifyBody(
    val username: String,
    val code: String,
)

@Serializable
data class PasswordResetVerifyResponse(
    @SerialName("reset_token") val resetToken: String,
)

@Serializable
data class PasswordResetCompleteBody(
    @SerialName("reset_token") val resetToken: String,
    @SerialName("new_password") val newPassword: String,
)

@Serializable
data class User(
    @SerialName("user_id") val userId: String? = null,
    val id: String? = null,
    val username: String,
    val name: String? = null,
    val role: String = "user",
    @SerialName("is_active") val isActive: Boolean = true,
) {
    val effectiveId: String get() = userId ?: id ?: ""
}

@Serializable
data class MeResponse(
    @SerialName("user_id") val userId: String,
    val username: String,
    val name: String? = null,
    val role: String = "user",
)
