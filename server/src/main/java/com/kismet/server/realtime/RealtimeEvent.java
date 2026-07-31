package com.kismet.server.realtime;

import java.time.Instant;

/**
 * Notification only. A blob event says that ciphertext is waiting and who from, never the
 * ciphertext itself, so the socket stays cheap and the client decides when to fetch and
 * decrypt.
 */
public record RealtimeEvent(String type, String userId, Instant at) {

	public static final String BLOB_AVAILABLE = "blob.available";
	public static final String FRIEND_PAIR_CREATED = "friend.pair.created";
	public static final String FRIEND_PAIR_REVOKED = "friend.pair.revoked";

	public static RealtimeEvent of(String type, String userId) {
		return new RealtimeEvent(type, userId, Instant.now());
	}
}
