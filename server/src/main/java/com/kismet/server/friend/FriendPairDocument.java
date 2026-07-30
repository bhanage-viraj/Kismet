package com.kismet.server.friend;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;

@Document(collection = "friend_pairs")
public class FriendPairDocument {
	@Id
	private String id;
	private String userAId;
	private String userBId;
	private PairStatus status;
	private ConnectedVia connectedVia;

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
}
