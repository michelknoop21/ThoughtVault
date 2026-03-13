package nl.prezent.transcriptstudio.data.remote

import kotlinx.coroutines.runBlocking
import nl.prezent.transcriptstudio.service.SettingsRepository
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.Interceptor
import okhttp3.Response
import javax.inject.Inject
import javax.inject.Singleton

/**
 * OkHttp interceptor that rewrites the request URL to use the dynamically
 * configured base URL from SettingsRepository. This allows users to change
 * the server URL at runtime without recreating the Retrofit instance.
 */
@Singleton
class DynamicBaseUrlInterceptor @Inject constructor(
    private val settingsRepository: dagger.Lazy<SettingsRepository>,
) : Interceptor {

    override fun intercept(chain: Interceptor.Chain): Response {
        val originalRequest = chain.request()

        val baseUrl = runBlocking {
            settingsRepository.get().getApiBaseUrl()
        }

        val newBaseUrl = baseUrl.toHttpUrlOrNull() ?: return chain.proceed(originalRequest)

        // Replace the host, port, scheme, and path prefix from the original placeholder URL
        val originalUrl = originalRequest.url
        val newUrl = originalUrl.newBuilder()
            .scheme(newBaseUrl.scheme)
            .host(newBaseUrl.host)
            .port(newBaseUrl.port)
            // Replace the path: strip the original base path and prepend the new one
            .encodedPath(
                newBaseUrl.encodedPath.trimEnd('/') +
                    "/" +
                    originalUrl.encodedPath.trimStart('/')
            )
            .build()

        val newRequest = originalRequest.newBuilder()
            .url(newUrl)
            .build()

        return chain.proceed(newRequest)
    }
}
