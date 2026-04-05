use reqwest::ClientBuilder;
use std::time::Duration;

/// Build a reqwest client that skips TLS certificate verification.
/// This is needed because student VMs use self-signed certificates.
pub fn insecure_client() -> reqwest::Client {
    ClientBuilder::new()
        .danger_accept_invalid_certs(true)
        .timeout(Duration::from_secs(15))
        .connect_timeout(Duration::from_secs(10))
        .redirect(reqwest::redirect::Policy::limited(5))
        .build()
        .expect("Failed to build HTTP client")
}

pub struct HttpResponse {
    pub status: u16,
    pub body: String,
}

pub async fn get(url: &str) -> Result<HttpResponse, String> {
    let client = insecure_client();
    let resp = client
        .get(url)
        .send()
        .await
        .map_err(|e| format!("Connection failed: {e}"))?;
    let status = resp.status().as_u16();
    let body = resp.text().await.unwrap_or_default();
    Ok(HttpResponse { status, body })
}

pub async fn post(url: &str, content_type: &str, payload: &str) -> Result<HttpResponse, String> {
    let client = insecure_client();
    let resp = client
        .post(url)
        .header("Content-Type", content_type)
        .body(payload.to_string())
        .send()
        .await
        .map_err(|e| format!("Connection failed: {e}"))?;
    let status = resp.status().as_u16();
    let body = resp.text().await.unwrap_or_default();
    Ok(HttpResponse { status, body })
}
