use super::*;
use std::time::{Duration, Instant};

type Writer = WavWriter<std::io::BufWriter<std::fs::File>>;

// The file and timeline belong to the recording, never to a replaceable stream.
struct Sink {
    writer: Option<Writer>,
    written: u64,
}

impl Sink {
    fn write(&mut self, samples: &[i16], position: u64) -> Result<(), hound::Error> {
        if let Some(writer) = self.writer.as_mut() {
            write_timed_chunk(writer, samples, position, &mut self.written)?;
        }
        Ok(())
    }
}

#[derive(Default)]
struct Recovery {
    attempts: u8,
    pending: bool,
    exhausted: bool,
}

impl Recovery {
    fn attempt(&mut self) -> bool {
        self.pending = true;
        if self.attempts >= 10 {
            self.exhausted = true;
            return false;
        }
        self.attempts += 1;
        true
    }

    fn received_audio(&mut self) {
        self.attempts = 0;
        self.pending = false;
    }
}

pub(super) struct LoopbackCapture {
    stream: Option<cpal::Stream>,
    device: cpal::Device,
    config: cpal::SupportedStreamConfig,
    sink: Arc<Mutex<Sink>>,
    failed: Arc<AtomicBool>,
    callbacks: Arc<AtomicU64>,
    paused: Arc<AtomicBool>,
    clock: Arc<Mutex<CaptureClock>>,
    events: mpsc::UnboundedSender<RecordingEvent>,
    terminal: Arc<TerminalDiagnostic>,
    recovery: Recovery,
    last_health: Instant,
}

pub(super) fn log_devices(host: &cpal::Host, stage: &str) {
    let default = host.default_output_device();
    elog!("[Audio] Output devices ({stage}), default={:?}", default.as_ref().and_then(|d| d.name().ok()));
    match host.output_devices() {
        Ok(devices) => for device in devices {
            match device.default_output_config() {
                Ok(config) => elog!("[Audio] Output {:?}: {} Hz, {} channels, {:?}", device.name(), config.sample_rate().0, config.channels(), config.sample_format()),
                Err(error) => elog!("[Audio] Output {:?}: config unavailable: {error}", device.name()),
            }
        },
        Err(error) => elog!("[Audio] Output enumeration failed: {error}"),
    }
}

fn same_device(a: &cpal::Device, b: &cpal::Device) -> bool {
    #[cfg(target_os = "windows")]
    {
        // cpal's WASAPI equality compares endpoint IDs, including equal display names.
        match (a.as_inner(), b.as_inner()) {
            (cpal::platform::DeviceInner::Wasapi(a), cpal::platform::DeviceInner::Wasapi(b)) => a == b,
            _ => false,
        }
    }
    #[cfg(not(target_os = "windows"))]
    { a.name().ok().zip(b.name().ok()).is_some_and(|(a, b)| a == b) }
}

fn same_format(a: &cpal::SupportedStreamConfig, b: &cpal::SupportedStreamConfig) -> bool {
    a.sample_rate() == b.sample_rate() && a.channels() == b.channels() && a.sample_format() == b.sample_format()
}

impl LoopbackCapture {
    pub(super) fn start(
        host: &cpal::Host, path: &str, paused: Arc<AtomicBool>,
        clock: Arc<Mutex<CaptureClock>>, events: mpsc::UnboundedSender<RecordingEvent>,
        terminal: Arc<TerminalDiagnostic>,
    ) -> Result<Self, String> {
        let device = host.default_output_device().ok_or("Geen standaard uitvoerapparaat voor loopback")?;
        let config = device.default_output_config().map_err(|e| format!("Kan loopbackconfiguratie niet lezen: {e}"))?;
        let writer = WavWriter::create(path, WavSpec {
            channels: CHANNELS, sample_rate: TARGET_SAMPLE_RATE,
            bits_per_sample: BITS_PER_SAMPLE, sample_format: HoundSampleFormat::Int,
        }).map_err(|e| format!("Kan loopback WAV niet aanmaken: {e}"))?;
        let mut capture = Self {
            stream: None, device, config,
            sink: Arc::new(Mutex::new(Sink { writer: Some(writer), written: 0 })),
            failed: Arc::new(AtomicBool::new(false)), callbacks: Arc::new(AtomicU64::new(0)),
            paused, clock, events, terminal, recovery: Recovery::default(), last_health: Instant::now(),
        };
        if let Err(error) = capture.open() {
            drop(capture);
            let _ = std::fs::remove_file(path);
            return Err(error);
        }
        Ok(capture)
    }

    fn open(&mut self) -> Result<(), String> {
        self.failed.store(false, Ordering::Relaxed);
        self.callbacks.store(0, Ordering::Relaxed);
        elog!("[Audio] Loopback open: {:?}, {} Hz, {} channels, {:?}, written={}",
            self.device.name(), self.config.sample_rate().0, self.config.channels(),
            self.config.sample_format(), self.sink.lock().unwrap().written);
        let stream = match self.config.sample_format() {
            cpal::SampleFormat::I16 => self.build::<i16>(),
            cpal::SampleFormat::F32 => self.build::<f32>(),
            _ => Err("Niet-ondersteund loopback sampleformaat".into()),
        }?;
        stream.play().map_err(|e| format!("Kan loopbackstream niet starten: {e}"))?;
        self.stream = Some(stream);
        Ok(())
    }

    pub(super) fn poll(&mut self, host: &cpal::Host) {
        if self.recovery.exhausted { return; }
        if self.last_health.elapsed() >= Duration::from_secs(5) {
            self.last_health = Instant::now();
            elog!("[Audio] Loopback health: callbacks={}, failed={}, paused={}",
                self.callbacks.load(Ordering::Relaxed), self.failed.load(Ordering::Relaxed), self.paused.load(Ordering::Relaxed));
        }
        let next = host.default_output_device().ok_or_else(|| "Geen standaard uitvoerapparaat".to_string())
            .and_then(|device| device.default_output_config().map(|config| (device, config)).map_err(|e| e.to_string()));
        let changed = next.as_ref().map(|(device, config)| !same_device(&self.device, device) || !same_format(&self.config, config)).unwrap_or(true);
        let broken = self.failed.load(Ordering::Relaxed) || self.stream.is_none();
        if !changed && !broken {
            if self.recovery.pending && self.callbacks.load(Ordering::Relaxed) > 0 {
                self.recovery.received_audio();
                let _ = self.events.send(RecordingEvent::Warning("Systeemgeluid is opnieuw verbonden. Tijdens de onderbreking kan geluid ontbreken.".into()));
            }
            return;
        }
        self.stop_stream();
        if !self.recovery.pending {
            let _ = self.events.send(RecordingEvent::Warning("Systeemgeluid is onderbroken. Je microfoon blijft opnemen; opnieuw verbinden wordt geprobeerd.".into()));
        }
        if !self.recovery.attempt() {
            let _ = self.events.send(RecordingEvent::Warning("Systeemgeluid kon niet worden hersteld. Alleen je microfoon neemt verder op; je kunt de opname gewoon bewaren en verwerken.".into()));
            return;
        }
        elog!("[Audio] Loopback reconnect attempt {}, changed={changed}, failed={broken}", self.recovery.attempts);
        let result = next.and_then(|(device, config)| {
            self.device = device;
            self.config = config;
            self.open()
        });
        if let Err(error) = result { elog!("[Audio] Loopback reconnect failed: {error}"); }
    }

    pub(super) fn stop_stream(&mut self) { drop(self.stream.take()); }

    pub(super) fn finalize(&mut self) -> Result<(), String> {
        self.stop_stream();
        if let Some(writer) = self.sink.lock().map_err(|e| e.to_string())?.writer.take() {
            writer.finalize().map_err(|e| format!("Systeemaudio opslaan mislukt: {e}"))?;
        }
        Ok(())
    }

    fn build<T>(&self) -> Result<cpal::Stream, String>
    where T: cpal::SizedSample, f32: cpal::FromSample<T> {
        let sink = Arc::clone(&self.sink);
        let paused = Arc::clone(&self.paused);
        let clock = Arc::clone(&self.clock);
        let failed = Arc::clone(&self.failed);
        let callbacks = Arc::clone(&self.callbacks);
        let events = self.events.clone();
        let terminal = Arc::clone(&self.terminal);
        let rate = self.config.sample_rate().0;
        let channels = usize::from(self.config.channels());
        let mut resampler = StreamingResampler::new(rate, TARGET_SAMPLE_RATE);
        let mut meter = LevelMeter::new(rate);
        let mut last_log = Instant::now();
        let mut previous_capture: Option<cpal::StreamInstant> = None;
        let mut previous_frames = 0;
        let mut measured_frames = 0_u64;
        let mut measured_seconds = 0.0;
        let mut callback_count = 0_u64;
        let mut frames_total = 0_u64;
        let mut peak = 0.0_f32;
        self.device.build_input_stream(&self.config.config(), move |data: &[T], info| {
            let frames = data.len() / channels;
            if frames == 0 { return; }
            callbacks.fetch_add(1, Ordering::Relaxed);
            callback_count += 1;
            frames_total += frames as u64;
            let capture = info.timestamp().capture;
            if let Some(previous) = previous_capture {
                if let Some(delta) = capture.duration_since(&previous) {
                    measured_seconds += delta.as_secs_f64();
                    measured_frames += previous_frames;
                }
            }
            previous_capture = Some(capture);
            previous_frames = frames as u64;
            let mono: Vec<i16> = data.chunks_exact(channels).map(|frame| {
                let sample = frame.iter().map(|&s| s.to_sample::<f32>()).sum::<f32>() / channels as f32;
                peak = peak.max(sample.abs());
                if !paused.load(Ordering::Relaxed) {
                    if let Some((level, bands)) = meter.push(sample) {
                        let _ = events.send(RecordingEvent::SystemAudioLevel(level));
                        let _ = events.send(RecordingEvent::SystemAudioSpectrum(bands));
                    }
                }
                sample.to_sample::<i16>()
            }).collect();
            if last_log.elapsed() >= Duration::from_secs(5) {
                elog!("[Audio] Loopback callbacks={callback_count}, frames/callback={:.1}, configured={rate} Hz, timestamp_rate={:.1} Hz (includes gaps), peak={peak:.5}",
                    frames_total as f64 / callback_count as f64,
                    measured_frames as f64 / measured_seconds.max(f64::EPSILON));
                last_log = Instant::now();
                callback_count = 0; frames_total = 0; measured_frames = 0; measured_seconds = 0.0; peak = 0.0;
            }
            if paused.load(Ordering::Relaxed) { return; }
            let position = clock.lock().unwrap().position(info);
            let samples = resampler.process_i16(&mono);
            if let Err(error) = sink.lock().unwrap().write(&samples, position) {
                paused.store(true, Ordering::Relaxed);
                terminal.claim(RecordingDiagnosticCode::CaptureFailed);
                let _ = events.send(RecordingEvent::Error(format!("Systeemaudio opslaan mislukt: {error}")));
            }
        }, move |error| {
            elog!("[Audio] Loopback stream error: {error}");
            failed.store(true, Ordering::Relaxed);
        }, None).map_err(|e| format!("Loopbackstream openen mislukt: {e}"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reopening_at_a_new_rate_keeps_segments_and_gap_once() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("loopback.wav");
        let writer = WavWriter::create(&path, WavSpec {
            channels: 1, sample_rate: TARGET_SAMPLE_RATE, bits_per_sample: 16,
            sample_format: HoundSampleFormat::Int,
        }).unwrap();
        let mut sink = Sink { writer: Some(writer), written: 0 };
        let mut first_stream = StreamingResampler::new(48000, TARGET_SAMPLE_RATE);
        for chunk in 0..100_u64 {
            sink.write(&first_stream.process_i16(&[1000; 480]), chunk * 160).unwrap();
        }
        assert_eq!(sink.written, 16000);
        // A new stream owns a new resampler, but uses the same file and frame count.
        let mut second_stream = StreamingResampler::new(16000, TARGET_SAMPLE_RATE);
        for chunk in 0..100_u64 {
            sink.write(&second_stream.process_i16(&[2000; 160]), 24000 + chunk * 160).unwrap();
        }
        assert_eq!(sink.written, 40000);
        sink.write(&[9999; 160], 24000).unwrap(); // late packet must not add time
        assert_eq!(sink.written, 40000);
        sink.writer.take().unwrap().finalize().unwrap();
        let samples = hound::WavReader::open(path).unwrap().into_samples::<i16>().collect::<Result<Vec<_>, _>>().unwrap();
        assert_eq!(samples.len(), 40000);
        assert!(samples[..16000].iter().all(|&s| s == 1000));
        assert!(samples[16000..24000].iter().all(|&s| s == 0));
        assert!(samples[24000..].iter().all(|&s| s == 2000));
    }

    #[test]
    fn recovery_stops_after_ten_consecutive_failed_attempts() {
        let mut recovery = Recovery::default();
        for _ in 0..10 { assert!(recovery.attempt()); }
        assert!(!recovery.attempt());
        assert!(recovery.exhausted);
        assert_eq!(recovery.attempts, 10);
    }

    #[test]
    fn receiving_audio_resets_consecutive_failure_budget() {
        let mut recovery = Recovery::default();
        for _ in 0..9 { assert!(recovery.attempt()); }
        recovery.received_audio();
        assert!(!recovery.pending);
        for _ in 0..10 { assert!(recovery.attempt()); }
        assert!(!recovery.attempt());
    }
}
