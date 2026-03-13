use futures_util::StreamExt;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

use tauri::{AppHandle, Emitter};

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
