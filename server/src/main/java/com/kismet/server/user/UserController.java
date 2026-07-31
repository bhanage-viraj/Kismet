package com.kismet.server.user;

import java.util.List;
import java.util.Map;

import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import com.kismet.server.config.AuthUser;

@RestController
public class UserController {

	private final UserService userService;

	public UserController(UserService userService) {
		this.userService = userService;
	}

	@GetMapping("/me")
	public MeResponse me(@AuthenticationPrincipal AuthUser authUser) {
		UserDocument user = userService.requireById(authUser.userId());
		return MeResponse.from(user);
	}

	@PostMapping("/me/onboarding-complete")
	public MeResponse completeOnboarding(
			@AuthenticationPrincipal AuthUser authUser,
			@RequestBody AvailabilityRequest request) {
		UserDocument user = userService.completeOnboarding(
				authUser.userId(),
				request.weekdayAvailability(),
				request.weekendAvailability(),
				request.timeZoneId(),
				request.dailyAvailability() == null
						? null
						: request.dailyAvailability().stream()
								.map(day -> new UserService.AvailabilityInput(
										day.day(),
										day.startMinutes(),
										day.endMinutes(),
										day.busySegments() == null
												? List.of()
												: day.busySegments().stream()
														.map(busy -> new UserService.BusySegmentInput(
																busy.startMinutes(),
																busy.endMinutes()))
														.toList()))
								.toList());
		return MeResponse.from(user);
	}

	@PostMapping("/me/interests")
	public MeResponse updateInterests(
			@AuthenticationPrincipal AuthUser authUser,
			@RequestBody InterestsRequest request) {
		UserDocument user = userService.updateInterests(authUser.userId(), request.interests());
		return MeResponse.from(user);
	}

	@PutMapping("/me/public-key")
	public MeResponse updatePublicKey(
			@AuthenticationPrincipal AuthUser authUser,
			@RequestBody PublicKeyRequest request) {
		UserDocument user = userService.updatePublicKey(
				authUser.userId(),
				request.publicKey(),
				request.keyVersion());
		return MeResponse.from(user);
	}

	@PutMapping("/me/timezone")
	public MeResponse updateTimeZone(
			@AuthenticationPrincipal AuthUser authUser,
			@RequestBody TimeZoneRequest request) {
		UserDocument user = userService.updateTimeZone(authUser.userId(), request.timeZoneId());
		return MeResponse.from(user);
	}

	public record MeResponse(
			String id,
			String displayName,
			String email,
			List<String> interests,
			String weekdayAvailability,
			String weekendAvailability,
			Map<String, UserDocument.AvailabilityWindow> dailyAvailability,
			String timeZoneId,
			String publicKey,
			int keyVersion,
			boolean onboardingCompleted) {

		static MeResponse from(UserDocument user) {
			return new MeResponse(
					user.getId(),
					user.getDisplayName(),
					user.getEmail(),
					user.getInterests(),
					user.getWeekdayAvailability(),
					user.getWeekendAvailability(),
					user.getDailyAvailability(),
					user.getTimeZoneId(),
					user.getPublicKey(),
					user.getKeyVersion(),
					user.isOnboardingCompleted());
		}
	}

	public record InterestsRequest(List<String> interests) {
	}

	public record PublicKeyRequest(String publicKey, int keyVersion) {
	}

	public record TimeZoneRequest(String timeZoneId) {
	}

	public record AvailabilityRequest(
			String weekdayAvailability,
			String weekendAvailability,
			String timeZoneId,
			List<DailyAvailabilityRequest> dailyAvailability) {
	}

	public record DailyAvailabilityRequest(
			String day,
			int startMinutes,
			int endMinutes,
			List<BusySegmentRequest> busySegments) {
	}

	public record BusySegmentRequest(
			int startMinutes,
			int endMinutes) {
	}
}
