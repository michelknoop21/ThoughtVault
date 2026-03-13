package nl.prezent.transcriptstudio

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Assignment
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavHostController
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import dagger.hilt.android.AndroidEntryPoint
import nl.prezent.transcriptstudio.data.repository.AuthRepository
import nl.prezent.transcriptstudio.ui.navigation.AppNavHost
import nl.prezent.transcriptstudio.ui.navigation.Home
import nl.prezent.transcriptstudio.ui.navigation.Login
import nl.prezent.transcriptstudio.ui.navigation.Recording
import nl.prezent.transcriptstudio.ui.navigation.Settings
import nl.prezent.transcriptstudio.ui.navigation.Tasks
import nl.prezent.transcriptstudio.ui.navigation.Transcripts
import nl.prezent.transcriptstudio.ui.theme.BrandPrimary
import nl.prezent.transcriptstudio.ui.theme.TranscriptStudioTheme
import javax.inject.Inject

private data class BottomNavItem<T : Any>(
    val route: T,
    val icon: ImageVector,
    val label: String,
)

private val bottomNavItems = listOf(
    BottomNavItem(route = Home, icon = Icons.Default.Home, label = "Home"),
    BottomNavItem(route = Recording, icon = Icons.Default.Mic, label = "Opnemen"),
    BottomNavItem(route = Tasks, icon = Icons.Default.Assignment, label = "Taken"),
    BottomNavItem(route = Transcripts, icon = Icons.Default.Description, label = "Notulen"),
    BottomNavItem(route = Settings, icon = Icons.Default.Settings, label = "Instellingen"),
)

@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    @Inject lateinit var authRepository: AuthRepository

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContent {
            TranscriptStudioTheme {
                val navController = rememberNavController()
                var isAuthenticated by remember { mutableStateOf(false) }
                var isInitializing by remember { mutableStateOf(true) }

                LaunchedEffect(Unit) {
                    isAuthenticated = try {
                        if (authRepository.hasStoredToken()) {
                            authRepository.validateToken()
                        } else {
                            false
                        }
                    } catch (_: Exception) {
                        false
                    }
                    isInitializing = false
                }

                if (isInitializing) {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(48.dp),
                            color = BrandPrimary,
                        )
                    }
                } else {
                    MainContent(
                        navController = navController,
                        isAuthenticated = isAuthenticated,
                    )
                }
            }
        }
    }
}

@Composable
private fun MainContent(
    navController: NavHostController,
    isAuthenticated: Boolean,
) {
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentDestination = navBackStackEntry?.destination
    val showBottomBar = currentDestination?.hasRoute<Login>() != true

    Scaffold(
        bottomBar = {
            if (showBottomBar) {
                NavigationBar {
                    bottomNavItems.forEach { item ->
                        val selected = when (item.route) {
                            Home -> currentDestination?.hasRoute<Home>() == true
                            Recording -> currentDestination?.hasRoute<Recording>() == true
                            Tasks -> currentDestination?.hasRoute<Tasks>() == true
                            Transcripts -> currentDestination?.hasRoute<Transcripts>() == true
                            Settings -> currentDestination?.hasRoute<Settings>() == true
                            else -> false
                        }
                        NavigationBarItem(
                            selected = selected,
                            onClick = {
                                navController.navigate(item.route) {
                                    popUpTo(navController.graph.findStartDestination().id) {
                                        saveState = true
                                    }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            },
                            icon = { Icon(item.icon, contentDescription = item.label) },
                            label = { Text(item.label) },
                        )
                    }
                }
            }
        },
    ) { innerPadding ->
        AppNavHost(
            navController = navController,
            isAuthenticated = isAuthenticated,
            modifier = Modifier.padding(innerPadding),
        )
    }
}
