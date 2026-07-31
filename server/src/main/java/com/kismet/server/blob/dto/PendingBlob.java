package com.kismet.server.blob.dto;

import java.time.Instant;

public record PendingBlob(
		String id,
		String senderUserId,
		String kind,
		String ciphertext,
		int keyVersion,
		Instant updatedAt) {
}
