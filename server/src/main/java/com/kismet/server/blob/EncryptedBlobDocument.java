package com.kismet.server.blob;

import java.time.Instant;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;

/**
 * Opaque ciphertext relayed from one user to one friend. The server never decrypts these
 * and holds no key material.
 * <p>
 * For {@link BlobKind#LOCATION} this collection behaves as a mailbox with a single slot
 * per (sender, recipient, kind) rather than an append log: a unique index on that triple
 * means each new position overwrites the previous one in place. A client refreshing every
 * minute for 100 friends would otherwise write ~144k documents a day.
 */
@Document(collection = "encrypted_blobs")
public class EncryptedBlobDocument {
	@Id
	private String id;
	private String senderUserId;
	private String recipientUserId;
	private BlobKind kind;
	private String ciphertext;

	/** Recipient key version this was sealed to; lets the client skip undecryptable blobs. */
	private int keyVersion;

	private Instant createdAt;
	private Instant updatedAt;
	private Instant expiresAt;

	public String getId() { return id; }
	public void setId(String id) { this.id = id; }
	public String getSenderUserId() { return senderUserId; }
	public void setSenderUserId(String senderUserId) { this.senderUserId = senderUserId; }
	public String getRecipientUserId() { return recipientUserId; }
	public void setRecipientUserId(String recipientUserId) { this.recipientUserId = recipientUserId; }
	public BlobKind getKind() { return kind; }
	public void setKind(BlobKind kind) { this.kind = kind; }
	public String getCiphertext() { return ciphertext; }
	public void setCiphertext(String ciphertext) { this.ciphertext = ciphertext; }
	public int getKeyVersion() { return keyVersion; }
	public void setKeyVersion(int keyVersion) { this.keyVersion = keyVersion; }
	public Instant getCreatedAt() { return createdAt; }
	public void setCreatedAt(Instant createdAt) { this.createdAt = createdAt; }
	public Instant getUpdatedAt() { return updatedAt; }
	public void setUpdatedAt(Instant updatedAt) { this.updatedAt = updatedAt; }
	public Instant getExpiresAt() { return expiresAt; }
	public void setExpiresAt(Instant expiresAt) { this.expiresAt = expiresAt; }
}
