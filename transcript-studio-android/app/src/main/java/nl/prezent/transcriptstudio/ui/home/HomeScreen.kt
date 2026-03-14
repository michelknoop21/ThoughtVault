package nl.prezent.transcriptstudio.ui.home

import androidx.compose.foundation.background
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Article
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import nl.prezent.transcriptstudio.R
import nl.prezent.transcriptstudio.data.model.TaskStatus
import nl.prezent.transcriptstudio.data.model.Transcript
import nl.prezent.transcriptstudio.data.model.TranscriptTask
import nl.prezent.transcriptstudio.ui.components.ErrorBanner
import nl.prezent.transcriptstudio.ui.components.StatusBadge
import nl.prezent.transcriptstudio.ui.components.TSCard
import nl.prezent.transcriptstudio.ui.theme.BrandPrimary
import nl.prezent.transcriptstudio.ui.theme.BrandPrimaryDark
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

    Column(modifier = Modifier.fillMaxSize()) {
        // Branded top bar — clean surface with brand-colored title
        TopAppBar(
            title = {
                Text(
                    text = stringResource(R.string.home_title),
                    fontWeight = FontWeight.Bold,
                )
            },
            colors = TopAppBarDefaults.topAppBarColors(
                containerColor = MaterialTheme.colorScheme.surface,
                titleContentColor = MaterialTheme.colorScheme.onSurface,
            ),
        )

        PullToRefreshBox(
            isRefreshing = uiState.isRefreshing,
            onRefresh = viewModel::refresh,
            modifier = Modifier.fillMaxSize(),
        ) {
            if (uiState.isLoading) {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator(color = BrandPrimary)
                }
            } else {
                LazyColumn(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(horizontal = TS.Spacing.md),
                    verticalArrangement = Arrangement.spacedBy(TS.Spacing.md),
                ) {
                    item { Spacer(modifier = Modifier.height(TS.Spacing.xs)) }

                    // Greeting + branding
                    item {
                        GreetingSection(
                            userName = uiState.userName,
                            greetingType = uiState.greetingType,
                        )
                    }

                    // Hero CTA card (matching macOS gradient CTA)
                    item {
                        HeroCTACard(onClick = onNavigateToRecording)
                    }

                    // Error
                    if (uiState.error != null) {
                        item {
                            ErrorBanner(message = uiState.error!!)
                        }
                    }

                    // Active tasks
                    if (uiState.activeTasks.isNotEmpty()) {
                        item {
                            SectionHeader(title = stringResource(R.string.home_active_tasks))
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

                    // Recent transcripts
                    if (uiState.recentTranscripts.isNotEmpty()) {
                        item {
                            SectionHeader(title = stringResource(R.string.home_recent_transcripts))
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
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onSurface,
        )

        Spacer(modifier = Modifier.height(TS.Spacing.xs))

        Text(
            text = stringResource(R.string.home_subtitle),
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/**
 * Hero CTA card with gradient background — matches macOS HomeView CTA.
 * Gradient from BrandPrimary to BrandPrimaryDark with microphone icon.
 */
@Composable
private fun HeroCTACard(onClick: () -> Unit) {
    val ctaGradient = Brush.linearGradient(
        colors = listOf(BrandPrimary, BrandPrimaryDark),
    )
    val shape = RoundedCornerShape(TS.Radius.lg)

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .shadow(
                elevation = 16.dp,
                shape = shape,
                ambientColor = BrandPrimary.copy(alpha = 0.25f),
                spotColor = BrandPrimary.copy(alpha = 0.30f),
            )
            .clip(shape)
            .background(ctaGradient)
            .clickable(onClick = onClick)
            .padding(horizontal = TS.Spacing.lg, vertical = TS.Spacing.lg),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth(),
        ) {
            // Mic icon in circle with glass effect
            Box(
                modifier = Modifier
                    .size(52.dp)
                    .background(Color.White.copy(alpha = 0.18f), CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Default.Mic,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(26.dp),
                )
            }

            Spacer(modifier = Modifier.width(TS.Spacing.md))

            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = stringResource(R.string.home_quick_start),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                )
                Spacer(modifier = Modifier.height(2.dp))
                Text(
                    text = stringResource(R.string.home_cta_subtitle),
                    style = MaterialTheme.typography.bodySmall,
                    color = Color.White.copy(alpha = 0.75f),
                )
            }

            Icon(
                imageVector = Icons.Default.ChevronRight,
                contentDescription = null,
                tint = Color.White.copy(alpha = 0.6f),
                modifier = Modifier.size(20.dp),
            )
        }
    }
}

@Composable
private fun SectionHeader(title: String) {
    Text(
        text = title.uppercase(),
        style = MaterialTheme.typography.labelLarge,
        fontWeight = FontWeight.SemiBold,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        letterSpacing = 0.8.sp,
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

private fun formatDate(isoDate: String): String {
    return try {
        val datePart = isoDate.substringBefore("T")
        val parts = datePart.split("-")
        if (parts.size == 3) {
            "${parts[2]}-${parts[1]}-${parts[0]}"
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
