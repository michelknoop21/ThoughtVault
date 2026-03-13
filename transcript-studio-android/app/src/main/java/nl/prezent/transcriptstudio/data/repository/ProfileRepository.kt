package nl.prezent.transcriptstudio.data.repository

import nl.prezent.transcriptstudio.data.model.*
import nl.prezent.transcriptstudio.data.remote.ApiService
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ProfileRepository @Inject constructor(
    private val apiService: ApiService,
) {

    /**
     * Get all public/default profiles (no auth required).
     */
    suspend fun getPublicProfiles(): List<Profile> =
        apiService.getPublicProfiles()

    /**
     * Get the current user's own profiles with count/limit info.
     */
    suspend fun getMyProfiles(): ProfilesResponse =
        apiService.getMyProfiles()

    /**
     * Get all accessible profiles (default + own + public).
     */
    suspend fun getAccessibleProfiles(): List<Profile> =
        apiService.getAccessibleProfiles()

    suspend fun createProfile(
        name: String,
        description: String? = null,
        icon: String? = null,
        systemPrompt: String? = null,
        notulePrompt: String? = null,
        outputTemplate: String? = null,
        isPublic: Boolean = false,
    ): Profile = apiService.createProfile(
        ProfileCreateRequest(
            name = name,
            description = description,
            icon = icon,
            systemPrompt = systemPrompt,
            notulePrompt = notulePrompt,
            outputTemplate = outputTemplate,
            isPublic = isPublic,
        )
    )

    suspend fun updateProfile(
        profileId: String,
        name: String,
        description: String? = null,
        icon: String? = null,
        systemPrompt: String? = null,
        notulePrompt: String? = null,
        outputTemplate: String? = null,
        isPublic: Boolean = false,
    ): Profile = apiService.updateProfile(
        profileId = profileId,
        body = ProfileCreateRequest(
            name = name,
            description = description,
            icon = icon,
            systemPrompt = systemPrompt,
            notulePrompt = notulePrompt,
            outputTemplate = outputTemplate,
            isPublic = isPublic,
        ),
    )

    suspend fun deleteProfile(profileId: String) {
        apiService.deleteProfile(profileId)
    }
}
