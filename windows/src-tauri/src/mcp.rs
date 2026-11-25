//! Local MCP server. The running app listens on 127.0.0.1 and hands each JSON-RPC line to the
//! webview (event `mcp-request`), which answers through `mcp_respond`. `ThoughtVault.exe --mcp`
//! is a stdio bridge an MCP client launches; it finds the listener through `mcp.json`.
//! Every emitted line is settled by exactly one `mcp_respond`; an empty line means "no answer due".

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::io::{BufRead, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tauri::Emitter;
use tokio::io::{AsyncBufRead, AsyncBufReadExt, AsyncReadExt, AsyncWrite, AsyncWriteExt, BufReader};
use tokio::sync::{mpsc, watch};

const IDENTIFIER: &str = env!("TV_APP_IDENTIFIER");
const MAX_LINE: usize = 8 * 1024 * 1024;
const TOKEN_LINE_MAX: usize = 256;
const TOKEN_TIMEOUT: Duration = Duration::from_secs(5);
/// How long answers may still arrive after the client stopped sending.
const DRAIN_LIMIT: Duration = Duration::from_secs(30);
const NOT_RUNNING: &str = "ThoughtVault is niet geopend of de AI-koppeling staat uit.";

#[derive(Serialize, Deserialize, Debug, PartialEq)]
struct Endpoint {
    port: u16,
    token: String,
    pid: u32,
}

#[derive(Serialize, Clone)]
struct Request {
    conn: u64,
    line: String,
}

type Connections = Arc<Mutex<HashMap<u64, mpsc::UnboundedSender<String>>>>;

#[derive(Default)]
pub struct McpState {
    stop: Mutex<Option<watch::Sender<bool>>>,
    conns: Connections,
}

static NEXT_CONN: AtomicU64 = AtomicU64::new(1);

fn endpoint_path() -> Option<PathBuf> {
    dirs::data_dir().map(|dir| dir.join(IDENTIFIER).join("mcp.json"))
}

fn write_endpoint(path: &Path, endpoint: &Endpoint) -> Result<(), String> {
    let parent = path.parent().ok_or("Ongeldig opslagpad")?;
    std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    let mut file = tempfile::NamedTempFile::new_in(parent).map_err(|e| e.to_string())?;
    file.write_all(&serde_json::to_vec(endpoint).map_err(|e| e.to_string())?).map_err(|e| e.to_string())?;
    file.persist(path).map_err(|e| e.to_string())?;
    Ok(())
}

pub fn remove_endpoint() {
    if let Some(path) = endpoint_path() {
        let _ = std::fs::remove_file(path);
    }
}

fn new_token() -> Result<String, String> {
    let mut bytes = [0u8; 32];
    getrandom::fill(&mut bytes).map_err(|e| e.to_string())?;
    Ok(bytes.iter().map(|b| format!("{b:02x}")).collect())
}

fn token_matches(given: &str, expected: &str) -> bool {
    given.len() == expected.len() && given.bytes().zip(expected.bytes()).fold(0u8, |acc, (a, b)| acc | (a ^ b)) == 0
}

/// One line without its line ending; None at end of stream; an error when it exceeds `max` bytes.
async fn read_line<R: AsyncBufRead + Unpin>(reader: &mut R, max: usize) -> std::io::Result<Option<String>> {
    let mut buf = Vec::new();
    if (&mut *reader).take(max as u64 + 1).read_until(b'\n', &mut buf).await? == 0 {
        return Ok(None);
    }
    if buf.last() == Some(&b'\n') {
        buf.pop();
        if buf.last() == Some(&b'\r') {
            buf.pop();
        }
    }
    if buf.len() > max {
        return Err(std::io::Error::new(std::io::ErrorKind::InvalidData, "line too long"));
    }
    String::from_utf8(buf).map(Some).map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))
}

/// Copies app answers to the client. Ends on a write error, when the connection is dropped from
/// `conns`, or once the client stopped sending (`emitted` holds the request count) and every request
/// is settled, waiting at most DRAIN_LIMIT for that.
async fn write_answers<W: AsyncWrite + Unpin>(mut write: W, mut answers: mpsc::UnboundedReceiver<String>, mut emitted: watch::Receiver<Option<u64>>) {
    let mut answered = 0u64;
    let mut deadline: Option<tokio::time::Instant> = None;
    loop {
        if let Some(total) = *emitted.borrow() {
            if answered >= total {
                return;
            }
            deadline.get_or_insert_with(|| tokio::time::Instant::now() + DRAIN_LIMIT);
        }
        tokio::select! {
            answer = answers.recv() => {
                let Some(line) = answer else { return };
                answered += 1;
                if !line.is_empty() && (write.write_all(format!("{line}\n").as_bytes()).await.is_err() || write.flush().await.is_err()) {
                    return;
                }
            }
            changed = emitted.changed(), if deadline.is_none() => if changed.is_err() { return },
            _ = tokio::time::sleep_until(deadline.unwrap_or_else(tokio::time::Instant::now)), if deadline.is_some() => return,
        }
    }
}

async fn serve<F>(stream: tokio::net::TcpStream, token: String, emit: F, conns: Connections, mut stop: watch::Receiver<bool>)
where
    F: Fn(u64, String) -> bool,
{
    let (read, write) = stream.into_split();
    let mut reader = BufReader::new(read);
    match tokio::time::timeout(TOKEN_TIMEOUT, read_line(&mut reader, TOKEN_LINE_MAX)).await {
        Ok(Ok(Some(line))) if token_matches(&line, &token) => {}
        _ => return,
    }
    let conn = NEXT_CONN.fetch_add(1, Ordering::Relaxed);
    let (tx, rx) = mpsc::unbounded_channel::<String>();
    conns.lock().unwrap().insert(conn, tx);
    let (emitted_tx, emitted_rx) = watch::channel(None);
    let requests = async {
        let mut emitted = 0u64;
        while let Ok(Some(line)) = read_line(&mut reader, MAX_LINE).await {
            if !line.trim().is_empty() && emit(conn, line) {
                emitted += 1;
            }
        }
        // Half-close: the client is done sending, the writer keeps going until every request is settled.
        let _ = emitted_tx.send(Some(emitted));
        std::future::pending::<()>().await
    };
    tokio::select! {
        _ = write_answers(write, rx, emitted_rx) => {}
        _ = requests => {}
        _ = stop.changed() => {}
    }
    conns.lock().unwrap().remove(&conn);
}

async fn start(app: tauri::AppHandle, state: &McpState) -> Result<(), String> {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.map_err(|e| e.to_string())?;
    let port = listener.local_addr().map_err(|e| e.to_string())?.port();
    let token = new_token()?;
    let path = endpoint_path().ok_or("Kan app-data map niet vinden")?;
    write_endpoint(&path, &Endpoint { port, token: token.clone(), pid: std::process::id() })?;
    let (stop_tx, stop_rx) = watch::channel(false);
    *state.stop.lock().unwrap() = Some(stop_tx);
    let conns = state.conns.clone();
    tauri::async_runtime::spawn(async move {
        let mut stop = stop_rx.clone();
        loop {
            tokio::select! {
                accepted = listener.accept() => {
                    if let Ok((stream, _)) = accepted {
                        let app = app.clone();
                        let emit = move |conn, line| app.emit_to("main", "mcp-request", Request { conn, line }).is_ok();
                        tauri::async_runtime::spawn(serve(stream, token.clone(), emit, conns.clone(), stop_rx.clone()));
                    }
                }
                _ = stop.changed() => break,
            }
        }
    });
    elog!("[MCP] Koppeling luistert op 127.0.0.1:{}", port);
    Ok(())
}

fn stop(state: &McpState) {
    if let Some(stop) = state.stop.lock().unwrap().take() {
        let _ = stop.send(true);
    }
    state.conns.lock().unwrap().clear();
    remove_endpoint();
}

#[tauri::command]
pub async fn mcp_set_enabled(app: tauri::AppHandle, state: tauri::State<'_, McpState>, enabled: bool) -> Result<(), String> {
    let running = state.stop.lock().unwrap().is_some();
    match (enabled, running) {
        (true, false) => start(app, &state).await,
        (false, true) => {
            stop(&state);
            Ok(())
        }
        _ => Ok(()),
    }
}

/// Settles one request of `conn`; an empty `line` settles it without sending anything (notifications).
#[tauri::command]
pub fn mcp_respond(state: tauri::State<'_, McpState>, conn: u64, line: String) -> Result<(), String> {
    if line.contains('\n') {
        return Err("Antwoord bevat een regeleinde".into());
    }
    let conns = state.conns.lock().unwrap();
    let sender = conns.get(&conn).ok_or("Verbinding gesloten")?;
    sender.send(line).map_err(|_| "Verbinding gesloten".to_string())
}

#[tauri::command]
pub fn mcp_executable_path() -> Result<String, String> {
    std::env::current_exe().map(|p| p.to_string_lossy().to_string()).map_err(|e| e.to_string())
}

/// `ThoughtVault.exe --mcp`: copies stdin lines to the app and app lines to stdout. Returns the exit code.
pub fn run_bridge() -> i32 {
    let connect = || -> Option<std::net::TcpStream> {
        let endpoint: Endpoint = serde_json::from_slice(&std::fs::read(endpoint_path()?).ok()?).ok()?;
        let mut stream = std::net::TcpStream::connect(("127.0.0.1", endpoint.port)).ok()?;
        stream.write_all(format!("{}\n", endpoint.token).as_bytes()).ok()?;
        Some(stream)
    };
    let Some(stream) = connect() else {
        eprintln!("{NOT_RUNNING}");
        return 1;
    };
    // true: stdin ended; false: the app side ended.
    let (done_tx, done_rx) = std::sync::mpsc::channel::<bool>();
    let (Ok(mut to_app), Ok(from_app)) = (stream.try_clone(), stream.try_clone()) else {
        eprintln!("{NOT_RUNNING}");
        return 1;
    };
    let stdin_done = done_tx.clone();
    std::thread::spawn(move || {
        for line in std::io::stdin().lock().lines() {
            let Ok(line) = line else { break };
            if to_app.write_all(format!("{line}\n").as_bytes()).is_err() {
                break;
            }
        }
        let _ = stdin_done.send(true);
    });
    std::thread::spawn(move || {
        let mut stdout = std::io::stdout().lock();
        for line in std::io::BufReader::new(from_app).lines() {
            let Ok(line) = line else { break };
            if writeln!(stdout, "{line}").is_err() || stdout.flush().is_err() {
                break;
            }
        }
        let _ = done_tx.send(false);
    });
    // Either side may finish first. When stdin ends, only stop sending, so answers to the last
    // requests still reach stdout; the app closes the connection once all are settled.
    if done_rx.recv() == Ok(true) {
        let _ = stream.shutdown(std::net::Shutdown::Write);
        let _ = done_rx.recv_timeout(DRAIN_LIMIT);
    }
    let _ = stream.shutdown(std::net::Shutdown::Both);
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn token_is_64_hex_and_compares_exactly() {
        let token = new_token().unwrap();
        assert_eq!(token.len(), 64);
        assert!(token.chars().all(|c| c.is_ascii_hexdigit()));
        assert_ne!(token, new_token().unwrap());
        assert!(token_matches(&token, &token));
        assert!(!token_matches(&token[..63], &token));
        assert!(!token_matches(&format!("{}0", &token[..63]), &format!("{}1", &token[..63])));
    }

    #[test]
    fn endpoint_file_is_written_whole_and_removed() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("nested").join("mcp.json");
        let endpoint = Endpoint { port: 4321, token: "ab".repeat(32), pid: 7 };
        write_endpoint(&path, &endpoint).unwrap();
        let read: Endpoint = serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
        assert_eq!(read, endpoint);
        assert_eq!(std::fs::read_dir(path.parent().unwrap()).unwrap().count(), 1, "no temp file left behind");
        std::fs::remove_file(&path).unwrap();
        assert!(!path.exists());
    }

    #[tokio::test]
    async fn lines_are_capped() {
        let input = format!("short\r\n{}\nlast", "x".repeat(20));
        let mut reader = BufReader::new(input.as_bytes());
        assert_eq!(read_line(&mut reader, 10).await.unwrap().as_deref(), Some("short"));
        assert!(read_line(&mut reader, 10).await.is_err());
        let mut exact = BufReader::new("0123456789\n".as_bytes());
        assert_eq!(read_line(&mut exact, 10).await.unwrap().as_deref(), Some("0123456789"));
        assert_eq!(read_line(&mut exact, 10).await.unwrap(), None);
    }

    /// Runs the real `serve` on a loopback port; emitted lines go to the returned receiver.
    async fn serve_once(token: &str) -> (tokio::net::TcpStream, Connections, mpsc::UnboundedReceiver<(u64, String)>, watch::Sender<bool>) {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        let conns: Connections = Default::default();
        let (emitted_tx, emitted_rx) = mpsc::unbounded_channel();
        let (stop_tx, stop_rx) = watch::channel(false);
        let (server_conns, token) = (conns.clone(), token.to_string());
        tokio::spawn(async move {
            let (stream, _) = listener.accept().await.unwrap();
            let emit = move |conn, line| emitted_tx.send((conn, line)).is_ok();
            serve(stream, token, emit, server_conns, stop_rx).await;
        });
        (tokio::net::TcpStream::connect(("127.0.0.1", port)).await.unwrap(), conns, emitted_rx, stop_tx)
    }

    #[tokio::test]
    async fn wrong_token_closes_without_data() {
        let (mut client, conns, mut emitted, _stop) = serve_once(&"a".repeat(64)).await;
        client.write_all(format!("{}\n{{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}}\n", "b".repeat(64)).as_bytes()).await.unwrap();
        let mut received = Vec::new();
        // Closed either with FIN (EOF) or, when unread bytes were left, with a reset.
        if let Err(e) = tokio::time::timeout(Duration::from_secs(5), client.read_to_end(&mut received)).await.unwrap() {
            assert_eq!(e.kind(), std::io::ErrorKind::ConnectionReset);
        }
        assert!(received.is_empty());
        assert!(emitted.try_recv().is_err());
        assert!(conns.lock().unwrap().is_empty());
    }

    #[tokio::test]
    async fn half_closed_client_gets_every_answer_then_eof() {
        let token = "c".repeat(64);
        let (mut client, conns, mut emitted, _stop) = serve_once(&token).await;
        client.write_all(format!("{token}\nrequest\n\nnotification\n").as_bytes()).await.unwrap();
        client.shutdown().await.unwrap();
        let mut lines = Vec::new();
        for _ in 0..2 {
            lines.push(tokio::time::timeout(Duration::from_secs(5), emitted.recv()).await.unwrap().unwrap());
        }
        let [(conn, first), (_, second)] = <[_; 2]>::try_from(lines).unwrap();
        assert_eq!((first.as_str(), second.as_str()), ("request", "notification"));
        // The request side is at EOF; the connection must stay open for the outstanding answers.
        tokio::time::sleep(Duration::from_millis(100)).await;
        let sender = conns.lock().unwrap().get(&conn).cloned().expect("connection kept while answers are pending");
        sender.send(String::new()).unwrap();
        sender.send("answer".into()).unwrap();
        let mut received = String::new();
        tokio::time::timeout(Duration::from_secs(5), client.read_to_string(&mut received)).await.unwrap().unwrap();
        assert_eq!(received, "answer\n");
        tokio::time::sleep(Duration::from_millis(50)).await;
        assert!(conns.lock().unwrap().is_empty());
    }

    #[tokio::test]
    async fn drain_ends_once_every_request_is_settled() {
        let (answers_tx, answers_rx) = mpsc::unbounded_channel();
        let (emitted_tx, emitted_rx) = watch::channel(None);
        let mut out = Vec::new();
        answers_tx.send("one".into()).unwrap();
        answers_tx.send(String::new()).unwrap();
        emitted_tx.send(Some(2)).unwrap();
        tokio::time::timeout(Duration::from_secs(1), write_answers(&mut out, answers_rx, emitted_rx)).await.expect("ends without waiting for the cap");
        assert_eq!(out, b"one\n");
    }

    #[test]
    fn identifier_comes_from_the_build() {
        assert!(IDENTIFIER.starts_with("nl.prezent.transcript-studio"));
    }
}
