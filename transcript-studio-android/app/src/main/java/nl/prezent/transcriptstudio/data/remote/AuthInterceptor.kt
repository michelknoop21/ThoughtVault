package nl.prezent.transcriptstudio.data.remote

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
}

/**
 * OkHttp interceptor that injects the `Authorization: Bearer {token}` header
 * on all requests except auth/login and password-reset endpoints.
 */
@Singleton
class AuthInterceptor @Inject constructor(
    private val tokenProvider: dagger.Lazy<TokenProvider>,
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

        return if (token != null) {
            val authenticatedRequest = request.newBuilder()
                .header("Authorization", "Bearer $token")
                .build()
            chain.proceed(authenticatedRequest)
        } else {
            chain.proceed(request)
        }
    }
}
