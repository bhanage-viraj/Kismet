package com.kismet.server.push;

import java.util.List;

import org.springframework.data.mongodb.repository.MongoRepository;

public interface PushTokenRepository extends MongoRepository<PushTokenDocument, String> {
	List<PushTokenDocument> findAllByUserId(String userId);

	void deleteByDeviceToken(String deviceToken);

	void deleteAllByUserId(String userId);
}
