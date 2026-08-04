package com.kismet.server.blob;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Instant;
import java.util.List;
import java.util.Set;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.mongodb.core.BulkOperations;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.http.HttpStatus;

import com.kismet.server.blob.dto.BlobUploadResponse;
import com.kismet.server.blob.dto.CreateBlobRequest;
import com.kismet.server.blob.dto.PendingBlob;
import com.kismet.server.common.ApiException;
import com.kismet.server.friend.FriendService;
import com.kismet.server.push.PushWakeService;
import com.kismet.server.realtime.RealtimeEventPublisher;

@ExtendWith(MockitoExtension.class)
class BlobServiceTest {

	@Mock
	private EncryptedBlobRepository blobRepository;

	@Mock
	private MongoTemplate mongoTemplate;

	@Mock
	private BulkOperations bulkOperations;

	@Mock
	private FriendService friendService;

	@Mock
	private RealtimeEventPublisher realtimeEventPublisher;

	@Mock
	private PushWakeService pushWakeService;

	private BlobService blobService;

	@BeforeEach
	void setUp() {
		blobService = new BlobService(
				blobRepository, mongoTemplate, friendService, realtimeEventPublisher, pushWakeService, 12, 4096, 500);
	}

	@Test
	void uploadStoresOneBlobPerFriend() {
		givenFriends("user-1", "friend-a", "friend-b");
		givenBulkOps();

		BlobUploadResponse response = blobService.upload("user-1", List.of(
				new CreateBlobRequest("friend-a", "LOCATION", "cipher-a", 1),
				new CreateBlobRequest("friend-b", "LOCATION", "cipher-b", 2)));

		assertEquals(2, response.accepted());
		verify(bulkOperations, org.mockito.Mockito.times(2)).upsert(any(), any());
		verify(bulkOperations).execute();
		verify(realtimeEventPublisher).blobsAvailable(List.of("friend-a", "friend-b"), "user-1");
		verify(pushWakeService).wakeRecipients(List.of("friend-a", "friend-b"), "user-1", "LOCATION");
	}

	@Test
	void uploadWakesRecipientsForPulseBlobs() {
		givenFriends("user-1", "friend-a");
		givenBulkOps();

		BlobUploadResponse response = blobService.upload("user-1", List.of(
				new CreateBlobRequest("friend-a", "PULSE", "cipher-pulse", 1)));

		assertEquals(1, response.accepted());
		verify(pushWakeService).wakeRecipients(List.of("friend-a"), "user-1", "PULSE");
		verify(pushWakeService, never()).wakeRecipients(any(), any(), org.mockito.ArgumentMatchers.eq("LOCATION"));
	}

	@Test
	void arejectedUploadNotifiesNobody() {
		givenFriends("user-1", "friend-a");

		assertThrows(ApiException.class, () -> blobService.upload("user-1", List.of(
				new CreateBlobRequest("stranger", "LOCATION", "cipher", 1))));

		verify(realtimeEventPublisher, never()).blobsAvailable(any(), any());
	}

	@Test
	void uploadRejectsARecipientWhoIsNotAFriend() {
		givenFriends("user-1", "friend-a");

		ApiException ex = assertThrows(ApiException.class, () -> blobService.upload("user-1", List.of(
				new CreateBlobRequest("stranger", "LOCATION", "cipher", 1))));

		assertEquals(HttpStatus.FORBIDDEN, ex.getStatus());
		verify(mongoTemplate, never()).bulkOps(any(), any(Class.class));
	}

	@Test
	void uploadRejectsARecipientWhoseFriendshipWasRevoked() {
		// activeFriendIds excludes revoked pairs, so a stale client keeps getting 403.
		givenFriends("user-1");

		ApiException ex = assertThrows(ApiException.class, () -> blobService.upload("user-1", List.of(
				new CreateBlobRequest("ex-friend", "LOCATION", "cipher", 1))));

		assertEquals(HttpStatus.FORBIDDEN, ex.getStatus());
	}

	@Test
	void uploadRejectsSelfAddressedBlobs() {
		givenFriends("user-1", "friend-a");

		ApiException ex = assertThrows(ApiException.class, () -> blobService.upload("user-1", List.of(
				new CreateBlobRequest("user-1", "LOCATION", "cipher", 1))));

		assertEquals(HttpStatus.BAD_REQUEST, ex.getStatus());
	}

	@Test
	void uploadRejectsDuplicateSlotsInOneRequest() {
		givenFriends("user-1", "friend-a");

		ApiException ex = assertThrows(ApiException.class, () -> blobService.upload("user-1", List.of(
				new CreateBlobRequest("friend-a", "LOCATION", "cipher-1", 1),
				new CreateBlobRequest("friend-a", "LOCATION", "cipher-2", 1))));

		assertEquals(HttpStatus.BAD_REQUEST, ex.getStatus());
	}

	@Test
	void uploadAllowsDifferentKindsToTheSameFriend() {
		givenFriends("user-1", "friend-a");
		givenBulkOps();

		BlobUploadResponse response = blobService.upload("user-1", List.of(
				new CreateBlobRequest("friend-a", "LOCATION", "cipher-1", 1),
				new CreateBlobRequest("friend-a", "AVAILABILITY", "cipher-2", 1)));

		assertEquals(2, response.accepted());
	}

	@Test
	void uploadRejectsOversizedCiphertext() {
		blobService = new BlobService(
				blobRepository, mongoTemplate, friendService, realtimeEventPublisher, pushWakeService, 12, 8, 500);
		givenFriends("user-1", "friend-a");

		ApiException ex = assertThrows(ApiException.class, () -> blobService.upload("user-1", List.of(
				new CreateBlobRequest("friend-a", "LOCATION", "way-too-long-ciphertext", 1))));

		assertEquals(HttpStatus.PAYLOAD_TOO_LARGE, ex.getStatus());
	}

	@Test
	void uploadRejectsAnOversizedBatch() {
		blobService = new BlobService(
				blobRepository, mongoTemplate, friendService, realtimeEventPublisher, pushWakeService, 12, 4096, 1);

		ApiException ex = assertThrows(ApiException.class, () -> blobService.upload("user-1", List.of(
				new CreateBlobRequest("friend-a", "LOCATION", "cipher-1", 1),
				new CreateBlobRequest("friend-b", "LOCATION", "cipher-2", 1))));

		assertEquals(HttpStatus.PAYLOAD_TOO_LARGE, ex.getStatus());
	}

	@Test
	void uploadRejectsAnUnknownKind() {
		givenFriends("user-1", "friend-a");

		ApiException ex = assertThrows(ApiException.class, () -> blobService.upload("user-1", List.of(
				new CreateBlobRequest("friend-a", "TELEPATHY", "cipher", 1))));

		assertEquals(HttpStatus.BAD_REQUEST, ex.getStatus());
	}

	@Test
	void uploadAcceptsLowercaseKinds() {
		givenFriends("user-1", "friend-a");
		givenBulkOps();

		assertEquals(1, blobService.upload("user-1", List.of(
				new CreateBlobRequest("friend-a", "location", "cipher", 1))).accepted());
	}

	@Test
	void pendingReturnsCiphertextAndSender() {
		EncryptedBlobDocument blob = new EncryptedBlobDocument();
		blob.setId("blob-1");
		blob.setSenderUserId("friend-a");
		blob.setRecipientUserId("user-1");
		blob.setKind(BlobKind.LOCATION);
		blob.setCiphertext("sealed-payload");
		blob.setKeyVersion(4);
		blob.setUpdatedAt(Instant.parse("2026-07-31T06:40:00Z"));
		when(blobRepository.findAllByRecipientUserId("user-1")).thenReturn(List.of(blob));

		List<PendingBlob> pending = blobService.pending("user-1");

		assertEquals(1, pending.size());
		assertEquals("sealed-payload", pending.get(0).ciphertext());
		assertEquals("friend-a", pending.get(0).senderUserId());
		assertEquals("LOCATION", pending.get(0).kind());
		assertEquals(4, pending.get(0).keyVersion());
	}

	@Test
	void acknowledgeOnlyDeletesBlobsAddressedToTheCaller() {
		when(blobRepository.deleteByIdInAndRecipientUserId(List.of("blob-1"), "user-1")).thenReturn(1L);

		assertEquals(1L, blobService.acknowledge("user-1", List.of("blob-1")));
		verify(blobRepository).deleteByIdInAndRecipientUserId(List.of("blob-1"), "user-1");
	}

	@Test
	void acknowledgeRejectsAnEmptyList() {
		ApiException ex = assertThrows(ApiException.class,
				() -> blobService.acknowledge("user-1", List.of()));

		assertEquals(HttpStatus.BAD_REQUEST, ex.getStatus());
	}

	private void givenFriends(String userId, String... friendIds) {
		when(friendService.activeFriendIds(userId)).thenReturn(Set.of(friendIds));
	}

	private void givenBulkOps() {
		when(mongoTemplate.bulkOps(any(), any(Class.class))).thenReturn(bulkOperations);
	}
}
