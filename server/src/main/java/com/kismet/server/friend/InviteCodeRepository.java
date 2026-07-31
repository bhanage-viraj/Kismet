package com.kismet.server.friend;

import java.util.Optional;

import org.springframework.data.mongodb.repository.MongoRepository;

public interface InviteCodeRepository extends MongoRepository<InviteCodeDocument, String> {

	Optional<InviteCodeDocument> findByCode(String code);

	void deleteByOwnerUserId(String ownerUserId);
}
