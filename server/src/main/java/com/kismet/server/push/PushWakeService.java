package com.kismet.server.push;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Sends content-available silent pushes so a recipient can wake, fetch LOCATION blobs,
 * and compute proximity on-device. No-ops when APNs credentials are absent.
 */
@Service
public class PushWakeService {

	private static final Logger log = LoggerFactory.getLogger(PushWakeService.class);
	private static final long COOLDOWN_MILLIS = 30_000L;

	private final PushTokenService pushTokenService;
	private final ApnsAuthTokenProvider authTokenProvider;
	private final ObjectMapper objectMapper;
	private final HttpClient httpClient;
	private final ExecutorService executor;
	private final String bundleId;
	private final String host;
	private final Map<String, Long> lastWakeByUser = new ConcurrentHashMap<>();

	public PushWakeService(
			PushTokenService pushTokenService,
			ApnsAuthTokenProvider authTokenProvider,
			ObjectMapper objectMapper,
			@Value("${kismet.apns.bundle-id:}") String bundleId,
			@Value("${kismet.apns.production:false}") boolean production) {
		this.pushTokenService = pushTokenService;
		this.authTokenProvider = authTokenProvider;
		this.objectMapper = objectMapper;
		this.bundleId = bundleId == null ? "" : bundleId.trim();
		this.host = production
				? "https://api.push.apple.com"
				: "https://api.sandbox.push.apple.com";
		this.httpClient = HttpClient.newBuilder()
				.version(HttpClient.Version.HTTP_2)
				.connectTimeout(Duration.ofSeconds(10))
				.build();
		this.executor = Executors.newVirtualThreadPerTaskExecutor();
	}

	/**
	 * Fire-and-forget wake. Safe to call from the blob upload path — never blocks the HTTP response.
	 */
	public void wakeRecipientsForLocationBlob(Iterable<String> recipientUserIds, String senderUserId) {
		if (!authTokenProvider.isEnabled() || bundleId.isBlank()) {
			return;
		}
		for (String recipientUserId : recipientUserIds) {
			if (recipientUserId == null || recipientUserId.isBlank()) {
				continue;
			}
			if (!shouldWake(recipientUserId)) {
				continue;
			}
			executor.execute(() -> sendToUser(recipientUserId, senderUserId));
		}
	}

	private boolean shouldWake(String userId) {
		long now = System.currentTimeMillis();
		Long previous = lastWakeByUser.put(userId, now);
		return previous == null || now - previous >= COOLDOWN_MILLIS;
	}

	private void sendToUser(String recipientUserId, String senderUserId) {
		var tokens = pushTokenService.tokensForUser(recipientUserId);
		if (tokens.isEmpty()) {
			return;
		}
		for (PushTokenDocument token : tokens) {
			try {
				sendSilent(token.getDeviceToken(), senderUserId);
			}
			catch (Exception ex) {
				log.debug("Silent push failed for user {}: {}", recipientUserId, ex.getMessage());
			}
		}
	}

	private void sendSilent(String deviceToken, String senderUserId) throws Exception {
		String body = objectMapper.writeValueAsString(Map.of(
				"aps", Map.of("content-available", 1),
				"type", "blob.available",
				"kind", "LOCATION",
				"senderUserId", senderUserId));

		HttpRequest request = HttpRequest.newBuilder()
				.uri(URI.create(host + "/3/device/" + deviceToken))
				.timeout(Duration.ofSeconds(15))
				.header("authorization", "bearer " + authTokenProvider.currentToken())
				.header("apns-topic", bundleId)
				.header("apns-push-type", "background")
				.header("apns-priority", "5")
				.header("apns-expiration", "0")
				.header("content-type", "application/json")
				.POST(HttpRequest.BodyPublishers.ofString(body))
				.build();

		HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
		int status = response.statusCode();
		if (status == 200) {
			return;
		}
		if (status == 410 || status == 400) {
			// Unregistered / BadDeviceToken — drop so we stop retrying dead tokens.
			pushTokenService.removeDeviceToken(deviceToken);
			log.info("Removed stale APNs token (status={})", status);
			return;
		}
		log.warn("APNs silent push status={} body={}", status, response.body());
	}
}
