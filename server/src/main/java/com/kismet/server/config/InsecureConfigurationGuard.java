package com.kismet.server.config;

import java.util.ArrayList;
import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * Refuses to start when the settings that gate authentication are still at their
 * development values.
 * <p>
 * Both of these fail open rather than closed, which is what makes them worth a startup
 * check: a missing environment variable produces a server that looks healthy and serves
 * traffic while accepting forged identities. Local work opts in explicitly via
 * {@code kismet.security.allow-insecure-config}, so the unsafe path is never the one you
 * get by forgetting something.
 */
@Component
public class InsecureConfigurationGuard {

	/** The value shipped in application.yml and .env.example. */
	static final String DEV_JWT_SECRET = "dev-only-change-me-use-at-least-32-chars!!";

	private static final Logger log = LoggerFactory.getLogger(InsecureConfigurationGuard.class);

	public InsecureConfigurationGuard(
			@Value("${kismet.jwt.secret}") String jwtSecret,
			@Value("${kismet.apple.verify-token}") boolean verifyAppleToken,
			@Value("${kismet.security.allow-insecure-config:false}") boolean allowInsecureConfig) {
		List<String> problems = findProblems(jwtSecret, verifyAppleToken);
		if (problems.isEmpty()) {
			return;
		}
		if (!allowInsecureConfig) {
			throw new IllegalStateException(describe(problems));
		}
		for (String problem : problems) {
			log.warn("Insecure configuration allowed for local use: {}", problem);
		}
	}

	static List<String> findProblems(String jwtSecret, boolean verifyAppleToken) {
		List<String> problems = new ArrayList<>();
		if (DEV_JWT_SECRET.equals(jwtSecret)) {
			problems.add("JWT_SECRET is still the development default, so anyone with a copy of "
					+ "the source can mint access tokens for any account.");
		}
		if (!verifyAppleToken) {
			problems.add("APPLE_VERIFY_TOKEN is false, so identity tokens are decoded without "
					+ "checking Apple's signature and any account can be impersonated.");
		}
		return problems;
	}

	private static String describe(List<String> problems) {
		StringBuilder message = new StringBuilder("Refusing to start with insecure configuration:");
		for (String problem : problems) {
			message.append("\n  - ").append(problem);
		}
		return message.append("\nSet real values for these, or set ALLOW_INSECURE_CONFIG=true ")
				.append("to accept them for local development.")
				.toString();
	}
}
