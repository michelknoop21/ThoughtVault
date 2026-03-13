package nl.prezent.transcriptstudio.ui.admin

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
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
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.BugReport
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Dashboard
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Feedback
import androidx.compose.material.icons.filled.Key
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.VpnKey
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.ScrollableTabRow
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import nl.prezent.transcriptstudio.R
import nl.prezent.transcriptstudio.data.model.AdminSettings
import nl.prezent.transcriptstudio.data.model.AdminUser
import nl.prezent.transcriptstudio.data.model.ErrorLog
import nl.prezent.transcriptstudio.data.model.Feedback
import nl.prezent.transcriptstudio.data.model.InviteCode
import nl.prezent.transcriptstudio.data.model.SystemStats
import nl.prezent.transcriptstudio.ui.components.EmptyState
import nl.prezent.transcriptstudio.ui.components.StatusBadge
import nl.prezent.transcriptstudio.ui.components.TSCard
import nl.prezent.transcriptstudio.ui.components.TSPrimaryButton
import nl.prezent.transcriptstudio.ui.components.TSSecondaryButton
import nl.prezent.transcriptstudio.ui.theme.BrandAccent
import nl.prezent.transcriptstudio.ui.theme.BrandOrange
import nl.prezent.transcriptstudio.ui.theme.BrandPrimary
import nl.prezent.transcriptstudio.ui.theme.BrandSecondary
import nl.prezent.transcriptstudio.ui.theme.StatusError
import nl.prezent.transcriptstudio.ui.theme.StatusSuccess
import nl.prezent.transcriptstudio.ui.theme.StatusWarning
import nl.prezent.transcriptstudio.ui.theme.TS

private data class AdminTab(val title: String, val icon: ImageVector)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AdminScreen(
    onNavigateBack: () -> Unit,
    viewModel: AdminViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }

    val adminTabs = listOf(
        AdminTab(stringResource(R.string.admin_tab_overview), Icons.Default.Dashboard),
        AdminTab(stringResource(R.string.admin_tab_users), Icons.Default.People),
        AdminTab(stringResource(R.string.admin_tab_invites), Icons.Default.VpnKey),
        AdminTab(stringResource(R.string.admin_tab_feedback), Icons.Default.Feedback),
        AdminTab(stringResource(R.string.admin_tab_logging), Icons.Default.BugReport),
        AdminTab(stringResource(R.string.admin_tab_settings), Icons.Default.Settings),
    )

    // Show success/error messages via snackbar
    LaunchedEffect(uiState.successMessage) {
        uiState.successMessage?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearMessages()
        }
    }
    LaunchedEffect(uiState.error) {
        uiState.error?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearMessages()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.admin_title)) },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = stringResource(R.string.admin_back),
                        )
                    }
                },
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
        ) {
            ScrollableTabRow(
                selectedTabIndex = uiState.selectedTab,
                edgePadding = TS.Spacing.md,
            ) {
                adminTabs.forEachIndexed { index, tab ->
                    Tab(
                        selected = uiState.selectedTab == index,
                        onClick = { viewModel.selectTab(index) },
                        text = { Text(tab.title) },
                        icon = {
                            Icon(
                                imageVector = tab.icon,
                                contentDescription = tab.title,
                                modifier = Modifier.size(18.dp),
                            )
                        },
                    )
                }
            }

            when (uiState.selectedTab) {
                0 -> DashboardTab(
                    stats = uiState.stats,
                    isLoading = uiState.statsLoading,
                )
                1 -> UsersTab(
                    users = uiState.users,
                    isLoading = uiState.usersLoading,
                    onCreateUser = viewModel::createUser,
                    onResetPassword = viewModel::resetUserPassword,
                    onReset2FA = viewModel::resetUser2FA,
                    onDeleteUser = viewModel::deleteUser,
                )
                2 -> InvitesTab(
                    inviteCodes = uiState.inviteCodes,
                    isLoading = uiState.inviteCodesLoading,
                    onCreateCode = viewModel::createInviteCode,
                    onDeleteCode = viewModel::deleteInviteCode,
                )
                3 -> FeedbackTab(
                    feedbackItems = uiState.feedbackItems,
                    isLoading = uiState.feedbackLoading,
                    onUpdateStatus = viewModel::updateFeedbackStatus,
                    onUpdateResponse = viewModel::updateFeedbackResponse,
                    onDelete = viewModel::deleteFeedback,
                )
                4 -> ErrorLogsTab(
                    errorLogs = uiState.errorLogs,
                    isLoading = uiState.errorLogsLoading,
                    severityFilter = uiState.errorSeverityFilter,
                    onSeverityFilterChange = viewModel::setErrorSeverityFilter,
                )
                5 -> SettingsTab(
                    settings = uiState.settings,
                    isLoading = uiState.settingsLoading,
                    isSaving = uiState.settingsSaving,
                    onSave = viewModel::updateSettings,
                )
            }
        }
    }
}

// -- Tab 0: Dashboard --

@Composable
private fun DashboardTab(
    stats: SystemStats?,
    isLoading: Boolean,
) {
    if (isLoading) {
        LoadingIndicator()
        return
    }
    if (stats == null) {
        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.Center,
        ) {
            EmptyState(
                icon = Icons.Default.Dashboard,
                title = stringResource(R.string.admin_dashboard_empty),
            )
        }
        return
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = TS.Spacing.md),
        verticalArrangement = Arrangement.spacedBy(TS.Spacing.sm),
    ) {
        item { Spacer(modifier = Modifier.height(TS.Spacing.sm)) }

        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(TS.Spacing.sm),
            ) {
                StatCard(
                    label = stringResource(R.string.admin_stat_users),
                    value = stats.totalUsers.toString(),
                    modifier = Modifier.weight(1f),
                )
                StatCard(
                    label = stringResource(R.string.admin_stat_active),
                    value = stats.activeUsers.toString(),
                    modifier = Modifier.weight(1f),
                )
            }
        }

        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(TS.Spacing.sm),
            ) {
                StatCard(
                    label = stringResource(R.string.admin_stat_transcriptions),
                    value = stats.totalNotes.toString(),
                    modifier = Modifier.weight(1f),
                )
                StatCard(
                    label = stringResource(R.string.admin_stat_active_tasks),
                    value = stats.activeTasks.toString(),
                    modifier = Modifier.weight(1f),
                )
            }
        }

        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(TS.Spacing.sm),
            ) {
                StatCard(
                    label = stringResource(R.string.admin_stat_feedback),
                    value = stats.pendingFeedback.toString(),
                    modifier = Modifier.weight(1f),
                )
                StatCard(
                    label = stringResource(R.string.admin_stat_errors),
                    value = stats.errorCount.toString(),
                    modifier = Modifier.weight(1f),
                )
            }
        }

        item { Spacer(modifier = Modifier.height(TS.Spacing.sm)) }
    }
}

@Composable
private fun StatCard(
    label: String,
    value: String,
    modifier: Modifier = Modifier,
) {
    TSCard(modifier = modifier) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(TS.Spacing.md),
        ) {
            Text(
                text = value,
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold,
                color = BrandPrimary,
            )
            Spacer(modifier = Modifier.height(TS.Spacing.xs))
            Text(
                text = label,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

// -- Tab 1: Users --

@Composable
private fun UsersTab(
    users: List<AdminUser>,
    isLoading: Boolean,
    onCreateUser: (String, String, String?, String) -> Unit,
    onResetPassword: (String, String) -> Unit,
    onReset2FA: (String) -> Unit,
    onDeleteUser: (String) -> Unit,
) {
    var showCreateDialog by remember { mutableStateOf(false) }

    if (showCreateDialog) {
        CreateUserDialog(
            onDismiss = { showCreateDialog = false },
            onConfirm = { username, password, name, role ->
                onCreateUser(username, password, name, role)
                showCreateDialog = false
            },
        )
    }

    if (isLoading) {
        LoadingIndicator()
        return
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = TS.Spacing.md),
        verticalArrangement = Arrangement.spacedBy(TS.Spacing.sm),
    ) {
        item { Spacer(modifier = Modifier.height(TS.Spacing.sm)) }

        item {
            TSPrimaryButton(
                text = stringResource(R.string.admin_users_create),
                onClick = { showCreateDialog = true },
                modifier = Modifier.fillMaxWidth(),
            )
        }

        if (users.isEmpty()) {
            item {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = TS.Spacing.xl),
                    contentAlignment = Alignment.Center,
                ) {
                    EmptyState(
                        icon = Icons.Default.People,
                        title = stringResource(R.string.admin_users_empty),
                    )
                }
            }
        } else {
            items(users, key = { it.id ?: it.username }) { user ->
                UserCard(
                    user = user,
                    onResetPassword = onResetPassword,
                    onReset2FA = onReset2FA,
                    onDelete = onDeleteUser,
                )
            }
        }

        item { Spacer(modifier = Modifier.height(TS.Spacing.sm)) }
    }
}

@Composable
private fun UserCard(
    user: AdminUser,
    onResetPassword: (String, String) -> Unit,
    onReset2FA: (String) -> Unit,
    onDelete: (String) -> Unit,
) {
    var showDeleteDialog by remember { mutableStateOf(false) }
    var showResetPasswordDialog by remember { mutableStateOf(false) }
    val userId = user.id ?: return

    if (showDeleteDialog) {
        ConfirmDialog(
            title = stringResource(R.string.admin_users_delete_title),
            message = stringResource(R.string.admin_users_delete_message, user.username),
            confirmText = stringResource(R.string.admin_feedback_delete_confirm),
            onConfirm = {
                onDelete(userId)
                showDeleteDialog = false
            },
            onDismiss = { showDeleteDialog = false },
        )
    }

    if (showResetPasswordDialog) {
        ResetPasswordDialog(
            username = user.username,
            onDismiss = { showResetPasswordDialog = false },
            onConfirm = { newPassword ->
                onResetPassword(userId, newPassword)
                showResetPasswordDialog = false
            },
        )
    }

    TSCard(modifier = Modifier.fillMaxWidth()) {
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
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = user.name ?: user.username,
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        text = user.username,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                StatusBadge(
                    text = user.role,
                    color = if (user.role == "admin") BrandOrange else BrandSecondary,
                )
            }

            Spacer(modifier = Modifier.height(TS.Spacing.sm))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    text = if (user.lastLogin != null) stringResource(R.string.admin_users_last_login, formatDateTime(user.lastLogin)) else stringResource(R.string.admin_users_never_logged_in),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (user.noteCount != null) {
                    Text(
                        text = stringResource(R.string.admin_users_note_count, user.noteCount),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            Spacer(modifier = Modifier.height(TS.Spacing.sm))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(TS.Spacing.sm),
            ) {
                TSSecondaryButton(
                    text = stringResource(R.string.admin_users_password_button),
                    onClick = { showResetPasswordDialog = true },
                )
                if (user.twofaEnabled == true) {
                    TSSecondaryButton(
                        text = stringResource(R.string.admin_users_reset_2fa),
                        onClick = { onReset2FA(userId) },
                    )
                }
                Spacer(modifier = Modifier.weight(1f))
                IconButton(onClick = { showDeleteDialog = true }) {
                    Icon(
                        imageVector = Icons.Default.Delete,
                        contentDescription = stringResource(R.string.admin_users_delete_cd),
                        tint = StatusError,
                    )
                }
            }
        }
    }
}

@Composable
private fun CreateUserDialog(
    onDismiss: () -> Unit,
    onConfirm: (username: String, password: String, name: String?, role: String) -> Unit,
) {
    var username by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }
    var name by rememberSaveable { mutableStateOf("") }
    var role by rememberSaveable { mutableStateOf("user") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.admin_create_user_title)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(TS.Spacing.sm)) {
                OutlinedTextField(
                    value = username,
                    onValueChange = { username = it },
                    label = { Text(stringResource(R.string.admin_create_user_email)) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = password,
                    onValueChange = { password = it },
                    label = { Text(stringResource(R.string.admin_create_user_password)) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text(stringResource(R.string.admin_create_user_name)) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                Row(horizontalArrangement = Arrangement.spacedBy(TS.Spacing.sm)) {
                    FilterChip(
                        selected = role == "user",
                        onClick = { role = "user" },
                        label = { Text(stringResource(R.string.admin_create_user_role_user)) },
                    )
                    FilterChip(
                        selected = role == "admin",
                        onClick = { role = "admin" },
                        label = { Text(stringResource(R.string.admin_create_user_role_admin)) },
                    )
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    onConfirm(
                        username,
                        password,
                        name.ifBlank { null },
                        role,
                    )
                },
                enabled = username.isNotBlank() && password.isNotBlank(),
            ) {
                Text(stringResource(R.string.admin_create_user_confirm))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.admin_create_user_cancel))
            }
        },
    )
}

@Composable
private fun ResetPasswordDialog(
    username: String,
    onDismiss: () -> Unit,
    onConfirm: (String) -> Unit,
) {
    var newPassword by rememberSaveable { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.admin_reset_password_title)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(TS.Spacing.sm)) {
                Text(stringResource(R.string.admin_reset_password_message, username))
                OutlinedTextField(
                    value = newPassword,
                    onValueChange = { newPassword = it },
                    label = { Text(stringResource(R.string.admin_reset_password_label)) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = { onConfirm(newPassword) },
                enabled = newPassword.isNotBlank(),
            ) {
                Text(stringResource(R.string.admin_reset_password_confirm))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.admin_reset_password_cancel))
            }
        },
    )
}

// -- Tab 2: Invite Codes --

@Composable
private fun InvitesTab(
    inviteCodes: List<InviteCode>,
    isLoading: Boolean,
    onCreateCode: (maxUses: Int, expiresHours: Int) -> Unit,
    onDeleteCode: (String) -> Unit,
) {
    var showCreateDialog by remember { mutableStateOf(false) }

    if (showCreateDialog) {
        CreateInviteDialog(
            onDismiss = { showCreateDialog = false },
            onConfirm = { maxUses, expiresHours ->
                onCreateCode(maxUses, expiresHours)
                showCreateDialog = false
            },
        )
    }

    if (isLoading) {
        LoadingIndicator()
        return
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = TS.Spacing.md),
        verticalArrangement = Arrangement.spacedBy(TS.Spacing.sm),
    ) {
        item { Spacer(modifier = Modifier.height(TS.Spacing.sm)) }

        item {
            TSPrimaryButton(
                text = stringResource(R.string.admin_invites_create),
                onClick = { showCreateDialog = true },
                modifier = Modifier.fillMaxWidth(),
            )
        }

        if (inviteCodes.isEmpty()) {
            item {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = TS.Spacing.xl),
                    contentAlignment = Alignment.Center,
                ) {
                    EmptyState(
                        icon = Icons.Default.VpnKey,
                        title = stringResource(R.string.admin_invites_empty),
                    )
                }
            }
        } else {
            items(inviteCodes, key = { it.code }) { code ->
                InviteCodeCard(
                    inviteCode = code,
                    onDelete = { onDeleteCode(code.code) },
                )
            }
        }

        item { Spacer(modifier = Modifier.height(TS.Spacing.sm)) }
    }
}

@Composable
private fun InviteCodeCard(
    inviteCode: InviteCode,
    onDelete: () -> Unit,
) {
    val context = LocalContext.current
    var showDeleteDialog by remember { mutableStateOf(false) }

    if (showDeleteDialog) {
        ConfirmDialog(
            title = stringResource(R.string.admin_invites_delete_title),
            message = stringResource(R.string.admin_invites_delete_message, inviteCode.code),
            confirmText = stringResource(R.string.admin_feedback_delete_confirm),
            onConfirm = {
                onDelete()
                showDeleteDialog = false
            },
            onDismiss = { showDeleteDialog = false },
        )
    }

    TSCard(modifier = Modifier.fillMaxWidth()) {
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
                    text = inviteCode.code,
                    style = MaterialTheme.typography.titleSmall,
                    fontFamily = FontFamily.Monospace,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.weight(1f),
                )
                Row {
                    IconButton(onClick = {
                        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                        clipboard.setPrimaryClip(ClipData.newPlainText("invite code", inviteCode.code))
                    }) {
                        Icon(
                            imageVector = Icons.Default.ContentCopy,
                            contentDescription = stringResource(R.string.admin_invites_copy_cd),
                            modifier = Modifier.size(20.dp),
                        )
                    }
                    IconButton(onClick = { showDeleteDialog = true }) {
                        Icon(
                            imageVector = Icons.Default.Delete,
                            contentDescription = stringResource(R.string.admin_invites_delete_cd),
                            tint = StatusError,
                            modifier = Modifier.size(20.dp),
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(TS.Spacing.xs))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(
                    text = stringResource(R.string.admin_invites_usage, inviteCode.currentUses, inviteCode.maxUses),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                if (inviteCode.expiresAt != null) {
                    Text(
                        text = stringResource(R.string.admin_invites_expires, formatDateTime(inviteCode.expiresAt)),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            if (!inviteCode.isActive) {
                Spacer(modifier = Modifier.height(TS.Spacing.xs))
                StatusBadge(text = stringResource(R.string.admin_invites_inactive), color = StatusError)
            }
        }
    }
}

@Composable
private fun CreateInviteDialog(
    onDismiss: () -> Unit,
    onConfirm: (maxUses: Int, expiresHours: Int) -> Unit,
) {
    var maxUses by rememberSaveable { mutableStateOf("1") }
    var expiresHours by rememberSaveable { mutableStateOf("48") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.admin_invites_create_title)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(TS.Spacing.sm)) {
                OutlinedTextField(
                    value = maxUses,
                    onValueChange = { maxUses = it.filter { c -> c.isDigit() } },
                    label = { Text(stringResource(R.string.admin_invites_max_uses)) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = expiresHours,
                    onValueChange = { expiresHours = it.filter { c -> c.isDigit() } },
                    label = { Text(stringResource(R.string.admin_invites_valid_hours)) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    onConfirm(
                        maxUses.toIntOrNull() ?: 1,
                        expiresHours.toIntOrNull() ?: 48,
                    )
                },
            ) {
                Text(stringResource(R.string.admin_invites_create_confirm))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.admin_invites_create_cancel))
            }
        },
    )
}

// -- Tab 3: Feedback --

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun FeedbackTab(
    feedbackItems: List<Feedback>,
    isLoading: Boolean,
    onUpdateStatus: (Int, String) -> Unit,
    onUpdateResponse: (Int, String) -> Unit,
    onDelete: (Int) -> Unit,
) {
    if (isLoading) {
        LoadingIndicator()
        return
    }

    if (feedbackItems.isEmpty()) {
        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.Center,
        ) {
            EmptyState(
                icon = Icons.Default.Feedback,
                title = stringResource(R.string.admin_feedback_empty_title),
                subtitle = stringResource(R.string.admin_feedback_empty_subtitle),
            )
        }
        return
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = TS.Spacing.md),
        verticalArrangement = Arrangement.spacedBy(TS.Spacing.sm),
    ) {
        item { Spacer(modifier = Modifier.height(TS.Spacing.sm)) }

        items(feedbackItems, key = { it.id ?: 0 }) { feedback ->
            FeedbackCard(
                feedback = feedback,
                onUpdateStatus = onUpdateStatus,
                onUpdateResponse = onUpdateResponse,
                onDelete = onDelete,
            )
        }

        item { Spacer(modifier = Modifier.height(TS.Spacing.sm)) }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun FeedbackCard(
    feedback: Feedback,
    onUpdateStatus: (Int, String) -> Unit,
    onUpdateResponse: (Int, String) -> Unit,
    onDelete: (Int) -> Unit,
) {
    val feedbackId = feedback.id ?: return
    var expanded by remember { mutableStateOf(false) }
    var showDeleteDialog by remember { mutableStateOf(false) }
    var adminResponse by rememberSaveable(feedbackId) {
        mutableStateOf(feedback.adminResponse ?: "")
    }
    var showStatusMenu by remember { mutableStateOf(false) }

    if (showDeleteDialog) {
        ConfirmDialog(
            title = stringResource(R.string.admin_feedback_delete_title),
            message = stringResource(R.string.admin_feedback_delete_message),
            confirmText = stringResource(R.string.admin_feedback_delete_confirm),
            onConfirm = {
                onDelete(feedbackId)
                showDeleteDialog = false
            },
            onDismiss = { showDeleteDialog = false },
        )
    }

    TSCard(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { expanded = !expanded },
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(TS.Spacing.md),
        ) {
            // Header row
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = feedback.title ?: stringResource(R.string.admin_feedback_no_title),
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = if (expanded) Int.MAX_VALUE else 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    if (feedback.username != null) {
                        Text(
                            text = feedback.username,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }

                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(TS.Spacing.xs),
                    verticalArrangement = Arrangement.spacedBy(TS.Spacing.xs),
                ) {
                    if (feedback.category != null) {
                        StatusBadge(
                            text = feedback.category,
                            color = BrandSecondary,
                        )
                    }
                    StatusBadge(
                        text = feedback.status ?: "open",
                        color = feedbackStatusColor(feedback.status),
                    )
                }
            }

            // Expand indicator
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.Center,
            ) {
                Icon(
                    imageVector = if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                    contentDescription = if (expanded) stringResource(R.string.admin_feedback_collapse) else stringResource(R.string.admin_feedback_expand),
                    modifier = Modifier.size(16.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            // Expanded content
            if (expanded) {
                Spacer(modifier = Modifier.height(TS.Spacing.sm))

                if (feedback.description != null) {
                    Text(
                        text = feedback.description,
                        style = MaterialTheme.typography.bodyMedium,
                    )
                    Spacer(modifier = Modifier.height(TS.Spacing.sm))
                }

                if (feedback.createdAt != null) {
                    Text(
                        text = stringResource(R.string.admin_feedback_received, formatDateTime(feedback.createdAt)),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(modifier = Modifier.height(TS.Spacing.sm))
                }

                // Admin response field
                OutlinedTextField(
                    value = adminResponse,
                    onValueChange = { adminResponse = it },
                    label = { Text(stringResource(R.string.admin_feedback_response_label)) },
                    modifier = Modifier.fillMaxWidth(),
                    minLines = 2,
                    maxLines = 5,
                )

                Spacer(modifier = Modifier.height(TS.Spacing.sm))

                // Actions row
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(TS.Spacing.sm),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    // Status dropdown
                    Box {
                        TSSecondaryButton(
                            text = stringResource(R.string.admin_feedback_status_prefix, feedback.status ?: "open"),
                            onClick = { showStatusMenu = true },
                        )
                        DropdownMenu(
                            expanded = showStatusMenu,
                            onDismissRequest = { showStatusMenu = false },
                        ) {
                            listOf("open", "in_progress", "resolved", "closed").forEach { status ->
                                DropdownMenuItem(
                                    text = { Text(feedbackStatusLabel(status)) },
                                    onClick = {
                                        onUpdateStatus(feedbackId, status)
                                        showStatusMenu = false
                                    },
                                )
                            }
                        }
                    }

                    if (adminResponse.isNotBlank() && adminResponse != (feedback.adminResponse ?: "")) {
                        TSPrimaryButton(
                            text = stringResource(R.string.admin_feedback_save),
                            onClick = { onUpdateResponse(feedbackId, adminResponse) },
                        )
                    }

                    Spacer(modifier = Modifier.weight(1f))

                    IconButton(onClick = { showDeleteDialog = true }) {
                        Icon(
                            imageVector = Icons.Default.Delete,
                            contentDescription = stringResource(R.string.admin_feedback_delete_cd),
                            tint = StatusError,
                        )
                    }
                }
            }
        }
    }
}

private fun feedbackStatusColor(status: String?) = when (status) {
    "resolved", "closed" -> StatusSuccess
    "in_progress" -> BrandOrange
    else -> BrandSecondary
}

@Composable
private fun feedbackStatusLabel(status: String) = when (status) {
    "open" -> stringResource(R.string.admin_feedback_status_open)
    "in_progress" -> stringResource(R.string.admin_feedback_status_in_progress)
    "resolved" -> stringResource(R.string.admin_feedback_status_resolved)
    "closed" -> stringResource(R.string.admin_feedback_status_closed)
    else -> status
}

// -- Tab 4: Error Logs --

@Composable
private fun ErrorLogsTab(
    errorLogs: List<ErrorLog>,
    isLoading: Boolean,
    severityFilter: String?,
    onSeverityFilterChange: (String?) -> Unit,
) {
    if (isLoading) {
        LoadingIndicator()
        return
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = TS.Spacing.md),
        verticalArrangement = Arrangement.spacedBy(TS.Spacing.sm),
    ) {
        item { Spacer(modifier = Modifier.height(TS.Spacing.sm)) }

        // Severity filter row
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(TS.Spacing.sm),
            ) {
                FilterChip(
                    selected = severityFilter == null,
                    onClick = { onSeverityFilterChange(null) },
                    label = { Text(stringResource(R.string.admin_logs_filter_all)) },
                )
                FilterChip(
                    selected = severityFilter == "error",
                    onClick = { onSeverityFilterChange("error") },
                    label = { Text("Error") },
                )
                FilterChip(
                    selected = severityFilter == "warning",
                    onClick = { onSeverityFilterChange("warning") },
                    label = { Text("Warning") },
                )
                FilterChip(
                    selected = severityFilter == "info",
                    onClick = { onSeverityFilterChange("info") },
                    label = { Text("Info") },
                )
            }
        }

        if (errorLogs.isEmpty()) {
            item {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = TS.Spacing.xl),
                    contentAlignment = Alignment.Center,
                ) {
                    EmptyState(
                        icon = Icons.Default.BugReport,
                        title = stringResource(R.string.admin_logs_empty_title),
                        subtitle = stringResource(R.string.admin_logs_empty_subtitle),
                    )
                }
            }
        } else {
            items(errorLogs, key = { it.id ?: 0 }) { log ->
                ErrorLogCard(log = log)
            }
        }

        item { Spacer(modifier = Modifier.height(TS.Spacing.sm)) }
    }
}

@Composable
private fun ErrorLogCard(log: ErrorLog) {
    var expanded by remember { mutableStateOf(false) }

    TSCard(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { expanded = !expanded },
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
                Row(
                    horizontalArrangement = Arrangement.spacedBy(TS.Spacing.sm),
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.weight(1f),
                ) {
                    StatusBadge(
                        text = log.severity ?: "unknown",
                        color = severityColor(log.severity),
                    )
                    Text(
                        text = log.message ?: stringResource(R.string.admin_logs_no_message),
                        style = MaterialTheme.typography.bodyMedium,
                        maxLines = if (expanded) Int.MAX_VALUE else 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                Icon(
                    imageVector = if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                    contentDescription = if (expanded) stringResource(R.string.admin_feedback_collapse) else stringResource(R.string.admin_feedback_expand),
                    modifier = Modifier.size(16.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            Spacer(modifier = Modifier.height(TS.Spacing.xs))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                if (log.endpoint != null) {
                    Text(
                        text = log.endpoint,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        fontFamily = FontFamily.Monospace,
                    )
                }
                if (log.createdAt != null) {
                    Text(
                        text = formatDateTime(log.createdAt),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            if (expanded) {
                if (log.username != null) {
                    Spacer(modifier = Modifier.height(TS.Spacing.xs))
                    Text(
                        text = stringResource(R.string.admin_logs_user, log.username),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }

                if (log.stackTrace != null) {
                    Spacer(modifier = Modifier.height(TS.Spacing.sm))
                    Text(
                        text = log.stackTrace,
                        style = MaterialTheme.typography.bodySmall,
                        fontFamily = FontFamily.Monospace,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

private fun severityColor(severity: String?) = when (severity?.lowercase()) {
    "error" -> StatusError
    "warning" -> StatusWarning
    "info" -> BrandSecondary
    else -> BrandAccent
}

// -- Tab 5: Settings --

@Composable
private fun SettingsTab(
    settings: AdminSettings?,
    isLoading: Boolean,
    isSaving: Boolean,
    onSave: (AdminSettings) -> Unit,
) {
    if (isLoading) {
        LoadingIndicator()
        return
    }

    var webhookUrl by rememberSaveable(settings) {
        mutableStateOf(settings?.webhookUrl ?: "")
    }
    var notificationWebhookUrl by rememberSaveable(settings) {
        mutableStateOf(settings?.notificationWebhookUrl ?: "")
    }
    var ms365ClientId by rememberSaveable(settings) {
        mutableStateOf(settings?.ms365ClientId ?: "")
    }
    var ms365TenantId by rememberSaveable(settings) {
        mutableStateOf(settings?.ms365TenantId ?: "")
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = TS.Spacing.md),
        verticalArrangement = Arrangement.spacedBy(TS.Spacing.md),
    ) {
        item { Spacer(modifier = Modifier.height(TS.Spacing.sm)) }

        item {
            OutlinedTextField(
                value = webhookUrl,
                onValueChange = { webhookUrl = it },
                label = { Text(stringResource(R.string.admin_settings_webhook_url)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
        }

        item {
            OutlinedTextField(
                value = notificationWebhookUrl,
                onValueChange = { notificationWebhookUrl = it },
                label = { Text(stringResource(R.string.admin_settings_notification_webhook)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
        }

        item {
            OutlinedTextField(
                value = ms365ClientId,
                onValueChange = { ms365ClientId = it },
                label = { Text(stringResource(R.string.admin_settings_ms365_client_id)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
        }

        item {
            OutlinedTextField(
                value = ms365TenantId,
                onValueChange = { ms365TenantId = it },
                label = { Text(stringResource(R.string.admin_settings_ms365_tenant_id)) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
        }

        item {
            TSPrimaryButton(
                text = if (isSaving) stringResource(R.string.admin_settings_saving) else stringResource(R.string.admin_settings_save),
                onClick = {
                    onSave(
                        AdminSettings(
                            webhookUrl = webhookUrl.ifBlank { null },
                            notificationWebhookUrl = notificationWebhookUrl.ifBlank { null },
                            ms365ClientId = ms365ClientId.ifBlank { null },
                            ms365TenantId = ms365TenantId.ifBlank { null },
                        ),
                    )
                },
                enabled = !isSaving,
                modifier = Modifier.fillMaxWidth(),
            )
        }

        item { Spacer(modifier = Modifier.height(TS.Spacing.sm)) }
    }
}

// -- Shared Components --

@Composable
private fun LoadingIndicator() {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        CircularProgressIndicator(color = BrandPrimary)
    }
}

@Composable
private fun ConfirmDialog(
    title: String,
    message: String,
    confirmText: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { Text(message) },
        confirmButton = {
            TextButton(onClick = onConfirm) {
                Text(confirmText, color = StatusError)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.admin_confirm_cancel))
            }
        },
    )
}

/**
 * Format an ISO datetime string to a shorter display form.
 * Falls back to the raw string on parse failure.
 */
private fun formatDateTime(isoString: String): String {
    return try {
        // Trim to "yyyy-MM-dd HH:mm" for display
        val cleaned = isoString.replace("T", " ")
        if (cleaned.length >= 16) cleaned.substring(0, 16) else cleaned
    } catch (_: Exception) {
        isoString
    }
}
