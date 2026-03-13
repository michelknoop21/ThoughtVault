package nl.prezent.transcriptstudio.di

import android.content.Context
import androidx.room.Room
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import nl.prezent.transcriptstudio.data.local.AppDatabase
import nl.prezent.transcriptstudio.data.local.QueuedUploadDao
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object DatabaseModule {

    @Provides
    @Singleton
    fun provideAppDatabase(
        @ApplicationContext context: Context,
    ): AppDatabase = Room.databaseBuilder(
        context,
        AppDatabase::class.java,
        "transcript_studio.db",
    ).fallbackToDestructiveMigration()
        .build()

    @Provides
    fun provideQueuedUploadDao(database: AppDatabase): QueuedUploadDao =
        database.queuedUploadDao()
}
