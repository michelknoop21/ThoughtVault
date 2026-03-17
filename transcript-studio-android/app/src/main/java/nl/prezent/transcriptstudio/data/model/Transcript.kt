package nl.prezent.transcriptstudio.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class Transcript(
    val id: Int? = null,
    @SerialName("task_id") val taskId: String? = null,
    val title: String? = null,
    val filename: String? = null,
    @SerialName("notule_html") val notuleHtml: String? = null,
    val result: String? = null,
    @SerialName("raw_transcription") val rawTranscription: String? = null,
    val transcription: String? = null,
    val tags: List<String> = emptyList(),
    @SerialName("profile_id") val profileId: String? = null,
    @SerialName("profile_name") val profileName: String? = null,
    val duration: Double? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
) {
    val effectiveNotuleHtml: String? get() = notuleHtml ?: result
    val effectiveTranscription: String? get() = rawTranscription ?: transcription
    val effectiveTitle: String get() = title ?: filename ?: "Naamloze opname"
    val effectiveId: String get() = taskId ?: id?.toString() ?: ""
}

@Serializable
data class TranscriptsResponse(
    val items: List<Transcript> = emptyList(),
    val total: Int? = null,
    val page: Int? = null,
    val limit: Int? = null,
)

@Serializable
data class TranscriptUpdateRequest(
    val transcription: String? = null,
    val title: String? = null,
    @SerialName("notule_html") val notuleHtml: String? = null,
    val tags: List<String>? = null,
    @SerialName("reset_to_original") val resetToOriginal: Boolean? = null,
)

@Serializable
data class TranscriptRegenerateRequest(
    @SerialName("profile_id") val profileId: String? = null,
    @SerialName("new_profile_id") val newProfileId: String? = null,
)

@Serializable
data class BulkDeleteRequest(
    val ids: List<String>,
)

@Serializable
data class BulkTagsRequest(
    val ids: List<String>,
    val tags: List<String>,
    val action: String, // "add" or "remove"
)
