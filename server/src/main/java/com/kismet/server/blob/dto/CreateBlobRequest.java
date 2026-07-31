package com.kismet.server.blob.dto;

import jakarta.validation.constraints.NotBlank;

/** {@code keyVersion} is the recipient key version the ciphertext was sealed to. */
public record CreateBlobRequest(
		@NotBlank String recipientUserId,
		@NotBlank String kind,
		@NotBlank String ciphertext,
		int keyVersion) {
}
