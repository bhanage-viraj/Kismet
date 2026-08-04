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
public class PushTokenService {

	private final PushTokenRepository repository;
	private final MongoTemplate mongoTemplate;

	public PushTokenService(PushTokenRepository repository, MongoTemplate mongoTemplate) {
		this.repository = repository;
		this.mongoTemplate = mongoTemplate;
	}

	public void register(String userId, String deviceToken, String platform, String bundleId) {
		String token = normalizeToken(deviceToken);
		String normalizedPlatform = normalizePlatform(platform);
		String normalizedBundle = normalizeBundle(bundleId);
		Instant now = Instant.now();

		Query query = Query.query(Criteria
				.where("userId").is(userId)
				.and("deviceToken").is(token));
		Update update = new Update()
				.set("platform", normalizedPlatform)
				.set("updatedAt", now)
				.setOnInsert("createdAt", now)
				.setOnInsert("userId", userId)
				.setOnInsert("deviceToken", token);
		if (normalizedBundle != null) {
			update.set("bundleId", normalizedBundle);
		}
		mongoTemplate.upsert(query, update, PushTokenDocument.class);

		// Same physical device logging into a different account should not keep dual routing.
		Query otherOwners = Query.query(Criteria
				.where("deviceToken").is(token)
				.and("userId").ne(userId));
		mongoTemplate.remove(otherOwners, PushTokenDocument.class);
	}

	public void unregister(String userId, String deviceToken) {
		String token = normalizeToken(deviceToken);
		Query query = Query.query(Criteria
				.where("userId").is(userId)
				.and("deviceToken").is(token));
		mongoTemplate.remove(query, PushTokenDocument.class);
	}

	public List<PushTokenDocument> tokensForUser(String userId) {
		return repository.findAllByUserId(userId);
	}

	public void removeDeviceToken(String deviceToken) {
		repository.deleteByDeviceToken(normalizeToken(deviceToken));
	}

	private static String normalizeToken(String deviceToken) {
		if (deviceToken == null || deviceToken.isBlank()) {
			throw new ApiException(HttpStatus.BAD_REQUEST, "Device token is required");
		}
		String token = deviceToken.trim().replace(" ", "").toLowerCase(Locale.ROOT);
		if (token.length() < 16) {
			throw new ApiException(HttpStatus.BAD_REQUEST, "Device token looks invalid");
		}
		return token;
	}

	private static String normalizePlatform(String platform) {
		if (platform == null || platform.isBlank()) {
			return "ios";
		}
		return platform.trim().toLowerCase(Locale.ROOT);
	}

	private static String normalizeBundle(String bundleId) {
		if (bundleId == null || bundleId.isBlank()) {
			return null;
		}
		return bundleId.trim();
	}
}
