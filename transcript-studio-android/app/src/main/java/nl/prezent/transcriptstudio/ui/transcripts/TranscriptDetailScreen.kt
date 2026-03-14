package nl.prezent.transcriptstudio.ui.transcripts

import android.annotation.SuppressLint
import android.webkit.WebView
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.FormatBold
import androidx.compose.material.icons.filled.FormatItalic
import androidx.compose.material.icons.filled.FormatListBulleted
import androidx.compose.material.icons.filled.FormatListNumbered
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Save
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Title
import androidx.compose.material.icons.filled.Undo
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
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
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.hilt.navigation.compose.hiltViewModel
import nl.prezent.transcriptstudio.R
import nl.prezent.transcriptstudio.ui.components.EmptyState
import nl.prezent.transcriptstudio.ui.components.TSPrimaryButton
import nl.prezent.transcriptstudio.ui.components.TSTextField
import nl.prezent.transcriptstudio.ui.theme.BrandPrimary
import nl.prezent.transcriptstudio.ui.theme.TS

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TranscriptDetailScreen(
    transcriptId: String,
    onNavigateBack: () -> Unit,
    viewModel: TranscriptDetailViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
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

    // Keep a reference to the WebView for JS interaction
    var webViewRef by remember { mutableStateOf<WebView?>(null) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    if (state.isEditing) {
                        TSTextField(
                            value = state.editTitle,
                            onValueChange = { viewModel.updateEditTitle(it) },
                            label = "",
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth(),
                            textStyle = MaterialTheme.typography.titleMedium,
                        )
                    } else {
                        Text(
                            text = state.transcript?.effectiveTitle ?: "",
                            maxLines = 1,
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                },
                navigationIcon = {
                    IconButton(onClick = {
                        when {
                            state.isEditingNotule -> viewModel.cancelEditNotule()
                            state.isEditing -> viewModel.cancelEditTitle()
                            else -> onNavigateBack()
                        }
                    }) {
                        Icon(
                            imageVector = if (state.isEditingNotule) Icons.Default.Close
                            else Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.transcript_detail_back),
                        )
                    }
                },
                actions = {
                    when {
                        state.isEditingNotule -> {
                            // Save button when editing notule
                            if (state.isSavingNotule) {
                                CircularProgressIndicator(
                                    modifier = Modifier
                                        .size(24.dp)
                                        .padding(end = TS.Spacing.sm),
                                    strokeWidth = 2.dp,
                                    color = BrandPrimary,
                                )
                            } else {
                                IconButton(onClick = {
                                    // Extract HTML from WebView and save
                                    webViewRef?.evaluateJavascript(
                                        "document.getElementById('editor').innerHTML"
                                    ) { result ->
                                        // JS returns a JSON-encoded string
                                        val html = result
                                            ?.removeSurrounding("\"")
                                            ?.replace("\\n", "\n")
                                            ?.replace("\\\"", "\"")
                                            ?.replace("\\/", "/")
                                            ?.replace("\\u003C", "<")
                                            ?.replace("\\u003E", ">")
                                            ?: ""
                                        viewModel.saveNotuleHtml(html)
                                    }
                                }) {
                                    Icon(
                                        imageVector = Icons.Default.Save,
                                        contentDescription = stringResource(R.string.transcript_detail_save),
                                        tint = BrandPrimary,
                                    )
                                }
                            }
                        }

                        state.isEditing -> {
                            TextButton(onClick = { viewModel.saveTitle(state.editTitle) }) {
                                Text(stringResource(R.string.transcript_detail_save))
                            }
                        }

                        else -> {
                            // Edit notule button (only on notule tab with content)
                            if (state.selectedTab == 0 && !state.transcript?.effectiveNotuleHtml.isNullOrBlank()) {
                                IconButton(onClick = { viewModel.startEditNotule() }) {
                                    Icon(
                                        imageVector = Icons.Default.Edit,
                                        contentDescription = stringResource(R.string.transcript_detail_edit_notule),
                                    )
                                }
                            }

                            IconButton(onClick = { showMenu = true }) {
                                Icon(
                                    imageVector = Icons.Default.MoreVert,
                                    contentDescription = stringResource(R.string.transcript_detail_menu),
                                )
                            }
                            DropdownMenu(
                                expanded = showMenu,
                                onDismissRequest = { showMenu = false },
                            ) {
                                DropdownMenuItem(
                                    text = { Text(stringResource(R.string.transcript_detail_edit_title)) },
                                    onClick = {
                                        showMenu = false
                                        viewModel.startEditTitle()
                                    },
                                )
                                DropdownMenuItem(
                                    text = { Text(stringResource(R.string.transcript_detail_share)) },
                                    leadingIcon = {
                                        Icon(Icons.Default.Share, contentDescription = null)
                                    },
                                    onClick = {
                                        showMenu = false
                                        viewModel.shareTranscript(context)
                                    },
                                )
                                DropdownMenuItem(
                                    text = { Text(stringResource(R.string.transcript_detail_regenerate)) },
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
                                            stringResource(R.string.transcript_detail_delete),
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
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                    titleContentColor = MaterialTheme.colorScheme.onSurface,
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
                    CircularProgressIndicator(color = BrandPrimary)
                }
            }

            state.transcript != null -> {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(padding),
                ) {
                    // Tab row (hidden when editing notule)
                    if (!state.isEditingNotule) {
                        TabRow(
                            selectedTabIndex = state.selectedTab,
                            containerColor = MaterialTheme.colorScheme.surface,
                            contentColor = BrandPrimary,
                        ) {
                            Tab(
                                selected = state.selectedTab == 0,
                                onClick = { viewModel.selectTab(0) },
                                text = { Text(stringResource(R.string.transcript_detail_tab_notule)) },
                            )
                            Tab(
                                selected = state.selectedTab == 1,
                                onClick = { viewModel.selectTab(1) },
                                text = { Text(stringResource(R.string.transcript_detail_tab_transcription)) },
                            )
                        }
                    }

                    // Formatting toolbar (visible when editing)
                    AnimatedVisibility(
                        visible = state.isEditingNotule,
                        enter = slideInVertically { -it },
                        exit = slideOutVertically { -it },
                    ) {
                        FormattingToolbar(
                            onCommand = { command ->
                                webViewRef?.evaluateJavascript(
                                    "document.execCommand('$command', false, null)", null
                                )
                            },
                            onHeading = {
                                webViewRef?.evaluateJavascript(
                                    "document.execCommand('formatBlock', false, 'h3')", null
                                )
                            },
                        )
                    }

                    // Tab content
                    when (state.selectedTab) {
                        0 -> NotuleTab(
                            html = state.transcript?.effectiveNotuleHtml,
                            isDarkTheme = isDarkTheme,
                            isEditing = state.isEditingNotule,
                            onWebViewReady = { webViewRef = it },
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
            title = { Text(stringResource(R.string.transcript_detail_delete_title)) },
            text = { Text(stringResource(R.string.transcript_detail_delete_message)) },
            confirmButton = {
                TextButton(onClick = { viewModel.deleteTranscript() }) {
                    Text(stringResource(R.string.transcript_detail_delete_confirm), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { viewModel.hideDeleteDialog() }) {
                    Text(stringResource(R.string.transcript_detail_delete_dismiss))
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

@SuppressLint("SetJavaScriptEnabled")
@Composable
private fun NotuleTab(
    html: String?,
    isDarkTheme: Boolean,
    isEditing: Boolean = false,
    onWebViewReady: (WebView) -> Unit = {},
) {
    if (html.isNullOrBlank()) {
        EmptyState(
            icon = Icons.Default.Refresh,
            title = stringResource(R.string.transcript_detail_notule_empty_title),
            subtitle = stringResource(R.string.transcript_detail_notule_empty_subtitle),
            modifier = Modifier
                .fillMaxSize()
                .padding(TS.Spacing.xl),
        )
    } else {
        val bgColor = if (isDarkTheme) "#1A1C29" else "#FFFFFF"
        val fgColor = if (isDarkTheme) "#F2F2F8" else "#33333B"
        val focusOutline = if (isEditing) "outline: none;" else ""
        val caretColor = if (isEditing) "caret-color: #E50074;" else ""

        val styledHtml = buildString {
            append("<!DOCTYPE html><html><head>")
            append("<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">")
            append("<style>")
            append("body { background: $bgColor; color: $fgColor; ")
            append("font-family: -apple-system, system-ui, sans-serif; ")
            append("padding: 16px; margin: 0; font-size: 15px; line-height: 1.6; }")
            append("#editor { $focusOutline $caretColor min-height: 200px; }")
            append("a { color: #E50074; }")
            append("h1, h2, h3 { margin-top: 1em; margin-bottom: 0.5em; }")
            append("ul, ol { padding-left: 1.5em; }")
            append("</style></head><body>")
            append("<div id=\"editor\"")
            if (isEditing) {
                append(" contenteditable=\"true\"")
            }
            append(">")
            append(html)
            append("</div></body></html>")
        }

        AndroidView(
            factory = { ctx ->
                WebView(ctx).apply {
                    settings.javaScriptEnabled = true
                    settings.domStorageEnabled = true
                    setBackgroundColor(android.graphics.Color.TRANSPARENT)
                    loadDataWithBaseURL(null, styledHtml, "text/html", "UTF-8", null)
                    onWebViewReady(this)
                }
            },
            update = { webView ->
                webView.loadDataWithBaseURL(null, styledHtml, "text/html", "UTF-8", null)
                onWebViewReady(webView)
            },
            modifier = Modifier.fillMaxSize(),
        )
    }
}

/** Formatting toolbar for the notule editor — bold, italic, lists, headings. */
@Composable
private fun FormattingToolbar(
    onCommand: (String) -> Unit,
    onHeading: () -> Unit,
) {
    Column {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(MaterialTheme.colorScheme.surfaceContainerHigh)
                .padding(horizontal = TS.Spacing.sm, vertical = TS.Spacing.xs),
            horizontalArrangement = Arrangement.spacedBy(2.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            FormatButton(icon = Icons.Default.FormatBold, description = "Vet", onClick = { onCommand("bold") })
            FormatButton(icon = Icons.Default.FormatItalic, description = "Cursief", onClick = { onCommand("italic") })

            Spacer(modifier = Modifier.width(TS.Spacing.sm))

            FormatButton(icon = Icons.Default.Title, description = "Kop", onClick = onHeading)

            Spacer(modifier = Modifier.width(TS.Spacing.sm))

            FormatButton(icon = Icons.Default.FormatListBulleted, description = "Opsomming", onClick = { onCommand("insertUnorderedList") })
            FormatButton(icon = Icons.Default.FormatListNumbered, description = "Genummerde lijst", onClick = { onCommand("insertOrderedList") })

            Spacer(modifier = Modifier.width(TS.Spacing.sm))

            FormatButton(icon = Icons.Default.Undo, description = "Ongedaan maken", onClick = { onCommand("undo") })
        }
        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
    }
}

@Composable
private fun FormatButton(
    icon: ImageVector,
    description: String,
    onClick: () -> Unit,
) {
    IconButton(
        onClick = onClick,
        modifier = Modifier.size(36.dp),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = description,
            modifier = Modifier.size(20.dp),
            tint = MaterialTheme.colorScheme.onSurface,
        )
    }
}

@Composable
private fun TranscriptionTab(transcription: String?) {
    if (transcription.isNullOrBlank()) {
        EmptyState(
            icon = Icons.Default.Refresh,
            title = stringResource(R.string.transcript_detail_transcription_empty_title),
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
        title = { Text(stringResource(R.string.transcript_detail_regenerate_title)) },
        text = {
            if (profiles.isEmpty()) {
                Text(stringResource(R.string.transcript_detail_regenerate_no_profiles))
            } else {
                Column {
                    Text(
                        text = stringResource(R.string.transcript_detail_regenerate_choose),
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
                text = stringResource(R.string.transcript_detail_regenerate_confirm),
                onClick = { onConfirm(selectedProfileId) },
            )
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.transcript_detail_regenerate_dismiss))
            }
        },
    )
}
