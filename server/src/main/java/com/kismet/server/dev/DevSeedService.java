package com.kismet.server.dev;

import java.security.SecureRandom;
import java.time.Instant;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

import com.kismet.server.common.ApiException;
import com.kismet.server.friend.ConnectedVia;
import com.kismet.server.friend.FriendPairDocument;
import com.kismet.server.friend.FriendPairRepository;
import com.kismet.server.friend.FriendPairedEvent;
import com.kismet.server.friend.FriendService;
import com.kismet.server.friend.PairStatus;
import com.kismet.server.friend.dto.FriendSummary;
import com.kismet.server.user.UserDocument;
import com.kismet.server.user.UserRepository;
import com.kismet.server.user.UserService;

/**
 * Creates a synthetic friend and pairs them with the caller for single-device demos.
 * Gated by {@code kismet.dev.seed-enabled}.
 */
@Service
public class DevSeedService {

	public static final String TEST_FRIEND_APPLE_SUB = "dev.test.friend.alex";
	public static final String TEST_FRIEND_DISPLAY_NAME = "Alex (Test)";

	private final boolean seedEnabled;
	private final UserRepository userRepository;
	private final UserService userService;
	private final FriendPairRepository friendPairRepository;
	private final FriendService friendService;
	private final ApplicationEventPublisher eventPublisher;
	private final SecureRandom random = new SecureRandom();

	public DevSeedService(
			@Value("${kismet.dev.seed-enabled:false}") boolean seedEnabled,
			UserRepository userRepository,
			UserService userService,
			FriendPairRepository friendPairRepository,
			FriendService friendService,
			ApplicationEventPublisher eventPublisher) {
		this.seedEnabled = seedEnabled;
		this.userRepository = userRepository;
		this.userService = userService;
		this.friendPairRepository = friendPairRepository;
		this.friendService = friendService;
		this.eventPublisher = eventPublisher;
	}

	public boolean isSeedEnabled() {
		return seedEnabled;
	}

	public FriendSummary seedTestFriend(String callerUserId) {
		if (!seedEnabled) {
			throw new ApiException(
					HttpStatus.NOT_FOUND,
					"Dev seed is disabled. Set DEV_SEED_ENABLED=true on the server.");
		}

		userService.requireById(callerUserId);
		UserDocument bot = findOrCreateTestFriend();
		if (bot.getId().equals(callerUserId)) {
			throw new ApiException(HttpStatus.BAD_REQUEST, "Cannot seed a test friend against the bot itself");
		}

		Instant now = Instant.now();
		String userAId = FriendPairDocument.canonicalA(callerUserId, bot.getId());
		String userBId = FriendPairDocument.canonicalB(callerUserId, bot.getId());

		FriendPairDocument pair = friendPairRepository.findByUserAIdAndUserBId(userAId, userBId).orElse(null);
		boolean newlyActive = false;
		if (pair == null) {
			pair = FriendPairDocument.create(
					callerUserId, bot.getId(), ConnectedVia.INVITE_CODE, PairStatus.ACTIVE, now);
			newlyActive = true;
		}
		else if (pair.getStatus() != PairStatus.ACTIVE) {
			pair.setStatus(PairStatus.ACTIVE);
			pair.setConnectedVia(ConnectedVia.INVITE_CODE);
			pair.setRequestedByUserId(callerUserId);
			pair.setAcceptedAt(now);
			pair.setUpdatedAt(now);
			newlyActive = true;
		}

		FriendPairDocument saved;
		try {
			saved = friendPairRepository.save(pair);
		}
		catch (DuplicateKeyException ex) {
			saved = friendPairRepository.findByUserAIdAndUserBId(userAId, userBId)
					.orElseThrow(() -> new ApiException(HttpStatus.CONFLICT, "Could not create test friendship"));
		}

		if (newlyActive) {
			eventPublisher.publishEvent(new FriendPairedEvent(callerUserId, bot.getId()));
		}

		return friendService.listFriends(callerUserId).stream()
				.filter(friend -> friend.userId().equals(bot.getId()))
				.findFirst()
				.orElseGet(() -> new FriendSummary(
						saved.getId(),
						bot.getId(),
						bot.getDisplayName(),
						bot.getPublicKey(),
						bot.getKeyVersion(),
						saved.getStatus().name(),
						ConnectedVia.INVITE_CODE.name(),
						saved.getAcceptedAt() == null ? saved.getCreatedAt() : saved.getAcceptedAt(),
						true));
	}

	private UserDocument findOrCreateTestFriend() {
		Optional<UserDocument> existing = userRepository.findByAppleSub(TEST_FRIEND_APPLE_SUB);
		if (existing.isPresent()) {
			UserDocument bot = existing.get();
			boolean dirty = false;
			if (!TEST_FRIEND_DISPLAY_NAME.equals(bot.getDisplayName())) {
				bot.setDisplayName(TEST_FRIEND_DISPLAY_NAME);
				dirty = true;
			}
			if (bot.getDailyAvailability().isEmpty()) {
				applyAlwaysFreeAvailability(bot);
				dirty = true;
			}
			if (bot.getPublicKey() == null || bot.getPublicKey().isBlank()) {
				bot.setPublicKey(randomPublicKey());
				bot.setKeyVersion(Math.max(1, bot.getKeyVersion()));
				bot.setKeyUpdatedAt(Instant.now());
				dirty = true;
			}
			if (!bot.isOnboardingCompleted()) {
				bot.setOnboardingCompleted(true);
				dirty = true;
			}
			return dirty ? userService.save(bot) : bot;
		}

		Instant now = Instant.now();
		UserDocument bot = new UserDocument();
		bot.setAppleSub(TEST_FRIEND_APPLE_SUB);
		bot.setDisplayName(TEST_FRIEND_DISPLAY_NAME);
		bot.setEmail("alex.test@kismet.dev");
		bot.setInterests(List.of("coffee", "music", "food"));
		bot.setOnboardingCompleted(true);
		bot.setPublicKey(randomPublicKey());
		bot.setKeyVersion(1);
		bot.setKeyUpdatedAt(now);
		bot.setCreatedAt(now);
		bot.setUpdatedAt(now);
		applyAlwaysFreeAvailability(bot);
		return userRepository.save(bot);
	}

	private static void applyAlwaysFreeAvailability(UserDocument bot) {
		bot.setTimeZoneId("Asia/Singapore");
		bot.setWeekdayAvailability("Anytime");
		bot.setWeekendAvailability("Anytime");
		Map<String, UserDocument.AvailabilityWindow> weekly = new LinkedHashMap<>();
		for (String day : List.of(
				"monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")) {
			weekly.put(day, new UserDocument.AvailabilityWindow(0, 24 * 60, List.of()));
		}
		bot.setDailyAvailability(weekly);
	}

	private String randomPublicKey() {
		byte[] key = new byte[32];
		random.nextBytes(key);
		return Base64.getEncoder().encodeToString(key);
	}
}
