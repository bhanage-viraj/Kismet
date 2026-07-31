package com.kismet.server.blob;

import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import com.kismet.server.friend.FriendRevokedEvent;

@ExtendWith(MockitoExtension.class)
class FriendRevokedBlobCleanupTest {

	@Mock
	private BlobService blobService;

	@InjectMocks
	private FriendRevokedBlobCleanup cleanup;

	@Test
	void revokingDeletesCiphertextInBothDirections() {
		when(blobService.deleteAllBetween("user-1", "friend-a")).thenReturn(2L);

		cleanup.onFriendRevoked(new FriendRevokedEvent("user-1", "friend-a"));

		// deleteAllBetween matches either direction, so one call covers both mailboxes.
		verify(blobService).deleteAllBetween("user-1", "friend-a");
	}
}
