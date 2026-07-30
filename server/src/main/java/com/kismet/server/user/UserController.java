package com.kismet.server.user;

import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
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
	public MeResponse completeOnboarding(@AuthenticationPrincipal AuthUser authUser) {
		UserDocument user = userService.markOnboardingCompleted(authUser.userId());
		return MeResponse.from(user);
	}

	public record MeResponse(
			String id,
			String displayName,
			String email,
			boolean onboardingCompleted) {

		static MeResponse from(UserDocument user) {
			return new MeResponse(
					user.getId(),
					user.getDisplayName(),
					user.getEmail(),
					user.isOnboardingCompleted());
		}
	}
}
