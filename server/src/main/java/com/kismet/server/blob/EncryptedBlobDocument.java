package com.kismet.server.blob;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;

@Document(collection = "encrypted_blobs")
public class EncryptedBlobDocument {
	@Id
	private String id;
	private String senderUserId;
	private String recipientUserId;
	private BlobKind kind;
	private String ciphertext;

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
}
