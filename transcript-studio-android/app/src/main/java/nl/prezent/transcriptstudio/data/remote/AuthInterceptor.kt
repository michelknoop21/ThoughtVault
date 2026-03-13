package nl.prezent.transcriptstudio.data.remote

import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import okhttp3.Interceptor
import okhttp3.Response
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Interface for providing the auth token to the interceptor.
 * Implemented by SecureTokenStore to avoid circular DI dependencies.
 */
interface TokenProvider {
    suspend fun getToken(): String?
    suspend fun clearToken()
}

/**
 * Emits auth events (e.g. session expired) that the UI layer can observe
 * to navigate back to the login screen.
 */
@Singleton
class AuthEventBus @Inject constructor() {
    sealed interface Event {
        data object SessionExpired : Event
    }

    private val _events = MutableSharedFlow<Event>(extraBufferCapacity = 1)
    val events: SharedFlow<Event> = _events.asSharedFlow()

    fun emitSessionExpired() {
        _events.tryEmit(Event.SessionExpired)
    }
}

/**
 * OkHttp interceptor that injects the `Authorization: Bearer {token}` header
 * on all requests except auth/login and password-reset endpoints.
 * Also handles 401 responses by clearing the token and emitting a session-expired event.
 */
@Singleton
class AuthInterceptor @Inject constructor(
    private val tokenProvider: dagger.Lazy<TokenProvider>,
    private val authEventBus: AuthEventBus,
) : Interceptor {

    private val skipPaths = listOf(
        "auth/login",
        "auth/register",
        "auth/password-reset",
        "health",
    )

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val path = request.url.encodedPath

        // Skip auth header for unauthenticated endpoints
        if (skipPaths.any { path.contains(it) }) {
            return chain.proceed(request)
        }

        // Retrieve token synchronously using runBlocking (interceptors are sync)
        val token = kotlinx.coroutines.runBlocking {
            tokenProvider.get().getToken()
        }

        val response = if (token != null) {
            val authenticatedRequest = request.newBuilder()
                .header("X-User-Token", token)
                .build()
            chain.proceed(authenticatedRequest)
        } else {
            chain.proceed(request)
        }

        // Handle 401: clear stored token and notify UI to navigate to login
        if (response.code == 401 && !skipPaths.any { path.contains(it) }) {
            kotlinx.coroutines.runBlocking {
                tokenProvider.get().clearToken()
            }
            authEventBus.emitSessionExpired()
        }

        return response
    }
}
