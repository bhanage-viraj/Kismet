package com.kismet.server.blob.dto;

import java.time.Instant;

public record BlobUploadResponse(int accepted, Instant expiresAt) {
}
