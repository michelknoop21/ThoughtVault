package nl.prezent.transcriptstudio

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.fragment.app.FragmentActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Assignment
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.outlined.Assignment
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Mic
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavHostController
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import dagger.hilt.android.AndroidEntryPoint
import nl.prezent.transcriptstudio.data.remote.AuthEventBus
import nl.prezent.transcriptstudio.data.repository.AuthRepository
import nl.prezent.transcriptstudio.ui.components.YingaBar
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
    val selectedIcon: ImageVector,
    val unselectedIcon: ImageVector,
    val label: String,
)

private val bottomNavItems = listOf(
    BottomNavItem(route = Home, selectedIcon = Icons.Filled.Home, unselectedIcon = Icons.Outlined.Home, label = "Home"),
    BottomNavItem(route = Recording, selectedIcon = Icons.Filled.Mic, unselectedIcon = Icons.Outlined.Mic, label = "Opnemen"),
    BottomNavItem(route = Tasks, selectedIcon = Icons.Filled.Assignment, unselectedIcon = Icons.Outlined.Assignment, label = "Taken"),
    BottomNavItem(route = Transcripts, selectedIcon = Icons.Filled.Description, unselectedIcon = Icons.Outlined.Description, label = "Notulen"),
    BottomNavItem(route = Settings, selectedIcon = Icons.Filled.Settings, unselectedIcon = Icons.Outlined.Settings, label = "Instellingen"),
)

@AndroidEntryPoint
class MainActivity : FragmentActivity() {

    @Inject lateinit var authRepository: AuthRepository
    @Inject lateinit var authEventBus: AuthEventBus

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

                // Observe 401 session-expired events and navigate to login
                LaunchedEffect(Unit) {
                    authEventBus.events.collect { event ->
                        when (event) {
                            AuthEventBus.Event.SessionExpired -> {
                                isAuthenticated = false
                                navController.navigate(Login) {
                                    popUpTo(navController.graph.id) { inclusive = true }
                                }
                            }
                        }
                    }
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
    val currentRoute = currentDestination?.route
    val showBottomBar = currentRoute != null
            && !currentRoute.contains("Login")
            && !currentRoute.contains("TranscriptDetail")
            && !currentRoute.contains("Admin")

    val navItemColors = NavigationBarItemDefaults.colors(
        selectedIconColor = BrandPrimary,
        selectedTextColor = BrandPrimary,
        indicatorColor = BrandPrimary.copy(alpha = 0.10f),
        unselectedIconColor = MaterialTheme.colorScheme.onSurfaceVariant,
        unselectedTextColor = MaterialTheme.colorScheme.onSurfaceVariant,
    )

    Scaffold(
        bottomBar = {
            if (showBottomBar) {
                Column {
                    // Yinga brand bar as top accent on the navigation
                    YingaBar(height = 3.dp)

                    NavigationBar(
                        containerColor = MaterialTheme.colorScheme.surface,
                        tonalElevation = 0.dp,
                    ) {
                        bottomNavItems.forEach { item ->
                            val routeClass = item.route::class.qualifiedName.orEmpty()
                            val selected = currentRoute?.contains(routeClass) == true
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
                                icon = {
                                    Icon(
                                        imageVector = if (selected) item.selectedIcon else item.unselectedIcon,
                                        contentDescription = item.label,
                                    )
                                },
                                label = {
                                    Text(
                                        text = item.label,
                                        style = MaterialTheme.typography.labelSmall,
                                    )
                                },
                                colors = navItemColors,
                            )
                        }
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
