package com.kismet.server.friend.dto;

import java.util.List;

public record FriendListResponse(List<FriendSummary> friends) {
}
