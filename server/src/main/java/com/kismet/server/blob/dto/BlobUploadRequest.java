package com.kismet.server.blob.dto;

import java.util.List;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotEmpty;

/**
 * Uploads are batched because one location refresh produces a separate ciphertext per
 * friend, and sending those as N round trips from a phone on cellular is not viable.
 */
public record BlobUploadRequest(@NotEmpty @Valid List<CreateBlobRequest> blobs) {
}
