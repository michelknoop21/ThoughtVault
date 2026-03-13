package nl.prezent.transcriptstudio.ui.login

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Fingerprint
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.fragment.app.FragmentActivity
import androidx.hilt.navigation.compose.hiltViewModel
import nl.prezent.transcriptstudio.ui.components.TSCard
import nl.prezent.transcriptstudio.ui.components.TSPrimaryButton
import nl.prezent.transcriptstudio.ui.components.YingaBar
import nl.prezent.transcriptstudio.ui.components.YingaFooter
import nl.prezent.transcriptstudio.ui.theme.BrandPrimary
import nl.prezent.transcriptstudio.ui.theme.StatusError
import nl.prezent.transcriptstudio.ui.theme.TS

@Composable
fun LoginScreen(
    onLoginSuccess: () -> Unit,
    viewModel: LoginViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val activity = LocalContext.current as FragmentActivity

    // Check biometric availability when the screen appears
    LaunchedEffect(Unit) {
        viewModel.checkBiometric(activity)
    }

    // Collect navigation events
    LaunchedEffect(Unit) {
        viewModel.events.collect { event ->
            when (event) {
                is LoginViewModel.Event.LoginSuccess -> onLoginSuccess()
            }
        }
    }

    Column(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        YingaBar()

        Spacer(modifier = Modifier.height(TS.Spacing.xxl))

        Text(
            text = "TranscriptStudio",
            style = MaterialTheme.typography.headlineMedium,
            color = MaterialTheme.colorScheme.onBackground,
        )

        Spacer(modifier = Modifier.height(TS.Spacing.xl))

        if (state.requires2FA) {
            TwoFAForm(
                state = state,
                onCodeChange = viewModel::update2FACode,
                onVerify = viewModel::verify2FA,
                onCancel = viewModel::cancel2FA,
            )
        } else {
            LoginForm(
                state = state,
                onEmailChange = viewModel::updateEmail,
                onPasswordChange = viewModel::updatePassword,
                onLogin = viewModel::login,
                onBiometricLogin = { viewModel.biometricLogin(activity) },
            )
        }

        Spacer(modifier = Modifier.weight(1f))

        YingaFooter()
    }
}

@Composable
private fun LoginForm(
    state: LoginViewModel.UiState,
    onEmailChange: (String) -> Unit,
    onPasswordChange: (String) -> Unit,
    onLogin: () -> Unit,
    onBiometricLogin: () -> Unit,
) {
    var passwordVisible by remember { mutableStateOf(false) }

    TSCard(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = TS.Spacing.md),
    ) {
        Column(
            modifier = Modifier.padding(TS.Spacing.md),
        ) {
            OutlinedTextField(
                value = state.email,
                onValueChange = onEmailChange,
                label = { Text("E-mailadres") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Email,
                    imeAction = ImeAction.Next,
                ),
                modifier = Modifier.fillMaxWidth(),
                enabled = !state.isLoading,
            )

            Spacer(modifier = Modifier.height(TS.Spacing.sm))

            OutlinedTextField(
                value = state.password,
                onValueChange = onPasswordChange,
                label = { Text("Wachtwoord") },
                singleLine = true,
                visualTransformation = if (passwordVisible) {
                    VisualTransformation.None
                } else {
                    PasswordVisualTransformation()
                },
                trailingIcon = {
                    IconButton(onClick = { passwordVisible = !passwordVisible }) {
                        Icon(
                            imageVector = if (passwordVisible) {
                                Icons.Default.VisibilityOff
                            } else {
                                Icons.Default.Visibility
                            },
                            contentDescription = if (passwordVisible) {
                                "Wachtwoord verbergen"
                            } else {
                                "Wachtwoord tonen"
                            },
                        )
                    }
                },
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Password,
                    imeAction = ImeAction.Done,
                ),
                keyboardActions = KeyboardActions(
                    onDone = { onLogin() },
                ),
                modifier = Modifier.fillMaxWidth(),
                enabled = !state.isLoading,
            )

            if (state.error != null) {
                Spacer(modifier = Modifier.height(TS.Spacing.sm))
                Text(
                    text = state.error,
                    style = MaterialTheme.typography.bodySmall,
                    color = StatusError,
                )
            }

            Spacer(modifier = Modifier.height(TS.Spacing.md))

            TSPrimaryButton(
                text = if (state.isLoading) "" else "Inloggen",
                onClick = onLogin,
                enabled = !state.isLoading,
                modifier = Modifier.fillMaxWidth(),
            )

            if (state.isLoading) {
                Spacer(modifier = Modifier.height(TS.Spacing.sm))
                CircularProgressIndicator(
                    modifier = Modifier
                        .size(24.dp)
                        .align(Alignment.CenterHorizontally),
                    color = BrandPrimary,
                    strokeWidth = 2.dp,
                )
            }
        }
    }

    TextButton(
        onClick = { /* TODO: password reset flow */ },
        modifier = Modifier.padding(top = TS.Spacing.sm),
    ) {
        Text(
            text = "Wachtwoord vergeten?",
            color = BrandPrimary,
        )
    }

    if (state.canUseBiometric) {
        IconButton(
            onClick = onBiometricLogin,
            enabled = !state.isLoading,
            modifier = Modifier.padding(top = TS.Spacing.xs),
        ) {
            Icon(
                imageVector = Icons.Default.Fingerprint,
                contentDescription = "Inloggen met biometrie",
                tint = BrandPrimary,
                modifier = Modifier.size(48.dp),
            )
        }
    }
}

@Composable
private fun TwoFAForm(
    state: LoginViewModel.UiState,
    onCodeChange: (String) -> Unit,
    onVerify: () -> Unit,
    onCancel: () -> Unit,
) {
    TSCard(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = TS.Spacing.md),
    ) {
        Column(
            modifier = Modifier.padding(TS.Spacing.md),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                text = "Voer de verificatiecode in",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurface,
            )

            Spacer(modifier = Modifier.height(TS.Spacing.md))

            OutlinedTextField(
                value = state.twoFACode,
                onValueChange = { value ->
                    // Only allow digits, max 6
                    if (value.length <= 6 && value.all { it.isDigit() }) {
                        onCodeChange(value)
                    }
                },
                label = { Text("Verificatiecode") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Number,
                    imeAction = ImeAction.Done,
                ),
                keyboardActions = KeyboardActions(
                    onDone = { onVerify() },
                ),
                modifier = Modifier.fillMaxWidth(),
                enabled = !state.isLoading,
            )

            if (state.error != null) {
                Spacer(modifier = Modifier.height(TS.Spacing.sm))
                Text(
                    text = state.error,
                    style = MaterialTheme.typography.bodySmall,
                    color = StatusError,
                )
            }

            Spacer(modifier = Modifier.height(TS.Spacing.md))

            TSPrimaryButton(
                text = if (state.isLoading) "" else "Verifieer",
                onClick = onVerify,
                enabled = !state.isLoading,
                modifier = Modifier.fillMaxWidth(),
            )

            if (state.isLoading) {
                Spacer(modifier = Modifier.height(TS.Spacing.sm))
                CircularProgressIndicator(
                    modifier = Modifier
                        .size(24.dp)
                        .align(Alignment.CenterHorizontally),
                    color = BrandPrimary,
                    strokeWidth = 2.dp,
                )
            }

            Spacer(modifier = Modifier.height(TS.Spacing.sm))

            TextButton(onClick = onCancel) {
                Text(
                    text = "Annuleer",
                    color = BrandPrimary,
                )
            }
        }
    }
}
