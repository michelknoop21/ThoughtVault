package nl.prezent.transcriptstudio.ui.settings

import androidx.compose.animation.AnimatedVisibility
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import nl.prezent.transcriptstudio.BuildConfig
import nl.prezent.transcriptstudio.R
import nl.prezent.transcriptstudio.ui.components.TSCard
import nl.prezent.transcriptstudio.ui.components.TSTextField
import nl.prezent.transcriptstudio.ui.components.TSPrimaryButton
import nl.prezent.transcriptstudio.ui.components.TSSecondaryButton
import nl.prezent.transcriptstudio.ui.components.YingaFooter
import nl.prezent.transcriptstudio.ui.theme.TS

@Composable
fun SettingsScreen(
    onLogout: () -> Unit,
    onNavigateToAdmin: () -> Unit,
    viewModel: SettingsViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }

    val feedbackSentMessage = stringResource(R.string.settings_feedback_sent)
    val passwordChangedMessage = stringResource(R.string.settings_feedback_password_changed)

    LaunchedEffect(Unit) {
        viewModel.events.collect { event ->
            when (event) {
                SettingsViewModel.Event.Logout -> onLogout()
                SettingsViewModel.Event.NavigateToAdmin -> onNavigateToAdmin()
            }
        }
    }

    LaunchedEffect(uiState.feedbackSuccess) {
        if (uiState.feedbackSuccess) {
            snackbarHostState.showSnackbar(feedbackSentMessage)
            viewModel.clearFeedbackSuccess()
        }
    }

    LaunchedEffect(uiState.passwordSuccess) {
        if (uiState.passwordSuccess) {
            snackbarHostState.showSnackbar(passwordChangedMessage)
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        SettingsContent(
            state = uiState,
            onUpdateBaseUrl = viewModel::updateBaseUrl,
            onUpdateApiPrefix = viewModel::updateApiPrefix,
            onSaveServer = viewModel::saveServerSettings,
            onCheckConnection = viewModel::checkConnection,
            onUpdateCurrentPassword = viewModel::updateCurrentPassword,
            onUpdateNewPassword = viewModel::updateNewPassword,
            onUpdateConfirmPassword = viewModel::updateConfirmPassword,
            onChangePassword = viewModel::changePassword,
            onUpdateFeedbackCategory = viewModel::updateFeedbackCategory,
            onUpdateFeedbackTitle = viewModel::updateFeedbackTitle,
            onUpdateFeedbackDescription = viewModel::updateFeedbackDescription,
            onSubmitFeedback = viewModel::submitFeedback,
            onLogout = viewModel::logout,
            onNavigateToAdmin = viewModel::navigateToAdmin,
        )

        SnackbarHost(
            hostState = snackbarHostState,
            modifier = Modifier.align(Alignment.BottomCenter),
        )
    }
}

@Composable
private fun SettingsContent(
    state: SettingsViewModel.UiState,
    onUpdateBaseUrl: (String) -> Unit,
    onUpdateApiPrefix: (String) -> Unit,
    onSaveServer: () -> Unit,
    onCheckConnection: () -> Unit,
    onUpdateCurrentPassword: (String) -> Unit,
    onUpdateNewPassword: (String) -> Unit,
    onUpdateConfirmPassword: (String) -> Unit,
    onChangePassword: () -> Unit,
    onUpdateFeedbackCategory: (String) -> Unit,
    onUpdateFeedbackTitle: (String) -> Unit,
    onUpdateFeedbackDescription: (String) -> Unit,
    onSubmitFeedback: () -> Unit,
    onLogout: () -> Unit,
    onNavigateToAdmin: () -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyColumn(
        modifier = modifier
            .fillMaxSize()
            .padding(horizontal = TS.Spacing.md),
        verticalArrangement = Arrangement.spacedBy(TS.Spacing.md),
    ) {
        item { Spacer(modifier = Modifier.height(TS.Spacing.sm)) }

        // Section 1: Server configuration
        item {
            ServerSection(
                baseUrl = state.baseUrl,
                apiPrefix = state.apiPrefix,
                connectionStatus = state.connectionStatus,
                saving = state.serverSaving,
                onUpdateBaseUrl = onUpdateBaseUrl,
                onUpdateApiPrefix = onUpdateApiPrefix,
                onSave = onSaveServer,
                onCheckConnection = onCheckConnection,
            )
        }

        // Section 2: Account
        item {
            AccountSection(
                userName = state.userName,
                userEmail = state.userEmail,
                userRole = state.userRole,
                currentPassword = state.currentPassword,
                newPassword = state.newPassword,
                confirmPassword = state.confirmPassword,
                passwordChanging = state.passwordChanging,
                passwordError = state.passwordError,
                passwordSuccess = state.passwordSuccess,
                onUpdateCurrentPassword = onUpdateCurrentPassword,
                onUpdateNewPassword = onUpdateNewPassword,
                onUpdateConfirmPassword = onUpdateConfirmPassword,
                onChangePassword = onChangePassword,
                onLogout = onLogout,
            )
        }

        // Section 3: Feedback
        item {
            FeedbackSection(
                category = state.feedbackCategory,
                title = state.feedbackTitle,
                description = state.feedbackDescription,
                submitting = state.feedbackSubmitting,
                onUpdateCategory = onUpdateFeedbackCategory,
                onUpdateTitle = onUpdateFeedbackTitle,
                onUpdateDescription = onUpdateFeedbackDescription,
                onSubmit = onSubmitFeedback,
            )
        }

        // Section 4: About
        item {
            AboutSection()
        }

        // Section 5: Admin link
        if (state.isAdmin) {
            item {
                AdminSection(onNavigateToAdmin = onNavigateToAdmin)
            }
        }

        item { Spacer(modifier = Modifier.height(TS.Spacing.lg)) }
    }
}

// -- Server Section --

@Composable
private fun ServerSection(
    baseUrl: String,
    apiPrefix: String,
    connectionStatus: SettingsViewModel.ConnectionStatus,
    saving: Boolean,
    onUpdateBaseUrl: (String) -> Unit,
    onUpdateApiPrefix: (String) -> Unit,
    onSave: () -> Unit,
    onCheckConnection: () -> Unit,
) {
    TSCard(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(TS.Spacing.md)) {
            SectionTitle(stringResource(R.string.settings_server_title))

            Spacer(modifier = Modifier.height(TS.Spacing.sm))

            TSTextField(
                value = baseUrl,
                onValueChange = onUpdateBaseUrl,
                label = stringResource(R.string.settings_server_url_label),
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Uri,
                    imeAction = ImeAction.Next,
                ),
                modifier = Modifier.fillMaxWidth(),
            )

            Spacer(modifier = Modifier.height(TS.Spacing.sm))

            TSTextField(
                value = apiPrefix,
                onValueChange = onUpdateApiPrefix,
                label = stringResource(R.string.settings_api_prefix_label),
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                modifier = Modifier.fillMaxWidth(),
            )

            Spacer(modifier = Modifier.height(TS.Spacing.sm))

            // Connection status
            ConnectionStatusRow(status = connectionStatus, onCheck = onCheckConnection)

            Spacer(modifier = Modifier.height(TS.Spacing.md))

            TSPrimaryButton(
                text = if (saving) stringResource(R.string.settings_saving) else stringResource(R.string.settings_save),
                onClick = onSave,
                enabled = !saving,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

@Composable
private fun ConnectionStatusRow(
    status: SettingsViewModel.ConnectionStatus,
    onCheck: () -> Unit,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(TS.Spacing.sm),
    ) {
        when (status) {
            SettingsViewModel.ConnectionStatus.Unknown -> {
                Text(
                    text = stringResource(R.string.settings_connection_unknown),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            SettingsViewModel.ConnectionStatus.Checking -> {
                CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                Text(
                    text = stringResource(R.string.settings_connection_checking),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            SettingsViewModel.ConnectionStatus.Connected -> {
                Icon(
                    imageVector = Icons.Filled.CheckCircle,
                    contentDescription = stringResource(R.string.settings_connection_connected_cd),
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(16.dp),
                )
                Text(
                    text = stringResource(R.string.settings_connection_connected),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
            SettingsViewModel.ConnectionStatus.Error -> {
                Icon(
                    imageVector = Icons.Filled.Warning,
                    contentDescription = stringResource(R.string.settings_connection_error_cd),
                    tint = MaterialTheme.colorScheme.error,
                    modifier = Modifier.size(16.dp),
                )
                Text(
                    text = stringResource(R.string.settings_connection_error),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                )
            }
        }

        Spacer(modifier = Modifier.weight(1f))

        Text(
            text = stringResource(R.string.settings_connection_test),
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.primary,
            modifier = Modifier.clickable(onClick = onCheck),
        )
    }
}

// -- Account Section --

@Composable
private fun AccountSection(
    userName: String,
    userEmail: String,
    userRole: String,
    currentPassword: String,
    newPassword: String,
    confirmPassword: String,
    passwordChanging: Boolean,
    passwordError: String?,
    passwordSuccess: Boolean,
    onUpdateCurrentPassword: (String) -> Unit,
    onUpdateNewPassword: (String) -> Unit,
    onUpdateConfirmPassword: (String) -> Unit,
    onChangePassword: () -> Unit,
    onLogout: () -> Unit,
) {
    TSCard(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(TS.Spacing.md)) {
            SectionTitle(stringResource(R.string.settings_account_title))

            Spacer(modifier = Modifier.height(TS.Spacing.sm))

            // User info
            if (userName.isNotBlank()) {
                ReadOnlyField(label = stringResource(R.string.settings_account_name), value = userName)
            }
            if (userEmail.isNotBlank()) {
                ReadOnlyField(label = stringResource(R.string.settings_account_email), value = userEmail)
            }

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(TS.Spacing.sm),
            ) {
                Text(
                    text = stringResource(R.string.settings_account_role),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                RoleBadge(role = userRole)
            }

            Spacer(modifier = Modifier.height(TS.Spacing.lg))

            // Password change
            Text(
                text = stringResource(R.string.settings_password_change_title),
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )

            Spacer(modifier = Modifier.height(TS.Spacing.sm))

            TSTextField(
                value = currentPassword,
                onValueChange = onUpdateCurrentPassword,
                label = stringResource(R.string.settings_password_current),
                singleLine = true,
                visualTransformation = PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Password,
                    imeAction = ImeAction.Next,
                ),
                modifier = Modifier.fillMaxWidth(),
            )

            Spacer(modifier = Modifier.height(TS.Spacing.sm))

            TSTextField(
                value = newPassword,
                onValueChange = onUpdateNewPassword,
                label = stringResource(R.string.settings_password_new),
                singleLine = true,
                visualTransformation = PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Password,
                    imeAction = ImeAction.Next,
                ),
                modifier = Modifier.fillMaxWidth(),
            )

            Spacer(modifier = Modifier.height(TS.Spacing.sm))

            TSTextField(
                value = confirmPassword,
                onValueChange = onUpdateConfirmPassword,
                label = stringResource(R.string.settings_password_confirm),
                singleLine = true,
                visualTransformation = PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Password,
                    imeAction = ImeAction.Done,
                ),
                modifier = Modifier.fillMaxWidth(),
            )

            if (passwordError != null) {
                Text(
                    text = passwordError,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(top = TS.Spacing.xs),
                )
            }

            AnimatedVisibility(visible = passwordSuccess) {
                Text(
                    text = stringResource(R.string.settings_password_changed),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.padding(vertical = TS.Spacing.xs),
                )
            }

            Spacer(modifier = Modifier.height(TS.Spacing.sm))

            TSPrimaryButton(
                text = if (passwordChanging) stringResource(R.string.settings_password_changing) else stringResource(R.string.settings_password_change_button),
                onClick = onChangePassword,
                enabled = !passwordChanging,
                modifier = Modifier.fillMaxWidth(),
            )

            Spacer(modifier = Modifier.height(TS.Spacing.lg))

            TSSecondaryButton(
                text = stringResource(R.string.settings_logout),
                onClick = onLogout,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

@Composable
private fun ReadOnlyField(label: String, value: String) {
    Column(modifier = Modifier.padding(bottom = TS.Spacing.sm)) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyLarge,
        )
    }
}

@Composable
private fun RoleBadge(role: String) {
    val displayText = when (role) {
        "admin" -> stringResource(R.string.settings_role_admin)
        else -> stringResource(R.string.settings_role_user)
    }
    val color = when (role) {
        "admin" -> MaterialTheme.colorScheme.primary
        else -> MaterialTheme.colorScheme.secondary
    }

    Text(
        text = displayText,
        style = MaterialTheme.typography.labelSmall,
        color = MaterialTheme.colorScheme.onPrimary,
        modifier = Modifier
            .clip(RoundedCornerShape(TS.Radius.xs))
            .background(color)
            .padding(horizontal = TS.Spacing.sm, vertical = TS.Spacing.xs),
    )
}

// -- Feedback Section --

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FeedbackSection(
    category: String,
    title: String,
    description: String,
    submitting: Boolean,
    onUpdateCategory: (String) -> Unit,
    onUpdateTitle: (String) -> Unit,
    onUpdateDescription: (String) -> Unit,
    onSubmit: () -> Unit,
) {
    val categories = listOf("Bug", "Feature", "Overig")
    var expanded by remember { mutableStateOf(false) }

    TSCard(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(TS.Spacing.md)) {
            SectionTitle(stringResource(R.string.settings_feedback_title))

            Spacer(modifier = Modifier.height(TS.Spacing.sm))

            ExposedDropdownMenuBox(
                expanded = expanded,
                onExpandedChange = { expanded = it },
            ) {
                OutlinedTextField(
                    value = category,
                    onValueChange = {},
                    readOnly = true,
                    label = { Text(stringResource(R.string.settings_feedback_category)) },
                    trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
                    modifier = Modifier
                        .fillMaxWidth()
                        .menuAnchor(MenuAnchorType.PrimaryNotEditable),
                )
                ExposedDropdownMenu(
                    expanded = expanded,
                    onDismissRequest = { expanded = false },
                ) {
                    categories.forEach { option ->
                        DropdownMenuItem(
                            text = { Text(option) },
                            onClick = {
                                onUpdateCategory(option)
                                expanded = false
                            },
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(TS.Spacing.sm))

            TSTextField(
                value = title,
                onValueChange = onUpdateTitle,
                label = stringResource(R.string.settings_feedback_item_title),
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                modifier = Modifier.fillMaxWidth(),
            )

            Spacer(modifier = Modifier.height(TS.Spacing.sm))

            TSTextField(
                value = description,
                onValueChange = onUpdateDescription,
                label = stringResource(R.string.settings_feedback_description),
                singleLine = false,
                modifier = Modifier.fillMaxWidth(),
            )

            Spacer(modifier = Modifier.height(TS.Spacing.md))

            TSPrimaryButton(
                text = if (submitting) stringResource(R.string.settings_feedback_submitting) else stringResource(R.string.settings_feedback_submit),
                onClick = onSubmit,
                enabled = !submitting && title.isNotBlank() && description.isNotBlank(),
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

// -- About Section --

@Composable
private fun AboutSection() {
    TSCard(modifier = Modifier.fillMaxWidth()) {
        Column(
            modifier = Modifier.padding(TS.Spacing.md),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            SectionTitle(stringResource(R.string.settings_about_title))

            Spacer(modifier = Modifier.height(TS.Spacing.sm))

            Text(
                text = stringResource(R.string.settings_about_app_name),
                style = MaterialTheme.typography.bodyLarge,
            )

            Spacer(modifier = Modifier.height(TS.Spacing.xs))

            Text(
                text = stringResource(R.string.settings_about_version, BuildConfig.VERSION_NAME),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Spacer(modifier = Modifier.height(TS.Spacing.md))

            YingaFooter()
        }
    }
}

// -- Admin Section --

@Composable
private fun AdminSection(onNavigateToAdmin: () -> Unit) {
    TSCard(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onNavigateToAdmin),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(TS.Spacing.md),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column {
                Text(
                    text = stringResource(R.string.settings_admin_title),
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    text = stringResource(R.string.settings_admin_subtitle),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Icon(
                imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = stringResource(R.string.settings_admin_navigate),
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

// -- Shared --

@Composable
private fun SectionTitle(title: String) {
    Text(
        text = title,
        style = MaterialTheme.typography.titleMedium,
        fontWeight = FontWeight.SemiBold,
    )
}
