package com.kismet.server.push;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

/**
 * Sends ActivityKit Live Activity updates/ends to peer devices.
 * Topic is {@code {bundleId}.push-type.liveactivity}.
 */
@Service
public class LiveActivityPushService {

	private static final Logger log = LoggerFactory.getLogger(LiveActivityPushService.class);

	private final LiveActivityTokenService tokenService;
	private final ApnsAuthTokenProvider authTokenProvider;
	private final HttpClient httpClient;
	private final ExecutorService executor;
	private final String host;

	public LiveActivityPushService(
			LiveActivityTokenService tokenService,
			ApnsAuthTokenProvider authTokenProvider,
			@Value("${kismet.apns.production:false}") boolean production) {
		this.tokenService = tokenService;
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

	public void pushUpdateToPeers(
			String meetupId,
			String senderUserId,
			String etaText,
			String distanceText,
			double progress,
			boolean isEnded,
			boolean isExpanded,
			String event) {
		if (!authTokenProvider.isEnabled()) {
			return;
		}
		String resolvedEvent = (event == null || event.isBlank()) ? "update" : event.trim().toLowerCase(Locale.ROOT);
		executor.execute(() -> {
			List<LiveActivityTokenDocument> tokens = tokenService.tokensForMeetup(meetupId);
			for (LiveActivityTokenDocument token : tokens) {
				if (token.getUserId() != null && token.getUserId().equals(senderUserId)) {
					continue; // Don't push back to the updater's own activity.
				}
				try {
					sendLiveActivity(token, etaText, distanceText, progress, isEnded, isExpanded, resolvedEvent);
				}
				catch (Exception ex) {
					log.debug("Live Activity push failed meetup={}: {}", meetupId, ex.getMessage());
				}
			}
		});
	}

	private void sendLiveActivity(
			LiveActivityTokenDocument token,
			String etaText,
			String distanceText,
			double progress,
			boolean isEnded,
			boolean isExpanded,
			String event) throws Exception {
		List<ApnsAuthTokenProvider.Account> candidates = candidatesFor(token.getBundleId());
		if (candidates.isEmpty()) {
			return;
		}

		long timestamp = System.currentTimeMillis() / 1000L;
		String body = "{"
				+ "\"aps\":{"
				+ "\"timestamp\":" + timestamp + ","
				+ "\"event\":\"" + jsonEscape(event) + "\","
				+ "\"content-state\":{"
				+ "\"etaText\":\"" + jsonEscape(etaText) + "\","
				+ "\"distanceText\":\"" + jsonEscape(distanceText) + "\","
				+ "\"progress\":" + progress + ","
				+ "\"isEnded\":" + isEnded + ","
				+ "\"isExpanded\":" + isExpanded
				+ "}"
				+ "}"
				+ "}";

		Exception lastError = null;
		for (ApnsAuthTokenProvider.Account account : candidates) {
			try {
				int status = postLiveActivity(token.getPushToken(), account, body);
				if (status == 200) {
					return;
				}
				if (status == 410) {
					tokenService.removeToken(token.getPushToken());
					return;
				}
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
		return authTokenProvider.accounts();
	}

	private int postLiveActivity(String deviceToken, ApnsAuthTokenProvider.Account account, String body)
			throws Exception {
		String topic = account.bundleId() + ".push-type.liveactivity";
		HttpRequest request = HttpRequest.newBuilder()
				.uri(URI.create(host + "/3/device/" + deviceToken))
				.timeout(Duration.ofSeconds(15))
				.header("authorization", "bearer " + account.currentToken())
				.header("apns-topic", topic)
				.header("apns-push-type", "liveactivity")
				.header("apns-priority", "10")
				.header("content-type", "application/json")
				.POST(HttpRequest.BodyPublishers.ofString(body))
				.build();

		HttpResponse<String> response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
		int status = response.statusCode();
		if (status == 400) {
			String responseBody = response.body() == null ? "" : response.body().toLowerCase(Locale.ROOT);
			if (responseBody.contains("baddevicetoken") || responseBody.contains("unregistered")) {
				tokenService.removeToken(deviceToken);
			}
			else {
				log.debug("Live Activity APNs 400 bundle={} body={}", account.bundleId(), response.body());
			}
		}
		else if (status != 200 && status != 410) {
			log.warn("Live Activity APNs status={} body={}", status, response.body());
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
