package com.kismet.server.push;

import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.kismet.server.common.ApiException;
import com.kismet.server.config.AuthUser;

@RestController
@RequestMapping("/push/live-activity")
public class LiveActivityTokenController {

	private final LiveActivityTokenService tokenService;
	private final LiveActivityPushService pushService;

	public LiveActivityTokenController(
			LiveActivityTokenService tokenService,
			LiveActivityPushService pushService) {
		this.tokenService = tokenService;
		this.pushService = pushService;
	}

	@PostMapping
	public OkResponse register(
			@AuthenticationPrincipal AuthUser authUser,
			@RequestBody LiveActivityTokenRequest request) {
		if (request == null) {
			throw new ApiException(HttpStatus.BAD_REQUEST, "Body is required");
		}
		tokenService.register(authUser.userId(), request.meetupId(), request.pushToken(), request.bundleId());
		return new OkResponse(true);
	}

	@PostMapping("/update")
	public OkResponse update(
			@AuthenticationPrincipal AuthUser authUser,
			@RequestBody LiveActivityUpdateRequest request) {
		if (request == null) {
			throw new ApiException(HttpStatus.BAD_REQUEST, "Body is required");
		}
		if (request.meetupId() == null || request.meetupId().isBlank()) {
			throw new ApiException(HttpStatus.BAD_REQUEST, "Meetup id is required");
		}
		pushService.pushUpdateToPeers(
				request.meetupId(),
				authUser.userId(),
				request.etaText() == null ? "—" : request.etaText(),
				request.distanceText() == null ? "—" : request.distanceText(),
				request.progress(),
				request.isEnded(),
				request.isExpanded(),
				request.event());
		return new OkResponse(true);
	}

	public record LiveActivityTokenRequest(String meetupId, String pushToken, String bundleId) {
	}

	public record LiveActivityUpdateRequest(
			String meetupId,
			String etaText,
			String distanceText,
			double progress,
			@JsonProperty("isEnded") boolean isEnded,
			@JsonProperty("isExpanded") boolean isExpanded,
			String event) {
	}

	public record OkResponse(boolean ok) {
	}
}
