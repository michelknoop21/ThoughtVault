use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AudioDevice {
    pub id: String,
    pub name: String,
    pub is_default: bool,
    pub is_input: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RecordingResult {
    pub file_path: String,
    pub duration_seconds: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum RecordingMode {
    Microphone,
    Combined,
}

impl std::fmt::Display for RecordingMode {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            RecordingMode::Microphone => write!(f, "microphone"),
            RecordingMode::Combined => write!(f, "combined"),
        }
    }
}

/// Messages sent to the recording thread
pub enum RecordingCommand {
    Pause,
    Resume,
    Stop,
}

/// Messages received back from the recording thread
#[derive(Debug)]
pub enum RecordingEvent {
    /// Processed audio envelope scalar 0.0–1.0 at ~30Hz
    AudioLevel(f32),
    SystemAudioLevel(f32),
    AudioSpectrum([f32; 7]),
    SystemAudioSpectrum([f32; 7]),
    /// Recording stopped, file path and duration
    Stopped { file_path: String, duration_seconds: f64 },
    /// Error occurred
    Error(String),
}

#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum RecordingDiagnosticCode { StartFailed, CaptureFailed, StopFailed, PauseFailed, ResumeFailed }

#[derive(Debug, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum RecordingErrorDiagnostic { Expected, NativeOwned }

#[derive(Debug, Serialize)]
pub struct RecordingCommandError {
    pub message: String,
    pub diagnostic: RecordingErrorDiagnostic,
}

impl RecordingCommandError {
    pub fn expected(message: impl Into<String>) -> Self {
        Self { message: message.into(), diagnostic: RecordingErrorDiagnostic::Expected }
    }
    pub fn native_owned(message: impl Into<String>) -> Self {
        Self { message: message.into(), diagnostic: RecordingErrorDiagnostic::NativeOwned }
    }
}

/// Publish the winning code atomically; callbacks never invoke Tauri dispatch.
#[derive(Default)]
pub struct TerminalDiagnostic {
    pending: std::sync::atomic::AtomicU8,
}
impl TerminalDiagnostic {
    pub fn claim(&self, code: RecordingDiagnosticCode) {
        let value = match code {
            RecordingDiagnosticCode::StartFailed => 1,
            RecordingDiagnosticCode::CaptureFailed => 2,
            RecordingDiagnosticCode::StopFailed => 3,
            RecordingDiagnosticCode::PauseFailed => 4,
            RecordingDiagnosticCode::ResumeFailed => 5,
        };
        let _ = self.pending.compare_exchange(0, value, std::sync::atomic::Ordering::AcqRel, std::sync::atomic::Ordering::Acquire);
    }

    /// Consume off the realtime thread once; 255 retains terminal ownership.
    pub fn take(&self) -> Option<RecordingDiagnosticCode> {
        let value = self.pending.fetch_update(std::sync::atomic::Ordering::AcqRel, std::sync::atomic::Ordering::Acquire,
            |value| if (1..=5).contains(&value) { Some(255) } else { None }).ok()?;
        match value {
            1 => Some(RecordingDiagnosticCode::StartFailed),
            2 => Some(RecordingDiagnosticCode::CaptureFailed),
            3 => Some(RecordingDiagnosticCode::StopFailed),
            4 => Some(RecordingDiagnosticCode::PauseFailed),
            5 => Some(RecordingDiagnosticCode::ResumeFailed),
            _ => None,
        }
    }
}

#[cfg(test)]
mod recording_command_error_tests {
    use super::*;
    #[test]
    fn native_classification_preserves_message_and_static_code() {
        assert_eq!(serde_json::to_value(RecordingCommandError::expected("Geen actieve opname")).unwrap(),
            serde_json::json!({"message": "Geen actieve opname", "diagnostic": "expected"}));
        assert_eq!(serde_json::to_value(RecordingCommandError::native_owned("original failure")).unwrap(),
            serde_json::json!({"message": "original failure", "diagnostic": "native-owned"}));
        assert_eq!(serde_json::to_value(RecordingDiagnosticCode::CaptureFailed).unwrap(), "capture_failed");
    }
}
