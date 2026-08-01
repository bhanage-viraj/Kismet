package com.kismet.server.config;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.Test;

class InsecureConfigurationGuardTest {

	private static final String REAL_SECRET = "a-real-secret-that-is-at-least-32-chars";

	@Test
	void productionSettingsStartNormally() {
		new InsecureConfigurationGuard(REAL_SECRET, true, false);
	}

	@Test
	void theDevelopmentSigningSecretStopsStartup() {
		IllegalStateException ex = assertThrows(IllegalStateException.class,
				() -> new InsecureConfigurationGuard(
						InsecureConfigurationGuard.DEV_JWT_SECRET, true, false));

		assertTrue(ex.getMessage().contains("JWT_SECRET"), ex.getMessage());
	}

	@Test
	void unverifiedAppleTokensStopStartup() {
		IllegalStateException ex = assertThrows(IllegalStateException.class,
				() -> new InsecureConfigurationGuard(REAL_SECRET, false, false));

		assertTrue(ex.getMessage().contains("APPLE_VERIFY_TOKEN"), ex.getMessage());
	}

	@Test
	void everyProblemIsReportedAtOnceRatherThanOnePerRestart() {
		IllegalStateException ex = assertThrows(IllegalStateException.class,
				() -> new InsecureConfigurationGuard(
						InsecureConfigurationGuard.DEV_JWT_SECRET, false, false));

		assertEquals(2, InsecureConfigurationGuard.findProblems(
				InsecureConfigurationGuard.DEV_JWT_SECRET, false).size());
		assertTrue(ex.getMessage().contains("JWT_SECRET"), ex.getMessage());
		assertTrue(ex.getMessage().contains("APPLE_VERIFY_TOKEN"), ex.getMessage());
	}

	@Test
	void theMessageSaysHowToProceed() {
		IllegalStateException ex = assertThrows(IllegalStateException.class,
				() -> new InsecureConfigurationGuard(REAL_SECRET, false, false));

		assertTrue(ex.getMessage().contains("ALLOW_INSECURE_CONFIG"), ex.getMessage());
	}

	@Test
	void localDevelopmentCanOptInExplicitly() {
		new InsecureConfigurationGuard(InsecureConfigurationGuard.DEV_JWT_SECRET, false, true);
	}
}
