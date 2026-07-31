package com.kismet.server;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.Instant;
import java.util.HashSet;
import java.util.Set;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DuplicateKeyException;

import com.kismet.server.blob.BlobKind;
import com.kismet.server.blob.EncryptedBlobDocument;
import com.kismet.server.blob.EncryptedBlobRepository;
import com.kismet.server.friend.ConnectedVia;
import com.kismet.server.friend.FriendPairDocument;
import com.kismet.server.friend.FriendPairRepository;
import com.kismet.server.friend.PairStatus;

/**
 * Asserts the constraints that only exist in the database. These are the guarantees the
 * service layer assumes but cannot enforce on its own.
 */
class MongoIndexIntegrationTest extends AbstractIntegrationTest {

	@Autowired
	private FriendPairRepository friendPairRepository;

	@Autowired
	private EncryptedBlobRepository blobRepository;

	@Test
	void indexesAreCreatedAtStartup() {
		assertTrue(indexNames("friend_pairs").contains("uniq_friend_pair"));
		assertTrue(indexNames("invite_codes").contains("uniq_invite_code"));
		assertTrue(indexNames("invite_codes").contains("ttl_invite_code"));
		assertTrue(indexNames("encrypted_blobs").contains("uniq_blob_slot"));
		assertTrue(indexNames("encrypted_blobs").contains("ttl_blob"));
		assertTrue(indexNames("users").contains("uniq_apple_sub"));
	}

	@Test
	void aDuplicateFriendPairIsRejectedByTheIndex() {
		friendPairRepository.save(pair("user-1", "user-9"));

		assertThrows(DuplicateKeyException.class, () -> friendPairRepository.save(pair("user-1", "user-9")));
	}

	@Test
	void canonicalOrderingIsWhatMakesTheIndexCatchReversedPairs() {
		// Both users create the pair from their own side; canonical ordering means the two
		// rows collide rather than coexisting as separate friendships.
		friendPairRepository.save(FriendPairDocument.create(
				"user-1", "user-9", ConnectedVia.INVITE_CODE, PairStatus.ACTIVE, Instant.now()));

		FriendPairDocument reversed = FriendPairDocument.create(
				"user-9", "user-1", ConnectedVia.INVITE_CODE, PairStatus.ACTIVE, Instant.now());
		assertEquals("user-1", reversed.getUserAId());

		assertThrows(DuplicateKeyException.class, () -> friendPairRepository.save(reversed));
	}

	@Test
	void aSecondBlobForTheSameSlotIsRejected() {
		blobRepository.save(blob("sender-1", "recipient-1", BlobKind.LOCATION, "cipher-1"));

		assertThrows(DuplicateKeyException.class,
				() -> blobRepository.save(blob("sender-1", "recipient-1", BlobKind.LOCATION, "cipher-2")));
	}

	@Test
	void differentKindsAndRecipientsGetTheirOwnSlots() {
		blobRepository.save(blob("sender-1", "recipient-1", BlobKind.LOCATION, "cipher-1"));
		blobRepository.save(blob("sender-1", "recipient-1", BlobKind.AVAILABILITY, "cipher-2"));
		blobRepository.save(blob("sender-1", "recipient-2", BlobKind.LOCATION, "cipher-3"));

		assertEquals(3, blobRepository.count());
	}

	@Test
	void deletingBetweenTwoUsersClearsBothDirections() {
		blobRepository.save(blob("user-1", "user-9", BlobKind.LOCATION, "a-to-b"));
		blobRepository.save(blob("user-9", "user-1", BlobKind.LOCATION, "b-to-a"));
		blobRepository.save(blob("user-1", "other", BlobKind.LOCATION, "unrelated"));

		assertEquals(2L, blobRepository.deleteAllBetween("user-1", "user-9"));
		assertEquals(1, blobRepository.count());
	}

	@Test
	void acknowledgingCannotDeleteAnotherUsersBlobs() {
		EncryptedBlobDocument mine = blobRepository.save(
				blob("sender-1", "recipient-1", BlobKind.LOCATION, "mine"));
		EncryptedBlobDocument theirs = blobRepository.save(
				blob("sender-1", "recipient-2", BlobKind.LOCATION, "theirs"));

		// recipient-1 guesses the other id; the recipient filter must protect it.
		long deleted = blobRepository.deleteByIdInAndRecipientUserId(
				java.util.List.of(mine.getId(), theirs.getId()), "recipient-1");

		assertEquals(1L, deleted);
		assertTrue(blobRepository.findById(theirs.getId()).isPresent());
	}

	private Set<String> indexNames(String collection) {
		Set<String> names = new HashSet<>();
		mongoTemplate.indexOps(collection).getIndexInfo().forEach(index -> names.add(index.getName()));
		return names;
	}

	private static FriendPairDocument pair(String a, String b) {
		return FriendPairDocument.create(a, b, ConnectedVia.INVITE_CODE, PairStatus.ACTIVE, Instant.now());
	}

	private static EncryptedBlobDocument blob(String sender, String recipient, BlobKind kind, String cipher) {
		EncryptedBlobDocument blob = new EncryptedBlobDocument();
		blob.setSenderUserId(sender);
		blob.setRecipientUserId(recipient);
		blob.setKind(kind);
		blob.setCiphertext(cipher);
		blob.setKeyVersion(1);
		blob.setCreatedAt(Instant.now());
		blob.setUpdatedAt(Instant.now());
		blob.setExpiresAt(Instant.now().plusSeconds(3600));
		return blob;
	}
}
