package nl.prezent.transcriptstudio.data.remote

import nl.prezent.transcriptstudio.data.model.*
import okhttp3.MultipartBody
import okhttp3.RequestBody
import okhttp3.ResponseBody
import retrofit2.Response
import retrofit2.http.*

interface ApiService {

    // ── Auth ──────────────────────────────────────────────────────────────

    @POST("auth/login")
    suspend fun login(@Body request: LoginRequest): LoginResponse

    @POST("auth/login/verify-2fa")
    suspend fun verify2FA(@Body request: TwoFARequest): LoginResponse

    @POST("auth/register")
    suspend fun register(@Body request: RegisterRequest): RegisterResponse

    @POST("auth/logout")
    suspend fun logout(): Response<Unit>

    @GET("auth/validate")
    suspend fun validateToken(): Response<Unit>

    @GET("auth/me")
    suspend fun getMe(): MeResponse

    @POST("auth/change-password")
    suspend fun changePassword(@Body request: ChangePasswordRequest): Response<Unit>

    @POST("auth/password-reset/request")
    suspend fun requestPasswordReset(@Body request: PasswordResetRequestBody): Response<Unit>

    @POST("auth/password-reset/verify")
    suspend fun verifyPasswordReset(@Body request: PasswordResetVerifyBody): PasswordResetVerifyResponse

    @POST("auth/password-reset/complete")
    suspend fun completePasswordReset(@Body request: PasswordResetCompleteBody): Response<Unit>

    // ── Transcribe ───────────────────────────────────────────────────────

    @Multipart
    @POST("transcribe")
    suspend fun transcribe(
        @Part file: MultipartBody.Part,
        @Part("profile_id") profileId: RequestBody,
        @Part("mode") mode: RequestBody? = null,
    ): TranscribeResponse

    @POST("transcribe-text")
    suspend fun transcribeText(@Body body: Map<String, String>): TranscribeResponse

    // ── Tasks ────────────────────────────────────────────────────────────

    @GET("tasks/active")
    suspend fun getActiveTasks(): ActiveTasksResponse

    @GET("task/{taskId}")
    suspend fun getTaskStatus(@Path("taskId") taskId: String): TranscriptTask

    @POST("task/{taskId}/cancel")
    suspend fun cancelTask(@Path("taskId") taskId: String): CancelTaskResponse

    @DELETE("task/{taskId}")
    suspend fun deleteTask(@Path("taskId") taskId: String): Response<Unit>

    @POST("task/{taskId}/regenerate")
    suspend fun regenerateTask(
        @Path("taskId") taskId: String,
        @Body body: TranscriptRegenerateRequest,
    ): TranscribeResponse

    // ── Transcripts ──────────────────────────────────────────────────────

    @GET("transcripts")
    suspend fun getTranscripts(
        @Query("search") search: String? = null,
        @Query("tags") tags: String? = null,
    ): TranscriptsResponse

    @GET("transcripts/tags")
    suspend fun getTranscriptTags(): List<String>

    @GET("transcripts/{taskId}")
    suspend fun getTranscript(@Path("taskId") taskId: String): Transcript

    @PUT("transcripts/{taskId}")
    suspend fun updateTranscript(
        @Path("taskId") taskId: String,
        @Body body: TranscriptUpdateRequest,
    ): Transcript

    @DELETE("transcripts/{taskId}")
    suspend fun deleteTranscript(@Path("taskId") taskId: String): Response<Unit>

    @POST("transcripts/{taskId}/regenerate")
    suspend fun regenerateTranscript(
        @Path("taskId") taskId: String,
        @Body body: TranscriptRegenerateRequest? = null,
    ): TranscribeResponse

    @GET("transcripts/{taskId}/export")
    suspend fun exportTranscript(
        @Path("taskId") taskId: String,
        @Query("format") format: String = "txt",
    ): ResponseBody

    @POST("transcripts/bulk-delete")
    suspend fun bulkDeleteTranscripts(@Body body: BulkDeleteRequest): Response<Unit>

    @POST("transcripts/bulk-tags")
    suspend fun bulkTagTranscripts(@Body body: BulkTagsRequest): Response<Unit>

    // ── Profiles ─────────────────────────────────────────────────────────

    @GET("settings/profiles")
    suspend fun getPublicProfiles(): List<Profile>

    @GET("profiles/me")
    suspend fun getMyProfiles(): ProfilesResponse

    @POST("profiles/me")
    suspend fun createProfile(@Body body: ProfileCreateRequest): Profile

    @GET("profiles/me/{profileId}")
    suspend fun getMyProfile(@Path("profileId") profileId: String): Profile

    @PUT("profiles/me/{profileId}")
    suspend fun updateProfile(
        @Path("profileId") profileId: String,
        @Body body: ProfileCreateRequest,
    ): Profile

    @DELETE("profiles/me/{profileId}")
    suspend fun deleteProfile(@Path("profileId") profileId: String): Response<Unit>

    @GET("profiles/accessible")
    suspend fun getAccessibleProfiles(): ProfilesResponse

    // ── Feedback ─────────────────────────────────────────────────────────

    @POST("feedback")
    suspend fun submitFeedback(@Body body: FeedbackRequest): Feedback

    @GET("feedback/my")
    suspend fun getMyFeedback(): List<Feedback>

    @GET("feedback/unread-count")
    suspend fun getUnreadFeedbackCount(): Map<String, Int>

    @POST("feedback/{id}/mark-read")
    suspend fun markFeedbackRead(@Path("id") id: Int): Response<Unit>

    // ── Admin: Users ─────────────────────────────────────────────────────

    @GET("admin/users")
    suspend fun getAdminUsers(): AdminUsersResponse

    @POST("admin/users")
    suspend fun createUser(@Body body: CreateUserRequest): AdminUser

    @POST("admin/users/{id}/password")
    suspend fun resetUserPassword(@Path("id") id: String, @Body body: Map<String, String>): Response<Unit>

    @DELETE("admin/users/{id}")
    suspend fun deleteUser(@Path("id") id: String): Response<Unit>

    @POST("admin/users/{id}/2fa/reset")
    suspend fun resetUser2FA(@Path("id") id: String): Response<Unit>

    @GET("admin/users/{id}/2fa/status")
    suspend fun getUser2FAStatus(@Path("id") id: String): Map<String, Boolean>

    // ── Admin: Invites ───────────────────────────────────────────────────

    @POST("admin/invites")
    suspend fun createInviteCode(@Body body: CreateInviteRequest): InviteCode

    @GET("admin/invites")
    suspend fun getInviteCodes(): InviteCodesResponse

    @DELETE("admin/invites/{code}")
    suspend fun deleteInviteCode(@Path("code") code: String): Response<Unit>

    // ── Admin: Feedback ──────────────────────────────────────────────────

    @GET("admin/feedback")
    suspend fun getAdminFeedback(
        @Query("status") status: String? = null,
        @Query("category") category: String? = null,
        @Query("user_id") userId: String? = null,
    ): AdminFeedbackResponse

    @GET("admin/feedback/{id}")
    suspend fun getAdminFeedbackDetail(@Path("id") id: Int): Feedback

    @PUT("admin/feedback/{id}")
    suspend fun updateAdminFeedback(
        @Path("id") id: Int,
        @Body body: FeedbackUpdateRequest,
    ): Feedback

    @DELETE("admin/feedback/{id}")
    suspend fun deleteAdminFeedback(@Path("id") id: Int): Response<Unit>

    @GET("admin/feedback/pending-count")
    suspend fun getPendingFeedbackCount(): Map<String, Int>

    // ── Admin: Errors & Metrics ──────────────────────────────────────────

    @GET("admin/errors")
    suspend fun getErrorLogs(
        @Query("limit") limit: Int? = null,
        @Query("severity") severity: String? = null,
        @Query("user_id") userId: String? = null,
        @Query("search") search: String? = null,
    ): ErrorLogsResponse

    @GET("admin/metrics")
    suspend fun getMetrics(): SystemStats

    @GET("admin/dashboard/metrics")
    suspend fun getDashboardMetrics(@Query("days") days: Int = 7): SystemStats

    // ── Admin: Settings ──────────────────────────────────────────────────

    @GET("admin/settings")
    suspend fun getAdminSettings(): AdminSettings

    @POST("admin/settings")
    suspend fun updateAdminSettings(@Body body: AdminSettings): AdminSettings

    // ── Health ───────────────────────────────────────────────────────────

    @GET("health")
    suspend fun health(): Map<String, String>
}
