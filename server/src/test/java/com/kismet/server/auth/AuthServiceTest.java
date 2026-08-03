package com.kismet.server.auth;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.List;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.kismet.server.auth.dto.AppleAuthRequest;
import com.kismet.server.auth.dto.AuthResponse;
import com.kismet.server.user.UserDocument;
import com.kismet.server.user.UserService;

@ExtendWith(MockitoExtension.class)
class AuthServiceTest {

	@Mock
	private UserService userService;

	private JwtService jwtService;
	private AppleTokenVerifier appleTokenVerifier;
	private AuthService authService;

	@BeforeEach
	void setUp() {
		jwtService = new JwtService("dev-only-change-me-use-at-least-32-chars!!", 3600, 2592000);
		appleTokenVerifier = new AppleTokenVerifier("bhanageviraj.indeKismet", false);
		authService = new AuthService(appleTokenVerifier, jwtService, userService);
	}

	@Test
	void signInWithAppleCreatesSessionForNewUser() {
		UserDocument created = new UserDocument();
		created.setId("user-1");
		created.setAppleSub("apple-sub-1");
		created.setEmail("ada@example.com");
		created.setDisplayName("Ada Lovelace");
		created.setOnboardingCompleted(false);

		when(userService.findOrCreateByAppleSub(eq("apple-sub-1"), eq("ada@example.com"), eq("Ada Lovelace")))
				.thenReturn(new UserService.FindOrCreateResult(created, true));
		when(userService.updateInterests(eq("user-1"), eq(List.of("coffee", "coding"))))
				.thenAnswer(invocation -> {
					created.setInterests(invocation.getArgument(1));
					return created;
				});
		when(userService.save(any(UserDocument.class))).thenAnswer(invocation -> invocation.getArgument(0));

		AppleAuthRequest request = new AppleAuthRequest();
		request.setIdentityToken(fakeAppleToken("apple-sub-1", "bhanageviraj.indeKismet", "ada@example.com"));
		AppleAuthRequest.FullName name = new AppleAuthRequest.FullName();
		name.setGivenName("Ada");
		name.setFamilyName("Lovelace");
		request.setFullName(name);
		request.setEmail("ada@example.com");
		request.setInterests(List.of("coffee", "coding"));

		AuthResponse response = authService.signInWithApple(request);

		assertNotNull(response.getAccessToken());
		assertNotNull(response.getRefreshToken());
		assertEquals(3600, response.getExpiresIn());
		assertEquals("user-1", response.getUser().getId());
		assertEquals(List.of("coffee", "coding"), response.getUser().getInterests());
		assertEquals(true, response.getUser().getIsNewUser());
		verify(userService).updateInterests("user-1", List.of("coffee", "coding"));

		ArgumentCaptor<UserDocument> captor = ArgumentCaptor.forClass(UserDocument.class);
		verify(userService).save(captor.capture());
		assertNotNull(captor.getValue().getRefreshTokenHash());
	}

	@Test
	void refreshRotatesTokensWhenHashMatches() {
		String refresh = jwtService.createRefreshToken("user-1");
		UserDocument user = new UserDocument();
		user.setId("user-1");
		user.setDisplayName("Ada");
		user.setOnboardingCompleted(true);
		user.setRefreshTokenHash(sha256(refresh));

		when(userService.requireById("user-1")).thenReturn(user);
		when(userService.save(any(UserDocument.class))).thenAnswer(invocation -> invocation.getArgument(0));

		AuthResponse response = authService.refresh(refresh);
		assertNotNull(response.getAccessToken());
		assertEquals("user-1", response.getUser().getId());
		assertEquals(true, response.getUser().isOnboardingCompleted());
	}

	private static String fakeAppleToken(String sub, String aud, String email) {
		String header = base64Url("{\"alg\":\"none\",\"typ\":\"JWT\"}");
		String payload = base64Url("{\"sub\":\"" + sub + "\",\"aud\":\"" + aud + "\",\"email\":\"" + email
				+ "\",\"exp\":4102444800}");
		return header + "." + payload + ".sig";
	}

	private static String base64Url(String value) {
		return Base64.getUrlEncoder().withoutPadding().encodeToString(value.getBytes(StandardCharsets.UTF_8));
	}

	private static String sha256(String value) {
		try {
			var digest = java.security.MessageDigest.getInstance("SHA-256");
			return java.util.HexFormat.of().formatHex(digest.digest(value.getBytes(StandardCharsets.UTF_8)));
		} catch (Exception ex) {
			throw new IllegalStateException(ex);
		}
	}
}
