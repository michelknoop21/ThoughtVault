use futures_util::StreamExt;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

use tauri::{AppHandle, Emitter};
use tokio_util::io::ReaderStream;

#[derive(Debug, Serialize, Deserialize)]
pub struct HttpRequest {
    pub url: String,
    pub method: String,
    pub headers: Option<HashMap<String, String>>,
    pub body: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct HttpResponse {
    pub status: u16,
    pub body: String,
    pub headers: HashMap<String, String>,
}

/// Generic HTTP proxy — bypasses WebView CORS restrictions.
#[tauri::command]
pub async fn proxy_request(request: HttpRequest) -> Result<HttpResponse, String> {
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(30))
        .build()
        .map_err(|e| e.to_string())?;

    let mut req = match request.method.to_uppercase().as_str() {
        "GET"    => client.get(&request.url),
        "POST"   => client.post(&request.url),
        "PUT"    => client.put(&request.url),
        "PATCH"  => client.patch(&request.url),
        "DELETE" => client.delete(&request.url),
        "HEAD"   => client.head(&request.url),
        other    => return Err(format!("Niet ondersteunde HTTP-methode: {}", other)),
    };

    if let Some(headers) = request.headers {
        for (key, value) in &headers {
            req = req.header(key.as_str(), value.as_str());
        }
    }

    if let Some(body) = request.body {
        req = req.body(body);
    }

    let response = req.send().await.map_err(|e| e.to_string())?;
    let status = response.status().as_u16();

    let mut resp_headers = HashMap::new();
    for (k, v) in response.headers() {
        if let Ok(val) = v.to_str() {
            resp_headers.insert(k.to_string(), val.to_string());
        }
    }

    let body = response.text().await.map_err(|e| e.to_string())?;

    Ok(HttpResponse { status, body, headers: resp_headers })
}

/// Upload a file via multipart/form-data — bypasses WebView CORS/network restrictions.
/// This is more reliable than browser-native fetch because it goes through Rust/reqwest.
#[tauri::command]
pub async fn proxy_upload(
    file_path: String,
    upload_url: String,
    token: String,
    profile_id: String,
    mode: String,
    use_premium: Option<bool>,
) -> Result<HttpResponse, String> {
    do_proxy_upload(file_path, upload_url, token, profile_id, mode, use_premium.unwrap_or(false)).await
}

/// Core upload logic, separated from the Tauri command wrapper for testability.
///
/// The upload is hardened against a class of Windows-only failures (file mutation
/// by Defender / OneDrive / Search Indexer between read passes, system proxy
/// MITM, connection-pool reuse, HTTP/2 ALPN race, Nagle stalls). Strategy:
///
///   1. Copy the source file to %LOCALAPPDATA%\Temp (auto-deleted on drop).
///      The copy is a single sweep with a post-check that size is stable.
///   2. For files ≤ 200 MB: read the temp copy fully into memory and use
///      `Part::bytes(...)`. No streaming → no race window between Content-Length
///      and the bytes that actually hit the wire.
///   3. For larger files: stream from the temp copy. The temp copy itself has
///      already been integrity-checked, and Temp is outside OneDrive's KFM root.
///   4. Validate WAV magic before sending — surface corruption as a friendly
///      client-side error instead of an obscure server-side 422.
///   5. Reqwest client config: explicit User-Agent, tcp_nodelay, no proxy,
///      http1_only, fresh connection per upload (no_pool_idle).
///   6. Send a SHA-256 prefix as `X-Upload-Sha256` so backend logs can correlate
///      what the client sent against what the server received.
pub async fn do_proxy_upload(
    file_path: String,
    upload_url: String,
    token: String,
    profile_id: String,
    mode: String,
    use_premium: bool,
) -> Result<HttpResponse, String> {
    use std::time::Instant;
    let t_start = Instant::now();

    let path = std::path::Path::new(&file_path);
    if !path.exists() {
        return Err(format!("Bestand niet gevonden: {}", file_path));
    }

    let metadata_size = tokio::fs::metadata(&file_path)
        .await
        .map_err(|e| format!("Kan bestandsinfo niet lezen: {}", e))?
        .len();
    if metadata_size == 0 {
        return Err("Opnamebestand is leeg (0 bytes)".to_string());
    }

    const MAX_UPLOAD_SIZE: u64 = 500 * 1024 * 1024;
    if metadata_size > MAX_UPLOAD_SIZE {
        return Err(format!(
            "Het bestand is te groot ({:.0} MB). Maximaal 500 MB toegestaan. Maak kortere opnames.",
            metadata_size as f64 / 1_048_576.0
        ));
    }

    let original_filename = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("recording.wav")
        .to_string();

    // ─── Step 1: copy to a stable location outside any sync/scan path. ───
    // tempfile creates+opens the file; we discard the open handle (drop _f)
    // and keep the TempPath, which auto-deletes on drop at end of function.
    let temp = tempfile::Builder::new()
        .prefix("ts-upload-")
        .suffix(".wav")
        .tempfile_in(std::env::temp_dir())
        .map_err(|e| format!("Kan tijdelijk bestand niet aanmaken: {}", e))?;
    let (_f, temp_path) = temp.into_parts();
    drop(_f);

    let t_copy = Instant::now();
    tokio::fs::copy(&file_path, &temp_path)
        .await
        .map_err(|e| format!("Kan bestand niet kopiëren naar tijdelijke locatie: {}", e))?;
    let copy_size = tokio::fs::metadata(&*temp_path)
        .await
        .map_err(|e| format!("Kan kopie-info niet lezen: {}", e))?
        .len();
    if copy_size != metadata_size {
        return Err(format!(
            "Bestandsgrootte gewijzigd tijdens kopiëren ({} → {} bytes). Mogelijk wordt het bestand op dat moment door antivirus of cloud-sync aangeraakt. Probeer het opnieuw.",
            metadata_size, copy_size
        ));
    }
    let copy_elapsed = t_copy.elapsed();

    // ─── Step 2: in-memory upload for ≤ 200 MB (covers all of Bas's case). ──
    const IN_MEMORY_LIMIT: u64 = 200 * 1024 * 1024;
    let in_memory: Option<Vec<u8>> = if copy_size <= IN_MEMORY_LIMIT {
        let bytes = tokio::fs::read(&*temp_path)
            .await
            .map_err(|e| format!("Kan kopie niet inlezen: {}", e))?;
        if bytes.len() as u64 != copy_size {
            return Err(format!(
                "Inlezen leverde {} bytes maar kopie zegt {} bytes. Probeer het opnieuw.",
                bytes.len(),
                copy_size
            ));
        }
        Some(bytes)
    } else {
        None
    };

    // ─── Step 3: WAV sanity check on in-memory bytes. ───
    if let Some(bytes) = &in_memory {
        if original_filename.to_lowercase().ends_with(".wav")
            && (bytes.len() < 12 || &bytes[0..4] != b"RIFF" || &bytes[8..12] != b"WAVE")
        {
            return Err(
                "Het opnamebestand lijkt corrupt (geen geldige WAV-header). Maak een nieuwe opname en probeer opnieuw."
                    .to_string(),
            );
        }
    }

    // ─── Step 4: SHA-256 prefix for client↔server log correlation. ───
    let sha_prefix = if let Some(bytes) = &in_memory {
        use sha2::{Digest, Sha256};
        let h = Sha256::digest(bytes);
        let hex: String = h.iter().map(|b| format!("{:02x}", b)).collect();
        hex[..16].to_string()
    } else {
        "stream".to_string()
    };

    eprintln!(
        "[Upload] {} ({} bytes, sha256={}) → {}  copy_took={:?}  mode={}",
        original_filename,
        copy_size,
        sha_prefix,
        upload_url,
        copy_elapsed,
        if in_memory.is_some() { "memory" } else { "stream" }
    );

    // ─── Step 5: hardened reqwest client. ───
    let client = reqwest::Client::builder()
        .user_agent(format!(
            "TranscriptStudio-Windows/{}",
            env!("CARGO_PKG_VERSION")
        ))
        .tcp_nodelay(true)
        .pool_max_idle_per_host(0)
        .http1_only()
        .no_proxy()
        .timeout(std::time::Duration::from_secs(600))
        .build()
        .map_err(|e| e.to_string())?;

    // ─── Step 6: build multipart body. ───
    let file_part = if let Some(bytes) = in_memory {
        reqwest::multipart::Part::bytes(bytes)
            .file_name(original_filename.clone())
            .mime_str("audio/wav")
            .map_err(|e| e.to_string())?
    } else {
        // > 200 MB: stream from the (already integrity-checked) temp copy.
        let f = tokio::fs::File::open(&*temp_path)
            .await
            .map_err(|e| format!("Kan kopie niet openen voor upload: {}", e))?;
        let stream = ReaderStream::with_capacity(f, 64 * 1024);
        let body = reqwest::Body::wrap_stream(stream);
        reqwest::multipart::Part::stream_with_length(body, copy_size)
            .file_name(original_filename.clone())
            .mime_str("audio/wav")
            .map_err(|e| e.to_string())?
    };

    let form = reqwest::multipart::Form::new()
        .part("file", file_part)
        .text("profile_id", profile_id)
        .text("mode", mode)
        .text("use_premium", use_premium.to_string());

    // ─── Step 7: send. ───
    let t_send = Instant::now();
    let response = client
        .post(&upload_url)
        .header("X-User-Token", &token)
        .header("X-Upload-Sha256", &sha_prefix)
        .multipart(form)
        .send()
        .await
        .map_err(|e| {
            if e.is_timeout() {
                "Upload time-out: het bestand is mogelijk te groot of de verbinding te langzaam. Probeer het opnieuw.".to_string()
            } else if e.is_connect() {
                "Kan geen verbinding maken met de server. Controleer je internetverbinding en probeer het opnieuw.".to_string()
            } else {
                "Upload mislukt door een netwerkfout. Controleer je internetverbinding en probeer het later opnieuw.".to_string()
            }
        })?;

    let status = response.status().as_u16();
    let mut resp_headers = HashMap::new();
    for (k, v) in response.headers() {
        if let Ok(val) = v.to_str() {
            resp_headers.insert(k.to_string(), val.to_string());
        }
    }
    let body = response.text().await.map_err(|e| e.to_string())?;

    eprintln!(
        "[Upload] Response: {} ({} bytes)  send_took={:?}  total={:?}",
        status,
        body.len(),
        t_send.elapsed(),
        t_start.elapsed()
    );

    Ok(HttpResponse {
        status,
        body,
        headers: resp_headers,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::net::TcpListener;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    /// Create a minimal WAV file (valid header + some audio data)
    fn create_test_wav(path: &std::path::Path) {
        let spec = hound::WavSpec {
            channels: 1,
            sample_rate: 16000,
            bits_per_sample: 16,
            sample_format: hound::SampleFormat::Int,
        };
        let mut writer = hound::WavWriter::create(path, spec).unwrap();
        // Write 0.1 seconds of silence (1600 samples)
        for _ in 0..1600 {
            writer.write_sample(0i16).unwrap();
        }
        writer.finalize().unwrap();
    }

    /// Start a minimal HTTP server that captures the request and returns a JSON response
    async fn start_test_server() -> (String, tokio::sync::oneshot::Sender<()>, tokio::sync::oneshot::Receiver<CapturedRequest>) {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let url = format!("http://127.0.0.1:{}/transcribe", addr.port());

        let (shutdown_tx, mut shutdown_rx) = tokio::sync::oneshot::channel::<()>();
        let (captured_tx, captured_rx) = tokio::sync::oneshot::channel::<CapturedRequest>();

        tokio::spawn(async move {
            tokio::select! {
                result = listener.accept() => {
                    if let Ok((mut stream, _)) = result {
                        let mut buf = vec![0u8; 1024 * 1024]; // 1MB buffer
                        let mut total = 0;

                        // Read the full request
                        loop {
                            match stream.read(&mut buf[total..]).await {
                                Ok(0) => break,
                                Ok(n) => {
                                    total += n;
                                    // Check if we've received the full request
                                    let data = &buf[..total];
                                    if let Some(pos) = find_subsequence(data, b"\r\n\r\n") {
                                        // Parse Content-Length
                                        let header_str = String::from_utf8_lossy(&data[..pos]);
                                        if let Some(cl) = parse_content_length(&header_str) {
                                            let body_start = pos + 4;
                                            let body_received = total - body_start;
                                            if body_received >= cl {
                                                break;
                                            }
                                        } else {
                                            // No content-length, wait a bit for more data
                                            tokio::time::sleep(std::time::Duration::from_millis(50)).await;
                                            match stream.try_read(&mut buf[total..]) {
                                                Ok(0) | Err(_) => break,
                                                Ok(n) => { total += n; break; }
                                            }
                                        }
                                    }
                                }
                                Err(_) => break,
                            }
                        }

                        let request_data = buf[..total].to_vec();
                        let header_end = find_subsequence(&request_data, b"\r\n\r\n").unwrap_or(total);
                        let headers = String::from_utf8_lossy(&request_data[..header_end]).to_string();

                        let captured = CapturedRequest {
                            headers,
                            body_size: total.saturating_sub(header_end + 4),
                            raw: request_data,
                        };

                        // Send success response
                        let response_body = r#"{"task_id":"test-task-123","status":"pending"}"#;
                        let response = format!(
                            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
                            response_body.len(),
                            response_body
                        );
                        let _ = stream.write_all(response.as_bytes()).await;
                        let _ = stream.shutdown().await;

                        let _ = captured_tx.send(captured);
                    }
                }
                _ = &mut shutdown_rx => {}
            }
        });

        (url, shutdown_tx, captured_rx)
    }

    /// Start a test server that returns an error response
    async fn start_error_server(status: u16, body: &str) -> (String, tokio::sync::oneshot::Sender<()>) {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let url = format!("http://127.0.0.1:{}/transcribe", addr.port());

        let (shutdown_tx, mut shutdown_rx) = tokio::sync::oneshot::channel::<()>();
        let resp_body = body.to_string();

        tokio::spawn(async move {
            tokio::select! {
                result = listener.accept() => {
                    if let Ok((mut stream, _)) = result {
                        // Read request (don't care about contents)
                        let mut buf = vec![0u8; 1024 * 1024];
                        let mut total = 0;
                        loop {
                            match tokio::time::timeout(
                                std::time::Duration::from_millis(200),
                                stream.read(&mut buf[total..])
                            ).await {
                                Ok(Ok(0)) | Ok(Err(_)) | Err(_) => break,
                                Ok(Ok(n)) => { total += n; }
                            }
                        }

                        let response = format!(
                            "HTTP/1.1 {} Error\r\nContent-Type: application/json\r\nContent-Length: {}\r\n\r\n{}",
                            status,
                            resp_body.len(),
                            resp_body
                        );
                        let _ = stream.write_all(response.as_bytes()).await;
                        let _ = stream.shutdown().await;
                    }
                }
                _ = &mut shutdown_rx => {}
            }
        });

        (url, shutdown_tx)
    }

    #[derive(Debug)]
    struct CapturedRequest {
        headers: String,
        body_size: usize,
        raw: Vec<u8>,
    }

    fn find_subsequence(haystack: &[u8], needle: &[u8]) -> Option<usize> {
        haystack.windows(needle.len()).position(|w| w == needle)
    }

    fn parse_content_length(headers: &str) -> Option<usize> {
        for line in headers.lines() {
            if line.to_lowercase().starts_with("content-length:") {
                return line.split(':').nth(1)?.trim().parse().ok();
            }
        }
        None
    }

    // -- Tests --

    #[tokio::test]
    async fn test_upload_nonexistent_file() {
        let result = do_proxy_upload(
            "/tmp/does-not-exist-12345.wav".to_string(),
            "http://localhost:1234/transcribe".to_string(),
            "test-token".to_string(),
            "profile-1".to_string(),
            "combined".to_string(),
            false,
        ).await;

        assert!(result.is_err());
        let err = result.unwrap_err();
        assert!(err.contains("Bestand niet gevonden"), "Expected 'Bestand niet gevonden', got: {}", err);
    }

    #[tokio::test]
    async fn test_upload_empty_file() {
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("empty.wav");
        std::fs::File::create(&file_path).unwrap();

        let result = do_proxy_upload(
            file_path.to_string_lossy().to_string(),
            "http://localhost:1234/transcribe".to_string(),
            "test-token".to_string(),
            "profile-1".to_string(),
            "combined".to_string(),
            false,
        ).await;

        assert!(result.is_err());
        let err = result.unwrap_err();
        assert!(err.contains("leeg (0 bytes)"), "Expected 'leeg (0 bytes)', got: {}", err);
    }

    #[tokio::test]
    async fn test_upload_success() {
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("test_recording.wav");
        create_test_wav(&file_path);

        let (url, _shutdown, captured_rx) = start_test_server().await;

        let result = do_proxy_upload(
            file_path.to_string_lossy().to_string(),
            url,
            "my-auth-token".to_string(),
            "profile-abc".to_string(),
            "combined".to_string(),
            false,
        ).await;

        assert!(result.is_ok(), "Upload should succeed, got: {:?}", result.err());
        let response = result.unwrap();
        assert_eq!(response.status, 200);
        assert!(response.body.contains("test-task-123"));

        // Verify the captured request
        let captured = captured_rx.await.unwrap();
        let headers_lower = captured.headers.to_lowercase();
        assert!(captured.headers.contains("POST /transcribe"), "Should POST to /transcribe");
        assert!(headers_lower.contains("x-user-token: my-auth-token"), "Should include auth token, got: {}", captured.headers);
        assert!(headers_lower.contains("multipart/form-data"), "Should be multipart");

        // Verify multipart body contains expected fields
        let raw_str = String::from_utf8_lossy(&captured.raw);
        assert!(raw_str.contains("test_recording.wav"), "Should include filename");
        assert!(raw_str.contains("profile-abc"), "Should include profile_id");
        assert!(raw_str.contains("combined"), "Should include mode");
        assert!(captured.body_size > 0, "Body should not be empty");
    }

    #[tokio::test]
    async fn test_upload_server_error() {
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("test.wav");
        create_test_wav(&file_path);

        let error_body = r#"{"error":"Quota exceeded"}"#;
        let (url, _shutdown) = start_error_server(413, error_body).await;

        let result = do_proxy_upload(
            file_path.to_string_lossy().to_string(),
            url,
            "token".to_string(),
            "profile".to_string(),
            "microphone".to_string(),
            false,
        ).await;

        // Should return Ok with error status (not Err) — the HTTP response was received
        assert!(result.is_ok(), "Should return Ok even for HTTP errors");
        let response = result.unwrap();
        assert_eq!(response.status, 413);
        assert!(response.body.contains("Quota exceeded"));
    }

    #[tokio::test]
    async fn test_upload_network_error() {
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("test.wav");
        create_test_wav(&file_path);

        // Use a port that nothing is listening on
        let result = do_proxy_upload(
            file_path.to_string_lossy().to_string(),
            "http://127.0.0.1:1/transcribe".to_string(),
            "token".to_string(),
            "profile".to_string(),
            "combined".to_string(),
            false,
        ).await;

        assert!(result.is_err());
        let err = result.unwrap_err();
        assert!(err.contains("netwerkfout") || err.contains("verbinding"), "Expected network error message, got: {}", err);
    }

    #[tokio::test]
    async fn test_upload_filename_extraction() {
        // Test that the filename is correctly extracted from the path
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("recording_1234567890.wav");
        create_test_wav(&file_path);

        let (url, _shutdown, captured_rx) = start_test_server().await;

        let result = do_proxy_upload(
            file_path.to_string_lossy().to_string(),
            url,
            "token".to_string(),
            "p1".to_string(),
            "microphone".to_string(),
            false,
        ).await;

        assert!(result.is_ok());

        let captured = captured_rx.await.unwrap();
        let raw_str = String::from_utf8_lossy(&captured.raw);
        assert!(raw_str.contains("recording_1234567890.wav"), "Should use original filename");
    }
}

/// Server-Sent Events stream — emits chunks to frontend via Tauri events.
/// `event_name` is the Tauri event name to emit for each SSE message.
#[tauri::command]
pub async fn http_sse_stream(
    app: AppHandle,
    url: String,
    headers: Option<HashMap<String, String>>,
    event_name: String,
) -> Result<(), String> {
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(300))
        .build()
        .map_err(|e| e.to_string())?;

    let mut req = client.get(&url);

    if let Some(hdrs) = headers {
        for (key, value) in &hdrs {
            req = req.header(key.as_str(), value.as_str());
        }
    }

    let response = req.send().await.map_err(|e| e.to_string())?;

    if !response.status().is_success() {
        return Err(format!("SSE verbinding mislukt: HTTP {}", response.status()));
    }

    let mut stream = response.bytes_stream();
    let mut buffer = String::new();

    while let Some(chunk) = stream.next().await {
        let chunk = chunk.map_err(|e| e.to_string())?;
        let text = String::from_utf8_lossy(&chunk);
        buffer.push_str(&text);

        // Process complete SSE lines from buffer
        while let Some(pos) = buffer.find('\n') {
            let line = buffer[..pos].trim().to_string();
            buffer.drain(..=pos);

            if line.starts_with("data: ") {
                let data = &line[6..];
                if data != "[DONE]" {
                    let _ = app.emit(&event_name, data);
                } else {
                    let _ = app.emit(&format!("{}-done", event_name), "");
                    return Ok(());
                }
            }
        }
    }

    let _ = app.emit(&format!("{}-done", event_name), "");
    Ok(())
}
