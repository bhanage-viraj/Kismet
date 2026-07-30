package com.kismet.server.friend;

import org.springframework.data.mongodb.repository.MongoRepository;

public interface FriendPairRepository extends MongoRepository<FriendPairDocument, String> {
}
