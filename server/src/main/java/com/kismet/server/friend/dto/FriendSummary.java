package com.kismet.server.friend.dto;

import java.time.Instant;

/**
 * A friend as the caller sees them. {@code publicKey} is included because the client needs
 * it to seal location blobs for this friend; it is null until they publish one.
 */
public record FriendSummary(
		String pairId,
		String userId,
		String displayName,
		String publicKey,
		int keyVersion,
		String status,
		String connectedVia,
		Instant since,
		boolean initiatedByMe) {
}
