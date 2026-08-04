package com.kismet.server.push;

import java.util.List;

import org.springframework.data.mongodb.repository.MongoRepository;

public interface LiveActivityTokenRepository extends MongoRepository<LiveActivityTokenDocument, String> {
	List<LiveActivityTokenDocument> findAllByMeetupId(String meetupId);

	void deleteByMeetupIdAndUserId(String meetupId, String userId);

	void deleteByPushToken(String pushToken);
}
