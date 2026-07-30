package com.kismet.server.user;

import java.util.Optional;

import org.springframework.data.mongodb.repository.MongoRepository;

public interface UserRepository extends MongoRepository<UserDocument, String> {

	Optional<UserDocument> findByAppleSub(String appleSub);
}
