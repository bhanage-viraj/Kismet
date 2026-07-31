package com.kismet.server.availability;

import java.time.Instant;

/**
 * Exactly one of {@code freeUntil} and {@code freeFrom} is set: the first when the user is
 * free now, the second when they are not but will be. Both are null if nothing is known or
 * no free time is scheduled in the week ahead.
 */
public record AvailabilitySnapshot(AvailabilityStatus status, Instant freeUntil, Instant freeFrom) {

	public static AvailabilitySnapshot unknown() {
		return new AvailabilitySnapshot(AvailabilityStatus.UNKNOWN, null, null);
	}

	public static AvailabilitySnapshot free(Instant until) {
		return new AvailabilitySnapshot(AvailabilityStatus.FREE, until, null);
	}

	public static AvailabilitySnapshot busy(Instant nextFreeAt) {
		return new AvailabilitySnapshot(AvailabilityStatus.BUSY, null, nextFreeAt);
	}
}
