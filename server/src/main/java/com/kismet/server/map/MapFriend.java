package com.kismet.server.map;

import java.time.Instant;
import java.util.List;

import com.kismet.server.availability.AvailabilitySnapshot;

/**
 * A friend as the map sees them. Deliberately carries no coordinates: the server only
 * reports that a location blob exists and when it was last refreshed, and the client joins
 * that against the ciphertext it decrypts locally.
 */
public record MapFriend(
		String userId,
		String displayName,
		AvailabilitySnapshot availability,
		List<String> sharedInterests,
		boolean hasLocationBlob,
		Instant blobUpdatedAt) {
}
