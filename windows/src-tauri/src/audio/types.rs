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
    /// Recording stopped, file path and duration
    Stopped { file_path: String, duration_seconds: f64 },
    /// Error occurred
    Error(String),
}
