package com.kismet.server.config;

import java.util.concurrent.TimeUnit;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.data.domain.Sort;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.data.mongodb.core.index.Index;
import org.springframework.stereotype.Component;

/**
 * Creates indexes explicitly at startup rather than relying on auto-index-creation, which
 * is off by default. The uniqueness and TTL guarantees the friend graph depends on are
 * enforced by these indexes, so they need to exist deterministically.
 */
@Component
public class MongoIndexInitializer implements ApplicationRunner {

	private static final Logger log = LoggerFactory.getLogger(MongoIndexInitializer.class);

	private final MongoTemplate mongoTemplate;

	public MongoIndexInitializer(MongoTemplate mongoTemplate) {
		this.mongoTemplate = mongoTemplate;
	}

	@Override
	public void run(ApplicationArguments args) {
		mongoTemplate.indexOps("users").createIndex(
				new Index().on("appleSub", Sort.Direction.ASC).unique().named("uniq_apple_sub"));

		// Canonical ordering of the two ids is what makes this index able to reject a
		// duplicate pair regardless of which user initiated it.
		mongoTemplate.indexOps("friend_pairs").createIndex(
				new Index()
						.on("userAId", Sort.Direction.ASC)
						.on("userBId", Sort.Direction.ASC)
						.unique()
						.named("uniq_friend_pair"));
		mongoTemplate.indexOps("friend_pairs").createIndex(
				new Index().on("userAId", Sort.Direction.ASC).named("idx_user_a"));
		mongoTemplate.indexOps("friend_pairs").createIndex(
				new Index().on("userBId", Sort.Direction.ASC).named("idx_user_b"));

		mongoTemplate.indexOps("invite_codes").createIndex(
				new Index().on("code", Sort.Direction.ASC).unique().named("uniq_invite_code"));
		mongoTemplate.indexOps("invite_codes").createIndex(
				new Index()
						.on("expiresAt", Sort.Direction.ASC)
						.expire(0, TimeUnit.SECONDS)
						.named("ttl_invite_code"));

		log.info("Mongo indexes ensured for users, friend_pairs, invite_codes");
	}
}
