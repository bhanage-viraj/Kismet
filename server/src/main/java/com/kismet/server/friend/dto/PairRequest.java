package com.kismet.server.friend.dto;

import jakarta.validation.constraints.NotBlank;

public record PairRequest(@NotBlank String inviteCode) {
}
