package checks;

import domain.HttpRequestException;
import org.bouncycastle.jce.provider.BouncyCastleProvider;
import org.bouncycastle.jsse.provider.BouncyCastleJsseProvider;

import javax.net.ssl.*;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.security.Security;
import java.security.cert.X509Certificate;

/**
 * God I hate Java's built-in TLS handling, This is where I realize that I'll never EVER will 
 * intentionally write java. 
 * This helper uses BouncyCastle's JSSE provider which is more lenient.  I almost started writing a rust helper.
 * Java is the only language where I have to write 200 lines of code just to ignore TLS errors.
 * Please don't make me write Java again. I will write literally anything else. Go, Rust, Go, Python, Go, even PHP, just not Java.
 * I don't care if it's the "industry standard", it's the worst language I've ever had to work with, and I have worked with some truly awful languages. 
 */
public final class HttpHelper {

    private static final SSLSocketFactory TRUST_ALL_SF;

    static {
        try {
            // Register BouncyCastle as highest-priority JSSE + JCE provider
            Security.insertProviderAt(new BouncyCastleProvider(), 1);
            Security.insertProviderAt(new BouncyCastleJsseProvider(), 2);

            SSLContext sc = SSLContext.getInstance("TLS", "BCJSSE");
            sc.init(null, new TrustManager[]{new X509ExtendedTrustManager() {
                @Override public void checkClientTrusted(X509Certificate[] c, String t) {}
                @Override public void checkServerTrusted(X509Certificate[] c, String t) {}
                @Override public void checkClientTrusted(X509Certificate[] c, String t, java.net.Socket s) {}
                @Override public void checkServerTrusted(X509Certificate[] c, String t, java.net.Socket s) {}
                @Override public void checkClientTrusted(X509Certificate[] c, String t, SSLEngine e) {}
                @Override public void checkServerTrusted(X509Certificate[] c, String t, SSLEngine e) {}
                @Override public X509Certificate[] getAcceptedIssuers() { return new X509Certificate[0]; }
            }}, new java.security.SecureRandom());
            TRUST_ALL_SF = sc.getSocketFactory();
        } catch (java.security.NoSuchAlgorithmException | java.security.NoSuchProviderException
                 | java.security.KeyManagementException e) {
            throw new ExceptionInInitializerError(e);
        }
    }

    private HttpHelper() {}

    public record HttpResponse(int statusCode, String body) {}

    public static HttpResponse get(String url) {
        try {
            HttpURLConnection conn = openConnection(url);
            conn.setRequestMethod("GET");
            conn.setConnectTimeout(10_000);
            conn.setReadTimeout(10_000);
            conn.setInstanceFollowRedirects(true);
            int code = conn.getResponseCode();
            String body = readBody(conn);
            conn.disconnect();
            return new HttpResponse(code, body);
        } catch (Exception e) {
            throw new HttpRequestException("HTTP GET failed for " + url + ": " + e.getMessage(), e);
        }
    }


    public static HttpResponse post(String url, String contentType, String payload) {
        try {
            HttpURLConnection conn = openConnection(url);
            conn.setRequestMethod("POST");
            conn.setConnectTimeout(10_000);
            conn.setReadTimeout(10_000);
            conn.setDoOutput(true);
            conn.setRequestProperty("Content-Type", contentType);
            conn.getOutputStream().write(payload.getBytes(StandardCharsets.UTF_8));
            int code = conn.getResponseCode();
            String body = readBody(conn);
            conn.disconnect();
            return new HttpResponse(code, body);
        } catch (Exception e) {
            throw new HttpRequestException("HTTP POST failed for " + url + ": " + e.getMessage(), e);
        }
    }

    private static HttpURLConnection openConnection(String url) throws java.io.IOException {
        HttpURLConnection conn = (HttpURLConnection) URI.create(url).toURL().openConnection();
        if (conn instanceof HttpsURLConnection httpsConn) {
            httpsConn.setSSLSocketFactory(TRUST_ALL_SF);
            httpsConn.setHostnameVerifier((h, s) -> true);
        }
        return conn;
    }

    private static String readBody(HttpURLConnection conn) {
        try {
            InputStream is = conn.getResponseCode() < 400 ? conn.getInputStream() : conn.getErrorStream();
            if (is == null) return "";
            return new String(is.readAllBytes(), StandardCharsets.UTF_8);
        } catch (java.io.IOException e) {
            return "";
        }
    }
}
