package com.kismet.server.friend;

/** Published when a code is redeemed. {@code userId} is the redeemer. */
public record FriendPairedEvent(String userId, String friendUserId) {
}
