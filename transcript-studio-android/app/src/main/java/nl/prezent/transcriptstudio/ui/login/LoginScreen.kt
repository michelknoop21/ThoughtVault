package nl.prezent.transcriptstudio.ui.login

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Fingerprint
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.fragment.app.FragmentActivity
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import nl.prezent.transcriptstudio.R
import nl.prezent.transcriptstudio.ui.components.AppLogo
import nl.prezent.transcriptstudio.ui.components.ErrorBanner
import nl.prezent.transcriptstudio.ui.components.TSCard
import nl.prezent.transcriptstudio.ui.components.TSPrimaryButton
import nl.prezent.transcriptstudio.ui.components.TSTextField
import nl.prezent.transcriptstudio.ui.components.YingaBar
import nl.prezent.transcriptstudio.ui.components.YingaFooter
import nl.prezent.transcriptstudio.ui.theme.BrandPrimary
import nl.prezent.transcriptstudio.ui.theme.BrandSecondary
import nl.prezent.transcriptstudio.ui.theme.TS

// Soft gradient matching macOS LoginView background
private val LoginGradient = Brush.linearGradient(
    colors = listOf(
        Color(0xFFF4F4FA),
        Color(0xFFEBEDF7),
    ),
)

@Composable
fun LoginScreen(
    onLoginSuccess: () -> Unit,
    viewModel: LoginViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val activity = LocalContext.current as FragmentActivity

    LaunchedEffect(Unit) {
        viewModel.checkBiometric(activity)
    }

    LaunchedEffect(Unit) {
        viewModel.events.collect { event ->
            when (event) {
                is LoginViewModel.Event.LoginSuccess -> onLoginSuccess()
            }
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(LoginGradient),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .imePadding()
                .verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            // Yinga brand bar at top (matches macOS)
            YingaBar()

            Spacer(modifier = Modifier.height(TS.Spacing.xl))

            // Branding: logo + title
            AppLogo(size = 64.dp, cornerRadius = 14.dp)

            Spacer(modifier = Modifier.height(TS.Spacing.md))

            Text(
                text = stringResource(R.string.login_app_title),
                style = MaterialTheme.typography.headlineLarge.copy(
                    fontWeight = FontWeight.Bold,
                ),
                color = BrandPrimary,
            )

            Spacer(modifier = Modifier.height(TS.Spacing.xl))

            // Form card — centered, max width on tablets
            AnimatedVisibility(
                visible = state.requires2FA,
                enter = fadeIn() + slideInVertically { it / 4 },
                exit = fadeOut() + slideOutVertically { -it / 4 },
            ) {
                TwoFAForm(
                    state = state,
                    onCodeChange = viewModel::update2FACode,
                    onVerify = viewModel::verify2FA,
                    onCancel = viewModel::cancel2FA,
                )
            }

            AnimatedVisibility(
                visible = !state.requires2FA,
                enter = fadeIn(),
                exit = fadeOut(),
            ) {
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

            Spacer(modifier = Modifier.height(TS.Spacing.md))
        }
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

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = TS.Spacing.lg)
            .widthIn(max = 420.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        TSCard(
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column(
                modifier = Modifier.padding(TS.Spacing.lg),
            ) {
                // Section header (matches macOS title3Bold)
                Text(
                    text = stringResource(R.string.login_title),
                    style = MaterialTheme.typography.titleLarge.copy(
                        fontWeight = FontWeight.Bold,
                    ),
                    color = MaterialTheme.colorScheme.onSurface,
                )

                Spacer(modifier = Modifier.height(TS.Spacing.xs))

                Text(
                    text = stringResource(R.string.login_subtitle),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )

                Spacer(modifier = Modifier.height(TS.Spacing.lg))

                // Email field with label above (matches macOS style)
                TSTextField(
                    value = state.email,
                    onValueChange = onEmailChange,
                    label = stringResource(R.string.login_email_label),
                    placeholder = "naam@bedrijf.nl",
                    enabled = !state.isLoading,
                    keyboardOptions = KeyboardOptions(
                        keyboardType = KeyboardType.Email,
                        imeAction = ImeAction.Next,
                    ),
                    modifier = Modifier.fillMaxWidth(),
                )

                Spacer(modifier = Modifier.height(TS.Spacing.md))

                // Password field with label above
                TSTextField(
                    value = state.password,
                    onValueChange = onPasswordChange,
                    label = stringResource(R.string.login_password_label),
                    placeholder = "",
                    enabled = !state.isLoading,
                    visualTransformation = if (passwordVisible) {
                        VisualTransformation.None
                    } else {
                        PasswordVisualTransformation()
                    },
                    keyboardOptions = KeyboardOptions(
                        keyboardType = KeyboardType.Password,
                        imeAction = ImeAction.Done,
                    ),
                    keyboardActions = KeyboardActions(
                        onDone = { onLogin() },
                    ),
                    trailingIcon = {
                        IconButton(
                            onClick = { passwordVisible = !passwordVisible },
                            modifier = Modifier.size(24.dp),
                        ) {
                            Icon(
                                imageVector = if (passwordVisible) {
                                    Icons.Default.VisibilityOff
                                } else {
                                    Icons.Default.Visibility
                                },
                                contentDescription = if (passwordVisible) {
                                    stringResource(R.string.login_password_hide)
                                } else {
                                    stringResource(R.string.login_password_show)
                                },
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.size(20.dp),
                            )
                        }
                    },
                    modifier = Modifier.fillMaxWidth(),
                )

                // Error banner
                AnimatedVisibility(visible = state.error != null) {
                    Column {
                        Spacer(modifier = Modifier.height(TS.Spacing.md))
                        ErrorBanner(message = state.error ?: "")
                    }
                }

                Spacer(modifier = Modifier.height(TS.Spacing.lg))

                // Primary action button with loading state inside
                TSPrimaryButton(
                    text = stringResource(R.string.login_button),
                    onClick = onLogin,
                    enabled = !state.isLoading,
                    isLoading = state.isLoading,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }

        // Forgot password link
        TextButton(
            onClick = { /* TODO: password reset flow */ },
            modifier = Modifier.padding(top = TS.Spacing.xs),
        ) {
            Text(
                text = stringResource(R.string.login_forgot_password),
                style = MaterialTheme.typography.bodySmall,
                color = BrandPrimary,
            )
        }

        // Biometric login button
        if (state.canUseBiometric) {
            Spacer(modifier = Modifier.height(TS.Spacing.sm))
            BiometricButton(
                onClick = onBiometricLogin,
                enabled = !state.isLoading,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

@Composable
private fun BiometricButton(
    onClick: () -> Unit,
    enabled: Boolean,
    modifier: Modifier = Modifier,
) {
    val shape = RoundedCornerShape(TS.Radius.sm)
    Row(
        modifier = modifier
            .clip(shape)
            .background(BrandSecondary.copy(alpha = 0.06f))
            .border(1.dp, BrandSecondary.copy(alpha = 0.25f), shape)
            .clickable(enabled = enabled, onClick = onClick)
            .padding(vertical = 10.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = Icons.Default.Fingerprint,
            contentDescription = null,
            tint = BrandSecondary,
            modifier = Modifier.size(18.dp),
        )
        Spacer(modifier = Modifier.width(TS.Spacing.sm))
        Text(
            text = stringResource(R.string.login_biometric),
            color = BrandSecondary,
            style = MaterialTheme.typography.bodyLarge.copy(
                fontWeight = FontWeight.Medium,
            ),
        )
    }
}

@Composable
private fun TwoFAForm(
    state: LoginViewModel.UiState,
    onCodeChange: (String) -> Unit,
    onVerify: () -> Unit,
    onCancel: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = TS.Spacing.lg)
            .widthIn(max = 420.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        TSCard(
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column(
                modifier = Modifier.padding(TS.Spacing.lg),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                // Shield icon (matches macOS lock.shield.fill)
                Icon(
                    imageVector = Icons.Default.Fingerprint,
                    contentDescription = null,
                    tint = BrandPrimary,
                    modifier = Modifier.size(40.dp),
                )

                Spacer(modifier = Modifier.height(TS.Spacing.sm))

                Text(
                    text = stringResource(R.string.login_2fa_title),
                    style = MaterialTheme.typography.titleLarge.copy(
                        fontWeight = FontWeight.Bold,
                    ),
                    color = MaterialTheme.colorScheme.onSurface,
                )

                Spacer(modifier = Modifier.height(TS.Spacing.xs))

                Text(
                    text = stringResource(R.string.login_2fa_subtitle),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                )

                Spacer(modifier = Modifier.height(TS.Spacing.lg))

                // Monospaced code input (matches macOS)
                TSTextField(
                    value = state.twoFACode,
                    onValueChange = { value ->
                        if (value.length <= 6 && value.all { it.isDigit() }) {
                            onCodeChange(value)
                            if (value.length == 6) onVerify()
                        }
                    },
                    label = stringResource(R.string.login_2fa_code_label),
                    enabled = !state.isLoading,
                    textStyle = TextStyle(
                        fontFamily = FontFamily.Monospace,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 20.sp,
                        textAlign = TextAlign.Center,
                        letterSpacing = 4.sp,
                    ),
                    keyboardOptions = KeyboardOptions(
                        keyboardType = KeyboardType.Number,
                        imeAction = ImeAction.Done,
                    ),
                    keyboardActions = KeyboardActions(
                        onDone = { onVerify() },
                    ),
                    modifier = Modifier.fillMaxWidth(),
                )

                // Error banner
                AnimatedVisibility(visible = state.error != null) {
                    Column {
                        Spacer(modifier = Modifier.height(TS.Spacing.md))
                        ErrorBanner(message = state.error ?: "")
                    }
                }

                Spacer(modifier = Modifier.height(TS.Spacing.lg))

                TSPrimaryButton(
                    text = stringResource(R.string.login_2fa_verify),
                    onClick = onVerify,
                    enabled = !state.isLoading,
                    isLoading = state.isLoading,
                    modifier = Modifier.fillMaxWidth(),
                )

                Spacer(modifier = Modifier.height(TS.Spacing.sm))

                TextButton(onClick = onCancel) {
                    Text(
                        text = stringResource(R.string.login_2fa_cancel),
                        style = MaterialTheme.typography.bodySmall,
                        color = BrandPrimary,
                    )
                }
            }
        }
    }
}
