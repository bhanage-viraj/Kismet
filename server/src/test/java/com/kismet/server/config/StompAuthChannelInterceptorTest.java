package com.kismet.server.config;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.security.Principal;

import org.junit.jupiter.api.Test;
import org.springframework.messaging.Message;
import org.springframework.messaging.simp.stomp.StompCommand;
import org.springframework.messaging.simp.stomp.StompHeaderAccessor;
import org.springframework.messaging.support.MessageBuilder;

import com.kismet.server.auth.JwtService;

class StompAuthChannelInterceptorTest {

	private final JwtService jwtService =
			new JwtService("dev-only-change-me-use-at-least-32-chars!!", 3600, 2592000);
	private final StompAuthChannelInterceptor interceptor = new StompAuthChannelInterceptor(jwtService);

	@Test
	void aValidAccessTokenBecomesTheSessionPrincipal() {
		Message<byte[]> message = connect("Bearer " + jwtService.createAccessToken("user-1"));

		Message<?> result = interceptor.preSend(message, null);

		Principal principal = StompHeaderAccessor.wrap(result).getUser();
		assertNotNull(principal);
		// The principal name is the user destination key, so /user/{id}/queue/map routes here.
		assertEquals("user-1", principal.getName());
	}

	@Test
	void connectWithoutATokenIsRejected() {
		assertThrows(IllegalArgumentException.class, () -> interceptor.preSend(connect(null), null));
	}

	@Test
	void connectWithAMalformedHeaderIsRejected() {
		assertThrows(IllegalArgumentException.class,
				() -> interceptor.preSend(connect("Basic abc123"), null));
	}

	@Test
	void connectWithAGarbageTokenIsRejected() {
		assertThrows(IllegalArgumentException.class,
				() -> interceptor.preSend(connect("Bearer not-a-jwt"), null));
	}

	@Test
	void connectWithATokenSignedByADifferentSecretIsRejected() {
		JwtService attacker = new JwtService("another-secret-that-is-long-enough-here!!", 3600, 2592000);

		assertThrows(IllegalArgumentException.class,
				() -> interceptor.preSend(connect("Bearer " + attacker.createAccessToken("user-1")), null));
	}

	@Test
	void aRefreshTokenCannotBeUsedToOpenASocket() {
		assertThrows(IllegalArgumentException.class,
				() -> interceptor.preSend(
						connect("Bearer " + jwtService.createRefreshToken("user-1")), null));
	}

	@Test
	void nonConnectFramesPassThroughUntouched() {
		// Only CONNECT establishes identity; later frames reuse the session principal.
		StompHeaderAccessor accessor = StompHeaderAccessor.create(StompCommand.SEND);
		Message<byte[]> message = MessageBuilder.createMessage(new byte[0], accessor.getMessageHeaders());

		assertSame(message, interceptor.preSend(message, null));
		assertNull(StompHeaderAccessor.wrap(message).getUser());
	}

	/**
	 * Mirrors how Spring's STOMP handler builds inbound frames: the accessor is left
	 * mutable so interceptors can attach a principal. Reading the headers off an immutable
	 * accessor is what makes {@code setUser} fail.
	 */
	private static Message<byte[]> connect(String authorization) {
		StompHeaderAccessor accessor = StompHeaderAccessor.create(StompCommand.CONNECT);
		accessor.setLeaveMutable(true);
		if (authorization != null) {
			accessor.setNativeHeader("Authorization", authorization);
		}
		return MessageBuilder.createMessage(new byte[0], accessor.getMessageHeaders());
	}
}
