package nl.prezent.transcriptstudio.di

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.preferencesDataStore
import com.google.crypto.tink.Aead
import com.google.crypto.tink.KeyTemplates
import com.google.crypto.tink.aead.AeadConfig
import com.google.crypto.tink.integration.android.AndroidKeysetManager
import dagger.Binds
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import nl.prezent.transcriptstudio.data.remote.TokenProvider
import nl.prezent.transcriptstudio.service.SecureTokenStore
import javax.inject.Singleton

private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "ts_preferences")

@Module
@InstallIn(SingletonComponent::class)
object AuthModule {

    @Provides
    @Singleton
    fun provideDataStore(
        @ApplicationContext context: Context,
    ): DataStore<Preferences> = context.dataStore

    @Provides
    @Singleton
    fun provideAead(
        @ApplicationContext context: Context,
    ): Aead {
        AeadConfig.register()
        val keysetManager = AndroidKeysetManager.Builder()
            .withSharedPref(context, "ts_keyset", "ts_keyset_prefs")
            .withKeyTemplate(KeyTemplates.get("AES256_GCM"))
            .withMasterKeyUri("android-keystore://ts_master_key")
            .build()
        return keysetManager.keysetHandle.getPrimitive(Aead::class.java)
    }
}

@Module
@InstallIn(SingletonComponent::class)
abstract class TokenProviderModule {

    @Binds
    @Singleton
    abstract fun bindTokenProvider(
        secureTokenStore: SecureTokenStore,
    ): TokenProvider
}
