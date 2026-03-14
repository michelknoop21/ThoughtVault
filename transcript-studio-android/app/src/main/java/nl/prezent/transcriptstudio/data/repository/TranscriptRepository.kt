package nl.prezent.transcriptstudio.data.repository

import nl.prezent.transcriptstudio.data.model.*
import nl.prezent.transcriptstudio.data.remote.ApiService
import okhttp3.ResponseBody
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class TranscriptRepository @Inject constructor(
    private val apiService: ApiService,
) {

    suspend fun getTranscripts(
        search: String? = null,
        tags: String? = null,
    ): TranscriptsResponse = apiService.getTranscripts(search = search, tags = tags)

    suspend fun getTranscriptTags(): List<String> = apiService.getTranscriptTags()

    suspend fun getTranscript(taskId: String): Transcript =
        apiService.getTranscript(taskId)

    suspend fun updateTranscript(
        taskId: String,
        title: String? = null,
        transcription: String? = null,
        notuleHtml: String? = null,
        tags: List<String>? = null,
        resetToOriginal: Boolean? = null,
    ): Transcript = apiService.updateTranscript(
        taskId = taskId,
        body = TranscriptUpdateRequest(
            title = title,
            transcription = transcription,
            notuleHtml = notuleHtml,
            tags = tags,
            resetToOriginal = resetToOriginal,
        ),
    )

    suspend fun deleteTranscript(taskId: String) {
        apiService.deleteTranscript(taskId)
    }

    suspend fun regenerateNotule(taskId: String, profileId: String? = null): TranscribeResponse =
        apiService.regenerateTranscript(
            taskId = taskId,
            body = if (profileId != null) TranscriptRegenerateRequest(newProfileId = profileId) else null,
        )

    suspend fun exportTranscript(taskId: String, format: String = "txt"): ResponseBody =
        apiService.exportTranscript(taskId = taskId, format = format)

    suspend fun bulkDelete(ids: List<String>) {
        apiService.bulkDeleteTranscripts(BulkDeleteRequest(ids = ids))
    }

    suspend fun bulkTags(ids: List<String>, tags: List<String>, action: String) {
        apiService.bulkTagTranscripts(BulkTagsRequest(ids = ids, tags = tags, action = action))
    }
}
