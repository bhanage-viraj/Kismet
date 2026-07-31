package com.kismet.server.friend;

import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.function.Function;
import java.util.stream.Collectors;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

import com.kismet.server.common.ApiException;
import com.kismet.server.friend.dto.FriendSummary;
import com.kismet.server.friend.dto.InviteCodeResponse;
import com.kismet.server.user.UserDocument;
import com.kismet.server.user.UserService;

@Service
public class FriendService {

	/** Crockford base32: no I, L, O or U, so codes survive being read aloud and retyped. */
	private static final char[] CODE_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ".toCharArray();
	private static final int CODE_LENGTH = 8;
	private static final int MAX_CODE_GENERATION_ATTEMPTS = 5;

	private final FriendPairRepository friendPairRepository;
	private final InviteCodeRepository inviteCodeRepository;
	private final UserService userService;
	private final SecureRandom random = new SecureRandom();
	private final Duration inviteCodeTtl;
	private final int maxFriends;

	public FriendService(
			FriendPairRepository friendPairRepository,
			InviteCodeRepository inviteCodeRepository,
			UserService userService,
			@Value("${kismet.friends.invite-code-ttl-minutes:60}") long inviteCodeTtlMinutes,
			@Value("${kismet.friends.max-friends:500}") int maxFriends) {
		this.friendPairRepository = friendPairRepository;
		this.inviteCodeRepository = inviteCodeRepository;
		this.userService = userService;
		this.inviteCodeTtl = Duration.ofMinutes(inviteCodeTtlMinutes);
		this.maxFriends = maxFriends;
	}

	/**
	 * Issues a fresh single-use code for the caller, replacing any previous one so an old
	 * code that was screenshotted or shared cannot be redeemed later.
	 */
	public InviteCodeResponse createInvite(String userId) {
		userService.requireById(userId);
		inviteCodeRepository.deleteByOwnerUserId(userId);

		Instant now = Instant.now();
		for (int attempt = 0; attempt < MAX_CODE_GENERATION_ATTEMPTS; attempt++) {
			InviteCodeDocument invite = new InviteCodeDocument();
			invite.setCode(generateCode());
			invite.setOwnerUserId(userId);
			invite.setUsesRemaining(1);
			invite.setCreatedAt(now);
			invite.setExpiresAt(now.plus(inviteCodeTtl));
			try {
				InviteCodeDocument saved = inviteCodeRepository.save(invite);
				return new InviteCodeResponse(
						saved.getCode(),
						"kismet://pair?code=" + saved.getCode(),
						saved.getExpiresAt());
			}
			catch (DuplicateKeyException ex) {
				// Collision on the unique code index; try another value.
			}
		}
		throw new ApiException(HttpStatus.INTERNAL_SERVER_ERROR, "Could not allocate an invite code");
	}

	/**
	 * Redeems someone else's code and activates the friendship immediately. Holding the
	 * code is the consent signal, so there is no separate approval step.
	 */
	public FriendSummary redeemInvite(String userId, String rawCode) {
		String code = normalizeCode(rawCode);
		if (code.isEmpty()) {
			throw new ApiException(HttpStatus.BAD_REQUEST, "Invite code is required");
		}

		InviteCodeDocument invite = inviteCodeRepository.findByCode(code)
				.orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "Invite code not found"));
		if (invite.getExpiresAt() != null && invite.getExpiresAt().isBefore(Instant.now())) {
			// TTL deletion is best-effort and lags, so expiry is also checked on read.
			inviteCodeRepository.delete(invite);
			throw new ApiException(HttpStatus.GONE, "Invite code has expired");
		}
		if (invite.getUsesRemaining() <= 0) {
			throw new ApiException(HttpStatus.GONE, "Invite code has already been used");
		}

		String ownerUserId = invite.getOwnerUserId();
		if (ownerUserId.equals(userId)) {
			throw new ApiException(HttpStatus.BAD_REQUEST, "You cannot pair with yourself");
		}

		UserDocument owner = userService.requireById(ownerUserId);
		userService.requireById(userId);
		assertUnderFriendLimit(userId);
		assertUnderFriendLimit(ownerUserId);

		Instant now = Instant.now();
		String userAId = FriendPairDocument.canonicalA(userId, ownerUserId);
		String userBId = FriendPairDocument.canonicalB(userId, ownerUserId);

		FriendPairDocument pair = friendPairRepository.findByUserAIdAndUserBId(userAId, userBId)
				.orElse(null);
		if (pair == null) {
			pair = FriendPairDocument.create(
					userId, ownerUserId, ConnectedVia.INVITE_CODE, PairStatus.ACTIVE, now);
		}
		else if (pair.getStatus() == PairStatus.ACTIVE) {
			throw new ApiException(HttpStatus.CONFLICT, "You are already connected");
		}
		else {
			// Re-friending after a revoke reuses the row; the unique index would reject a
			// second one.
			pair.setStatus(PairStatus.ACTIVE);
			pair.setConnectedVia(ConnectedVia.INVITE_CODE);
			pair.setRequestedByUserId(userId);
			pair.setAcceptedAt(now);
			pair.setUpdatedAt(now);
		}

		FriendPairDocument saved;
		try {
			saved = friendPairRepository.save(pair);
		}
		catch (DuplicateKeyException ex) {
			throw new ApiException(HttpStatus.CONFLICT, "You are already connected");
		}

		invite.setUsesRemaining(invite.getUsesRemaining() - 1);
		if (invite.getUsesRemaining() <= 0) {
			inviteCodeRepository.delete(invite);
		}
		else {
			inviteCodeRepository.save(invite);
		}

		return toSummary(saved, owner, userId);
	}

	/**
	 * Active friends with the public keys the caller needs in order to seal blobs for them.
	 */
	public List<FriendSummary> listFriends(String userId) {
		List<FriendPairDocument> pairs =
				friendPairRepository.findAllByUserIdAndStatus(userId, PairStatus.ACTIVE);
		if (pairs.isEmpty()) {
			return List.of();
		}

		Set<String> friendIds = new LinkedHashSet<>();
		for (FriendPairDocument pair : pairs) {
			friendIds.add(pair.otherUserId(userId));
		}
		Map<String, UserDocument> usersById = userService.findAllByIds(friendIds).stream()
				.collect(Collectors.toMap(UserDocument::getId, Function.identity()));

		List<FriendSummary> summaries = new ArrayList<>(pairs.size());
		for (FriendPairDocument pair : pairs) {
			UserDocument friend = usersById.get(pair.otherUserId(userId));
			if (friend != null) {
				summaries.add(toSummary(pair, friend, userId));
			}
		}
		return List.copyOf(summaries);
	}

	public Set<String> activeFriendIds(String userId) {
		return friendPairRepository.findAllByUserIdAndStatus(userId, PairStatus.ACTIVE).stream()
				.map(pair -> pair.otherUserId(userId))
				.collect(Collectors.toCollection(LinkedHashSet::new));
	}

	public boolean areActiveFriends(String userId, String otherUserId) {
		if (userId.equals(otherUserId)) {
			return false;
		}
		return friendPairRepository
				.findByUserAIdAndUserBId(
						FriendPairDocument.canonicalA(userId, otherUserId),
						FriendPairDocument.canonicalB(userId, otherUserId))
				.filter(pair -> pair.getStatus() == PairStatus.ACTIVE)
				.isPresent();
	}

	/**
	 * Revokes a friendship. Either side can do this and it applies in both directions;
	 * there is no one-way unfriend.
	 */
	public void revokeFriend(String userId, String friendUserId) {
		if (userId.equals(friendUserId)) {
			throw new ApiException(HttpStatus.BAD_REQUEST, "You cannot unfriend yourself");
		}

		Optional<FriendPairDocument> found = friendPairRepository.findByUserAIdAndUserBId(
				FriendPairDocument.canonicalA(userId, friendUserId),
				FriendPairDocument.canonicalB(userId, friendUserId));
		FriendPairDocument pair = found
				.orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "You are not connected"));
		if (pair.getStatus() == PairStatus.REVOKED) {
			return;
		}

		pair.setStatus(PairStatus.REVOKED);
		pair.setUpdatedAt(Instant.now());
		friendPairRepository.save(pair);
	}

	private void assertUnderFriendLimit(String userId) {
		if (friendPairRepository.countByUserIdAndStatus(userId, PairStatus.ACTIVE) >= maxFriends) {
			throw new ApiException(HttpStatus.CONFLICT, "Friend limit reached");
		}
	}

	private FriendSummary toSummary(FriendPairDocument pair, UserDocument friend, String viewerId) {
		return new FriendSummary(
				pair.getId(),
				friend.getId(),
				friend.getDisplayName(),
				friend.getPublicKey(),
				friend.getKeyVersion(),
				pair.getStatus().name(),
				pair.getConnectedVia() == null ? null : pair.getConnectedVia().name(),
				pair.getAcceptedAt() == null ? pair.getCreatedAt() : pair.getAcceptedAt(),
				pair.getRequestedByUserId() != null && pair.getRequestedByUserId().equals(viewerId));
	}

	private String generateCode() {
		StringBuilder builder = new StringBuilder(CODE_LENGTH);
		for (int i = 0; i < CODE_LENGTH; i++) {
			builder.append(CODE_ALPHABET[random.nextInt(CODE_ALPHABET.length)]);
		}
		return builder.toString();
	}

	private static String normalizeCode(String rawCode) {
		if (rawCode == null) {
			return "";
		}
		return rawCode.replaceAll("[\\s-]", "").toUpperCase(Locale.ROOT);
	}
}
