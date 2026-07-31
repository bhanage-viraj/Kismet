package com.kismet.server.blob.dto;

import java.util.List;

public record PendingBlobsResponse(List<PendingBlob> blobs) {
}
