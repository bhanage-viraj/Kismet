package com.kismet.server.map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

import java.time.Instant;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;

import com.kismet.server.availability.AvailabilityEvaluator;
import com.kismet.server.availability.AvailabilitySnapshot;
import com.kismet.server.availability.AvailabilityStatus;
import com.kismet.server.blob.BlobKind;
import com.kismet.server.blob.EncryptedBlobDocument;
import com.kismet.server.blob.EncryptedBlobRepository;
import com.kismet.server.common.ApiException;
import com.kismet.server.friend.FriendService;
import com.kismet.server.user.UserDocument;
import com.kismet.server.user.UserService;

@ExtendWith(MockitoExtension.class)
class MapServiceTest {

	@Mock
	private FriendService friendService;

	@Mock
	private UserService userService;

	@Mock
	private EncryptedBlobRepository blobRepository;

	@Mock
	private AvailabilityEvaluator availabilityEvaluator;

	private MapService mapService;

	@BeforeEach
	void setUp() {
		mapService = new MapService(friendService, userService, blobRepository, availabilityEvaluator);
	}

	@Test
	void mapViewNeverCarriesCoordinatesOnlyBlobFreshness() {
		givenViewer("user-1", "coffee", "gym");
		givenFriends("user-1", "friend-a");
		UserDocument friend = user("friend-a", "Ada", "coffee", "reading");
		when(userService.findAllByIds(any())).thenReturn(List.of(friend));
		givenLocationBlob("user-1", "friend-a", Instant.parse("2026-07-31T06:40:00Z"));
		when(availabilityEvaluator.evaluate(any(), any()))
				.thenReturn(AvailabilitySnapshot.free(Instant.parse("2026-07-31T16:00:00Z")));

		List<MapFriend> friends = mapService.friendsForMap("user-1");

		assertEquals(1, friends.size());
		MapFriend mapFriend = friends.get(0);
		assertEquals("friend-a", mapFriend.userId());
		assertEquals("Ada", mapFriend.displayName());
		assertEquals(AvailabilityStatus.FREE, mapFriend.availability().status());
		assertEquals(List.of("coffee"), mapFriend.sharedInterests());
		assertTrue(mapFriend.hasLocationBlob());
		assertEquals(Instant.parse("2026-07-31T06:40:00Z"), mapFriend.blobUpdatedAt());
		assertFalse(mapFriend.isTestSeed());
	}

	@Test
	void aFriendWithNoBlobIsReportedAsHavingNoLocation() {
		givenViewer("user-1");
		givenFriends("user-1", "friend-a");
		when(userService.findAllByIds(any())).thenReturn(List.of(user("friend-a", "Ada")));
		when(blobRepository.findAllByRecipientUserIdAndKind("user-1", BlobKind.LOCATION))
				.thenReturn(List.of());
		when(availabilityEvaluator.evaluate(any(), any())).thenReturn(AvailabilitySnapshot.unknown());

		MapFriend mapFriend = mapService.friendsForMap("user-1").get(0);

		assertFalse(mapFriend.hasLocationBlob());
		assertNull(mapFriend.blobUpdatedAt());
	}

	@Test
	void noFriendsMeansNoDatabaseLookupForBlobs() {
		givenViewer("user-1");
		when(friendService.activeFriendIds("user-1")).thenReturn(Set.of());

		assertEquals(List.of(), mapService.friendsForMap("user-1"));
		org.mockito.Mockito.verify(blobRepository, org.mockito.Mockito.never())
				.findAllByRecipientUserIdAndKind(any(), any());
	}

	@Test
	void sharedInterestsAreTheIntersectionNotTheUnion() {
		givenViewer("user-1", "coffee", "gym", "coding");
		givenFriends("user-1", "friend-a");
		when(userService.findAllByIds(any()))
				.thenReturn(List.of(user("friend-a", "Ada", "gym", "coding", "travel")));
		when(blobRepository.findAllByRecipientUserIdAndKind(any(), any())).thenReturn(List.of());
		when(availabilityEvaluator.evaluate(any(), any())).thenReturn(AvailabilitySnapshot.unknown());

		assertEquals(List.of("gym", "coding"), mapService.friendsForMap("user-1").get(0).sharedInterests());
	}

	@Test
	void friendDetailRejectsSomeoneYouAreNotConnectedTo() {
		when(friendService.areActiveFriends("user-1", "stranger")).thenReturn(false);

		ApiException ex = assertThrows(ApiException.class,
				() -> mapService.friendDetail("user-1", "stranger"));

		assertEquals(HttpStatus.NOT_FOUND, ex.getStatus());
	}

	@Test
	void friendDetailReturnsTheFriendWhenConnected() {
		when(friendService.areActiveFriends("user-1", "friend-a")).thenReturn(true);
		givenViewer("user-1", "coffee");
		when(userService.requireById("friend-a")).thenReturn(user("friend-a", "Ada", "coffee"));
		givenLocationBlob("user-1", "friend-a", Instant.parse("2026-07-31T06:40:00Z"));
		when(availabilityEvaluator.evaluate(any(), any()))
				.thenReturn(AvailabilitySnapshot.busy(Instant.parse("2026-07-31T10:00:00Z")));

		MapFriend detail = mapService.friendDetail("user-1", "friend-a");

		assertEquals("friend-a", detail.userId());
		assertEquals(AvailabilityStatus.BUSY, detail.availability().status());
		assertTrue(detail.hasLocationBlob());
	}

	private void givenViewer(String userId, String... interests) {
		when(userService.requireById(userId)).thenReturn(user(userId, "Viewer", interests));
	}

	private void givenFriends(String userId, String... friendIds) {
		when(friendService.activeFriendIds(userId))
				.thenReturn(new LinkedHashSet<>(List.of(friendIds)));
	}

	private void givenLocationBlob(String recipientUserId, String senderUserId, Instant updatedAt) {
		EncryptedBlobDocument blob = new EncryptedBlobDocument();
		blob.setSenderUserId(senderUserId);
		blob.setRecipientUserId(recipientUserId);
		blob.setKind(BlobKind.LOCATION);
		blob.setUpdatedAt(updatedAt);
		when(blobRepository.findAllByRecipientUserIdAndKind(recipientUserId, BlobKind.LOCATION))
				.thenReturn(List.of(blob));
	}

	private static UserDocument user(String id, String displayName, String... interests) {
		UserDocument user = new UserDocument();
		user.setId(id);
		user.setDisplayName(displayName);
		user.setInterests(List.of(interests));
		return user;
	}
}
