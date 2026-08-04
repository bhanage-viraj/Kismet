package com.kismet.server.friend;

public enum ConnectedVia {
	QR,
	INVITE_CODE,
	/** In-person Multipeer Bump ceremony — mutual consent already happened on-device. */
	BUMP
}
