package com.kismet.server.auth;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Date;
import java.util.UUID;

import javax.crypto.SecretKey;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;

@Service
public class JwtService {

	public static final String CLAIM_TYPE = "type";
	public static final String TYPE_ACCESS = "access";
	public static final String TYPE_REFRESH = "refresh";

	private final SecretKey secretKey;
	private final long accessTtlSeconds;
	private final long refreshTtlSeconds;

	public JwtService(
			@Value("${kismet.jwt.secret}") String secret,
			@Value("${kismet.jwt.access-ttl-seconds}") long accessTtlSeconds,
			@Value("${kismet.jwt.refresh-ttl-seconds}") long refreshTtlSeconds) {
		byte[] keyBytes = secret.getBytes(StandardCharsets.UTF_8);
		if (keyBytes.length < 32) {
			throw new IllegalStateException("JWT_SECRET must be at least 32 characters");
		}
		this.secretKey = Keys.hmacShaKeyFor(keyBytes);
		this.accessTtlSeconds = accessTtlSeconds;
		this.refreshTtlSeconds = refreshTtlSeconds;
	}

	public String createAccessToken(String userId) {
		return createToken(userId, TYPE_ACCESS, accessTtlSeconds);
	}

	public String createRefreshToken(String userId) {
		return createToken(userId, TYPE_REFRESH, refreshTtlSeconds);
	}

	public long getAccessTtlSeconds() {
		return accessTtlSeconds;
	}

	public Claims parseAndValidate(String token, String expectedType) {
		Claims claims = Jwts.parser()
				.verifyWith(secretKey)
				.build()
				.parseSignedClaims(token)
				.getPayload();

		String type = claims.get(CLAIM_TYPE, String.class);
		if (!expectedType.equals(type)) {
			throw new IllegalArgumentException("Unexpected token type");
		}
		return claims;
	}

	private String createToken(String userId, String type, long ttlSeconds) {
		Instant now = Instant.now();
		return Jwts.builder()
				.subject(userId)
				// Timestamps are second-granular, so without a unique id two tokens minted
				// for the same user in the same second are byte-identical. Refresh rotation
				// compares hashes, and would then leave the previous token still valid.
				.id(UUID.randomUUID().toString())
				.claim(CLAIM_TYPE, type)
				.issuedAt(Date.from(now))
				.expiration(Date.from(now.plusSeconds(ttlSeconds)))
				.signWith(secretKey)
				.compact();
	}
}
