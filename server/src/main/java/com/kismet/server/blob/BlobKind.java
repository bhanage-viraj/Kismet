package com.kismet.server.blob;

public enum BlobKind {
	AVAILABILITY,
	LOCATION,
	MESSAGE,
	/** Short-lived meetup invite ciphertext; client seals expiresAt inside the payload. */
	PULSE,
	/** Opt-in sealed interest ids for on-device intersection (interestMatch). */
	INTEREST_MATCH,
	/** Pulse accept → peer starts a shared Live Activity (ciphertext only). */
	MEETUP
}
