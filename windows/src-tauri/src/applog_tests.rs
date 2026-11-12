use super::*;

#[test]
fn append_writes_level_category_and_scrubbed_message() {
    let d = tempfile::tempdir().unwrap();
    append(d.path(), "error", "Fout", r#"open "C:\Users\Jan\x.wav" mislukt"#).unwrap();
    let text = std::fs::read_to_string(d.path().join("thoughtvault.log")).unwrap();
    assert!(text.contains(" ERROR [Fout] open \"k-"));
    assert!(!text.contains("Jan"));
    assert!(text.ends_with("\" mislukt\n"));
}

#[test]
fn rotates_when_the_next_line_would_exceed_the_limit() {
    let d = tempfile::tempdir().unwrap();
    std::fs::write(d.path().join("thoughtvault.log"), vec![b'a'; (MAX_BYTES - 10) as usize])
        .unwrap();
    append(d.path(), "info", "Test", "volgende regel").unwrap();
    assert_eq!(
        std::fs::metadata(d.path().join("thoughtvault.1.log")).unwrap().len(),
        MAX_BYTES - 10
    );
    assert!(std::fs::read_to_string(d.path().join("thoughtvault.log"))
        .unwrap()
        .contains("volgende regel"));
}

#[test]
fn prune_removes_rotated_file_older_than_seven_days() {
    let d = tempfile::tempdir().unwrap();
    let old = d.path().join("thoughtvault.1.log");
    std::fs::write(&old, "x").unwrap();
    let now = std::time::SystemTime::now();
    std::fs::File::options()
        .write(true)
        .open(&old)
        .unwrap()
        .set_modified(now - std::time::Duration::from_secs(6 * 86_400))
        .unwrap();
    prune(d.path(), now);
    assert!(old.exists());
    std::fs::File::options()
        .write(true)
        .open(&old)
        .unwrap()
        .set_modified(now - std::time::Duration::from_secs(8 * 86_400))
        .unwrap();
    prune(d.path(), now);
    assert!(!old.exists());
}

#[test]
fn tail_spans_both_files_and_starts_on_a_line_boundary() {
    let d = tempfile::tempdir().unwrap();
    let lines =
        |r: std::ops::Range<u32>| r.map(|i| format!("line-{i:04}\n")).collect::<String>(); // 10 bytes each
    std::fs::write(d.path().join("thoughtvault.1.log"), lines(0..5)).unwrap();
    std::fs::write(d.path().join("thoughtvault.log"), lines(5..10)).unwrap();
    let t = tail(d.path(), 75).unwrap();
    assert_eq!(t, lines(3..10)); // 70 bytes, the partial line before is dropped
    assert!(tail(d.path(), 10_000_000).unwrap().len() as u64 <= TAIL_LIMIT);
}

#[test]
fn mask_token_is_stable_and_short() {
    let a = mask_token("Overleg Gemeente");
    assert_eq!(a, mask_token("Overleg Gemeente"));
    assert_ne!(a, mask_token("Overleg Provincie"));
    assert!(
        a.starts_with("k-") && a.len() == 8 && a[2..].chars().all(|c| c.is_ascii_hexdigit())
    );
}

#[test]
fn scrub_masks_emails_and_windows_paths_with_spaces() {
    let s = scrub(r"Bestand niet gevonden: C:\Users\Jan\Documents\Overleg Gemeente.wav");
    assert!(s.starts_with("Bestand niet gevonden: k-"));
    assert!(!s.contains("Jan") && !s.contains("Overleg"));
    let q = scrub(r#"open "C:\Users\Jan\a b.wav": os error 2"#);
    assert!(q.ends_with(r#"": os error 2"#) && !q.contains("Jan"));
    let unc = scrub(r"\\server\share\Klant X\notulen.txt kon niet worden gelezen");
    assert!(!unc.contains("Klant"));
    let m = scrub("mail jan.devries@example.nl faalde");
    assert_eq!(m, format!("mail {} faalde", mask_token("jan.devries@example.nl")));
    assert_eq!(scrub("Model niet geladen na 30 s"), "Model niet geladen na 30 s");
    assert_eq!(scrub("mail a@example.com."), format!("mail {}", mask_token("a@example.com.")));
    assert_eq!(
        scrub(r"open C:\Users\Jan\x.wav mislukt"),
        format!("open {}", mask_token(r"C:\Users\Jan\x.wav mislukt"))
    );
    for path in [r"C:\Users\Jan\meeting.wav", "C:/Users/Jan/meeting.wav"] {
        assert_eq!(
            scrub(&format!("open path_{path}")),
            format!("open path_{}", mask_token(path))
        );
    }
}

#[test]
fn rotation_replaces_an_existing_rotated_file() {
    let d = tempfile::tempdir().unwrap();
    fs::write(d.path().join(ROTATED), "old").unwrap();
    fs::write(d.path().join(CURRENT), vec![b'a'; MAX_BYTES as usize]).unwrap();
    append(d.path(), "info", "Test", "new").unwrap();
    assert_eq!(fs::metadata(d.path().join(ROTATED)).unwrap().len(), MAX_BYTES);
}

#[test]
fn tail_ignores_missing_files_but_propagates_other_errors() {
    let d = tempfile::tempdir().unwrap();
    assert_eq!(tail(d.path(), 100).unwrap(), "");
    fs::create_dir(d.path().join(CURRENT)).unwrap();
    assert!(tail(d.path(), 100).is_err());
}

#[test]
fn concurrent_appends_keep_every_line() {
    let d = tempfile::tempdir().unwrap();
    std::thread::scope(|scope| {
        for _ in 0..8 {
            scope.spawn(|| {
                for _ in 0..20 {
                    append(d.path(), "info", "Test", "concurrent").unwrap();
                }
            });
        }
    });
    assert_eq!(tail(d.path(), TAIL_LIMIT).unwrap().lines().count(), 160);
}

#[test]
fn tail_handles_line_boundaries_zero_limits_and_unicode() {
    let d = tempfile::tempdir().unwrap();
    fs::write(d.path().join(CURRENT), "eerste\nlaatst é\n").unwrap();
    assert_eq!(tail(d.path(), "laatst é\n".len() as u64).unwrap(), "laatst é\n");
    assert_eq!(tail(d.path(), 0).unwrap(), "");
    assert_eq!(tail(d.path(), 2).unwrap(), "");
}

#[test]
fn invalid_marker_still_reports_a_previous_crash() {
    let d = tempfile::tempdir().unwrap();
    fs::write(d.path().join(MARKER), [255]).unwrap();
    assert_eq!(session_begin_at(d.path()), PreviousSession { crashed: true, stage: None });
}

#[test]
fn session_marker_reports_crash_with_running_stage() {
    let d = tempfile::tempdir().unwrap();
    assert_eq!(session_begin_at(d.path()), PreviousSession { crashed: false, stage: None });
    session_stage_at(d.path(), Some("transcriberen")).unwrap();
    assert_eq!(
        session_begin_at(d.path()),
        PreviousSession { crashed: true, stage: Some("transcriberen".into()) }
    );
    session_end_at(d.path());
    assert_eq!(session_begin_at(d.path()), PreviousSession { crashed: false, stage: None });
    session_stage_at(d.path(), None).unwrap();
    assert_eq!(session_begin_at(d.path()), PreviousSession { crashed: true, stage: None });
}

#[test]
fn session_begin_once_reports_clean_on_later_calls() {
    let d = tempfile::tempdir().unwrap();
    std::fs::create_dir_all(d.path()).unwrap();
    std::fs::write(d.path().join("session.open"), "notule").unwrap();
    let started = std::sync::atomic::AtomicBool::new(false);
    assert_eq!(
        session_begin_once(d.path(), &started),
        PreviousSession { crashed: true, stage: Some("notule".into()) }
    );
    assert_eq!(
        session_begin_once(d.path(), &started),
        PreviousSession { crashed: false, stage: None }
    );
}

// FIFO barrier is test-only; runtime tail/exit do not wait for pending diagnostics.
fn flush_logs() {
    let (tx, rx) = std::sync::mpsc::channel();
    LOG_QUEUE.get().unwrap().send(LogEntry::Flush(tx)).unwrap();
    rx.recv().unwrap();
}

#[test]
fn log_scrub_command_uses_the_same_rules() {
    assert_eq!(log_scrub(r"C:\Users\Jan\a.wav".into()), scrub(r"C:\Users\Jan\a.wav"));
}

// One test owns global initialization; other tests use the directory-based helpers.
#[test]
fn global_commands_handle_startup_session_lifecycle_and_io_failures() {
    assert!(LOG_DIR.get().is_none());
    write("info", "Test", "voor init");
    assert_eq!(log_tail(100).unwrap(), "");
    session_stage(Some("before-init".into()));
    session_end();
    assert!(!session_begin().crashed);

    let d = tempfile::tempdir().unwrap();
    fs::write(d.path().join(MARKER), "transcriberen").unwrap();
    fs::write(d.path().join(ROTATED), "expired").unwrap();
    fs::File::options().write(true).open(d.path().join(ROTATED)).unwrap()
        .set_modified(SystemTime::now() - KEEP_ROTATED - Duration::from_secs(60)).unwrap();
    init(d.path().to_path_buf());
    assert!(!d.path().join(ROTATED).exists());
    assert_eq!(session_begin(), PreviousSession { crashed: true, stage: Some("transcriberen".into()) });
    session_stage(Some("notule".into()));
    assert!(!session_begin().crashed);
    assert_eq!(fs::read_to_string(d.path().join(MARKER)).unwrap(), "notule");
    session_stage(None);
    assert_eq!(fs::read_to_string(d.path().join(MARKER)).unwrap(), "");
    session_end();
    assert!(!d.path().join(MARKER).exists());

    log_write("error".into(), "Test\njan@example.nl".into(), r"open C:\Users\Jan\a.wav".into());
    let mut evaluated = 0;
    elog!("macro-value={}", { evaluated += 1; evaluated });
    assert_eq!(evaluated, 1);
    flush_logs();
    let text = log_tail(TAIL_LIMIT).unwrap();
    assert!(text.contains("[rust] macro-value=1"));
    assert!(text.contains(" ERROR [Test k-"));
    assert!(!text.contains("Jan") && !text.contains("jan@example.nl"));
    write("error\nforged", "[Test]", "invalid-level-marker");
    flush_logs();
    assert!(log_tail(TAIL_LIMIT).unwrap().contains(" INFO [ Test ] invalid-level-marker"));
    // Tests in other modules run in parallel and append through elog! once init() has run,
    // so the newest line of the shared file is not necessarily this test's line.
    let last_line_with = |marker: &str| {
        fs::read_to_string(d.path().join(CURRENT)).unwrap().lines().rev()
            .find(|l| l.contains(marker)).map(str::to_owned)
            .unwrap_or_else(|| panic!("no log line contains {marker}"))
    };
    // Both metadata and message are bounded only after complete secrets are scrubbed.
    let private_path = format!("C:\\Users\\{}\\meeting.wav", "Jan".repeat(MAX_RUNTIME_CHARS));
    write("info", "limit", &format!("{} {}", "🦀".repeat(MAX_RUNTIME_CHARS - 10), private_path));
    flush_logs();
    let line = last_line_with(" INFO [limit] ");
    assert!(line.contains("k-"));
    assert!(!line.contains("Jan") && !line.contains("C:"));
    assert!(line.len() <= MAX_RUNTIME_CHARS * 4 + 40);
    write("info", &"🦀".repeat(MAX_RUNTIME_CHARS * 2), &"x".repeat(MAX_BYTES as usize + 1));
    flush_logs();
    let line = last_line_with(" INFO [🦀");
    assert_eq!(line.matches('🦀').count(), MAX_RUNTIME_CHARS);
    assert!(!line.contains('x'));
    assert!(line.len() <= MAX_RUNTIME_CHARS * 4 + 40);
    assert!(fs::metadata(d.path().join(CURRENT)).unwrap().len() <= MAX_BYTES);

    let ignored = tempfile::tempdir().unwrap();
    init(ignored.path().to_path_buf());
    assert_eq!(LOG_DIR.get().unwrap(), d.path());

    // Hold disk I/O while a separate caller must finish even with a saturated queue.
    let guard = LOG_LOCK.lock().unwrap();
    let (done, completion) = std::sync::mpsc::channel();
    let caller = std::thread::spawn(move || {
        for _ in 0..QUEUE_CAPACITY + 2 { write("info", "Test", "blocked-writer"); }
        let full = matches!(LOG_QUEUE.get().unwrap().try_send(
            LogEntry::Line("info".into(), "Test".into(), "overflow".into())
        ), Err(std::sync::mpsc::TrySendError::Full(_)));
        write("info", "Test", "must-drop-without-waiting");
        let _ = done.send(full);
    });
    let completed = completion.recv_timeout(Duration::from_secs(5));
    drop(guard); // Release before joining/asserting so a blocking regression can unwind.
    caller.join().unwrap();
    assert!(completed.expect("write waited for log-file I/O or queue space"));
    flush_logs();
    assert!(!log_tail(TAIL_LIMIT).unwrap().contains("must-drop-without-waiting"));

    {
        // A parallel elog! append must not hold the file open while it is replaced.
        let _guard = LOG_LOCK.lock().unwrap();
        fs::remove_file(d.path().join(CURRENT)).unwrap();
        fs::create_dir(d.path().join(CURRENT)).unwrap();
    }
    write("info", "Test", "cannot write to a directory");
    flush_logs();
    assert!(log_tail(100).is_err());
}
