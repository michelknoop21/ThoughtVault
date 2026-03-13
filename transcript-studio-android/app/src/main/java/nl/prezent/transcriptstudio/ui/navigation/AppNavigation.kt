package nl.prezent.transcriptstudio.ui.navigation

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.toRoute
import nl.prezent.transcriptstudio.ui.admin.AdminScreen
import nl.prezent.transcriptstudio.ui.home.HomeScreen
import nl.prezent.transcriptstudio.ui.login.LoginScreen
import nl.prezent.transcriptstudio.ui.recording.RecordingScreen
import nl.prezent.transcriptstudio.ui.settings.SettingsScreen
import nl.prezent.transcriptstudio.ui.tasks.TasksScreen
import nl.prezent.transcriptstudio.ui.transcripts.TranscriptDetailScreen
import nl.prezent.transcriptstudio.ui.transcripts.TranscriptsScreen

@Composable
fun AppNavHost(
    navController: NavHostController,
    isAuthenticated: Boolean,
    modifier: Modifier = Modifier,
) {
    NavHost(
        navController = navController,
        startDestination = if (isAuthenticated) Home else Login,
        modifier = modifier,
    ) {
        composable<Login> {
            LoginScreen(onLoginSuccess = {
                navController.navigate(Home) {
                    popUpTo<Login> { inclusive = true }
                }
            })
        }
        composable<Home> { HomeScreen() }
        composable<Recording> { RecordingScreen() }
        composable<Tasks> {
            TasksScreen(onNavigateToTranscript = { id ->
                navController.navigate(TranscriptDetail(id))
            })
        }
        composable<Transcripts> { TranscriptsScreen() }
        composable<TranscriptDetail> { backStackEntry ->
            val detail = backStackEntry.toRoute<TranscriptDetail>()
            TranscriptDetailScreen(transcriptId = detail.id)
        }
        composable<Settings> { SettingsScreen() }
        composable<Admin> { AdminScreen() }
    }
}
