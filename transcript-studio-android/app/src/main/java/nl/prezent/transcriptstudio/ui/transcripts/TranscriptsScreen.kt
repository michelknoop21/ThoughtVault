package nl.prezent.transcriptstudio.ui.transcripts

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
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
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import nl.prezent.transcriptstudio.R
import nl.prezent.transcriptstudio.ui.components.EmptyState
import nl.prezent.transcriptstudio.ui.components.TSCard
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

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.transcripts_title)) },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                ),
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            // Search bar
            OutlinedTextField(
                value = state.searchQuery,
                onValueChange = { viewModel.updateSearch(it) },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = TS.Spacing.md, vertical = TS.Spacing.sm),
                placeholder = { Text(stringResource(R.string.transcripts_search_placeholder)) },
                leadingIcon = {
                    Icon(
                        imageVector = Icons.Default.Search,
                        contentDescription = stringResource(R.string.transcripts_search_content_description),
                    )
                },
                singleLine = true,
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
        Column(
            modifier = Modifier.padding(TS.Spacing.md),
        ) {
            Text(
                text = transcript.effectiveTitle,
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurface,
            )

            if (transcript.createdAt != null) {
                Text(
                    text = transcript.createdAt,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = TS.Spacing.xs),
                )
            }

            if (transcript.tags.isNotEmpty()) {
                FlowRow(
                    modifier = Modifier.padding(top = TS.Spacing.sm),
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
    }
}
