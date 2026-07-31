package com.kismet.server.blob;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

import com.kismet.server.friend.FriendRevokedEvent;

/**
 * Removes ciphertext in both directions the moment a friendship ends. Waiting for the TTL
 * would leave an ex-friend's device able to fetch and decrypt a location it should no
 * longer have access to for up to another 12 hours.
 */
@Component
public class FriendRevokedBlobCleanup {

	private static final Logger log = LoggerFactory.getLogger(FriendRevokedBlobCleanup.class);

	private final BlobService blobService;

	public FriendRevokedBlobCleanup(BlobService blobService) {
		this.blobService = blobService;
	}

	@EventListener
	public void onFriendRevoked(FriendRevokedEvent event) {
		long deleted = blobService.deleteAllBetween(event.userId(), event.friendUserId());
		log.info("Deleted {} blobs after {} revoked {}", deleted, event.userId(), event.friendUserId());
	}
}
