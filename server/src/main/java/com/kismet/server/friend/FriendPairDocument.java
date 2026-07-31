package com.kismet.server.friend;

import java.time.Instant;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;

/**
 * One row per friendship. {@code userAId} and {@code userBId} are stored in canonical
 * order (lexicographically smaller id always in {@code userAId}) so the unique compound
 * index rejects duplicates no matter which side initiated the pairing.
 */
@Document(collection = "friend_pairs")
public class FriendPairDocument {
	@Id
	private String id;
	private String userAId;
	private String userBId;
	private PairStatus status;
	private ConnectedVia connectedVia;
	private String requestedByUserId;
	private Instant createdAt;
	private Instant acceptedAt;
	private Instant updatedAt;

	public static FriendPairDocument create(
			String requesterUserId,
			String targetUserId,
			ConnectedVia connectedVia,
			PairStatus status,
			Instant now) {
		FriendPairDocument pair = new FriendPairDocument();
		pair.setUserAId(canonicalA(requesterUserId, targetUserId));
		pair.setUserBId(canonicalB(requesterUserId, targetUserId));
		pair.setStatus(status);
		pair.setConnectedVia(connectedVia);
		pair.setRequestedByUserId(requesterUserId);
		pair.setCreatedAt(now);
		pair.setUpdatedAt(now);
		if (status == PairStatus.ACTIVE) {
			pair.setAcceptedAt(now);
		}
		return pair;
	}

	public static String canonicalA(String first, String second) {
		return first.compareTo(second) <= 0 ? first : second;
	}

	public static String canonicalB(String first, String second) {
		return first.compareTo(second) <= 0 ? second : first;
	}

	/** Returns the id of whichever member of this pair is not {@code userId}. */
	public String otherUserId(String userId) {
		return userAId.equals(userId) ? userBId : userAId;
	}

	public boolean involves(String userId) {
		return userAId.equals(userId) || userBId.equals(userId);
	}

	public String getId() { return id; }
	public void setId(String id) { this.id = id; }
	public String getUserAId() { return userAId; }
	public void setUserAId(String userAId) { this.userAId = userAId; }
	public String getUserBId() { return userBId; }
	public void setUserBId(String userBId) { this.userBId = userBId; }
	public PairStatus getStatus() { return status; }
	public void setStatus(PairStatus status) { this.status = status; }
	public ConnectedVia getConnectedVia() { return connectedVia; }
	public void setConnectedVia(ConnectedVia connectedVia) { this.connectedVia = connectedVia; }
	public String getRequestedByUserId() { return requestedByUserId; }
	public void setRequestedByUserId(String requestedByUserId) { this.requestedByUserId = requestedByUserId; }
	public Instant getCreatedAt() { return createdAt; }
	public void setCreatedAt(Instant createdAt) { this.createdAt = createdAt; }
	public Instant getAcceptedAt() { return acceptedAt; }
	public void setAcceptedAt(Instant acceptedAt) { this.acceptedAt = acceptedAt; }
	public Instant getUpdatedAt() { return updatedAt; }
	public void setUpdatedAt(Instant updatedAt) { this.updatedAt = updatedAt; }
}
