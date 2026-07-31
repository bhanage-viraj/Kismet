package com.kismet.server.map;

import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

import com.kismet.server.availability.AvailabilityEvaluator;
import com.kismet.server.blob.BlobKind;
import com.kismet.server.blob.EncryptedBlobDocument;
import com.kismet.server.blob.EncryptedBlobRepository;
import com.kismet.server.common.ApiException;
import com.kismet.server.friend.FriendService;
import com.kismet.server.user.UserDocument;
import com.kismet.server.user.UserService;

@Service
public class MapService {

	private final FriendService friendService;
	private final UserService userService;
	private final EncryptedBlobRepository blobRepository;
	private final AvailabilityEvaluator availabilityEvaluator;

	public MapService(
			FriendService friendService,
			UserService userService,
			EncryptedBlobRepository blobRepository,
			AvailabilityEvaluator availabilityEvaluator) {
		this.friendService = friendService;
		this.userService = userService;
		this.blobRepository = blobRepository;
		this.availabilityEvaluator = availabilityEvaluator;
	}

	public List<MapFriend> friendsForMap(String userId) {
		UserDocument viewer = userService.requireById(userId);
		Set<String> friendIds = friendService.activeFriendIds(userId);
		if (friendIds.isEmpty()) {
			return List.of();
		}

		Map<String, Instant> blobFreshness = locationBlobFreshness(userId);
		Instant now = Instant.now();
		List<MapFriend> result = new ArrayList<>(friendIds.size());
		for (UserDocument friend : userService.findAllByIds(friendIds)) {
			result.add(toMapFriend(viewer, friend, blobFreshness.get(friend.getId()), now));
		}
		return List.copyOf(result);
	}

	public MapFriend friendDetail(String userId, String friendUserId) {
		if (!friendService.areActiveFriends(userId, friendUserId)) {
			throw new ApiException(HttpStatus.NOT_FOUND, "You are not connected");
		}
		UserDocument viewer = userService.requireById(userId);
		UserDocument friend = userService.requireById(friendUserId);
		return toMapFriend(viewer, friend, locationBlobFreshness(userId).get(friendUserId), Instant.now());
	}

	private MapFriend toMapFriend(UserDocument viewer, UserDocument friend, Instant blobUpdatedAt, Instant now) {
		return new MapFriend(
				friend.getId(),
				friend.getDisplayName(),
				availabilityEvaluator.evaluate(friend, now),
				sharedInterests(viewer, friend),
				blobUpdatedAt != null,
				blobUpdatedAt);
	}

	/**
	 * When each friend's location blob for this viewer was last refreshed. Lets the client
	 * render "last seen 3 minutes ago", and skip decrypting a blob it has already handled,
	 * without the server learning anything about the contents.
	 */
	private Map<String, Instant> locationBlobFreshness(String recipientUserId) {
		Map<String, Instant> freshness = new HashMap<>();
		for (EncryptedBlobDocument blob
				: blobRepository.findAllByRecipientUserIdAndKind(recipientUserId, BlobKind.LOCATION)) {
			freshness.put(blob.getSenderUserId(), blob.getUpdatedAt());
		}
		return freshness;
	}

	private static List<String> sharedInterests(UserDocument viewer, UserDocument friend) {
		List<String> shared = new ArrayList<>(viewer.getInterests());
		shared.retainAll(friend.getInterests());
		return List.copyOf(shared);
	}
}
