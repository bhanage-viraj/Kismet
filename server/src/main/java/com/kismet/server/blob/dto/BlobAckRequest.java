package com.kismet.server.blob.dto;

import java.util.List;

import jakarta.validation.constraints.NotEmpty;

public record BlobAckRequest(@NotEmpty List<String> blobIds) {
}
