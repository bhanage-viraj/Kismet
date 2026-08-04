package com.kismet.server.blob;

public enum BlobKind {
	AVAILABILITY,
	LOCATION,
	MESSAGE,
	/** Short-lived meetup invite ciphertext; client seals expiresAt inside the payload. */
	PULSE
}
