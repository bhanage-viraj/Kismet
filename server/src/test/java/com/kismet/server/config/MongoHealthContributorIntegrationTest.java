package com.kismet.server.config;

import static org.junit.jupiter.api.Assertions.assertInstanceOf;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.health.registry.HealthContributorRegistry;

import com.kismet.server.AbstractIntegrationTest;

/**
 * The scoped indicator displaces the auto-configured one purely through its bean name.
 * That coupling is invisible from the class itself and a Boot upgrade could quietly undo
 * it, which would bring back a health check that reports DOWN against Atlas, so what
 * actually answers for Mongo is asserted rather than assumed.
 */
class MongoHealthContributorIntegrationTest extends AbstractIntegrationTest {

	@Autowired
	private HealthContributorRegistry healthContributors;

	@Test
	void theScopedIndicatorIsWhatReportsMongoHealth() {
		assertInstanceOf(MongoDatabaseHealthIndicator.class,
				healthContributors.getContributor("mongo"));
	}
}
