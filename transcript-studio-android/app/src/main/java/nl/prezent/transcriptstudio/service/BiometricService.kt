package nl.prezent.transcriptstudio.service

import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import kotlinx.coroutines.suspendCancellableCoroutine
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume

/**
 * Wraps BiometricPrompt for fingerprint / face authentication.
 */
@Singleton
class BiometricService @Inject constructor() {

    /**
     * Check if biometric authentication (BIOMETRIC_STRONG) is available on this device.
     */
    fun canAuthenticate(activity: FragmentActivity): Boolean {
        val biometricManager = BiometricManager.from(activity)
        return biometricManager.canAuthenticate(BIOMETRIC_STRONG) ==
                BiometricManager.BIOMETRIC_SUCCESS
    }

    /**
     * Show the biometric prompt and return a [Result] indicating success or failure.
     */
    suspend fun authenticate(
        activity: FragmentActivity,
        title: String = "Inloggen",
        subtitle: String = "Gebruik biometrie om in te loggen",
    ): Result<Boolean> = suspendCancellableCoroutine { continuation ->
        val executor = ContextCompat.getMainExecutor(activity)

        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                if (continuation.isActive) {
                    continuation.resume(Result.success(true))
                }
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                if (continuation.isActive) {
                    if (errorCode == BiometricPrompt.ERROR_USER_CANCELED ||
                        errorCode == BiometricPrompt.ERROR_NEGATIVE_BUTTON ||
                        errorCode == BiometricPrompt.ERROR_CANCELED
                    ) {
                        continuation.resume(Result.success(false))
                    } else {
                        continuation.resume(Result.failure(Exception(errString.toString())))
                    }
                }
            }

            override fun onAuthenticationFailed() {
                // Called on each failed attempt; do not resolve yet — the system
                // will either call onAuthenticationSucceeded or onAuthenticationError.
            }
        }

        val prompt = BiometricPrompt(activity, executor, callback)
        val promptInfo = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .setSubtitle(subtitle)
            .setAllowedAuthenticators(BIOMETRIC_STRONG)
            .setNegativeButtonText("Annuleren")
            .build()

        prompt.authenticate(promptInfo)

        continuation.invokeOnCancellation {
            prompt.cancelAuthentication()
        }
    }
}
