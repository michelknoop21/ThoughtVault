package nl.prezent.transcriptstudio.data.repository

import nl.prezent.transcriptstudio.data.model.*
import nl.prezent.transcriptstudio.data.remote.ApiService
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AdminRepository @Inject constructor(
    private val apiService: ApiService,
) {

    // ── Users ────────────────────────────────────────────────────────────

    suspend fun getUsers(): List<AdminUser> = apiService.getAdminUsers().items

    suspend fun createUser(
        username: String,
        password: String,
        name: String? = null,
        role: String = "user",
    ): AdminUser = apiService.createUser(
        CreateUserRequest(username = username, password = password, name = name, role = role)
    )

    suspend fun resetUserPassword(id: String, newPassword: String) {
        apiService.resetUserPassword(id, mapOf("password" to newPassword))
    }

    suspend fun deleteUser(id: String) {
        apiService.deleteUser(id)
    }

    suspend fun resetUser2FA(id: String) {
        apiService.resetUser2FA(id)
    }

    suspend fun getUser2FAStatus(id: String): Map<String, Boolean> =
        apiService.getUser2FAStatus(id)

    // ── Invite Codes ─────────────────────────────────────────────────────

    suspend fun createInviteCode(maxUses: Int = 1, expiresHours: Int = 48): InviteCode =
        apiService.createInviteCode(CreateInviteRequest(maxUses = maxUses, expiresHours = expiresHours))

    suspend fun getInviteCodes(): List<InviteCode> = apiService.getInviteCodes()

    suspend fun deleteInviteCode(code: String) {
        apiService.deleteInviteCode(code)
    }

    // ── Feedback ─────────────────────────────────────────────────────────

    suspend fun getFeedback(
        status: String? = null,
        category: String? = null,
        userId: String? = null,
    ): List<Feedback> = apiService.getAdminFeedback(status = status, category = category, userId = userId)

    suspend fun getFeedbackDetail(id: Int): Feedback = apiService.getAdminFeedbackDetail(id)

    suspend fun updateFeedback(
        id: Int,
        status: String? = null,
        adminResponse: String? = null,
    ): Feedback = apiService.updateAdminFeedback(
        id = id,
        body = FeedbackUpdateRequest(status = status, adminResponse = adminResponse),
    )

    suspend fun deleteFeedback(id: Int) {
        apiService.deleteAdminFeedback(id)
    }

    suspend fun getPendingFeedbackCount(): Int =
        apiService.getPendingFeedbackCount()["count"] ?: 0

    // ── Errors & Metrics ─────────────────────────────────────────────────

    suspend fun getErrorLogs(
        limit: Int? = null,
        severity: String? = null,
        userId: String? = null,
        search: String? = null,
    ): List<ErrorLog> = apiService.getErrorLogs(
        limit = limit, severity = severity, userId = userId, search = search,
    )

    suspend fun getMetrics(): SystemStats = apiService.getMetrics()

    suspend fun getDashboardMetrics(days: Int = 7): SystemStats =
        apiService.getDashboardMetrics(days = days)

    // ── Settings ─────────────────────────────────────────────────────────

    suspend fun getSettings(): AdminSettings = apiService.getAdminSettings()

    suspend fun updateSettings(settings: AdminSettings): AdminSettings =
        apiService.updateAdminSettings(settings)
}
