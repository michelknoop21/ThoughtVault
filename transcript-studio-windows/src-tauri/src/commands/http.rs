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

/// Multipart file upload — reads file from disk, sends as audio/wav.
/// Extensive logging to aid debugging upload issues.
#[tauri::command]
pub async fn http_upload_file(
    url: String,
    file_path: String,
    field_name: String,
    additional_fields: Option<HashMap<String, String>>,
    headers: Option<HashMap<String, String>>,
) -> Result<HttpResponse, String> {
    eprintln!("[Upload] Starting upload to: {}", url);
    eprintln!("[Upload] File path: {}", file_path);

    let file_bytes = tokio::fs::read(&file_path)
        .await
        .map_err(|e| format!("Kan bestand niet lezen ({}): {}", file_path, e))?;

    let file_size = file_bytes.len();
    eprintln!("[Upload] File size: {} bytes", file_size);

    let filename = std::path::Path::new(&file_path)
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("recording.wav")
        .to_string();

    eprintln!("[Upload] Filename: {}", filename);
    eprintln!("[Upload] Field name: {}", field_name);

    let file_part = reqwest::multipart::Part::bytes(file_bytes)
        .file_name(filename.clone())
        .mime_str("audio/wav")
        .map_err(|e| e.to_string())?;

    let mut form = reqwest::multipart::Form::new()
        .part(field_name.clone(), file_part);

    if let Some(fields) = &additional_fields {
        eprintln!("[Upload] Additional fields: {:?}", fields);
        for (key, value) in fields {
            form = form.text(key.clone(), value.clone());
        }
    }

    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(120))
        .build()
        .map_err(|e| e.to_string())?;

    let mut req = client.post(&url).multipart(form);

    if let Some(hdrs) = headers {
        for (key, value) in &hdrs {
            req = req.header(key.as_str(), value.as_str());
        }
    }

    eprintln!("[Upload] Sending request...");
    let response = req.send().await.map_err(|e| {
        eprintln!("[Upload] Request failed: {}", e);
        e.to_string()
    })?;

    let status = response.status().as_u16();
    eprintln!("[Upload] Response status: {}", status);

    let mut resp_headers = HashMap::new();
    for (k, v) in response.headers() {
        if let Ok(val) = v.to_str() {
            resp_headers.insert(k.to_string(), val.to_string());
        }
    }

    let body = response.text().await.map_err(|e| e.to_string())?;
    eprintln!("[Upload] Response body: {}", &body[..body.len().min(500)]);

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
