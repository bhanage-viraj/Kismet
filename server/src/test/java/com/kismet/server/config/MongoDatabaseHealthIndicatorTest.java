package com.kismet.server.config;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import org.bson.Document;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.boot.health.contributor.Health;
import org.springframework.boot.health.contributor.Status;
import org.springframework.data.mongodb.MongoDatabaseFactory;

import com.mongodb.MongoException;
import com.mongodb.client.MongoDatabase;

@ExtendWith(MockitoExtension.class)
class MongoDatabaseHealthIndicatorTest {

	@Mock
	private MongoDatabaseFactory databaseFactory;

	@Mock
	private MongoDatabase database;

	@InjectMocks
	private MongoDatabaseHealthIndicator indicator;

	@Test
	void aReachableDatabaseReportsUp() {
		when(databaseFactory.getMongoDatabase()).thenReturn(database);
		when(database.getName()).thenReturn("kismet");
		when(database.runCommand(any(Document.class)))
				.thenReturn(new Document("maxWireVersion", 25));

		Health health = indicator.health();

		assertEquals(Status.UP, health.getStatus());
		assertEquals("kismet", health.getDetails().get("database"));
		assertEquals(25, health.getDetails().get("maxWireVersion"));
	}

	@Test
	void onlyTheConfiguredDatabaseIsPinged() {
		when(databaseFactory.getMongoDatabase()).thenReturn(database);
		when(database.runCommand(any(Document.class)))
				.thenReturn(new Document("maxWireVersion", 25));

		indicator.health();

		// Atlas refuses commands on `local`, so a check that walks every visible
		// database can never pass there.
		verify(database).runCommand(new Document("hello", 1));
	}

	@Test
	void anUnreachableDatabaseReportsDown() {
		when(databaseFactory.getMongoDatabase()).thenReturn(database);
		when(database.runCommand(any(Document.class)))
				.thenThrow(new MongoException("connection refused"));

		Health health = indicator.health();

		assertEquals(Status.DOWN, health.getStatus());
	}
}
