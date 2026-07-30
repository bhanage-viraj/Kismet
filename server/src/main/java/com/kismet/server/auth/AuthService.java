package com.kismet.server.auth;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import com.kismet.server.auth.dto.AppleAuthRequest;
import com.kismet.server.auth.dto.AuthResponse;
import com.kismet.server.common.ApiException;
import com.kismet.server.user.UserDocument;
import com.kismet.server.user.UserService;

import io.jsonwebtoken.Claims;

@Service
public class AuthService {

	private final AppleTokenVerifier appleTokenVerifier;
	private final JwtService jwtService;
	private final UserService userService;

	public AuthService(AppleTokenVerifier appleTokenVerifier, JwtService jwtService, UserService userService) {
		this.appleTokenVerifier = appleTokenVerifier;
		this.jwtService = jwtService;
		this.userService = userService;
	}

	public AuthResponse signInWithApple(AppleAuthRequest request) {
		AppleTokenVerifier.AppleIdentity identity = appleTokenVerifier.verify(request.getIdentityToken());

		String email = StringUtils.hasText(request.getEmail())
				? request.getEmail()
				: identity.email();
		String displayName = buildDisplayName(request.getFullName());

		UserService.FindOrCreateResult result = userService.findOrCreateByAppleSub(
				identity.subject(),
				email,
				displayName);

		UserDocument user = result.user();
		if (request.getInterests() != null && !request.getInterests().isEmpty()) {
			user = userService.updateInterests(user.getId(), request.getInterests());
		}

		return issueTokens(user, result.isNewUser());
	}

	public AuthResponse refresh(String refreshToken) {
		Claims claims;
		try {
			claims = jwtService.parseAndValidate(refreshToken, JwtService.TYPE_REFRESH);
		} catch (Exception ex) {
			throw new ApiException(HttpStatus.UNAUTHORIZED, "Invalid refresh token");
		}

		String userId = claims.getSubject();
		UserDocument user = userService.requireById(userId);
		String hash = sha256(refreshToken);
		if (user.getRefreshTokenHash() == null || !user.getRefreshTokenHash().equals(hash)) {
			throw new ApiException(HttpStatus.UNAUTHORIZED, "Refresh token revoked");
		}

		return issueTokens(user, false);
	}

	public void logout(String userId) {
		UserDocument user = userService.requireById(userId);
		user.setRefreshTokenHash(null);
		userService.save(user);
	}

	private AuthResponse issueTokens(UserDocument user, boolean isNewUser) {
		String accessToken = jwtService.createAccessToken(user.getId());
		String refreshToken = jwtService.createRefreshToken(user.getId());
		user.setRefreshTokenHash(sha256(refreshToken));
		userService.save(user);

		AuthResponse.UserPayload payload = new AuthResponse.UserPayload(
				user.getId(),
				user.getDisplayName(),
				user.getEmail(),
				user.getInterests(),
				isNewUser,
				user.isOnboardingCompleted());

		return new AuthResponse(accessToken, refreshToken, jwtService.getAccessTtlSeconds(), payload);
	}

	private static String buildDisplayName(AppleAuthRequest.FullName fullName) {
		if (fullName == null) {
			return null;
		}
		String given = fullName.getGivenName() != null ? fullName.getGivenName().trim() : "";
		String family = fullName.getFamilyName() != null ? fullName.getFamilyName().trim() : "";
		String combined = (given + " " + family).trim();
		return combined.isEmpty() ? null : combined;
	}

	private static String sha256(String value) {
		try {
			MessageDigest digest = MessageDigest.getInstance("SHA-256");
			byte[] hash = digest.digest(value.getBytes(StandardCharsets.UTF_8));
			return HexFormat.of().formatHex(hash);
		} catch (NoSuchAlgorithmException ex) {
			throw new IllegalStateException("SHA-256 not available", ex);
		}
	}
}
