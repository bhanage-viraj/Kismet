package com.kismet.server.push;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

/**
 * Sends content-available silent pushes so a recipient can wake, fetch LOCATION blobs,
 * and compute proximity on-device. No-ops when APNs credentials are absent.
 * Picks the APNs auth key / topic from the token's registered bundle ID when present.
 */
@Service
public class PushWakeService {

	private static final Logger log = LoggerFactory.getLogger(PushWakeService.class);
	private static final long COOLDOWN_MILLIS = 30_000L;

	private final PushTokenService pushTokenService;
	private final ApnsAuthTokenProvider authTokenProvider;
	private final HttpClient httpClient;
	private final ExecutorService executor;
	private final String host;
	private final Map<String, Long> lastWakeByUser = new ConcurrentHashMap<>();

	public PushWakeService(
			PushTokenService pushTokenService,
			ApnsAuthTokenProvider authTokenProvider,
			@Value("${kismet.apns.production:false}") boolean production) {
		this.pushTokenService = pushTokenService;
		this.authTokenProvider = authTokenProvider;
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
		wakeRecipients(recipientUserIds, senderUserId, "LOCATION");
	}

	/**
	 * Fire-and-forget wake for any blob kind (LOCATION, PULSE, …).
	 */
	public void wakeRecipients(Iterable<String> recipientUserIds, String senderUserId, String kind) {
		if (!authTokenProvider.isEnabled()) {
			return;
		}
		String wakeKind = (kind == null || kind.isBlank()) ? "LOCATION" : kind.trim().toUpperCase(Locale.ROOT);
		for (String recipientUserId : recipientUserIds) {
			if (recipientUserId == null || recipientUserId.isBlank()) {
				continue;
			}
			if (!shouldWake(recipientUserId)) {
				continue;
			}
			executor.execute(() -> sendToUser(recipientUserId, senderUserId, wakeKind));
		}
	}

	private boolean shouldWake(String userId) {
		long now = System.currentTimeMillis();
		Long previous = lastWakeByUser.put(userId, now);
		return previous == null || now - previous >= COOLDOWN_MILLIS;
	}

	private void sendToUser(String recipientUserId, String senderUserId, String kind) {
		var tokens = pushTokenService.tokensForUser(recipientUserId);
		if (tokens.isEmpty()) {
			return;
		}
		for (PushTokenDocument token : tokens) {
			try {
				sendSilent(token, senderUserId, kind);
			}
			catch (Exception ex) {
				log.debug("Silent push failed for user {}: {}", recipientUserId, ex.getMessage());
			}
		}
	}

	private void sendSilent(PushTokenDocument token, String senderUserId, String kind) throws Exception {
		List<ApnsAuthTokenProvider.Account> candidates = candidatesFor(token.getBundleId());
		if (candidates.isEmpty()) {
			return;
		}

		String body = "{\"aps\":{\"content-available\":1},\"type\":\"blob.available\","
				+ "\"kind\":\"" + jsonEscape(kind) + "\",\"senderUserId\":\""
				+ jsonEscape(senderUserId) + "\"}";

		Exception lastError = null;
		for (ApnsAuthTokenProvider.Account account : candidates) {
			try {
				int status = postSilent(token.getDeviceToken(), account, body);
				if (status == 200) {
					return;
				}
				if (status == 410) {
					pushTokenService.removeDeviceToken(token.getDeviceToken());
					log.info("Removed stale APNs token (status=410, bundle={})", account.bundleId());
					return;
				}
				if (status == 400) {
					// Wrong topic for this account — try the other; BadDeviceToken drops the row.
					continue;
				}
				log.warn("APNs silent push status={} bundle={}", status, account.bundleId());
			}
			catch (Exception ex) {
				lastError = ex;
			}
		}
		if (lastError != null) {
			throw lastError;
		}
	}

	private List<ApnsAuthTokenProvider.Account> candidatesFor(String bundleId) {
		ApnsAuthTokenProvider.Account exact = authTokenProvider.accountForBundle(bundleId);
		if (exact != null) {
			return List.of(exact);
		}
		// Legacy tokens without bundleId: try every configured Apple team.
		return authTokenProvider.accounts();
	}

	private int postSilent(String deviceToken, ApnsAuthTokenProvider.Account account, String body)
			throws Exception {
		HttpRequest request = HttpRequest.newBuilder()
				.uri(URI.create(host + "/3/device/" + deviceToken))
				.timeout(Duration.ofSeconds(15))
				.header("authorization", "bearer " + account.currentToken())
				.header("apns-topic", account.bundleId())
				.header("apns-push-type", "background")
				.header("apns-priority", "5")
				.header("apns-expiration", "0")
				.header("content-type", "application/json")
				.POST(HttpRequest.BodyPublishers.ofString(body))
				.build();

		HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
		int status = response.statusCode();
		if (status == 400) {
			String responseBody = response.body() == null ? "" : response.body().toLowerCase(Locale.ROOT);
			if (responseBody.contains("baddevicetoken") || responseBody.contains("unregistered")) {
				pushTokenService.removeDeviceToken(deviceToken);
				log.info("Removed stale APNs token (status=400, bundle={})", account.bundleId());
			}
			else {
				log.debug("APNs 400 for bundle={} body={}", account.bundleId(), response.body());
			}
		}
		else if (status != 200 && status != 410) {
			log.warn("APNs silent push status={} body={}", status, response.body());
		}
		return status;
	}

	private static String jsonEscape(String value) {
		if (value == null) {
			return "";
		}
		return value
				.replace("\\", "\\\\")
				.replace("\"", "\\\"")
				.replace("\n", "\\n")
				.replace("\r", "\\r")
				.replace("\t", "\\t");
	}
}
