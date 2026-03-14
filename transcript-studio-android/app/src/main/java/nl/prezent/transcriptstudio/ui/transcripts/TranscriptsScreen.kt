package nl.prezent.transcriptstudio.ui.transcripts

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Article
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.ui.unit.dp
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.hilt.navigation.compose.hiltViewModel
import nl.prezent.transcriptstudio.R
import nl.prezent.transcriptstudio.ui.components.EmptyState
import nl.prezent.transcriptstudio.ui.components.TSCard
import nl.prezent.transcriptstudio.ui.components.TSTextField
import nl.prezent.transcriptstudio.ui.theme.BrandSecondary
import nl.prezent.transcriptstudio.ui.theme.TS

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun TranscriptsScreen(
    onNavigateToDetail: (String) -> Unit,
    viewModel: TranscriptsViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }

    LaunchedEffect(state.error) {
        state.error?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearError()
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        Column(modifier = Modifier.fillMaxSize()) {
            TopAppBar(
                title = {
                    Text(
                        text = stringResource(R.string.transcripts_title),
                        fontWeight = FontWeight.Bold,
                    )
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                    titleContentColor = MaterialTheme.colorScheme.onSurface,
                ),
            )

            Column(
                modifier = Modifier.fillMaxSize(),
            ) {
            // Search bar
            TSTextField(
                value = state.searchQuery,
                onValueChange = { viewModel.updateSearch(it) },
                label = "",
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = TS.Spacing.md, vertical = TS.Spacing.sm),
                placeholder = stringResource(R.string.transcripts_search_placeholder),
                singleLine = true,
                leadingIcon = {
                    Icon(
                        imageVector = Icons.Default.Search,
                        contentDescription = stringResource(R.string.transcripts_search_content_description),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                        modifier = Modifier.size(20.dp),
                    )
                },
            )

            // Content
            when {
                state.isLoading -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) {
                        CircularProgressIndicator()
                    }
                }

                state.transcripts.isEmpty() && !state.isRefreshing -> {
                    EmptyState(
                        icon = Icons.Default.Description,
                        title = stringResource(R.string.transcripts_empty_title),
                        subtitle = stringResource(R.string.transcripts_empty_subtitle),
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(TS.Spacing.xl),
                    )
                }

                else -> {
                    PullToRefreshBox(
                        isRefreshing = state.isRefreshing,
                        onRefresh = { viewModel.refresh() },
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        LazyColumn(
                            modifier = Modifier.fillMaxSize(),
                            contentPadding = androidx.compose.foundation.layout.PaddingValues(
                                horizontal = TS.Spacing.md,
                                vertical = TS.Spacing.sm,
                            ),
                            verticalArrangement = Arrangement.spacedBy(TS.Spacing.sm),
                        ) {
                            items(
                                items = state.transcripts,
                                key = { it.effectiveId },
                            ) { transcript ->
                                TranscriptListItem(
                                    transcript = transcript,
                                    onClick = { onNavigateToDetail(transcript.effectiveId) },
                                )
                            }
                        }
                    }
                }
            }
            }
        }

        SnackbarHost(
            hostState = snackbarHostState,
            modifier = Modifier.align(Alignment.BottomCenter),
        )
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun TranscriptListItem(
    transcript: nl.prezent.transcriptstudio.data.model.Transcript,
    onClick: () -> Unit,
) {
    TSCard(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
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
                    color = MaterialTheme.colorScheme.onSurface,
                )

                if (transcript.createdAt != null) {
                    Text(
                        text = formatDate(transcript.createdAt),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }

                if (transcript.tags.isNotEmpty()) {
                    FlowRow(
                        modifier = Modifier.padding(top = TS.Spacing.xs),
                        horizontalArrangement = Arrangement.spacedBy(TS.Spacing.xs),
                        verticalArrangement = Arrangement.spacedBy(TS.Spacing.xs),
                    ) {
                        transcript.tags.forEach { tag ->
                            AssistChip(
                                onClick = { },
                                label = {
                                    Text(
                                        text = tag,
                                        style = MaterialTheme.typography.labelSmall,
                                    )
                                },
                                colors = AssistChipDefaults.assistChipColors(
                                    containerColor = MaterialTheme.colorScheme.surfaceVariant,
                                ),
                                border = null,
                            )
                        }
                    }
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
