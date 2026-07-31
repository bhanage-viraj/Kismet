package com.kismet.server.friend;

import java.time.Instant;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;

/**
 * A short-lived code that lets someone pair with {@code ownerUserId}. Codes expire via a
 * TTL index on {@code expiresAt}; a permanent per-user code would be a permanent liability
 * if it ever leaked.
 */
@Document(collection = "invite_codes")
public class InviteCodeDocument {
	@Id
	private String id;
	private String code;
	private String ownerUserId;
	private int usesRemaining;
	private Instant createdAt;
	private Instant expiresAt;

	public String getId() { return id; }
	public void setId(String id) { this.id = id; }
	public String getCode() { return code; }
	public void setCode(String code) { this.code = code; }
	public String getOwnerUserId() { return ownerUserId; }
	public void setOwnerUserId(String ownerUserId) { this.ownerUserId = ownerUserId; }
	public int getUsesRemaining() { return usesRemaining; }
	public void setUsesRemaining(int usesRemaining) { this.usesRemaining = usesRemaining; }
	public Instant getCreatedAt() { return createdAt; }
	public void setCreatedAt(Instant createdAt) { this.createdAt = createdAt; }
	public Instant getExpiresAt() { return expiresAt; }
	public void setExpiresAt(Instant expiresAt) { this.expiresAt = expiresAt; }
}
