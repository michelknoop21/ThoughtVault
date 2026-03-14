package nl.prezent.transcriptstudio.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class AdminUser(
    val id: String? = null,
    val username: String,
    val name: String? = null,
    val role: String = "user",
    @SerialName("is_active") val isActive: Boolean = true,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
    @SerialName("last_login") val lastLogin: String? = null,
    @SerialName("twofa_enabled") val twofaEnabled: Boolean? = null,
    @SerialName("note_count") val noteCount: Int? = null,
    @SerialName("invite_code_used") val inviteCodeUsed: String? = null,
)

@Serializable
data class AdminUsersResponse(
    val items: List<AdminUser> = emptyList(),
)

@Serializable
data class CreateUserRequest(
    val username: String,
    val password: String,
    val name: String? = null,
    val role: String = "user",
)

@Serializable
data class InviteCode(
    val id: Int? = null,
    val code: String,
    @SerialName("max_uses") val maxUses: Int = 1,
    @SerialName("current_uses") val currentUses: Int = 0,
    @SerialName("expires_at") val expiresAt: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("is_active") val isActive: Boolean = true,
)

@Serializable
data class CreateInviteRequest(
    @SerialName("max_uses") val maxUses: Int = 1,
    @SerialName("expires_hours") val expiresHours: Int = 48,
)

@Serializable
data class Feedback(
    val id: Int? = null,
    val category: String? = null,
    val title: String? = null,
    val description: String? = null,
    val status: String? = null,
    @SerialName("admin_response") val adminResponse: String? = null,
    @SerialName("user_id") val userId: String? = null,
    val username: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
)

@Serializable
data class FeedbackRequest(
    val category: String,
    val title: String,
    val description: String,
)

@Serializable
data class FeedbackUpdateRequest(
    val status: String? = null,
    @SerialName("admin_response") val adminResponse: String? = null,
)

@Serializable
data class ErrorLog(
    val id: Int? = null,
    val severity: String? = null,
    val message: String? = null,
    @SerialName("stack_trace") val stackTrace: String? = null,
    @SerialName("user_id") val userId: String? = null,
    val username: String? = null,
    val endpoint: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
)

@Serializable
data class SystemStats(
    @SerialName("total_users") val totalUsers: Int = 0,
    @SerialName("active_users") val activeUsers: Int = 0,
    @SerialName("total_tasks") val totalTasks: Int = 0,
    @SerialName("total_notes") val totalNotes: Int = 0,
    @SerialName("active_tasks") val activeTasks: Int = 0,
    @SerialName("pending_feedback") val pendingFeedback: Int = 0,
    @SerialName("error_count") val errorCount: Int = 0,
)

@Serializable
data class AdminSettings(
    val webhookUrl: String? = null,
    val notificationWebhookUrl: String? = null,
    @SerialName("ms365_client_id") val ms365ClientId: String? = null,
    @SerialName("ms365_tenant_id") val ms365TenantId: String? = null,
)
