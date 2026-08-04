package com.kismet.server.push;

import java.time.Instant;
import java.util.List;
import java.util.Locale;

import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.query.Criteria;
import org.springframework.data.mongodb.core.query.Query;
import org.springframework.data.mongodb.core.query.Update;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

import com.kismet.server.common.ApiException;

@Service
public class LiveActivityTokenService {

	private final LiveActivityTokenRepository repository;
	private final MongoTemplate mongoTemplate;

	public LiveActivityTokenService(LiveActivityTokenRepository repository, MongoTemplate mongoTemplate) {
		this.repository = repository;
		this.mongoTemplate = mongoTemplate;
	}

	public void register(String userId, String meetupId, String pushToken, String bundleId) {
		String meetup = require(meetupId, "Meetup id is required");
		String token = normalizeToken(pushToken);
		String bundle = normalizeBundle(bundleId);
		Instant now = Instant.now();

		Query query = Query.query(Criteria
				.where("meetupId").is(meetup)
				.and("userId").is(userId));
		Update update = new Update()
				.set("pushToken", token)
				.set("updatedAt", now)
				.setOnInsert("createdAt", now)
				.setOnInsert("meetupId", meetup)
				.setOnInsert("userId", userId);
		if (bundle != null) {
			update.set("bundleId", bundle);
		}
		mongoTemplate.upsert(query, update, LiveActivityTokenDocument.class);

		// Same ActivityKit token should only route to one user.
		Query otherOwners = Query.query(Criteria
				.where("pushToken").is(token)
				.and("userId").ne(userId));
		mongoTemplate.remove(otherOwners, LiveActivityTokenDocument.class);
	}

	public List<LiveActivityTokenDocument> tokensForMeetup(String meetupId) {
		return repository.findAllByMeetupId(require(meetupId, "Meetup id is required"));
	}

	public void removeToken(String pushToken) {
		repository.deleteByPushToken(normalizeToken(pushToken));
	}

	private static String require(String value, String message) {
		if (value == null || value.isBlank()) {
			throw new ApiException(HttpStatus.BAD_REQUEST, message);
		}
		return value.trim();
	}

	private static String normalizeToken(String pushToken) {
		if (pushToken == null || pushToken.isBlank()) {
			throw new ApiException(HttpStatus.BAD_REQUEST, "Push token is required");
		}
		String token = pushToken.trim().replace(" ", "").toLowerCase(Locale.ROOT);
		if (token.length() < 16) {
			throw new ApiException(HttpStatus.BAD_REQUEST, "Live Activity push token looks invalid");
		}
		return token;
	}

	private static String normalizeBundle(String bundleId) {
		if (bundleId == null || bundleId.isBlank()) {
			return null;
		}
		return bundleId.trim();
	}
}
