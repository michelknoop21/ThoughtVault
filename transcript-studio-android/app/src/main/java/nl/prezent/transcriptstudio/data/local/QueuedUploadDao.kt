package nl.prezent.transcriptstudio.data.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface QueuedUploadDao {

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(upload: QueuedUpload): Long

    @Query("SELECT * FROM queued_uploads ORDER BY createdAt ASC")
    fun getAll(): Flow<List<QueuedUpload>>

    @Query("SELECT * FROM queued_uploads ORDER BY createdAt ASC")
    suspend fun getAllOnce(): List<QueuedUpload>

    @Query("DELETE FROM queued_uploads WHERE id = :id")
    suspend fun delete(id: Long)

    @Query("UPDATE queued_uploads SET retryCount = retryCount + 1 WHERE id = :id")
    suspend fun incrementRetryCount(id: Long)

    @Query("DELETE FROM queued_uploads WHERE retryCount >= :maxRetries")
    suspend fun deleteExhausted(maxRetries: Int = 5)

    @Query("SELECT COUNT(*) FROM queued_uploads")
    fun count(): Flow<Int>
}
