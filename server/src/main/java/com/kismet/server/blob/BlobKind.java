package com.kismet.server.blob;

public enum BlobKind {
	AVAILABILITY,
	LOCATION,
	MESSAGE,
	/** Opt-in sealed interest ids for on-device intersection (interestMatch). */
	INTEREST_MATCH
}
