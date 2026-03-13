package nl.prezent.transcriptstudio.service

import android.util.Log
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import com.google.crypto.tink.Aead
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import nl.prezent.transcriptstudio.data.remote.TokenProvider
import java.util.Base64
import javax.inject.Inject
import javax.inject.Singleton

private const val TAG = "SecureTokenStore"

@Singleton
class SecureTokenStore @Inject constructor(
    private val aead: Aead,
    private val dataStore: DataStore<Preferences>,
) : TokenProvider {

    companion object {
        private val KEY_ENCRYPTED_TOKEN = stringPreferencesKey("encrypted_token")
        private val KEY_USER_ID = stringPreferencesKey("user_id")
        private val KEY_USER_NAME = stringPreferencesKey("user_name")
        private val KEY_USER_EMAIL = stringPreferencesKey("user_email")
        private val KEY_USER_ROLE = stringPreferencesKey("user_role")

        // Associated data for Tink AEAD — binds ciphertext to this context
        private val ASSOCIATED_DATA = "ts_token".toByteArray()
    }

    // ── Token ────────────────────────────────────────────────────────────

    suspend fun storeToken(token: String) {
        try {
            val encrypted = aead.encrypt(token.toByteArray(), ASSOCIATED_DATA)
            val encoded = Base64.getEncoder().encodeToString(encrypted)
            dataStore.edit { prefs ->
                prefs[KEY_ENCRYPTED_TOKEN] = encoded
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to encrypt/store token", e)
        }
    }

    suspend fun loadToken(): String? {
        return try {
            val prefs = dataStore.data.first()
            val encoded = prefs[KEY_ENCRYPTED_TOKEN] ?: return null
            val encrypted = Base64.getDecoder().decode(encoded)
            String(aead.decrypt(encrypted, ASSOCIATED_DATA))
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load/decrypt token", e)
            null
        }
    }

    override suspend fun clearToken() {
        dataStore.edit { prefs ->
            prefs.remove(KEY_ENCRYPTED_TOKEN)
        }
    }

    /** TokenProvider implementation for AuthInterceptor. */
    override suspend fun getToken(): String? = loadToken()

    /** Observe whether a token is stored (non-null). */
    val hasToken: Flow<Boolean> = dataStore.data.map { prefs ->
        prefs[KEY_ENCRYPTED_TOKEN] != null
    }

    // ── User info (non-sensitive, stored in plain text) ──────────────────

    suspend fun storeUserInfo(
        userId: String?,
        userName: String?,
        userEmail: String?,
        userRole: String?,
    ) {
        dataStore.edit { prefs ->
            userId?.let { prefs[KEY_USER_ID] = it }
            userName?.let { prefs[KEY_USER_NAME] = it }
            userEmail?.let { prefs[KEY_USER_EMAIL] = it }
            userRole?.let { prefs[KEY_USER_ROLE] = it }
        }
    }

    suspend fun getUserId(): String? = dataStore.data.first()[KEY_USER_ID]
    suspend fun getUserName(): String? = dataStore.data.first()[KEY_USER_NAME]
    suspend fun getUserEmail(): String? = dataStore.data.first()[KEY_USER_EMAIL]
    suspend fun getUserRole(): String? = dataStore.data.first()[KEY_USER_ROLE]

    val userRole: Flow<String?> = dataStore.data.map { it[KEY_USER_ROLE] }
    val userName: Flow<String?> = dataStore.data.map { it[KEY_USER_NAME] }

    suspend fun clearAll() {
        dataStore.edit { prefs ->
            prefs.clear()
        }
    }
}
