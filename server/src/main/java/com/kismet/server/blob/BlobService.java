package com.kismet.server.blob;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.mongodb.core.BulkOperations;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.query.Criteria;
import org.springframework.data.mongodb.core.query.Query;
import org.springframework.data.mongodb.core.query.Update;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

import com.kismet.server.blob.dto.BlobUploadResponse;
import com.kismet.server.blob.dto.CreateBlobRequest;
import com.kismet.server.blob.dto.PendingBlob;
import com.kismet.server.common.ApiException;
import com.kismet.server.friend.FriendService;
import com.kismet.server.push.PushWakeService;
import com.kismet.server.realtime.RealtimeEventPublisher;

@Service
public class BlobService {

	private final EncryptedBlobRepository blobRepository;
	private final MongoTemplate mongoTemplate;
	private final FriendService friendService;
	private final RealtimeEventPublisher realtimeEventPublisher;
	private final PushWakeService pushWakeService;
	private final Duration ttl;
	private final int maxCiphertextBytes;
	private final int maxBatchSize;

	public BlobService(
			EncryptedBlobRepository blobRepository,
			MongoTemplate mongoTemplate,
			FriendService friendService,
			RealtimeEventPublisher realtimeEventPublisher,
			PushWakeService pushWakeService,
			@Value("${kismet.blobs.ttl-hours:12}") long ttlHours,
			@Value("${kismet.blobs.max-ciphertext-bytes:4096}") int maxCiphertextBytes,
			@Value("${kismet.blobs.max-batch-size:500}") int maxBatchSize) {
		this.blobRepository = blobRepository;
		this.mongoTemplate = mongoTemplate;
		this.friendService = friendService;
		this.realtimeEventPublisher = realtimeEventPublisher;
		this.pushWakeService = pushWakeService;
		this.ttl = Duration.ofHours(ttlHours);
		this.maxCiphertextBytes = maxCiphertextBytes;
		this.maxBatchSize = maxBatchSize;
	}

	/**
	 * Stores one ciphertext per recipient, replacing that sender's previous blob of the
	 * same kind. Recipients are checked against the sender's active friend list, which is
	 * the only thing standing between this endpoint and an open relay: the server cannot
	 * inspect the payloads, so structural limits are the whole defence.
	 */
	public BlobUploadResponse upload(String senderUserId, List<CreateBlobRequest> requests) {
		if (requests == null || requests.isEmpty()) {
			throw new ApiException(HttpStatus.BAD_REQUEST, "No blobs supplied");
		}
		if (requests.size() > maxBatchSize) {
			throw new ApiException(HttpStatus.PAYLOAD_TOO_LARGE, "Too many blobs in one request");
		}

		Set<String> friendIds = friendService.activeFriendIds(senderUserId);
		Set<String> seen = new LinkedHashSet<>();
		List<EncryptedBlobDocument> blobs = new ArrayList<>(requests.size());
		Instant now = Instant.now();
		Instant expiresAt = now.plus(ttl);

		for (CreateBlobRequest request : requests) {
			BlobKind kind = parseKind(request.kind());
			String recipientUserId = request.recipientUserId();
			if (recipientUserId == null || recipientUserId.isBlank()) {
				throw new ApiException(HttpStatus.BAD_REQUEST, "Recipient is required");
			}
			if (recipientUserId.equals(senderUserId)) {
				throw new ApiException(HttpStatus.BAD_REQUEST, "You cannot send a blob to yourself");
			}
			if (!friendIds.contains(recipientUserId)) {
				throw new ApiException(HttpStatus.FORBIDDEN, "You are not connected to this recipient");
			}
			if (!seen.add(recipientUserId + "|" + kind)) {
				throw new ApiException(HttpStatus.BAD_REQUEST, "Duplicate recipient and kind in one request");
			}
			String ciphertext = request.ciphertext();
			if (ciphertext == null || ciphertext.isBlank()) {
				throw new ApiException(HttpStatus.BAD_REQUEST, "Ciphertext is required");
			}
			if (ciphertext.length() > maxCiphertextBytes) {
				throw new ApiException(HttpStatus.PAYLOAD_TOO_LARGE, "Ciphertext is too large");
			}

			EncryptedBlobDocument blob = new EncryptedBlobDocument();
			blob.setSenderUserId(senderUserId);
			blob.setRecipientUserId(recipientUserId);
			blob.setKind(kind);
			blob.setCiphertext(ciphertext);
			blob.setKeyVersion(request.keyVersion());
			blob.setUpdatedAt(now);
			blob.setExpiresAt(expiresAt);
			blobs.add(blob);
		}

		upsertAll(blobs, now);
		List<String> recipients = blobs.stream()
				.map(EncryptedBlobDocument::getRecipientUserId)
				.distinct()
				.toList();
		realtimeEventPublisher.blobsAvailable(recipients, senderUserId);

		wakeForKind(blobs, BlobKind.LOCATION, senderUserId);
		wakeForKind(blobs, BlobKind.PULSE, senderUserId);
		return new BlobUploadResponse(blobs.size(), expiresAt);
	}

	/** Everything addressed to this user. Ciphertext is returned exactly as it was stored. */
	public List<PendingBlob> pending(String recipientUserId) {
		return blobRepository.findAllByRecipientUserId(recipientUserId).stream()
				.map(blob -> new PendingBlob(
						blob.getId(),
						blob.getSenderUserId(),
						blob.getKind() == null ? null : blob.getKind().name(),
						blob.getCiphertext(),
						blob.getKeyVersion(),
						blob.getUpdatedAt()))
				.toList();
	}

	public long acknowledge(String recipientUserId, List<String> blobIds) {
		if (blobIds == null || blobIds.isEmpty()) {
			throw new ApiException(HttpStatus.BAD_REQUEST, "No blob ids supplied");
		}
		return blobRepository.deleteByIdInAndRecipientUserId(blobIds, recipientUserId);
	}

	public long deleteAllBetween(String userId, String otherUserId) {
		return blobRepository.deleteAllBetween(userId, otherUserId);
	}

	/**
	 * One round trip for the whole batch. Upserting on the unique slot key is what makes a
	 * refresh replace the previous blob instead of colliding with its index.
	 */
	private void upsertAll(List<EncryptedBlobDocument> blobs, Instant now) {
		BulkOperations bulk = mongoTemplate.bulkOps(BulkOperations.BulkMode.UNORDERED, EncryptedBlobDocument.class);
		for (EncryptedBlobDocument blob : blobs) {
			Query slot = Query.query(Criteria
					.where("senderUserId").is(blob.getSenderUserId())
					.and("recipientUserId").is(blob.getRecipientUserId())
					.and("kind").is(blob.getKind()));
			Update update = new Update()
					.set("ciphertext", blob.getCiphertext())
					.set("keyVersion", blob.getKeyVersion())
					.set("updatedAt", blob.getUpdatedAt())
					.set("expiresAt", blob.getExpiresAt())
					.setOnInsert("createdAt", now);
			bulk.upsert(slot, update);
		}
		bulk.execute();
	}

	private void wakeForKind(List<EncryptedBlobDocument> blobs, BlobKind kind, String senderUserId) {
		List<String> recipients = blobs.stream()
				.filter(blob -> blob.getKind() == kind)
				.map(EncryptedBlobDocument::getRecipientUserId)
				.distinct()
				.toList();
		if (!recipients.isEmpty()) {
			pushWakeService.wakeRecipients(recipients, senderUserId, kind.name());
		}
	}

	private static BlobKind parseKind(String kind) {
		if (kind == null || kind.isBlank()) {
			throw new ApiException(HttpStatus.BAD_REQUEST, "Blob kind is required");
		}
		try {
			return BlobKind.valueOf(kind.trim().toUpperCase(Locale.ROOT));
		}
		catch (IllegalArgumentException ex) {
			throw new ApiException(HttpStatus.BAD_REQUEST, "Unknown blob kind: " + kind);
		}
	}
}
