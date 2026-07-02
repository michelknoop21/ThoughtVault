# ThoughtVault Android — Implementation Skill

Project-specific skill for building the ThoughtVault Android client. All versions verified against latest stable releases as of March 2026.

## Verified Tech Stack (March 2026)

| Component | Version | Notes |
|-----------|---------|-------|
| Kotlin | 2.3.0 | K2 compiler default, strict concurrency |
| AGP | 9.1.0 | Built-in Kotlin support, no separate kotlin-android plugin needed |
| Gradle | 9.1+ | Required by AGP 9.x, JDK 17+ |
| Compose BOM | 2026.02.01 | Manages all Compose library versions |
| Material 3 | 1.4.x (stable) | M3 Expressive in alpha (1.5.0-alpha15) |
| Hilt | 2.57.1 | KSP only (kapt is maintenance mode) |
| KSP | 2.3.0-1.0.31 | Must match Kotlin version prefix |
| Retrofit | 3.0.0 | Major version, native kotlinx-serialization converter |
| OkHttp | 5.3.0 | Major version, includes okhttp-sse module |
| Room | 2.8.4 | KSP, Kotlin codegen |
| Navigation | 2.8.5+ | Type-safe @Serializable routes |
| kotlinx-serialization | 1.8.0 | Replaces Moshi entirely |
| DataStore | 1.1.1 | Preferences storage |
| Coroutines | 1.10.1 | |
| Min SDK | 28 | Android 9 |
| Target/Compile SDK | 36 | Android 16 |

### Key Changes from Original Plan

1. **Moshi replaced by kotlinx-serialization** — Retrofit 3.0 has built-in `converter-kotlinx-serialization`. No need for Moshi at all.
2. **EncryptedSharedPreferences is DEPRECATED** — Use DataStore + Tink (Google's crypto library) + Android Keystore for token encryption.
3. **kapt replaced by KSP** — For both Hilt and Room. Faster builds, better error messages.
4. **Sealed class routes replaced by @Serializable types** — Navigation 2.8+ uses Kotlin Serialization for type-safe routing.
5. **AGP 9.1 has built-in Kotlin** — No need for `org.jetbrains.kotlin.android` plugin separately.
6. **OkHttp 5.x** — New major version with better Kotlin support.

## Version Catalog (libs.versions.toml)

```toml
[versions]
agp = "9.1.0"
kotlin = "2.3.0"
compose-bom = "2026.02.01"
hilt = "2.57.1"
room = "2.8.4"
retrofit = "3.0.0"
okhttp = "5.3.0"
navigation = "2.8.5"
lifecycle = "2.8.7"
coroutines = "1.10.1"
serialization = "1.8.0"
datastore = "1.1.1"
tink = "1.15.0"
biometric = "1.2.0-alpha05"
immutable-collections = "0.3.8"

[libraries]
compose-bom = { group = "androidx.compose", name = "compose-bom", version.ref = "compose-bom" }
compose-ui = { group = "androidx.compose.ui", name = "ui" }
compose-ui-tooling = { group = "androidx.compose.ui", name = "ui-tooling" }
compose-ui-tooling-preview = { group = "androidx.compose.ui", name = "ui-tooling-preview" }
compose-material3 = { group = "androidx.compose.material3", name = "material3" }
compose-material-icons = { group = "androidx.compose.material", name = "material-icons-extended" }

navigation-compose = { group = "androidx.navigation", name = "navigation-compose", version.ref = "navigation" }

lifecycle-runtime-compose = { group = "androidx.lifecycle", name = "lifecycle-runtime-compose", version.ref = "lifecycle" }
lifecycle-viewmodel-compose = { group = "androidx.lifecycle", name = "lifecycle-viewmodel-compose", version.ref = "lifecycle" }

hilt-android = { group = "com.google.dagger", name = "hilt-android", version.ref = "hilt" }
hilt-compiler = { group = "com.google.dagger", name = "hilt-android-compiler", version.ref = "hilt" }
hilt-navigation-compose = { group = "androidx.hilt", name = "hilt-navigation-compose", version = "1.2.0" }

room-runtime = { group = "androidx.room", name = "room-runtime", version.ref = "room" }
room-compiler = { group = "androidx.room", name = "room-compiler", version.ref = "room" }
room-ktx = { group = "androidx.room", name = "room-ktx", version.ref = "room" }

retrofit = { group = "com.squareup.retrofit2", name = "retrofit", version.ref = "retrofit" }
retrofit-converter-serialization = { group = "com.squareup.retrofit2", name = "converter-kotlinx-serialization", version.ref = "retrofit" }
okhttp = { group = "com.squareup.okhttp3", name = "okhttp", version.ref = "okhttp" }
okhttp-sse = { group = "com.squareup.okhttp3", name = "okhttp-sse", version.ref = "okhttp" }
okhttp-logging = { group = "com.squareup.okhttp3", name = "logging-interceptor", version.ref = "okhttp" }

datastore-preferences = { group = "androidx.datastore", name = "datastore-preferences", version.ref = "datastore" }
tink-android = { group = "com.google.crypto.tink", name = "tink-android", version.ref = "tink" }

biometric = { group = "androidx.biometric", name = "biometric", version.ref = "biometric" }

kotlinx-serialization-json = { group = "org.jetbrains.kotlinx", name = "kotlinx-serialization-json", version.ref = "serialization" }
kotlinx-coroutines-android = { group = "org.jetbrains.kotlinx", name = "kotlinx-coroutines-android", version.ref = "coroutines" }
kotlinx-collections-immutable = { group = "org.jetbrains.kotlinx", name = "kotlinx-collections-immutable", version.ref = "immutable-collections" }

activity-compose = { group = "androidx.activity", name = "activity-compose", version = "1.9.3" }
core-ktx = { group = "androidx.core", name = "core-ktx", version = "1.15.0" }
webkit = { group = "androidx.webkit", name = "webkit", version = "1.12.1" }

[bundles]
compose = ["compose-ui", "compose-ui-tooling-preview", "compose-material3", "compose-material-icons"]
lifecycle = ["lifecycle-runtime-compose", "lifecycle-viewmodel-compose"]
networking = ["retrofit", "retrofit-converter-serialization", "okhttp", "okhttp-sse", "okhttp-logging"]
room = ["room-runtime", "room-ktx"]

[plugins]
android-application = { id = "com.android.application", version.ref = "agp" }
kotlin-serialization = { id = "org.jetbrains.kotlin.plugin.serialization", version.ref = "kotlin" }
compose-compiler = { id = "org.jetbrains.kotlin.plugin.compose", version.ref = "kotlin" }
hilt = { id = "com.google.dagger.hilt.android", version.ref = "hilt" }
ksp = { id = "com.google.devtools.ksp", version = "2.3.0-1.0.31" }
room = { id = "androidx.room", version.ref = "room" }
```

## Secure Token Storage (replaces EncryptedSharedPreferences)

```kotlin
// di/AuthModule.kt
@Module
@InstallIn(SingletonComponent::class)
object AuthModule {
    @Provides
    @Singleton
    fun provideAead(
        @ApplicationContext context: Context,
    ): Aead {
        TinkConfig.register()
        val keysetHandle = AndroidKeysetManager.Builder()
            .withSharedPref(context, "ts_keyset", "ts_keyset_prefs")
            .withKeyTemplate(AesGcmKeyManager.aes256GcmTemplate())
            .withMasterKeyUri("android-keystore://ts_master_key")
            .build()
            .keysetHandle
        return keysetHandle.getPrimitive(Aead::class.java)
    }
}

// service/SecureTokenStore.kt
@Singleton
class SecureTokenStore @Inject constructor(
    private val aead: Aead,
    private val dataStore: DataStore<Preferences>,
) {
    private val TOKEN_KEY = stringPreferencesKey("encrypted_token")

    suspend fun storeToken(token: String) {
        val encrypted = aead.encrypt(token.toByteArray(), null)
        val encoded = Base64.encodeToString(encrypted, Base64.NO_WRAP)
        dataStore.edit { it[TOKEN_KEY] = encoded }
    }

    suspend fun loadToken(): String? {
        val encoded = dataStore.data.first()[TOKEN_KEY] ?: return null
        return try {
            val encrypted = Base64.decode(encoded, Base64.NO_WRAP)
            String(aead.decrypt(encrypted, null))
        } catch (e: GeneralSecurityException) {
            null
        }
    }

    suspend fun clearToken() {
        dataStore.edit { it.remove(TOKEN_KEY) }
    }
}
```

## Navigation (type-safe @Serializable routes)

```kotlin
// navigation/Routes.kt
@Serializable data object Home
@Serializable data object Recording
@Serializable data object Tasks
@Serializable data object Transcripts
@Serializable data class TranscriptDetail(val id: String)
@Serializable data object Settings
@Serializable data object Admin
@Serializable data object Login

// navigation/AppNavigation.kt
@Composable
fun AppNavHost(
    navController: NavHostController,
    isAuthenticated: Boolean,
    modifier: Modifier = Modifier,
) {
    NavHost(
        navController = navController,
        startDestination = if (isAuthenticated) Home else Login,
        modifier = modifier,
    ) {
        composable<Login> { LoginScreen(onLoginSuccess = { navController.navigate(Home) { popUpTo<Login> { inclusive = true } } }) }
        composable<Home> { HomeScreen(/* ... */) }
        composable<Recording> { RecordingScreen(/* ... */) }
        composable<Tasks> { TasksScreen(/* ... */) }
        composable<Transcripts> { TranscriptsScreen(/* ... */) }
        composable<TranscriptDetail> { entry ->
            val route: TranscriptDetail = entry.toRoute()
            TranscriptDetailScreen(transcriptId = route.id)
        }
        composable<Settings> { SettingsScreen(/* ... */) }
        composable<Admin> { AdminScreen(/* ... */) }
    }
}
```

## Retrofit 3.0 + kotlinx-serialization Setup

```kotlin
// di/NetworkModule.kt
@Module
@InstallIn(SingletonComponent::class)
object NetworkModule {
    @Provides
    @Singleton
    fun provideJson(): Json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        coerceInputValues = true
        explicitNulls = false
    }

    @Provides
    @Singleton
    fun provideOkHttpClient(
        authInterceptor: AuthInterceptor,
    ): OkHttpClient = OkHttpClient.Builder()
        .addInterceptor(authInterceptor)
        .addInterceptor(HttpLoggingInterceptor().apply {
            level = if (BuildConfig.DEBUG) HttpLoggingInterceptor.Level.BODY
                    else HttpLoggingInterceptor.Level.NONE
        })
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(300, TimeUnit.SECONDS) // SSE needs long timeout
        .build()

    @Provides
    @Singleton
    fun provideRetrofit(
        okHttpClient: OkHttpClient,
        json: Json,
        settingsRepository: SettingsRepository,
    ): Retrofit = Retrofit.Builder()
        .baseUrl(settingsRepository.getBaseUrl())
        .client(okHttpClient)
        .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
        .build()

    @Provides
    @Singleton
    fun provideApiService(retrofit: Retrofit): ApiService =
        retrofit.create(ApiService::class.java)
}
```

## Data Models (kotlinx-serialization, flexible decoding)

```kotlin
// data/model/Task.kt
@Serializable
enum class TaskStatus(val progress: Float, val displayName: String) {
    @SerialName("pending") PENDING(0.0f, "Wachtrij"),
    @SerialName("queued") QUEUED(0.05f, "In wachtrij"),
    @SerialName("preparing") PREPARING(0.1f, "Voorbereiden"),
    @SerialName("transcribing") TRANSCRIBING(0.3f, "Transcriberen"),
    @SerialName("transcription_complete") TRANSCRIPTION_COMPLETE(0.5f, "Transcriptie klaar"),
    @SerialName("generating_notule") GENERATING_NOTULE(0.6f, "Notulen genereren"),
    @SerialName("processing_notule") PROCESSING_NOTULE(0.75f, "Notulen verwerken"),
    @SerialName("completing") COMPLETING(0.9f, "Afronden"),
    @SerialName("completed") COMPLETED(1.0f, "Voltooid"),
    @SerialName("error") ERROR(0.0f, "Fout");

    val isActive: Boolean get() = this !in listOf(COMPLETED, ERROR)
}

@Serializable
data class TranscriptTask(
    val id: String? = null,
    @SerialName("task_id") val taskId: String? = null,
    val status: TaskStatus = TaskStatus.PENDING,
    val progress: Float? = null,
    val title: String? = null,
    @SerialName("notule_html") val notuleHtml: String? = null,
    @SerialName("raw_transcription") val rawTranscription: String? = null,
    val transcription: String? = null, // backend inconsistency
    @SerialName("created_at") val createdAt: String? = null,
) {
    val effectiveTranscription: String? get() = rawTranscription ?: transcription
    val effectiveId: String get() = taskId ?: id ?: ""
}
```

## Design System — Yinga Brand (ported from Color+Brand.swift + Theme.swift)

### Colors (exact hex values from iOS source)

```kotlin
// ui/theme/Color.kt
// Light mode
val BrandPrimary = Color(0xFFE50074)       // Magenta
val BrandSecondary = Color(0xFF007BC4)     // Blue
val BrandAccent = Color(0xFF009F3C)        // Green
val BrandOrange = Color(0xFFF39200)        // Orange

val NeonBlue = Color(0xFF00C2FF)           // Waveform color

// Surface colors (light)
val SurfacePrimaryLight = Color(0xFFF8F7FA)
val SurfaceSecondaryLight = Color(0xFFFFFFFF)
val SurfaceElevatedLight = Color(0xFFFFFFFF)
val SurfaceGroupedLight = Color(0xFFF2F1F6)

// Label colors (light)
val LabelPrimaryLight = Color(0xFF1A1A2E)
val LabelSecondaryLight = Color(0xFF6B6B80)
val LabelTertiaryLight = Color(0xFF9999AD)

// Dark mode
val SurfacePrimaryDark = Color(0xFF0D0D1A)
val SurfaceSecondaryDark = Color(0xFF1A1A2E)
val SurfaceElevatedDark = Color(0xFF252540)
val SurfaceGroupedDark = Color(0xFF1A1A2E)

val LabelPrimaryDark = Color(0xFFE8E8F0)
val LabelSecondaryDark = Color(0xFF9999AD)
val LabelTertiaryDark = Color(0xFF6B6B80)

// Status
val StatusSuccess = Color(0xFF34C759)
val StatusWarning = Color(0xFFFF9500)
val StatusError = Color(0xFFFF3B30)
val StatusInfo = Color(0xFF007AFF)

// Accent tints
val AccentPrimaryTintLight = Color(0x1AE50074)  // 10% magenta
val AccentSecondaryTintLight = Color(0x1A007BC4) // 10% blue
```

### Spacing (8dp grid from Theme.swift)

```kotlin
// ui/theme/Spacing.kt
object TS {
    object Spacing {
        val xs = 4.dp
        val sm = 8.dp
        val md = 16.dp
        val lg = 24.dp
        val xl = 32.dp
        val xxl = 48.dp
    }
    object Radius {
        val xs = 6.dp
        val sm = 12.dp
        val md = 16.dp
        val lg = 20.dp
        val xl = 25.dp
    }
}
```

### Typography (from Theme.swift scale)

Map iOS typography to M3 scale. Do NOT duplicate M3 defaults — extend only where Yinga brand differs:

```kotlin
// ui/theme/Type.kt
val TSTypography = Typography(
    headlineLarge = TextStyle(fontSize = 34.sp, fontWeight = FontWeight.Bold, lineHeight = 41.sp),
    headlineMedium = TextStyle(fontSize = 28.sp, fontWeight = FontWeight.Bold, lineHeight = 34.sp),
    headlineSmall = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.Bold, lineHeight = 28.sp),
    titleLarge = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.SemiBold, lineHeight = 25.sp),
    titleMedium = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.SemiBold, lineHeight = 22.sp),
    bodyLarge = TextStyle(fontSize = 17.sp, lineHeight = 22.sp),
    bodyMedium = TextStyle(fontSize = 16.sp, lineHeight = 21.sp),
    bodySmall = TextStyle(fontSize = 13.sp, lineHeight = 18.sp),
    labelLarge = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.Medium, lineHeight = 21.sp),
    labelMedium = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Medium, lineHeight = 16.sp),
    labelSmall = TextStyle(fontSize = 10.sp, fontWeight = FontWeight.Medium, lineHeight = 13.sp),
)
```

### Theme Composition

```kotlin
// ui/theme/Theme.kt
@Composable
fun ThoughtVaultTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val colorScheme = if (darkTheme) {
        darkColorScheme(
            primary = BrandPrimary,
            secondary = BrandSecondary,
            tertiary = BrandAccent,
            background = SurfacePrimaryDark,
            surface = SurfaceSecondaryDark,
            surfaceVariant = SurfaceGroupedDark,
            onBackground = LabelPrimaryDark,
            onSurface = LabelPrimaryDark,
            onSurfaceVariant = LabelSecondaryDark,
            error = StatusError,
        )
    } else {
        lightColorScheme(
            primary = BrandPrimary,
            secondary = BrandSecondary,
            tertiary = BrandAccent,
            background = SurfacePrimaryLight,
            surface = SurfaceSecondaryLight,
            surfaceVariant = SurfaceGroupedLight,
            onBackground = LabelPrimaryLight,
            onSurface = LabelPrimaryLight,
            onSurfaceVariant = LabelSecondaryLight,
            error = StatusError,
        )
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = TSTypography,
        content = content,
    )
}
```

## 2026 Design Principles (Anti-Slop)

### What NOT to do
- No gratuitous gradients on every surface
- No glassmorphism-everywhere (use sparingly for elevated content only)
- No bouncy animations on every interaction
- No rounded corners on everything (follow M3 shape system)
- No emojis in UI unless part of the content
- No "hero" illustrations on every empty state
- No skeleton screens that animate forever
- No "AI-generated feeling" — avoid symmetrical, perfect layouts; add intentional asymmetry

### What TO do
- Use the Yinga brand colors purposefully: magenta for primary actions, blue for info, green for success
- White space over decoration
- Content-first hierarchy: the transcript text is the star, not the chrome
- M3 Expressive motion only where it adds meaning: task status transitions, recording state changes
- Spring animations for interactive elements (buttons, cards) — not decorative
- Consistent 8dp spacing grid
- Edge-to-edge layout (mandatory Android 15+)
- Predictive back gesture support
- Dark mode that inverts properly — test both modes equally

### Card Style (from iOS)
The iOS app uses a consistent card style: white background, subtle border, medium shadow. Port this:

```kotlin
@Composable
fun TSCard(
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    Card(
        modifier = modifier,
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface,
        ),
        border = BorderStroke(0.5.dp, MaterialTheme.colorScheme.outlineVariant),
        elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
        shape = RoundedCornerShape(TS.Radius.md),
        content = content,
    )
}
```

### Button Styles (from iOS)

```kotlin
// Primary: gradient magenta fill
@Composable
fun TSPrimaryButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    val scale by animateFloatAsState(
        targetValue = if (enabled) 1f else 0.97f,
        animationSpec = spring(stiffness = Spring.StiffnessMediumLow),
    )
    Button(
        onClick = onClick,
        modifier = modifier.scale(scale),
        enabled = enabled,
        colors = ButtonDefaults.buttonColors(containerColor = BrandPrimary),
        shape = RoundedCornerShape(TS.Radius.sm),
    ) {
        Text(text, color = Color.White, fontWeight = FontWeight.SemiBold)
    }
}
```

## Audio Recording (Android-specific)

```kotlin
// service/AudioRecorderService.kt — core recording logic
// Uses AudioRecord (not MediaRecorder) for raw PCM access
// Format: 16kHz, mono, ENCODING_PCM_16BIT — matches backend expectation
// RMS calculation at 60Hz for waveform visualizer
// Writes WAV header manually after recording stops
// Files in app-private storage: context.filesDir / "recordings"

// service/RecordingForegroundService.kt
// FOREGROUND_SERVICE_TYPE_MICROPHONE (required Android 14+)
// Notification with elapsed timer + stop action
// Communicates with RecordingViewModel via bound service or SharedFlow
```

## SSE Client (OkHttp 5.x EventSource)

```kotlin
// data/remote/SSEClient.kt
class SSEClient @Inject constructor(
    private val okHttpClient: OkHttpClient,
    private val json: Json,
) {
    fun observeTask(taskId: String, baseUrl: String, token: String): Flow<TaskStatus> = callbackFlow {
        val request = Request.Builder()
            .url("$baseUrl/task/$taskId/stream")
            .header("Authorization", "Bearer $token")
            .build()

        val factory = EventSources.createFactory(okHttpClient)
        val listener = object : EventSourceListener() {
            override fun onEvent(eventSource: EventSource, id: String?, type: String?, data: String) {
                val update = json.decodeFromString<TaskStatusUpdate>(data)
                trySend(update.status)
            }
            override fun onFailure(eventSource: EventSource, t: Throwable?, response: Response?) {
                close(t ?: Exception("SSE connection failed"))
            }
            override fun onClosed(eventSource: EventSource) {
                close()
            }
        }
        val eventSource = factory.newEventSource(request, listener)
        awaitClose { eventSource.cancel() }
    }.retry(5) { cause ->
        delay(minOf(1000L * (1 shl it), 30_000L)) // exponential backoff, max 30s
        true
    }
}
```

## Implementation Phases

### Phase 0: Scaffolding
- `transcript-studio-android/` project structure
- Gradle setup with version catalog (see above)
- App entry point, MainActivity, empty theme

### Phase 1: Infrastructure
- Design system (Colors, Typography, Spacing, Theme)
- Brand components (YingaBar, YingaLogo, YingaFooter)
- UI components (TSCard, TSPrimaryButton, TSSecondaryButton, StatusBadge, EmptyState)
- Retrofit 3.0 + OkHttp 5.x + kotlinx-serialization + AuthInterceptor
- SSEClient wrapper
- Room database (offline queue)
- NetworkMonitor (ConnectivityManager)
- SecureTokenStore (DataStore + Tink + Android Keystore)
- BiometricService
- Navigation shell (BottomNavBar + NavHost with @Serializable routes)

### Phase 2: Auth
- LoginScreen + LoginViewModel
- Login: email/password -> token -> SecureTokenStore -> navigate home
- 2FA: temp_token -> code entry -> full token
- Biometric login (BiometricPrompt)
- 401 handling: SharedFlow event -> login redirect
- Password reset

### Phase 3: Home + Recording
- HomeScreen: greeting, stats, recent transcripts, active tasks
- RecordingScreen: idle (profile picker) + active (waveform, timer, controls)
- AudioRecorderService (AudioRecord -> WAV, 16kHz mono)
- RecordingForegroundService (notification)
- Upload with progress, OfflineQueueManager

### Phase 4: Tasks + SSE
- TasksScreen: active task list with real-time status
- SSE per task via OkHttp EventSource
- Cancel/delete, auto-refresh, pull-to-refresh

### Phase 5: Transcripts
- TranscriptsScreen: paginated list, search (300ms debounce), filters
- TranscriptDetailScreen: WebView HTML + raw text tab
- Edit title/tags, export (Share, PDF via WebView print)
- Regenerate with profile picker

### Phase 6: Settings + Admin
- Settings: server URL, LLM, permissions, account, about, feedback
- Admin: 6 tabs (overview, users, invites, feedback, errors, settings)

### Phase 7: Polish
- UpdateCheckService (releases.json)
- Dark mode audit
- Edge cases: large uploads, interrupted recordings, backgrounding
- Error handling UX

## Source Files to Reference

| File | What to extract |
|------|----------------|
| `macos/Extensions/Color+Brand.swift` | Exact hex values per color, light/dark variants |
| `macos/Extensions/Theme.swift` | Spacing, radius, typography, button styles, card modifier |
| `macos/Models/Models.swift` | Data models, flexible decoding patterns, TaskStatus enum |
| `macos/Services/APIService.swift` | Full API contract, endpoints, SSE, field mapping |
| `macos/ViewModels/AuthViewModel.swift` | Auth flow, biometric, 2FA, token lifecycle |
| `macos/ViewModels/RecordingViewModel.swift` | Recording state machine, upload, SSE |
| `windows/src/services/api.ts` | Field mapping reference |
| `docs/API.md` | Backend API reference |

## Verification Checklist

- [ ] `./gradlew assembleDebug` compiles
- [ ] Login with test account, token in Tink-encrypted DataStore
- [ ] Record audio, WAV file is 16kHz mono 16-bit
- [ ] Upload succeeds, task appears in Tasks
- [ ] SSE updates real-time on Tasks screen
- [ ] Offline: record -> queue -> reconnect -> auto-upload
- [ ] Transcripts: list, search, detail (HTML WebView)
- [ ] Admin: all 6 tabs load
- [ ] Dark mode: all screens correct
- [ ] Edge-to-edge: content behind system bars with proper insets
