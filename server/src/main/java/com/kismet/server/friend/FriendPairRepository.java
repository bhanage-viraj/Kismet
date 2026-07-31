package com.kismet.server.friend;

import java.util.List;
import java.util.Optional;

import org.springframework.data.mongodb.repository.MongoRepository;
import org.springframework.data.mongodb.repository.Query;

public interface FriendPairRepository extends MongoRepository<FriendPairDocument, String> {

	Optional<FriendPairDocument> findByUserAIdAndUserBId(String userAId, String userBId);

	@Query("{ $or: [ { 'userAId': ?0 }, { 'userBId': ?0 } ], 'status': ?1 }")
	List<FriendPairDocument> findAllByUserIdAndStatus(String userId, PairStatus status);

	@Query("{ $or: [ { 'userAId': ?0 }, { 'userBId': ?0 } ] }")
	List<FriendPairDocument> findAllByUserId(String userId);

	@Query(value = "{ $or: [ { 'userAId': ?0 }, { 'userBId': ?0 } ], 'status': ?1 }", count = true)
	long countByUserIdAndStatus(String userId, PairStatus status);
}
