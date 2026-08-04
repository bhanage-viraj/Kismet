package com.kismet.server.friend.dto;

import jakarta.validation.constraints.NotBlank;

/**
 * Body for {@code POST /friends/pair}. Consent already happened on-device via Bump;
 * this only persists the friendship. {@code peerPublicKey} is optional and, when
 * present, is checked against the peer's published key for a TOFU mismatch.
 */
public record BumpPairRequest(
		@NotBlank String peerUserId,
		String peerPublicKey) {
}
