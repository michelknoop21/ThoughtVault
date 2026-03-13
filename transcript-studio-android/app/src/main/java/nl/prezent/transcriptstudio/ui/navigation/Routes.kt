package nl.prezent.transcriptstudio.ui.navigation

import kotlinx.serialization.Serializable

@Serializable data object Home

@Serializable data object Recording

@Serializable data object Tasks

@Serializable data object Transcripts

@Serializable data class TranscriptDetail(val id: String)

@Serializable data object Settings

@Serializable data object Admin

@Serializable data object Login
