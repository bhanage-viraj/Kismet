package com.kismet.server.friend;

import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.kismet.server.config.AuthUser;
import com.kismet.server.friend.dto.BumpPairRequest;
import com.kismet.server.friend.dto.FriendListResponse;
import com.kismet.server.friend.dto.FriendSummary;
import com.kismet.server.friend.dto.InviteCodeResponse;
import com.kismet.server.friend.dto.PairRequest;

import jakarta.validation.Valid;

@RestController
@RequestMapping("/friends")
public class FriendController {

	private final FriendService friendService;

	public FriendController(FriendService friendService) {
		this.friendService = friendService;
	}

	@PostMapping("/invite")
	public InviteCodeResponse createInvite(@AuthenticationPrincipal AuthUser authUser) {
		return friendService.createInvite(authUser.userId());
	}

	@PostMapping("/redeem")
	public FriendSummary redeemInvite(
			@AuthenticationPrincipal AuthUser authUser,
			@Valid @RequestBody PairRequest request) {
		return friendService.redeemInvite(authUser.userId(), request.inviteCode());
	}

	/**
	 * Persists a friendship after an in-person Bump ceremony. Mutual consent already
	 * happened on-device; this endpoint only writes the {@code ACTIVE} pair.
	 */
	@PostMapping("/pair")
	public FriendSummary pairViaBump(
			@AuthenticationPrincipal AuthUser authUser,
			@Valid @RequestBody BumpPairRequest request) {
		return friendService.pairViaBump(
				authUser.userId(), request.peerUserId(), request.peerPublicKey());
	}

	@GetMapping
	public FriendListResponse listFriends(@AuthenticationPrincipal AuthUser authUser) {
		return new FriendListResponse(friendService.listFriends(authUser.userId()));
	}

	@DeleteMapping("/{friendUserId}")
	public ResponseEntity<Void> revokeFriend(
			@AuthenticationPrincipal AuthUser authUser,
			@PathVariable String friendUserId) {
		friendService.revokeFriend(authUser.userId(), friendUserId);
		return ResponseEntity.noContent().build();
	}
}
