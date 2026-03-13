package nl.prezent.transcriptstudio.ui.theme

import androidx.compose.ui.unit.dp

/**
 * TranscriptStudio design tokens.
 * Mirrors the TS namespace from macos/Extensions/Theme.swift.
 */
object TS {

    /** 8dp base grid spacing scale. */
    object Spacing {
        /** 4dp — micro gaps, icon padding */
        val xs = 4.dp
        /** 8dp — base unit, default inner padding */
        val sm = 8.dp
        /** 16dp — standard section padding */
        val md = 16.dp
        /** 24dp — large section gaps */
        val lg = 24.dp
        /** 32dp — page-level vertical rhythm */
        val xl = 32.dp
        /** 48dp — hero-section spacing */
        val xxl = 48.dp
    }

    /** Corner radius scale. */
    object Radius {
        /** 6dp — small tags, badges */
        val xs = 6.dp
        /** 12dp — cards, input fields */
        val sm = 12.dp
        /** 16dp — modals, sheets */
        val md = 16.dp
        /** 20dp — large cards, panels */
        val lg = 20.dp
        /** 25dp — pill shapes, fully rounded elements */
        val xl = 25.dp
    }
}
