package com.kismet.server.config;

import org.bson.Document;
import org.springframework.boot.health.contributor.AbstractHealthIndicator;
import org.springframework.boot.health.contributor.Health;
import org.springframework.data.mongodb.MongoDatabaseFactory;
import org.springframework.stereotype.Component;

import com.mongodb.client.MongoDatabase;

/**
 * Reports Mongo health by pinging the one database this service uses.
 * <p>
 * Spring Boot's own indicator lists every database the credentials can see and runs
 * {@code hello} against each one. On Atlas that list includes {@code local}, which no
 * user is permitted to run commands against, so the check reports DOWN while the
 * application is perfectly healthy. Pinging the configured database instead still
 * catches the failures that matter here - the cluster being unreachable, credentials
 * being rotated - without asserting access the service never needs.
 * <p>
 * The bean name is what replaces the auto-configured indicator, and it also keeps this
 * reporting under the existing {@code mongo} key in {@code /actuator/health}.
 */
@Component("mongoHealthIndicator")
public class MongoDatabaseHealthIndicator extends AbstractHealthIndicator {

	private static final Document HELLO_COMMAND = new Document("hello", 1);

	private final MongoDatabaseFactory databaseFactory;

	public MongoDatabaseHealthIndicator(MongoDatabaseFactory databaseFactory) {
		super("MongoDB health check failed");
		this.databaseFactory = databaseFactory;
	}

	@Override
	protected void doHealthCheck(Health.Builder builder) {
		MongoDatabase database = databaseFactory.getMongoDatabase();
		Document result = database.runCommand(HELLO_COMMAND);

		builder.up()
				.withDetail("database", database.getName())
				.withDetail("maxWireVersion", result.getInteger("maxWireVersion"));
	}
}
