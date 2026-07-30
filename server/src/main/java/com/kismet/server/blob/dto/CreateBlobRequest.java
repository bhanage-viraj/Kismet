package com.kismet.server.blob.dto;

public record CreateBlobRequest(String kind, String ciphertext, String recipientUserId) {
}
