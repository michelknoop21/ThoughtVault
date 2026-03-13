package nl.prezent.transcriptstudio.ui.home

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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Article
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import nl.prezent.transcriptstudio.R
import nl.prezent.transcriptstudio.data.model.TaskStatus
import nl.prezent.transcriptstudio.data.model.Transcript
import nl.prezent.transcriptstudio.data.model.TranscriptTask
import nl.prezent.transcriptstudio.ui.components.StatusBadge
import nl.prezent.transcriptstudio.ui.components.TSCard
import nl.prezent.transcriptstudio.ui.components.TSPrimaryButton
import nl.prezent.transcriptstudio.ui.components.YingaBar
import nl.prezent.transcriptstudio.ui.theme.BrandPrimary
import nl.prezent.transcriptstudio.ui.theme.BrandSecondary
import nl.prezent.transcriptstudio.ui.theme.StatusError
import nl.prezent.transcriptstudio.ui.theme.StatusSuccess
import nl.prezent.transcriptstudio.ui.theme.StatusWarning
import nl.prezent.transcriptstudio.ui.theme.TS

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    onNavigateToRecording: () -> Unit,
    onNavigateToTask: (String) -> Unit,
    viewModel: HomeViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.home_title)) },
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
            if (uiState.isLoading) {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator()
                }
            } else {
                LazyColumn(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = TS.Spacing.md),
                    verticalArrangement = Arrangement.spacedBy(TS.Spacing.md),
                ) {
                    // Top spacing
                    item { Spacer(modifier = Modifier.height(TS.Spacing.xs)) }

                    // Greeting section
                    item {
                        GreetingSection(
                            userName = uiState.userName,
                            greetingType = uiState.greetingType,
                        )
                    }

                    // Quick-start button
                    item {
                        TSPrimaryButton(
                            text = stringResource(R.string.home_quick_start),
                            onClick = onNavigateToRecording,
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }

                    // Error message
                    if (uiState.error != null) {
                        item {
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

                    // Active tasks section
                    if (uiState.activeTasks.isNotEmpty()) {
                        item {
                            SectionHeader(
                                title = stringResource(R.string.home_active_tasks),
                            )
                        }

                        items(
                            items = uiState.activeTasks,
                            key = { "task-${it.effectiveId}" },
                        ) { task ->
                            ActiveTaskCard(
                                task = task,
                                onClick = {
                                    if (task.status.isTerminal) {
                                        onNavigateToTask(task.effectiveId)
                                    }
                                },
                            )
                        }
                    }

                    // Recent transcripts section
                    if (uiState.recentTranscripts.isNotEmpty()) {
                        item {
                            SectionHeader(
                                title = stringResource(R.string.home_recent_transcripts),
                            )
                        }

                        items(
                            items = uiState.recentTranscripts,
                            key = { "transcript-${it.effectiveId}" },
                        ) { transcript ->
                            RecentTranscriptCard(
                                transcript = transcript,
                                onClick = { onNavigateToTask(transcript.effectiveId) },
                            )
                        }
                    }

                    // Bottom spacing
                    item { Spacer(modifier = Modifier.height(TS.Spacing.lg)) }
                }
            }
        }
    }
}

@Composable
private fun GreetingSection(
    userName: String?,
    greetingType: HomeViewModel.GreetingType,
) {
    Column {
        YingaBar()
        Spacer(modifier = Modifier.height(TS.Spacing.md))

        val greeting = when (greetingType) {
            HomeViewModel.GreetingType.MORNING -> {
                if (userName != null) stringResource(R.string.home_greeting_morning, userName)
                else stringResource(R.string.home_greeting_fallback)
            }
            HomeViewModel.GreetingType.AFTERNOON -> {
                if (userName != null) stringResource(R.string.home_greeting_afternoon, userName)
                else stringResource(R.string.home_greeting_fallback)
            }
            HomeViewModel.GreetingType.EVENING -> {
                if (userName != null) stringResource(R.string.home_greeting_evening, userName)
                else stringResource(R.string.home_greeting_fallback)
            }
        }

        Text(
            text = greeting,
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onSurface,
        )
    }
}

@Composable
private fun SectionHeader(
    title: String,
) {
    Text(
        text = title,
        style = MaterialTheme.typography.titleMedium,
        fontWeight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.onSurface,
        modifier = Modifier.padding(top = TS.Spacing.sm),
    )
}

@Composable
private fun ActiveTaskCard(
    task: TranscriptTask,
    onClick: () -> Unit,
) {
    TSCard(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(enabled = task.status.isTerminal) { onClick() },
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(TS.Spacing.md),
        ) {
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

            val progress = task.progress ?: task.status.progress
            LinearProgressIndicator(
                progress = { progress },
                modifier = Modifier.fillMaxWidth(),
                color = task.status.toColor(),
                trackColor = MaterialTheme.colorScheme.surfaceVariant,
                strokeCap = StrokeCap.Round,
            )

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
        }
    }
}

@Composable
private fun RecentTranscriptCard(
    transcript: Transcript,
    onClick: () -> Unit,
) {
    TSCard(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onClick() },
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(TS.Spacing.md),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = Icons.Default.Article,
                contentDescription = null,
                modifier = Modifier.size(24.dp),
                tint = BrandSecondary,
            )
            Spacer(modifier = Modifier.width(TS.Spacing.sm))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = transcript.effectiveTitle,
                    style = MaterialTheme.typography.titleSmall,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                if (transcript.createdAt != null) {
                    Text(
                        text = formatDate(transcript.createdAt),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Icon(
                imageVector = Icons.Default.ChevronRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/**
 * Formats an ISO date string to a short display format.
 * Falls back to the raw string if parsing fails.
 */
private fun formatDate(isoDate: String): String {
    return try {
        // ISO format: "2026-03-13T10:30:00" — take date part
        val datePart = isoDate.substringBefore("T")
        val parts = datePart.split("-")
        if (parts.size == 3) {
            "${parts[2]}-${parts[1]}-${parts[0]}" // DD-MM-YYYY
        } else {
            isoDate
        }
    } catch (_: Exception) {
        isoDate
    }
}

private fun TaskStatus.toColor() = when (this) {
    TaskStatus.COMPLETED -> StatusSuccess
    TaskStatus.ERROR -> StatusError
    TaskStatus.TRANSCRIBING, TaskStatus.GENERATING_NOTULE -> BrandSecondary
    else -> StatusWarning
}
