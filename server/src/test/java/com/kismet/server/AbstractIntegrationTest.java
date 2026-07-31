package com.kismet.server;

import org.junit.jupiter.api.BeforeEach;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.mongodb.MongoDBContainer;

/**
 * Boots the application against a real MongoDB. Unique indexes, upsert-on-slot and TTL are
 * database behaviour, so mocking the repository would assert nothing about them.
 */
@SpringBootTest
@AutoConfigureMockMvc
public abstract class AbstractIntegrationTest {

	/**
	 * Started once for the whole JVM and deliberately never stopped: the JUnit
	 * {@code @Testcontainers} lifecycle would shut this down after the first test class,
	 * leaving later classes pointing at a dead port. Testcontainers' reaper removes it
	 * when the JVM exits.
	 */
	static final MongoDBContainer MONGO = new MongoDBContainer("mongo:7");

	static {
		MONGO.start();
	}

	@Autowired
	protected MongoTemplate mongoTemplate;

	@DynamicPropertySource
	static void mongoProperties(DynamicPropertyRegistry registry) {
		// Set explicitly rather than relying on a service connection, because this
		// application reads spring.mongodb.uri.
		registry.add("spring.mongodb.uri", () -> MONGO.getConnectionString() + "/kismet-test");
	}

	/** Each test starts from an empty database, but keeps the indexes created at startup. */
	@BeforeEach
	void clearCollections() {
		for (String collection : mongoTemplate.getCollectionNames()) {
			if (!collection.startsWith("system.")) {
				mongoTemplate.getCollection(collection).deleteMany(new org.bson.Document());
			}
		}
	}
}
