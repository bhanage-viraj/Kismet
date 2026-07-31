package com.kismet.server.config;

import org.springframework.messaging.Message;
import org.springframework.messaging.MessageChannel;
import org.springframework.messaging.simp.stomp.StompCommand;
import org.springframework.messaging.simp.stomp.StompHeaderAccessor;
import org.springframework.messaging.support.ChannelInterceptor;
import org.springframework.messaging.support.MessageHeaderAccessor;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.stereotype.Component;

import com.kismet.server.auth.JwtService;

import io.jsonwebtoken.Claims;

/**
 * Authenticates STOMP sessions from the CONNECT frame.
 * <p>
 * The WebSocket handshake is a plain HTTP upgrade that carries no bearer header, so the
 * HTTP filter chain cannot authenticate it and {@code /ws/**} has to be permitted there.
 * This interceptor is what actually establishes identity, and rejecting CONNECT here is
 * what keeps the endpoint from being open.
 */
@Component
public class StompAuthChannelInterceptor implements ChannelInterceptor {

	private final JwtService jwtService;

	public StompAuthChannelInterceptor(JwtService jwtService) {
		this.jwtService = jwtService;
	}

	@Override
	public Message<?> preSend(Message<?> message, MessageChannel channel) {
		StompHeaderAccessor accessor =
				MessageHeaderAccessor.getAccessor(message, StompHeaderAccessor.class);
		if (accessor == null || !StompCommand.CONNECT.equals(accessor.getCommand())) {
			return message;
		}

		String header = accessor.getFirstNativeHeader("Authorization");
		if (header == null || !header.startsWith("Bearer ")) {
			throw new IllegalArgumentException("Missing bearer token on STOMP CONNECT");
		}

		Claims claims;
		try {
			claims = jwtService.parseAndValidate(header.substring(7), JwtService.TYPE_ACCESS);
		}
		catch (Exception ex) {
			throw new IllegalArgumentException("Invalid bearer token on STOMP CONNECT");
		}

		AuthUser principal = new AuthUser(claims.getSubject());
		// The principal name becomes the user destination key, so publishing to
		// /user/{userId}/queue/... reaches exactly this session.
		accessor.setUser(new UsernamePasswordAuthenticationToken(
				principal, null, principal.getAuthorities()));
		return message;
	}
}
