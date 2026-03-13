package nl.prezent.transcriptstudio.ui.transcripts

import android.webkit.WebView
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.hilt.navigation.compose.hiltViewModel
import nl.prezent.transcriptstudio.ui.components.EmptyState
import nl.prezent.transcriptstudio.ui.components.TSPrimaryButton
import nl.prezent.transcriptstudio.ui.theme.TS

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TranscriptDetailScreen(
    transcriptId: String,
    onNavigateBack: () -> Unit,
    viewModel: TranscriptDetailViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsState()
    val context = LocalContext.current
    val snackbarHostState = remember { SnackbarHostState() }
    var showMenu by remember { mutableStateOf(false) }
    val isDarkTheme = isSystemInDarkTheme()

    // Handle navigation events
    LaunchedEffect(Unit) {
        viewModel.events.collect { event ->
            when (event) {
                is TranscriptDetailViewModel.Event.NavigateBack -> onNavigateBack()
            }
        }
    }

    // Show errors via snackbar
    LaunchedEffect(state.error) {
        state.error?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearError()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    if (state.isEditing) {
                        OutlinedTextField(
                            value = state.editTitle,
                            onValueChange = { viewModel.updateEditTitle(it) },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth(),
                            textStyle = MaterialTheme.typography.titleMedium,
                        )
                    } else {
                        Text(
                            text = state.transcript?.effectiveTitle ?: "",
                            maxLines = 1,
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                },
                navigationIcon = {
                    IconButton(onClick = {
                        if (state.isEditing) {
                            viewModel.cancelEditTitle()
                        } else {
                            onNavigateBack()
                        }
                    }) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Terug",
                        )
                    }
                },
                actions = {
                    if (state.isEditing) {
                        TextButton(onClick = { viewModel.saveTitle(state.editTitle) }) {
                            Text("Opslaan")
                        }
                    } else {
                        IconButton(onClick = { showMenu = true }) {
                            Icon(
                                imageVector = Icons.Default.MoreVert,
                                contentDescription = "Menu",
                            )
                        }
                        DropdownMenu(
                            expanded = showMenu,
                            onDismissRequest = { showMenu = false },
                        ) {
                            DropdownMenuItem(
                                text = { Text("Titel bewerken") },
                                onClick = {
                                    showMenu = false
                                    viewModel.startEditTitle()
                                },
                            )
                            DropdownMenuItem(
                                text = { Text("Delen") },
                                leadingIcon = {
                                    Icon(Icons.Default.Share, contentDescription = null)
                                },
                                onClick = {
                                    showMenu = false
                                    viewModel.shareTranscript(context)
                                },
                            )
                            DropdownMenuItem(
                                text = { Text("Opnieuw genereren") },
                                leadingIcon = {
                                    Icon(Icons.Default.Refresh, contentDescription = null)
                                },
                                onClick = {
                                    showMenu = false
                                    viewModel.showRegenerateDialog()
                                },
                            )
                            DropdownMenuItem(
                                text = {
                                    Text(
                                        "Verwijderen",
                                        color = MaterialTheme.colorScheme.error,
                                    )
                                },
                                leadingIcon = {
                                    Icon(
                                        Icons.Default.Delete,
                                        contentDescription = null,
                                        tint = MaterialTheme.colorScheme.error,
                                    )
                                },
                                onClick = {
                                    showMenu = false
                                    viewModel.showDeleteDialog()
                                },
                            )
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                ),
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        when {
            state.isLoading -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
            }

            state.transcript != null -> {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                ) {
                    // Tab row
                    TabRow(selectedTabIndex = state.selectedTab) {
                        Tab(
                            selected = state.selectedTab == 0,
                            onClick = { viewModel.selectTab(0) },
                            text = { Text("Notulen") },
                        )
                        Tab(
                            selected = state.selectedTab == 1,
                            onClick = { viewModel.selectTab(1) },
                            text = { Text("Transcriptie") },
                        )
                    }

                    // Tab content
                    when (state.selectedTab) {
                        0 -> NotuleTab(
                            html = state.transcript?.effectiveNotuleHtml,
                            isDarkTheme = isDarkTheme,
                        )

                        1 -> TranscriptionTab(
                            transcription = state.transcript?.effectiveTranscription,
                        )
                    }
                }
            }
        }
    }

    // Delete confirmation dialog
    if (state.showDeleteDialog) {
        AlertDialog(
            onDismissRequest = { viewModel.hideDeleteDialog() },
            title = { Text("Transcriptie verwijderen") },
            text = { Text("Weet je zeker dat je deze transcriptie wilt verwijderen?") },
            confirmButton = {
                TextButton(onClick = { viewModel.deleteTranscript() }) {
                    Text("Verwijderen", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { viewModel.hideDeleteDialog() }) {
                    Text("Annuleren")
                }
            },
        )
    }

    // Regenerate dialog with profile picker
    if (state.showRegenerateDialog) {
        RegenerateDialog(
            profiles = state.profiles,
            currentProfileId = state.transcript?.profileId?.toString(),
            onDismiss = { viewModel.hideRegenerateDialog() },
            onConfirm = { profileId -> viewModel.regenerateNotule(profileId) },
        )
    }
}

@Composable
private fun NotuleTab(
    html: String?,
    isDarkTheme: Boolean,
) {
    if (html.isNullOrBlank()) {
        EmptyState(
            icon = Icons.Default.Refresh,
            title = "Geen notulen beschikbaar",
            subtitle = "De notulen worden nog gegenereerd",
            modifier = Modifier
                .fillMaxSize()
                .padding(TS.Spacing.xl),
        )
    } else {
        val styledHtml = buildString {
            append("<!DOCTYPE html><html><head>")
            append("<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">")
            append("<style>")
            if (isDarkTheme) {
                append("body { background: #1A1C29; color: #F2F2F8; ")
            } else {
                append("body { background: #FFFFFF; color: #33333B; ")
            }
            append("font-family: -apple-system, system-ui, sans-serif; ")
            append("padding: 16px; margin: 0; font-size: 15px; line-height: 1.6; }")
            append("a { color: #E50074; }")
            append("h1, h2, h3 { margin-top: 1em; margin-bottom: 0.5em; }")
            append("ul, ol { padding-left: 1.5em; }")
            append("</style></head><body>")
            append(html)
            append("</body></html>")
        }

        AndroidView(
            factory = { ctx ->
                WebView(ctx).apply {
                    settings.javaScriptEnabled = false
                    setBackgroundColor(android.graphics.Color.TRANSPARENT)
                    loadDataWithBaseURL(null, styledHtml, "text/html", "UTF-8", null)
                }
            },
            update = { webView ->
                webView.loadDataWithBaseURL(null, styledHtml, "text/html", "UTF-8", null)
            },
            modifier = Modifier.fillMaxSize(),
        )
    }
}

@Composable
private fun TranscriptionTab(transcription: String?) {
    if (transcription.isNullOrBlank()) {
        EmptyState(
            icon = Icons.Default.Refresh,
            title = "Geen transcriptie beschikbaar",
            modifier = Modifier
                .fillMaxSize()
                .padding(TS.Spacing.xl),
        )
    } else {
        SelectionContainer {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(TS.Spacing.md),
            ) {
                Text(
                    text = transcription,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                )
            }
        }
    }
}

@Composable
private fun RegenerateDialog(
    profiles: List<nl.prezent.transcriptstudio.data.model.Profile>,
    currentProfileId: String?,
    onDismiss: () -> Unit,
    onConfirm: (String?) -> Unit,
) {
    var selectedProfileId by remember { mutableStateOf(currentProfileId) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Opnieuw genereren") },
        text = {
            if (profiles.isEmpty()) {
                Text("Geen profielen beschikbaar.")
            } else {
                Column {
                    Text(
                        text = "Kies een profiel:",
                        style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.padding(bottom = TS.Spacing.sm),
                    )
                    profiles.forEach { profile ->
                        val isSelected = selectedProfileId == profile.id
                        androidx.compose.foundation.layout.Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = TS.Spacing.xs),
                        ) {
                            RadioButton(
                                selected = isSelected,
                                onClick = { selectedProfileId = profile.id },
                            )
                            Column(modifier = Modifier.padding(start = TS.Spacing.sm)) {
                                Text(
                                    text = profile.name,
                                    style = MaterialTheme.typography.bodyMedium,
                                )
                                if (!profile.description.isNullOrBlank()) {
                                    Text(
                                        text = profile.description,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            }
                        }
                    }
                }
            }
        },
        confirmButton = {
            TSPrimaryButton(
                text = "Genereer",
                onClick = { onConfirm(selectedProfileId) },
            )
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Annuleren")
            }
        },
    )
}
