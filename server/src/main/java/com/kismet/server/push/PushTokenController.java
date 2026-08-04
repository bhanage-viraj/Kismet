package com.kismet.server.push;

import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.kismet.server.common.ApiException;
import com.kismet.server.config.AuthUser;

@RestController
@RequestMapping("/push")
public class PushTokenController {

	private final PushTokenService pushTokenService;

	public PushTokenController(PushTokenService pushTokenService) {
		this.pushTokenService = pushTokenService;
	}

	@PostMapping("/token")
	public PushTokenResponse register(
			@AuthenticationPrincipal AuthUser authUser,
			@RequestBody PushTokenRequest request) {
		if (request == null) {
			throw new ApiException(HttpStatus.BAD_REQUEST, "Body is required");
		}
		pushTokenService.register(authUser.userId(), request.deviceToken(), request.platform());
		return new PushTokenResponse(true);
	}

	@DeleteMapping("/token")
	public PushTokenResponse unregister(
			@AuthenticationPrincipal AuthUser authUser,
			@RequestBody PushTokenRequest request) {
		if (request == null || request.deviceToken() == null) {
			throw new ApiException(HttpStatus.BAD_REQUEST, "Device token is required");
		}
		pushTokenService.unregister(authUser.userId(), request.deviceToken());
		return new PushTokenResponse(true);
	}

	public record PushTokenResponse(boolean ok) {
	}
}
