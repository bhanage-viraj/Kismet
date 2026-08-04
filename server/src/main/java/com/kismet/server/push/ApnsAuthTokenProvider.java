package com.kismet.server.push;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.KeyFactory;
import java.security.PrivateKey;
import java.security.spec.PKCS8EncodedKeySpec;
import java.time.Instant;
import java.util.Base64;
import java.util.Date;
import java.util.concurrent.atomic.AtomicReference;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import io.jsonwebtoken.Jwts;

/**
 * Signs short-lived APNs provider JWTs (ES256) from an Auth Key (.p8).
 * Disabled when credentials are missing so local demos still boot.
 */
@Component
public class ApnsAuthTokenProvider {

	private static final Logger log = LoggerFactory.getLogger(ApnsAuthTokenProvider.class);
	private static final long REFRESH_AFTER_SECONDS = 40 * 60;

	private final boolean enabled;
	private final String keyId;
	private final String teamId;
	private final PrivateKey privateKey;
	private final AtomicReference<CachedToken> cached = new AtomicReference<>();

	public ApnsAuthTokenProvider(
			@Value("${kismet.apns.enabled:false}") boolean enabled,
			@Value("${kismet.apns.key-id:}") String keyId,
			@Value("${kismet.apns.team-id:}") String teamId,
			@Value("${kismet.apns.key-path:}") String keyPath,
			@Value("${kismet.apns.key-p8:}") String keyP8) {
		this.keyId = blankToNull(keyId);
		this.teamId = blankToNull(teamId);
		PrivateKey loaded = null;
		boolean ready = false;
		if (enabled) {
			try {
				String pem = blankToNull(keyP8);
				if (pem == null && blankToNull(keyPath) != null) {
					pem = Files.readString(Path.of(keyPath));
				}
				if (this.keyId != null && this.teamId != null && pem != null) {
					loaded = loadPrivateKey(pem);
					ready = true;
				}
				else {
					log.warn("APNs enabled but key-id / team-id / key material is incomplete — silent push disabled");
				}
			}
			catch (Exception ex) {
				log.warn("Failed to load APNs auth key — silent push disabled: {}", ex.getMessage());
			}
		}
		this.privateKey = loaded;
		this.enabled = ready;
		if (this.enabled) {
			log.info("APNs auth configured (team={}, keyId={})", this.teamId, this.keyId);
		}
	}

	public boolean isEnabled() {
		return enabled;
	}

	public String currentToken() {
		if (!enabled) {
			throw new IllegalStateException("APNs is not configured");
		}
		CachedToken existing = cached.get();
		long now = Instant.now().getEpochSecond();
		if (existing != null && now - existing.issuedAtEpochSeconds() < REFRESH_AFTER_SECONDS) {
			return existing.jwt();
		}
		String jwt = Jwts.builder()
				.header()
				.add("kid", keyId)
				.and()
				.issuer(teamId)
				.issuedAt(Date.from(Instant.ofEpochSecond(now)))
				.signWith(privateKey, Jwts.SIG.ES256)
				.compact();
		cached.set(new CachedToken(jwt, now));
		return jwt;
	}

	private static PrivateKey loadPrivateKey(String pem) throws Exception {
		String sanitized = pem
				.replace("-----BEGIN PRIVATE KEY-----", "")
				.replace("-----END PRIVATE KEY-----", "")
				.replaceAll("\\s", "");
		byte[] der = Base64.getDecoder().decode(sanitized.getBytes(StandardCharsets.US_ASCII));
		return KeyFactory.getInstance("EC").generatePrivate(new PKCS8EncodedKeySpec(der));
	}

	private static String blankToNull(String value) {
		if (value == null || value.isBlank()) {
			return null;
		}
		return value.trim();
	}

	private record CachedToken(String jwt, long issuedAtEpochSeconds) {
	}
}
