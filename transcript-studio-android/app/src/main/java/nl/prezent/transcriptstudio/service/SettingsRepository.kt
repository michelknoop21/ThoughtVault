package nl.prezent.transcriptstudio.service

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Simple DataStore-backed settings for configurable base URL and API prefix.
 * This allows the Android client to connect to different backend instances.
 */
@Singleton
class SettingsRepository @Inject constructor(
    private val dataStore: DataStore<Preferences>,
) {

    companion object {
        private val KEY_BASE_URL = stringPreferencesKey("base_url")
        private val KEY_API_PREFIX = stringPreferencesKey("api_prefix")

        const val DEFAULT_BASE_URL = "https://n8n.prezent.nl"
        const val DEFAULT_API_PREFIX = "/tstudio"
    }

    val baseUrl: Flow<String> = dataStore.data.map { prefs ->
        prefs[KEY_BASE_URL] ?: DEFAULT_BASE_URL
    }

    val apiPrefix: Flow<String> = dataStore.data.map { prefs ->
        prefs[KEY_API_PREFIX] ?: DEFAULT_API_PREFIX
    }

    suspend fun getBaseUrl(): String =
        dataStore.data.first()[KEY_BASE_URL] ?: DEFAULT_BASE_URL

    suspend fun getApiPrefix(): String =
        dataStore.data.first()[KEY_API_PREFIX] ?: DEFAULT_API_PREFIX

    /**
     * Returns the full API base URL, e.g. "https://n8n.prezent.nl/tstudio/api/"
     */
    suspend fun getApiBaseUrl(): String {
        val base = getBaseUrl().trimEnd('/')
        val prefix = getApiPrefix().trimEnd('/')
        return "$base$prefix/api/"
    }

    suspend fun setBaseUrl(url: String) {
        dataStore.edit { it[KEY_BASE_URL] = url }
    }

    suspend fun setApiPrefix(prefix: String) {
        dataStore.edit { it[KEY_API_PREFIX] = prefix }
    }
}
