package com.kismet.server.friend;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;

import com.kismet.server.common.ApiException;
import com.kismet.server.friend.dto.FriendSummary;
import com.kismet.server.friend.dto.InviteCodeResponse;
import com.kismet.server.user.UserDocument;
import com.kismet.server.user.UserService;

@ExtendWith(MockitoExtension.class)
class FriendServiceTest {

	@Mock
	private FriendPairRepository friendPairRepository;

	@Mock
	private InviteCodeRepository inviteCodeRepository;

	@Mock
	private UserService userService;

	private FriendService friendService;

	@BeforeEach
	void setUp() {
		friendService = new FriendService(friendPairRepository, inviteCodeRepository, userService, 60, 500);
	}

	@Test
	void createInviteIssuesCodeAndRevokesPreviousOne() {
		when(userService.requireById("user-1")).thenReturn(user("user-1", "Ada"));
		when(inviteCodeRepository.save(any(InviteCodeDocument.class)))
				.thenAnswer(invocation -> invocation.getArgument(0));

		InviteCodeResponse response = friendService.createInvite("user-1");

		verify(inviteCodeRepository).deleteByOwnerUserId("user-1");
		assertEquals(8, response.code().length());
		assertTrue(response.code().matches("[0-9A-HJKMNP-TV-Z]{8}"),
				"code should avoid ambiguous characters, got " + response.code());
		assertEquals("kismet://pair?code=" + response.code(), response.qrPayload());
		assertNotNull(response.expiresAt());
	}

	@Test
	void redeemCreatesActivePairWithCanonicallyOrderedIds() {
		// "user-9" redeems a code owned by "user-1", so the requester sorts second.
		givenValidInviteCode("ABCD1234", "user-1");
		when(userService.requireById("user-1")).thenReturn(user("user-1", "Ada"));
		when(userService.requireById("user-9")).thenReturn(user("user-9", "Grace"));
		when(friendPairRepository.findByUserAIdAndUserBId("user-1", "user-9")).thenReturn(Optional.empty());
		when(friendPairRepository.save(any(FriendPairDocument.class)))
				.thenAnswer(invocation -> invocation.getArgument(0));

		FriendSummary summary = friendService.redeemInvite("user-9", "ABCD1234");

		ArgumentCaptor<FriendPairDocument> captor = ArgumentCaptor.forClass(FriendPairDocument.class);
		verify(friendPairRepository).save(captor.capture());
		FriendPairDocument saved = captor.getValue();
		assertEquals("user-1", saved.getUserAId());
		assertEquals("user-9", saved.getUserBId());
		assertEquals(PairStatus.ACTIVE, saved.getStatus());
		assertEquals("user-9", saved.getRequestedByUserId());
		assertNotNull(saved.getAcceptedAt());

		assertEquals("user-1", summary.userId());
		assertEquals("Ada", summary.displayName());
		assertTrue(summary.initiatedByMe());
	}

	@Test
	void redeemNormalizesLowercaseAndDashedCodes() {
		givenValidInviteCode("ABCD1234", "user-1");
		when(userService.requireById(anyString())).thenAnswer(i -> user(i.getArgument(0), "Someone"));
		when(friendPairRepository.findByUserAIdAndUserBId(anyString(), anyString())).thenReturn(Optional.empty());
		when(friendPairRepository.save(any(FriendPairDocument.class)))
				.thenAnswer(invocation -> invocation.getArgument(0));

		assertNotNull(friendService.redeemInvite("user-9", "abcd-1234"));
	}

	@Test
	void redeemRejectsPairingWithYourself() {
		givenValidInviteCode("ABCD1234", "user-1");

		ApiException ex = assertThrows(ApiException.class,
				() -> friendService.redeemInvite("user-1", "ABCD1234"));

		assertEquals(HttpStatus.BAD_REQUEST, ex.getStatus());
		verify(friendPairRepository, never()).save(any());
	}

	@Test
	void redeemRejectsAnAlreadyActivePair() {
		givenValidInviteCode("ABCD1234", "user-1");
		when(userService.requireById(anyString())).thenAnswer(i -> user(i.getArgument(0), "Someone"));
		FriendPairDocument existing = FriendPairDocument.create(
				"user-1", "user-9", ConnectedVia.INVITE_CODE, PairStatus.ACTIVE, Instant.now());
		when(friendPairRepository.findByUserAIdAndUserBId("user-1", "user-9"))
				.thenReturn(Optional.of(existing));

		ApiException ex = assertThrows(ApiException.class,
				() -> friendService.redeemInvite("user-9", "ABCD1234"));

		assertEquals(HttpStatus.CONFLICT, ex.getStatus());
		verify(friendPairRepository, never()).save(any());
	}

	@Test
	void redeemReactivatesARevokedPairInsteadOfCreatingADuplicate() {
		givenValidInviteCode("ABCD1234", "user-1");
		when(userService.requireById(anyString())).thenAnswer(i -> user(i.getArgument(0), "Someone"));
		FriendPairDocument revoked = FriendPairDocument.create(
				"user-1", "user-9", ConnectedVia.INVITE_CODE, PairStatus.ACTIVE, Instant.now());
		revoked.setId("pair-1");
		revoked.setStatus(PairStatus.REVOKED);
		when(friendPairRepository.findByUserAIdAndUserBId("user-1", "user-9"))
				.thenReturn(Optional.of(revoked));
		when(friendPairRepository.save(any(FriendPairDocument.class)))
				.thenAnswer(invocation -> invocation.getArgument(0));

		friendService.redeemInvite("user-9", "ABCD1234");

		ArgumentCaptor<FriendPairDocument> captor = ArgumentCaptor.forClass(FriendPairDocument.class);
		verify(friendPairRepository).save(captor.capture());
		assertEquals("pair-1", captor.getValue().getId(), "should reuse the existing row");
		assertEquals(PairStatus.ACTIVE, captor.getValue().getStatus());
	}

	@Test
	void redeemRejectsAnExpiredCode() {
		InviteCodeDocument invite = new InviteCodeDocument();
		invite.setCode("ABCD1234");
		invite.setOwnerUserId("user-1");
		invite.setUsesRemaining(1);
		invite.setExpiresAt(Instant.now().minus(Duration.ofMinutes(5)));
		when(inviteCodeRepository.findByCode("ABCD1234")).thenReturn(Optional.of(invite));

		ApiException ex = assertThrows(ApiException.class,
				() -> friendService.redeemInvite("user-9", "ABCD1234"));

		assertEquals(HttpStatus.GONE, ex.getStatus());
		verify(inviteCodeRepository).delete(invite);
	}

	@Test
	void redeemRejectsAnExhaustedCode() {
		InviteCodeDocument invite = new InviteCodeDocument();
		invite.setCode("ABCD1234");
		invite.setOwnerUserId("user-1");
		invite.setUsesRemaining(0);
		invite.setExpiresAt(Instant.now().plus(Duration.ofMinutes(30)));
		when(inviteCodeRepository.findByCode("ABCD1234")).thenReturn(Optional.of(invite));

		ApiException ex = assertThrows(ApiException.class,
				() -> friendService.redeemInvite("user-9", "ABCD1234"));

		assertEquals(HttpStatus.GONE, ex.getStatus());
	}

	@Test
	void redeemRejectsAnUnknownCode() {
		when(inviteCodeRepository.findByCode("ZZZZZZZZ")).thenReturn(Optional.empty());

		ApiException ex = assertThrows(ApiException.class,
				() -> friendService.redeemInvite("user-9", "ZZZZZZZZ"));

		assertEquals(HttpStatus.NOT_FOUND, ex.getStatus());
	}

	@Test
	void redeemRejectsWhenTheFriendLimitIsReached() {
		friendService = new FriendService(friendPairRepository, inviteCodeRepository, userService, 60, 1);
		givenValidInviteCode("ABCD1234", "user-1");
		when(userService.requireById(anyString())).thenAnswer(i -> user(i.getArgument(0), "Someone"));
		when(friendPairRepository.countByUserIdAndStatus("user-9", PairStatus.ACTIVE)).thenReturn(1L);

		ApiException ex = assertThrows(ApiException.class,
				() -> friendService.redeemInvite("user-9", "ABCD1234"));

		assertEquals(HttpStatus.CONFLICT, ex.getStatus());
	}

	@Test
	void listFriendsReturnsTheOtherSideWithTheirPublicKey() {
		FriendPairDocument pair = FriendPairDocument.create(
				"user-9", "user-1", ConnectedVia.INVITE_CODE, PairStatus.ACTIVE, Instant.now());
		pair.setId("pair-1");
		when(friendPairRepository.findAllByUserIdAndStatus("user-9", PairStatus.ACTIVE))
				.thenReturn(List.of(pair));

		UserDocument friend = user("user-1", "Ada");
		friend.setPublicKey("base64-x25519-key");
		friend.setKeyVersion(3);
		when(userService.findAllByIds(any())).thenReturn(List.of(friend));

		List<FriendSummary> friends = friendService.listFriends("user-9");

		assertEquals(1, friends.size());
		assertEquals("user-1", friends.get(0).userId());
		assertEquals("base64-x25519-key", friends.get(0).publicKey());
		assertEquals(3, friends.get(0).keyVersion());
		assertEquals("ACTIVE", friends.get(0).status());
	}

	@Test
	void areActiveFriendsIsFalseForSelfAndForRevokedPairs() {
		assertFalse(friendService.areActiveFriends("user-1", "user-1"));

		FriendPairDocument revoked = FriendPairDocument.create(
				"user-1", "user-9", ConnectedVia.INVITE_CODE, PairStatus.ACTIVE, Instant.now());
		revoked.setStatus(PairStatus.REVOKED);
		when(friendPairRepository.findByUserAIdAndUserBId("user-1", "user-9"))
				.thenReturn(Optional.of(revoked));

		assertFalse(friendService.areActiveFriends("user-9", "user-1"));
	}

	@Test
	void revokeMarksThePairRevokedFromEitherSide() {
		FriendPairDocument pair = FriendPairDocument.create(
				"user-1", "user-9", ConnectedVia.INVITE_CODE, PairStatus.ACTIVE, Instant.now());
		when(friendPairRepository.findByUserAIdAndUserBId("user-1", "user-9"))
				.thenReturn(Optional.of(pair));
		when(friendPairRepository.save(any(FriendPairDocument.class)))
				.thenAnswer(invocation -> invocation.getArgument(0));

		friendService.revokeFriend("user-9", "user-1");

		ArgumentCaptor<FriendPairDocument> captor = ArgumentCaptor.forClass(FriendPairDocument.class);
		verify(friendPairRepository).save(captor.capture());
		assertEquals(PairStatus.REVOKED, captor.getValue().getStatus());
	}

	@Test
	void revokeRejectsAnUnknownFriendship() {
		when(friendPairRepository.findByUserAIdAndUserBId("user-1", "user-9")).thenReturn(Optional.empty());

		ApiException ex = assertThrows(ApiException.class,
				() -> friendService.revokeFriend("user-9", "user-1"));

		assertEquals(HttpStatus.NOT_FOUND, ex.getStatus());
	}

	private void givenValidInviteCode(String code, String ownerUserId) {
		InviteCodeDocument invite = new InviteCodeDocument();
		invite.setCode(code);
		invite.setOwnerUserId(ownerUserId);
		invite.setUsesRemaining(1);
		invite.setExpiresAt(Instant.now().plus(Duration.ofMinutes(30)));
		lenient().when(inviteCodeRepository.findByCode(code)).thenReturn(Optional.of(invite));
	}

	private static UserDocument user(String id, String displayName) {
		UserDocument user = new UserDocument();
		user.setId(id);
		user.setDisplayName(displayName);
		return user;
	}
}
