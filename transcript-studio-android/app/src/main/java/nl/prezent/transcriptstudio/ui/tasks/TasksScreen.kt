package nl.prezent.transcriptstudio.ui.tasks

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Assignment
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.text.style.TextOverflow
import androidx.hilt.navigation.compose.hiltViewModel
import nl.prezent.transcriptstudio.data.model.TaskStatus
import nl.prezent.transcriptstudio.data.model.TranscriptTask
import nl.prezent.transcriptstudio.ui.components.EmptyState
import nl.prezent.transcriptstudio.ui.components.StatusBadge
import nl.prezent.transcriptstudio.ui.components.TSCard
import nl.prezent.transcriptstudio.ui.theme.BrandSecondary
import nl.prezent.transcriptstudio.ui.theme.StatusError
import nl.prezent.transcriptstudio.ui.theme.StatusSuccess
import nl.prezent.transcriptstudio.ui.theme.StatusWarning
import nl.prezent.transcriptstudio.ui.theme.TS

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TasksScreen(
    onNavigateToTranscript: (String) -> Unit,
    viewModel: TasksViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()

    // Handle navigation events
    LaunchedEffect(Unit) {
        viewModel.events.collect { event ->
            when (event) {
                is TasksViewModel.Event.NavigateToTranscript -> {
                    onNavigateToTranscript(event.id)
                }
            }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Taken") },
            )
        },
    ) { padding ->
        PullToRefreshBox(
            isRefreshing = uiState.isRefreshing,
            onRefresh = viewModel::refresh,
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            if (uiState.tasks.isEmpty() && !uiState.isLoading) {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center,
                ) {
                    EmptyState(
                        icon = Icons.Default.Assignment,
                        title = "Geen actieve taken",
                        subtitle = "Start een opname om taken te zien",
                    )
                }
            } else {
                LazyColumn(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = TS.Spacing.md),
                    verticalArrangement = Arrangement.spacedBy(TS.Spacing.sm),
                ) {
                    // Top spacing
                    item { Spacer(modifier = Modifier.height(TS.Spacing.sm)) }

                    items(
                        items = uiState.tasks,
                        key = { it.effectiveId },
                    ) { task ->
                        TaskCard(
                            task = task,
                            onCancel = { viewModel.cancelTask(task.effectiveId) },
                            onClick = {
                                if (task.status == TaskStatus.COMPLETED) {
                                    onNavigateToTranscript(task.effectiveId)
                                }
                            },
                        )
                    }

                    // Bottom spacing
                    item { Spacer(modifier = Modifier.height(TS.Spacing.sm)) }
                }
            }

            // Error message
            if (uiState.error != null) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(TS.Spacing.md),
                    contentAlignment = Alignment.TopCenter,
                ) {
                    TSCard(modifier = Modifier.fillMaxWidth()) {
                        Text(
                            text = uiState.error!!,
                            modifier = Modifier.padding(TS.Spacing.md),
                            color = StatusError,
                            style = MaterialTheme.typography.bodyMedium,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun TaskCard(
    task: TranscriptTask,
    onCancel: () -> Unit,
    onClick: () -> Unit,
) {
    var showCancelDialog by remember { mutableStateOf(false) }

    if (showCancelDialog) {
        AlertDialog(
            onDismissRequest = { showCancelDialog = false },
            title = { Text("Taak annuleren") },
            text = { Text("Weet je zeker dat je deze taak wilt annuleren?") },
            confirmButton = {
                TextButton(onClick = {
                    showCancelDialog = false
                    onCancel()
                }) {
                    Text("Annuleren", color = StatusError)
                }
            },
            dismissButton = {
                TextButton(onClick = { showCancelDialog = false }) {
                    Text("Terug")
                }
            },
        )
    }

    TSCard(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = task.status == TaskStatus.COMPLETED) { onClick() },
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(TS.Spacing.md),
        ) {
            // Title row with status badge
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = task.effectiveTitle,
                    style = MaterialTheme.typography.titleSmall,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                StatusBadge(
                    text = task.status.displayName,
                    color = task.status.toColor(),
                    modifier = Modifier.padding(start = TS.Spacing.sm),
                )
            }

            Spacer(modifier = Modifier.height(TS.Spacing.sm))

            // Progress bar
            val progress = task.progress ?: task.status.progress
            LinearProgressIndicator(
                progress = { progress },
                modifier = Modifier.fillMaxWidth(),
                color = task.status.toColor(),
                trackColor = MaterialTheme.colorScheme.surfaceVariant,
                strokeCap = StrokeCap.Round,
            )

            // Status message if available
            if (task.message != null) {
                Spacer(modifier = Modifier.height(TS.Spacing.xs))
                Text(
                    text = task.message!!,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }

            // Cancel button for active tasks
            if (task.status.isActive) {
                Spacer(modifier = Modifier.height(TS.Spacing.xs))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End,
                ) {
                    IconButton(onClick = { showCancelDialog = true }) {
                        Icon(
                            imageVector = Icons.Default.Close,
                            contentDescription = "Annuleren",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
    }
}

private fun TaskStatus.toColor(): Color = when (this) {
    TaskStatus.COMPLETED -> StatusSuccess
    TaskStatus.ERROR -> StatusError
    TaskStatus.TRANSCRIBING, TaskStatus.GENERATING_NOTULE -> BrandSecondary
    else -> StatusWarning
}
