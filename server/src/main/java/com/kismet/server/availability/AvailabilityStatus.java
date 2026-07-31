package com.kismet.server.availability;

public enum AvailabilityStatus {
	FREE,
	BUSY,

	/** No timezone or no availability configured, so the question cannot be answered. */
	UNKNOWN
}
