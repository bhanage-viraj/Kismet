package com.kismet.server.friend;

/** Published when a friendship becomes ACTIVE (invite redeem or Bump). {@code userId} is the initiator. */
public record FriendPairedEvent(String userId, String friendUserId) {
}
