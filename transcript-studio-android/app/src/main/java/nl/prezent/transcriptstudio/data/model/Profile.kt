package nl.prezent.transcriptstudio.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class Profile(
    val id: String? = null,
    val name: String,
    val description: String? = null,
    val icon: String? = null,
    @SerialName("system_prompt") val systemPrompt: String? = null,
    @SerialName("notule_prompt") val notulePrompt: String? = null,
    @SerialName("output_template") val outputTemplate: String? = null,
    @SerialName("is_default") val isDefault: Boolean = false,
    @SerialName("is_public") val isPublic: Boolean = false,
    @SerialName("user_id") val userId: String? = null,
)

@Serializable
data class ProfileCreateRequest(
    val name: String,
    val description: String? = null,
    val icon: String? = null,
    val systemPrompt: String? = null,
    val notulePrompt: String? = null,
    val outputTemplate: String? = null,
    val isPublic: Boolean = false,
)

@Serializable
data class ProfilesResponse(
    val profiles: List<Profile> = emptyList(),
    val count: Int? = null,
    val limit: Int? = null,
)
