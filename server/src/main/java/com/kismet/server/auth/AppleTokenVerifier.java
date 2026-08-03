package com.kismet.server.auth;

import java.math.BigInteger;
import java.security.KeyFactory;
import java.security.interfaces.RSAPublicKey;
import java.security.spec.RSAPublicKeySpec;
import java.time.Instant;
import java.util.Arrays;
import java.util.Base64;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.stream.Collectors;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import com.kismet.server.common.ApiException;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;

@Component
public class AppleTokenVerifier {

	private static final String APPLE_ISS = "https://appleid.apple.com";
	private static final String APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys";

	/** Allowed Apple JWT `aud` values (bundle IDs). Comma-separated in config. */
	private final Set<String> clientIds;
	private final boolean verifyToken;
	private final RestClient restClient;
	private final Map<String, RSAPublicKey> keyCache = new ConcurrentHashMap<>();

	public AppleTokenVerifier(
			@Value("${kismet.apple.client-id}") String clientId,
			@Value("${kismet.apple.verify-token}") boolean verifyToken) {
		this.clientIds = parseClientIds(clientId);
		if (this.clientIds.isEmpty()) {
			throw new IllegalStateException("APPLE_CLIENT_ID must list at least one bundle ID");
		}
		this.verifyToken = verifyToken;
		this.restClient = RestClient.create();
	}

	static Set<String> parseClientIds(String raw) {
		if (raw == null || raw.isBlank()) {
			return Set.of();
		}
		return Arrays.stream(raw.split(","))
				.map(String::trim)
				.filter(s -> !s.isEmpty())
				.collect(Collectors.toCollection(LinkedHashSet::new));
	}

	public AppleIdentity verify(String identityToken) {
		if (identityToken == null || identityToken.isBlank()) {
			throw new ApiException(HttpStatus.BAD_REQUEST, "identityToken is required");
		}

		try {
			if (!verifyToken) {
				return decodeUnverified(identityToken);
			}
			return verifySigned(identityToken);
		} catch (ApiException ex) {
			throw ex;
		} catch (Exception ex) {
			throw new ApiException(HttpStatus.UNAUTHORIZED, "Invalid Apple identity token");
		}
	}

	private AppleIdentity verifySigned(String identityToken) throws Exception {
		String kid = readHeaderKid(identityToken);
		RSAPublicKey publicKey = resolveKey(kid);

		// Don't pin a single audience — teammate builds use a different bundle ID.
		// Signature + issuer are verified; aud is checked against the allowlist.
		Claims claims = Jwts.parser()
				.verifyWith(publicKey)
				.requireIssuer(APPLE_ISS)
				.build()
				.parseSignedClaims(identityToken)
				.getPayload();

		requireAllowedAudience(claims.getAudience());
		return fromClaims(claims);
	}

	@SuppressWarnings("unchecked")
	private AppleIdentity decodeUnverified(String identityToken) {
		Map<String, Object> payload = decodeJwtPart(identityToken, 1);

		String sub = (String) payload.get("sub");
		if (sub == null || sub.isBlank()) {
			throw new ApiException(HttpStatus.UNAUTHORIZED, "Apple token missing sub");
		}

		requireAllowedAudience(payload.get("aud"));

		Object expObj = payload.get("exp");
		if (expObj instanceof Number exp && Instant.ofEpochSecond(exp.longValue()).isBefore(Instant.now())) {
			throw new ApiException(HttpStatus.UNAUTHORIZED, "Apple token expired");
		}

		String email = payload.get("email") instanceof String e ? e : null;
		return new AppleIdentity(sub, email);
	}

	private void requireAllowedAudience(Object aud) {
		boolean ok = false;
		if (aud instanceof String audStr) {
			ok = clientIds.contains(audStr);
		} else if (aud instanceof Set<?> audSet) {
			ok = audSet.stream().anyMatch(v -> v instanceof String s && clientIds.contains(s));
		} else if (aud instanceof List<?> audList) {
			ok = audList.stream().anyMatch(v -> v instanceof String s && clientIds.contains(s));
		}
		if (!ok) {
			throw new ApiException(HttpStatus.UNAUTHORIZED, "Apple token audience mismatch");
		}
	}

	private AppleIdentity fromClaims(Claims claims) {
		String sub = claims.getSubject();
		if (sub == null || sub.isBlank()) {
			throw new ApiException(HttpStatus.UNAUTHORIZED, "Apple token missing sub");
		}
		String email = claims.get("email", String.class);
		return new AppleIdentity(sub, email);
	}

	private String readHeaderKid(String identityToken) {
		Map<String, Object> header = decodeJwtPart(identityToken, 0);
		Object kid = header.get("kid");
		if (!(kid instanceof String kidStr) || kidStr.isBlank()) {
			throw new ApiException(HttpStatus.UNAUTHORIZED, "Apple token missing kid");
		}
		return kidStr;
	}

	private RSAPublicKey resolveKey(String kid) throws Exception {
		RSAPublicKey cached = keyCache.get(kid);
		if (cached != null) {
			return cached;
		}
		refreshKeys();
		RSAPublicKey key = keyCache.get(kid);
		if (key == null) {
			throw new ApiException(HttpStatus.UNAUTHORIZED, "Unknown Apple signing key");
		}
		return key;
	}

	@SuppressWarnings("unchecked")
	private void refreshKeys() {
		Map<String, Object> jwks = restClient.get()
				.uri(APPLE_JWKS_URL)
				.retrieve()
				.body(new ParameterizedTypeReference<Map<String, Object>>() {
				});
		if (jwks == null) {
			return;
		}
		List<Map<String, Object>> keys = (List<Map<String, Object>>) jwks.get("keys");
		if (keys == null) {
			return;
		}
		for (Map<String, Object> key : keys) {
			String kid = (String) key.get("kid");
			String n = (String) key.get("n");
			String e = (String) key.get("e");
			if (kid == null || n == null || e == null) {
				continue;
			}
			try {
				keyCache.put(kid, toPublicKey(n, e));
			} catch (Exception ignored) {
				// skip malformed key
			}
		}
	}

	private static Map<String, Object> decodeJwtPart(String identityToken, int index) {
		String[] parts = identityToken.split("\\.");
		if (parts.length < 2 || index >= parts.length) {
			throw new ApiException(HttpStatus.UNAUTHORIZED, "Malformed identity token");
		}
		byte[] decoded = Base64.getUrlDecoder().decode(parts[index]);
		return parseJsonObject(decoded);
	}

	@SuppressWarnings("unchecked")
	private static Map<String, Object> parseJsonObject(byte[] json) {
		try {
			tools.jackson.databind.json.JsonMapper mapper = tools.jackson.databind.json.JsonMapper.builder().build();
			return mapper.readValue(json, Map.class);
		} catch (Exception ex) {
			throw new ApiException(HttpStatus.UNAUTHORIZED, "Malformed identity token");
		}
	}

	private static RSAPublicKey toPublicKey(String n, String e) throws Exception {
		byte[] modulus = Base64.getUrlDecoder().decode(n);
		byte[] exponent = Base64.getUrlDecoder().decode(e);
		RSAPublicKeySpec spec = new RSAPublicKeySpec(new BigInteger(1, modulus), new BigInteger(1, exponent));
		return (RSAPublicKey) KeyFactory.getInstance("RSA").generatePublic(spec);
	}

	public record AppleIdentity(String subject, String email) {
	}
}
