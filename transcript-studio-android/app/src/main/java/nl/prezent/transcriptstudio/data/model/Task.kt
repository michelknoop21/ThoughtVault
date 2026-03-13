package nl.prezent.transcriptstudio.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.Transient

@Serializable
enum class TaskStatus(
    @Transient val progress: Float = 0f,
    @Transient val displayName: String = "",
) {
    @SerialName("pending") PENDING(0.0f, "Wachten"),
    @SerialName("uploading") UPLOADING(0.15f, "Uploaden"),
    @SerialName("converting") CONVERTING(0.25f, "Converteren"),
    @SerialName("queued") QUEUED(0.05f, "In wachtrij"),
    @SerialName("preparing") PREPARING(0.1f, "Voorbereiden"),
    @SerialName("transcribing") TRANSCRIBING(0.45f, "Transcriberen"),
    @SerialName("transcribed") TRANSCRIBED(0.6f, "Getranscribeerd"),
    @SerialName("transcription_complete") TRANSCRIPTION_COMPLETE(0.5f, "Transcriptie klaar"),
    @SerialName("generating_notule") GENERATING_NOTULE(0.6f, "Notulen genereren"),
    @SerialName("processing_webhook") PROCESSING_WEBHOOK(0.85f, "Verwerken"),
    @SerialName("processing_notule") PROCESSING_NOTULE(0.75f, "Notulen verwerken"),
    @SerialName("completing") COMPLETING(0.9f, "Afronden"),
    @SerialName("completed") COMPLETED(1.0f, "Voltooid"),
    @SerialName("no_speech") NO_SPEECH(0.0f, "Geen spraak"),
    @SerialName("cancelled") CANCELLED(0.0f, "Geannuleerd"),
    @SerialName("error") ERROR(0.0f, "Fout");

    val isActive: Boolean get() = this !in listOf(COMPLETED, ERROR, CANCELLED, NO_SPEECH)
    val isTerminal: Boolean get() = this in listOf(COMPLETED, ERROR, CANCELLED, NO_SPEECH)
}

@Serializable
data class TranscriptTask(
    val id: String? = null,
    @SerialName("task_id") val taskId: String? = null,
    val status: TaskStatus = TaskStatus.PENDING,
    val progress: Float? = null,
    val title: String? = null,
    val filename: String? = null,
    @SerialName("notule_html") val notuleHtml: String? = null,
    @SerialName("raw_transcription") val rawTranscription: String? = null,
    val transcription: String? = null,
    @SerialName("error_message") val errorMessage: String? = null,
    val tags: List<String> = emptyList(),
    @SerialName("profile_id") val profileId: String? = null,
    @SerialName("created_at") val createdAt: String? = null,
    @SerialName("updated_at") val updatedAt: String? = null,
    @SerialName("queue_position") val queuePosition: Int? = null,
    @SerialName("extracted_title") val extractedTitle: String? = null,
    val message: String? = null,
) {
    val effectiveTranscription: String? get() = rawTranscription ?: transcription
    val effectiveId: String get() = taskId ?: id ?: ""
    val effectiveTitle: String get() = title ?: extractedTitle ?: filename ?: "Naamloze opname"
}

@Serializable
data class TaskStatusUpdate(
    @SerialName("task_id") val taskId: String? = null,
    val status: TaskStatus? = null,
    val progress: Float? = null,
    val message: String? = null,
    @SerialName("notule_html") val notuleHtml: String? = null,
    @SerialName("raw_transcription") val rawTranscription: String? = null,
    @SerialName("error_message") val errorMessage: String? = null,
)

@Serializable
data class ActiveTasksResponse(
    val tasks: List<TranscriptTask> = emptyList(),
)

@Serializable
data class TranscribeResponse(
    @SerialName("task_id") val taskId: String,
    val status: String? = null,
    @SerialName("queue_position") val queuePosition: Int? = null,
    val message: String? = null,
)

@Serializable
data class CancelTaskResponse(
    val success: Boolean,
    @SerialName("task_id") val taskId: String? = null,
    val message: String? = null,
)
