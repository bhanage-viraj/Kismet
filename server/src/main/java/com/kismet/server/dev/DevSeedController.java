package com.kismet.server.dev;

import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.kismet.server.config.AuthUser;
import com.kismet.server.friend.dto.FriendSummary;

@RestController
@RequestMapping("/dev")
public class DevSeedController {

	private final DevSeedService devSeedService;

	public DevSeedController(DevSeedService devSeedService) {
		this.devSeedService = devSeedService;
	}

	/**
	 * Creates (or reactivates) synthetic friend "Alex (Test)" paired with the caller.
	 * Requires {@code DEV_SEED_ENABLED=true}.
	 */
	@PostMapping("/seed-test-friend")
	public FriendSummary seedTestFriend(@AuthenticationPrincipal AuthUser authUser) {
		return devSeedService.seedTestFriend(authUser.userId());
	}
}
