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
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicReference;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import io.jsonwebtoken.Jwts;

/**
 * Signs short-lived APNs provider JWTs (ES256) from one or two Auth Keys (.p8).
 * Supports two Apple teams / bundle IDs so both developer accounts can receive silent pushes.
 */
@Component
public class ApnsAuthTokenProvider {

	private static final Logger log = LoggerFactory.getLogger(ApnsAuthTokenProvider.class);
	private static final long REFRESH_AFTER_SECONDS = 40 * 60;

	private final Map<String, Account> accountsByBundle = new LinkedHashMap<>();

	public ApnsAuthTokenProvider(
			@Value("${kismet.apns.enabled:false}") boolean enabled,
			@Value("${kismet.apns.key-id:}") String keyId,
			@Value("${kismet.apns.team-id:}") String teamId,
			@Value("${kismet.apns.key-path:}") String keyPath,
			@Value("${kismet.apns.key-p8:}") String keyP8,
			@Value("${kismet.apns.bundle-id:}") String bundleId,
			@Value("${kismet.apns.secondary.key-id:}") String secondaryKeyId,
			@Value("${kismet.apns.secondary.team-id:}") String secondaryTeamId,
			@Value("${kismet.apns.secondary.key-path:}") String secondaryKeyPath,
			@Value("${kismet.apns.secondary.key-p8:}") String secondaryKeyP8,
			@Value("${kismet.apns.secondary.bundle-id:}") String secondaryBundleId) {
		if (!enabled) {
			return;
		}
		addAccount("primary", keyId, teamId, keyPath, keyP8, bundleId);
		addAccount("secondary", secondaryKeyId, secondaryTeamId, secondaryKeyPath, secondaryKeyP8, secondaryBundleId);
		if (accountsByBundle.isEmpty()) {
			log.warn("APNs enabled but no complete key/team/bundle credentials — silent push disabled");
		}
	}

	public boolean isEnabled() {
		return !accountsByBundle.isEmpty();
	}

	public List<Account> accounts() {
		return List.copyOf(accountsByBundle.values());
	}

	public Account accountForBundle(String bundleId) {
		if (bundleId == null || bundleId.isBlank()) {
			return null;
		}
		return accountsByBundle.get(normalizeBundle(bundleId));
	}

	private void addAccount(
			String label,
			String keyId,
			String teamId,
			String keyPath,
			String keyP8,
			String bundleId) {
		String kid = blankToNull(keyId);
		String tid = blankToNull(teamId);
		String bid = blankToNull(bundleId);
		try {
			String pem = blankToNull(keyP8);
			if (pem == null && blankToNull(keyPath) != null) {
				pem = Files.readString(Path.of(keyPath));
			}
			if (kid == null || tid == null || bid == null || pem == null) {
				return;
			}
			Account account = new Account(kid, tid, normalizeBundle(bid), loadPrivateKey(pem));
			accountsByBundle.put(account.bundleId(), account);
			log.info("APNs auth configured ({}, team={}, keyId={}, bundle={})",
					label, account.teamId(), account.keyId(), account.bundleId());
		}
		catch (Exception ex) {
			log.warn("Failed to load APNs {} auth key — skipping: {}", label, ex.getMessage());
		}
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

	private static String normalizeBundle(String bundleId) {
		return bundleId.trim();
	}

	public static final class Account {
		private final String keyId;
		private final String teamId;
		private final String bundleId;
		private final PrivateKey privateKey;
		private final AtomicReference<CachedToken> cached = new AtomicReference<>();

		Account(String keyId, String teamId, String bundleId, PrivateKey privateKey) {
			this.keyId = keyId;
			this.teamId = teamId;
			this.bundleId = bundleId;
			this.privateKey = privateKey;
		}

		public String keyId() {
			return keyId;
		}

		public String teamId() {
			return teamId;
		}

		public String bundleId() {
			return bundleId;
		}

		public String currentToken() {
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
	}

	private record CachedToken(String jwt, long issuedAtEpochSeconds) {
	}
}
