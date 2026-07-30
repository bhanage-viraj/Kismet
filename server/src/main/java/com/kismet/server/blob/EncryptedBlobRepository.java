package com.kismet.server.blob;

import org.springframework.data.mongodb.repository.MongoRepository;

public interface EncryptedBlobRepository extends MongoRepository<EncryptedBlobDocument, String> {
}
