package com.kismet.server.user;

import java.util.List;
import java.util.Map;

import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
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

	public record MeResponse(
			String id,
			String displayName,
			String email,
			List<String> interests,
			String weekdayAvailability,
			String weekendAvailability,
			Map<String, UserDocument.AvailabilityWindow> dailyAvailability,
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
					user.isOnboardingCompleted());
		}
	}

	public record InterestsRequest(List<String> interests) {
	}

	public record AvailabilityRequest(
			String weekdayAvailability,
			String weekendAvailability,
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
