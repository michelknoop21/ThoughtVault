//! Optional MCP on loopback only. No account, relay, payload persistence or CORS.
use serde_json::{json, Value};
use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
    time::{SystemTime, UNIX_EPOCH},
};
use tauri::{Emitter, State};
use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::TcpListener,
    sync::{oneshot, Semaphore},
};

#[derive(Default)]
pub struct LocalMcp(pub Mutex<Option<Server>>);
pub struct Server {
    token: String,
    scopes: Vec<String>,
    stop: oneshot::Sender<()>,
    pending: Arc<Mutex<HashMap<String, oneshot::Sender<Value>>>>,
}
fn tools() -> Vec<Value> {
    serde_json::from_str(include_str!("../../src/services/mcpTools.json")).unwrap()
}
fn scope(name: &str) -> Option<String> {
    tools()
        .iter()
        .find(|t| t["name"] == name)
        .and_then(|t| t["scope"].as_str().map(str::to_owned))
}
fn request_length(header: &str, token: &str) -> Result<usize, u16> {
    if header.len() > 16384 {
        return Err(400);
    }
    let mut lines = header.split("\r\n");
    let first = lines.next().ok_or(400u16)?;
    let mut headers = HashMap::new();
    for line in lines.filter(|line| !line.is_empty()) {
        let (key, value) = line.split_once(':').ok_or(400u16)?;
        if headers
            .insert(key.to_ascii_lowercase(), value.trim().to_string())
            .is_some()
        {
            return Err(400);
        }
    }
    if headers.get("authorization") != Some(&format!("Bearer {token}"))
        || headers.contains_key("origin")
        || headers.contains_key("transfer-encoding")
        || !headers
            .get("host")
            .is_some_and(|host| ["127.0.0.1:11219", "localhost:11219"].contains(&host.as_str()))
    {
        return Err(403);
    }
    if first != "POST /mcp HTTP/1.1" {
        return Err(405);
    }
    if headers
        .get("mcp-protocol-version")
        .is_some_and(|version| version != "2025-06-18")
    {
        return Err(400);
    }
    let length = headers
        .get("content-length")
        .and_then(|value| value.parse::<usize>().ok())
        .ok_or(400u16)?;
    if length > 2_000_000 {
        return Err(400);
    }
    Ok(length)
}
#[tauri::command]
pub async fn local_mcp_start(
    app: tauri::AppHandle,
    state: State<'_, LocalMcp>,
    token: String,
    scopes: Vec<String>,
) -> Result<String, String> {
    if token.len() != 64
        || !token.bytes().all(|b| b.is_ascii_hexdigit())
        || scopes
            .iter()
            .any(|s| !["read", "write", "record"].contains(&s.as_str()))
    {
        return Err("Ongeldige MCP-instelling.".into());
    }
    local_mcp_stop(state.clone());
    let listener = TcpListener::bind("127.0.0.1:11219")
        .await
        .map_err(|_| "Lokale MCP-poort is bezet.".to_string())?;
    let (stop, mut stopped) = oneshot::channel();
    let pending = Arc::new(Mutex::new(HashMap::new()));
    *state.0.lock().unwrap() = Some(Server {
        token: token.clone(),
        scopes: scopes.clone(),
        stop,
        pending: pending.clone(),
    });
    let capacity = Arc::new(Semaphore::new(8));
    tauri::async_runtime::spawn(async move {
        loop {
            tokio::select! {
                _ = &mut stopped => break,
                accepted = listener.accept() => {
                    let Ok((mut stream,_))=accepted else { continue };
                    let Ok(permit)=capacity.clone().try_acquire_owned() else { continue };
                    let app=app.clone(); let token=token.clone(); let scopes=scopes.clone(); let pending=pending.clone();
                    tauri::async_runtime::spawn(async move {
                        let _permit=permit;
                        let result=tokio::time::timeout(std::time::Duration::from_secs(35), async {
                            let mut bytes=Vec::new(); let mut chunk=[0;4096];
                            let header_end=loop {
                                let n=stream.read(&mut chunk).await.map_err(|_| ())?; if n==0 {return Err(())}; bytes.extend_from_slice(&chunk[..n]);
                                if let Some(pos)=bytes.windows(4).position(|x| x==b"\r\n\r\n") {break pos+4}; if bytes.len()>16384 {return Err(())}
                            };
                            let header=std::str::from_utf8(&bytes[..header_end]).map_err(|_| ())?;
                            let length=match request_length(header, &token) {
                                Ok(length)=>length,
                                Err(status)=>return Ok((status,json!({"error":"Ongeldige lokale MCP-aanvraag."}))),
                            };
                            while bytes.len()<header_end+length {let n=stream.read(&mut chunk).await.map_err(|_|())?; if n==0{return Err(())}; bytes.extend_from_slice(&chunk[..n]);}
                            let request: Value=serde_json::from_slice(&bytes[header_end..header_end+length]).map_err(|_|())?;
                            if request["jsonrpc"]!="2.0" || !request["method"].is_string() {return Err(())}
                            let id=request.get("id").cloned().unwrap_or(Value::Null);
                            if id.is_null() {return Ok((202,Value::Null))}
                            let response=match request["method"].as_str().unwrap_or("") {
                                "initialize"=>json!({"protocolVersion":"2025-06-18","capabilities":{"tools":{"listChanged":false}},"serverInfo":{"name":"ThoughtVault Windows","version":"1.0"},"instructions":"Local app only. Read revisions before writes. Never retry uncertain recording results."}),
                                "ping"=>json!({}),
                                "tools/list"=>json!({"tools":tools().into_iter().filter(|t|scopes.contains(&t["scope"].as_str().unwrap().to_owned())).map(|mut t|{t.as_object_mut().unwrap().remove("scope");t}).collect::<Vec<_>>()}),
                                "tools/call"=>{
                                    let name=request["params"]["name"].as_str().unwrap_or("");
                                    let required=scope(name);
                                    if !required.as_ref().is_some_and(|s|scopes.contains(s)) {json!({"isError":true,"content":[{"type":"text","text":"Tool niet toegestaan."}]})}
                                    else if name=="list_devices" {json!({"content":[{"type":"text","text":"Only this local Windows app is available."}],"structuredContent":{"devices":[{"id":"local","platform":"Windows","online":true}]}})}
                                    else {
                                        let args=request["params"].get("arguments").cloned().unwrap_or(json!({}));
                                        if !args.is_object() {return Err(())}
                                        let command_id=SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos().to_string();
                                        let (send,receive)=oneshot::channel(); pending.lock().unwrap().insert(command_id.clone(),send);
                                        app.emit("local-mcp-command",json!({"id":command_id,"device_id":"local","scope":required,"expires_at":SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs()+25,"tool":name,"arguments":args})).map_err(|_|())?;
                                        let reply=tokio::time::timeout(std::time::Duration::from_secs(25),receive).await;
                                        pending.lock().unwrap().remove(&command_id);
                                        let value=match reply {Ok(Ok(v))=>v,_=>json!({"error":"Resultaat onzeker; herhaal opname- of schrijfopdrachten niet automatisch."})};
                                        json!({"isError":value.get("error").is_some(),"content":[{"type":"text","text":value.to_string()}],"structuredContent":value})
                                    }
                                },
                                _=>return Ok((200,json!({"jsonrpc":"2.0","id":id,"error":{"code":-32601,"message":"Onbekende methode"}}))),
                            };
                            Ok((200,json!({"jsonrpc":"2.0","id":id,"result":response})))
                        }).await;
                        let (status,body)=match result {Ok(Ok(v))=>v,_=>(400,json!({"error":"Ongeldige of verlopen aanvraag."}))};
                        let body=if body.is_null(){String::new()}else{body.to_string()};
                        let response=format!("HTTP/1.1 {status} OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",body.len());
                        let _=stream.write_all(response.as_bytes()).await;
                    });
                }
            }
        }
    });
    Ok("http://127.0.0.1:11219/mcp".into())
}
#[tauri::command]
pub fn local_mcp_stop(state: State<'_, LocalMcp>) {
    if let Some(server) = state.0.lock().unwrap().take() {
        let _ = server.stop.send(());
        server.pending.lock().unwrap().clear();
    }
}
#[tauri::command]
pub fn local_mcp_reply(state: State<'_, LocalMcp>, id: String, result: Value) {
    if let Some(server) = state.0.lock().unwrap().as_ref() {
        if let Some(sender) = server.pending.lock().unwrap().remove(&id) {
            let _ = sender.send(result);
        }
    }
}
#[tauri::command]
pub fn local_mcp_allowed(
    state: State<'_, LocalMcp>,
    token: String,
    tool: String,
    id: String,
) -> bool {
    state.0.lock().unwrap().as_ref().is_some_and(|s| {
        s.token == token
            && s.pending.lock().unwrap().contains_key(&id)
            && scope(&tool).is_some_and(|required| s.scopes.contains(&required))
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn reject_unsafe_http_headers() {
        let valid = "POST /mcp HTTP/1.1\r\nHost: localhost:11219\r\nAuthorization: Bearer synthetic\r\nContent-Length: 2\r\n\r\n";
        assert_eq!(request_length(valid, "synthetic"), Ok(2));
        for extra in [
            "Origin: https://example.invalid",
            "Transfer-Encoding: chunked",
        ] {
            assert_eq!(
                request_length(
                    &valid.replace("\r\n\r\n", &format!("\r\n{extra}\r\n\r\n")),
                    "synthetic"
                ),
                Err(403)
            );
        }
        assert_eq!(request_length(valid, "wrong"), Err(403));
        assert_eq!(
            request_length(
                &valid.replace("localhost:11219", "example.invalid"),
                "synthetic"
            ),
            Err(403)
        );
        assert_eq!(
            request_length(&valid.replace("POST", "GET"), "synthetic"),
            Err(405)
        );
        assert_eq!(
            request_length(
                &valid.replace("Content-Length: 2", "Content-Length: 2000001"),
                "synthetic"
            ),
            Err(400)
        );
        assert_eq!(
            request_length(
                &valid.replace(
                    "Content-Length: 2",
                    "Content-Length: 2\r\nContent-Length: 2"
                ),
                "synthetic"
            ),
            Err(400)
        );
    }
    #[test]
    fn catalog_permissions_do_not_trust_caller_scope() {
        assert_eq!(tools().len(), 15);
        assert_eq!(scope("get_transcript").as_deref(), Some("read"));
        assert_eq!(scope("save_minutes").as_deref(), Some("write"));
        assert_eq!(scope("start_recording").as_deref(), Some("record"));
        assert_eq!(scope("unknown"), None);
    }
}
