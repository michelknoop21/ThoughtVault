package nl.prezent.transcriptstudio.data.local

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "queued_uploads")
data class QueuedUpload(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val type: String, // "audio" or "text"
    val filePath: String,
    val profileId: String,
    val retryCount: Int = 0,
    val createdAt: Long = System.currentTimeMillis(),
)
