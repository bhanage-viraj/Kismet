package com.kismet.server.blob;

import java.util.Collection;
import java.util.List;

import org.springframework.data.mongodb.repository.MongoRepository;
import org.springframework.data.mongodb.repository.Query;

public interface EncryptedBlobRepository extends MongoRepository<EncryptedBlobDocument, String> {

	List<EncryptedBlobDocument> findAllByRecipientUserId(String recipientUserId);

	List<EncryptedBlobDocument> findAllByRecipientUserIdAndKind(String recipientUserId, BlobKind kind);

	/**
	 * Deletes are always scoped to the recipient so a caller cannot acknowledge, and
	 * thereby destroy, blobs addressed to someone else by guessing ids.
	 */
	long deleteByIdInAndRecipientUserId(Collection<String> ids, String recipientUserId);

	@Query(delete = true, value = """
			{ $or: [
			  { 'senderUserId': ?0, 'recipientUserId': ?1 },
			  { 'senderUserId': ?1, 'recipientUserId': ?0 }
			] }""")
	long deleteAllBetween(String userId, String otherUserId);
}
