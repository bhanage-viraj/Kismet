package com.kismet.server.friend.dto;

import java.time.Instant;

public record InviteCodeResponse(String code, String qrPayload, Instant expiresAt) {
}
