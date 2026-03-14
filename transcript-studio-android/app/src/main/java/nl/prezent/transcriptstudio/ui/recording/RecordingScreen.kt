package nl.prezent.transcriptstudio.ui.recording

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.OutlinedIconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import nl.prezent.transcriptstudio.R
import nl.prezent.transcriptstudio.service.RecordingForegroundService
import nl.prezent.transcriptstudio.ui.components.ErrorBanner
import nl.prezent.transcriptstudio.ui.components.PulsingRecordingDot
import nl.prezent.transcriptstudio.ui.components.TSCard
import nl.prezent.transcriptstudio.ui.components.TSPrimaryButton
import nl.prezent.transcriptstudio.ui.theme.BrandPrimary
import nl.prezent.transcriptstudio.ui.theme.StatusError
import nl.prezent.transcriptstudio.ui.theme.TS

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RecordingScreen(
    viewModel: RecordingViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val snackbarHostState = remember { SnackbarHostState() }

    // Permission launcher
    var hasPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO)
                    == PackageManager.PERMISSION_GRANTED
        )
    }
    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        hasPermission = granted
        if (granted) {
            viewModel.startRecording()
        }
    }

    // Cancel confirmation dialog
    var showCancelDialog by remember { mutableStateOf(false) }

    // Handle events
    LaunchedEffect(Unit) {
        viewModel.events.collect { event ->
            when (event) {
                is RecordingViewModel.Event.ShowMessage -> {
                    snackbarHostState.showSnackbar(event.message)
                }
                is RecordingViewModel.Event.StartForegroundService -> {
                    context.startForegroundService(
                        RecordingForegroundService.startIntent(context)
                    )
                }
                is RecordingViewModel.Event.StopForegroundService -> {
                    context.stopService(
                        RecordingForegroundService.stopIntent(context)
                    )
                }
            }
        }
    }

    if (showCancelDialog) {
        AlertDialog(
            onDismissRequest = { showCancelDialog = false },
            title = { Text(stringResource(R.string.recording_cancel_confirm_title)) },
            text = { Text(stringResource(R.string.recording_cancel_confirm_message)) },
            confirmButton = {
                TextButton(onClick = {
                    showCancelDialog = false
                    viewModel.cancelRecording()
                }) {
                    Text(stringResource(R.string.recording_cancel_confirm_yes), color = StatusError)
                }
            },
            dismissButton = {
                TextButton(onClick = { showCancelDialog = false }) {
                    Text(stringResource(R.string.recording_cancel_confirm_no))
                }
            },
        )
    }

    Scaffold(
        topBar = {
            if (uiState.isIdle) {
                TopAppBar(
                    title = {
                        Text(
                            text = stringResource(R.string.recording_title),
                            fontWeight = FontWeight.Bold,
                        )
                    },
                    colors = TopAppBarDefaults.topAppBarColors(
                        containerColor = MaterialTheme.colorScheme.surface,
                        titleContentColor = MaterialTheme.colorScheme.onSurface,
                    ),
                )
            }
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        AnimatedContent(
            targetState = uiState.isIdle,
            label = "recording-state-transition",
            transitionSpec = {
                (fadeIn(spring(stiffness = Spring.StiffnessMediumLow)) +
                        scaleIn(initialScale = 0.96f, animationSpec = spring(stiffness = Spring.StiffnessMediumLow)))
                    .togetherWith(
                        fadeOut(spring(stiffness = Spring.StiffnessMediumLow)) +
                                scaleOut(targetScale = 0.96f, animationSpec = spring(stiffness = Spring.StiffnessMediumLow))
                    )
            },
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) { isIdle ->
            if (isIdle) {
                IdleContent(
                    uiState = uiState,
                    hasPermission = hasPermission,
                    onSelectProfile = viewModel::selectProfile,
                    onStartRecording = {
                        if (hasPermission) {
                            viewModel.startRecording()
                        } else {
                            permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                        }
                    },
                )
            } else {
                ActiveRecordingContent(
                    uiState = uiState,
                    onPause = viewModel::pauseRecording,
                    onResume = viewModel::resumeRecording,
                    onStop = viewModel::stopRecording,
                    onCancel = { showCancelDialog = true },
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun IdleContent(
    uiState: RecordingViewModel.UiState,
    hasPermission: Boolean,
    onSelectProfile: (nl.prezent.transcriptstudio.data.model.Profile) -> Unit,
    onStartRecording: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = TS.Spacing.lg),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(modifier = Modifier.height(TS.Spacing.xxl))

        // Microphone icon with subtle accent background
        Box(
            modifier = Modifier
                .size(96.dp)
                .background(
                    BrandPrimary.copy(alpha = 0.08f),
                    CircleShape,
                ),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = Icons.Default.Mic,
                contentDescription = null,
                modifier = Modifier.size(48.dp),
                tint = BrandPrimary,
            )
        }

        Spacer(modifier = Modifier.height(TS.Spacing.lg))

        Text(
            text = stringResource(R.string.recording_idle_subtitle),
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )

        Spacer(modifier = Modifier.height(TS.Spacing.xl))

        // Profile selector
        if (uiState.isLoadingProfiles) {
            CircularProgressIndicator(
                modifier = Modifier.size(24.dp),
                color = BrandPrimary,
                strokeWidth = 2.dp,
            )
        } else if (uiState.profiles.isNotEmpty()) {
            ProfileDropdown(
                profiles = uiState.profiles,
                selectedProfile = uiState.selectedProfile,
                onSelectProfile = onSelectProfile,
                modifier = Modifier.fillMaxWidth(),
            )
        } else {
            Text(
                text = stringResource(R.string.recording_no_profiles),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        Spacer(modifier = Modifier.height(TS.Spacing.xl))

        TSPrimaryButton(
            text = stringResource(R.string.recording_start),
            onClick = onStartRecording,
            modifier = Modifier.fillMaxWidth(),
            enabled = uiState.selectedProfile != null && !uiState.isUploading,
        )

        if (!hasPermission) {
            Spacer(modifier = Modifier.height(TS.Spacing.sm))
            Text(
                text = stringResource(R.string.recording_permission_required),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }

        // Uploading indicator
        AnimatedVisibility(visible = uiState.isUploading) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier.padding(top = TS.Spacing.lg),
            ) {
                CircularProgressIndicator(
                    modifier = Modifier.size(24.dp),
                    color = BrandPrimary,
                    strokeWidth = 2.dp,
                )
                Spacer(modifier = Modifier.height(TS.Spacing.sm))
                Text(
                    text = stringResource(R.string.recording_uploading),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        // Error display
        if (uiState.error != null) {
            Spacer(modifier = Modifier.height(TS.Spacing.md))
            ErrorBanner(message = uiState.error)
        }

        Spacer(modifier = Modifier.height(TS.Spacing.xl))
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ProfileDropdown(
    profiles: List<nl.prezent.transcriptstudio.data.model.Profile>,
    selectedProfile: nl.prezent.transcriptstudio.data.model.Profile?,
    onSelectProfile: (nl.prezent.transcriptstudio.data.model.Profile) -> Unit,
    modifier: Modifier = Modifier,
) {
    var expanded by remember { mutableStateOf(false) }

    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { expanded = it },
        modifier = modifier,
    ) {
        OutlinedTextField(
            value = selectedProfile?.name ?: "",
            onValueChange = {},
            readOnly = true,
            label = { Text(stringResource(R.string.recording_select_profile)) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier
                .fillMaxWidth()
                .menuAnchor(MenuAnchorType.PrimaryNotEditable),
        )
        ExposedDropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
        ) {
            profiles.forEach { profile ->
                DropdownMenuItem(
                    text = {
                        Column {
                            Text(
                                text = profile.name,
                                style = MaterialTheme.typography.bodyLarge,
                            )
                            if (!profile.description.isNullOrBlank()) {
                                Text(
                                    text = profile.description,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    },
                    onClick = {
                        onSelectProfile(profile)
                        expanded = false
                    },
                )
            }
        }
    }
}

/** Immersive dark gradient for active recording screen */
private val recordingBackground = Brush.verticalGradient(
    colors = listOf(
        Color(0xFF0B0C15),
        Color(0xFF111225),
        Color(0xFF0F1020),
    ),
)

@Composable
private fun ActiveRecordingContent(
    uiState: RecordingViewModel.UiState,
    onPause: () -> Unit,
    onResume: () -> Unit,
    onStop: () -> Unit,
    onCancel: () -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(recordingBackground),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = TS.Spacing.lg),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(modifier = Modifier.height(TS.Spacing.xl))

            // Recording status indicator
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Center,
            ) {
                if (uiState.isRecording) {
                    PulsingRecordingDot(size = 10.dp)
                    Spacer(modifier = Modifier.width(TS.Spacing.sm))
                    Text(
                        text = stringResource(R.string.recording_active),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = StatusError,
                    )
                } else {
                    Text(
                        text = stringResource(R.string.recording_paused),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = Color.White.copy(alpha = 0.6f),
                    )
                }
            }

            Spacer(modifier = Modifier.height(TS.Spacing.lg))

            // Timer display — large, light, on dark background
            Text(
                text = uiState.elapsedFormatted,
                style = MaterialTheme.typography.displayLarge.copy(
                    fontWeight = FontWeight.Light,
                    fontSize = 72.sp,
                    letterSpacing = 2.sp,
                ),
                color = Color.White,
            )

            Spacer(modifier = Modifier.height(TS.Spacing.xl))

            // Waveform — self-contained dark container, no TSCard wrapper
            WaveformVisualizer(
                audioLevel = uiState.audioLevel,
                isActive = uiState.isRecording,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = TS.Spacing.sm),
            )

            Spacer(modifier = Modifier.weight(1f))

            // Control buttons
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = TS.Spacing.xxl),
                horizontalArrangement = Arrangement.SpaceEvenly,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                // Cancel button
                OutlinedIconButton(
                    onClick = onCancel,
                    modifier = Modifier.size(56.dp),
                ) {
                    Icon(
                        imageVector = Icons.Default.Cancel,
                        contentDescription = stringResource(R.string.recording_cancel),
                        tint = Color.White.copy(alpha = 0.7f),
                    )
                }

                // Pause/Resume button
                if (uiState.isRecording) {
                    FilledIconButton(
                        onClick = onPause,
                        modifier = Modifier.size(56.dp),
                        colors = IconButtonDefaults.filledIconButtonColors(
                            containerColor = Color.White.copy(alpha = 0.15f),
                            contentColor = Color.White,
                        ),
                    ) {
                        Icon(
                            imageVector = Icons.Default.Pause,
                            contentDescription = stringResource(R.string.recording_pause),
                        )
                    }
                } else {
                    FilledIconButton(
                        onClick = onResume,
                        modifier = Modifier.size(56.dp),
                        colors = IconButtonDefaults.filledIconButtonColors(
                            containerColor = Color.White.copy(alpha = 0.15f),
                            contentColor = Color.White,
                        ),
                    ) {
                        Icon(
                            imageVector = Icons.Default.PlayArrow,
                            contentDescription = stringResource(R.string.recording_resume),
                        )
                    }
                }

                // Stop button — prominent red
                FilledIconButton(
                    onClick = onStop,
                    modifier = Modifier
                        .size(72.dp)
                        .shadow(
                            elevation = 12.dp,
                            shape = CircleShape,
                            ambientColor = StatusError.copy(alpha = 0.3f),
                            spotColor = StatusError.copy(alpha = 0.3f),
                        ),
                    shape = CircleShape,
                    colors = IconButtonDefaults.filledIconButtonColors(
                        containerColor = StatusError,
                        contentColor = Color.White,
                    ),
                ) {
                    Icon(
                        imageVector = Icons.Default.Stop,
                        contentDescription = stringResource(R.string.recording_stop),
                        modifier = Modifier.size(36.dp),
                    )
                }
            }
        }
    }
}
