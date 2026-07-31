package com.kismet.server.friend;

/**
 * Published when a friendship ends. Delivered as an event rather than a direct call
 * because {@code BlobService} already depends on {@code FriendService} to authorise
 * uploads, so calling back the other way would create a dependency cycle.
 */
public record FriendRevokedEvent(String userId, String friendUserId) {
}
