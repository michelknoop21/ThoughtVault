package nl.prezent.transcriptstudio.data.local

import androidx.room.Database
import androidx.room.RoomDatabase

@Database(
    entities = [QueuedUpload::class],
    version = 1,
    exportSchema = true,
)
abstract class AppDatabase : RoomDatabase() {
    abstract fun queuedUploadDao(): QueuedUploadDao
}
