package com.kismet.server.realtime;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;

import java.util.List;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.messaging.simp.SimpMessagingTemplate;

import com.kismet.server.friend.FriendPairedEvent;
import com.kismet.server.friend.FriendRevokedEvent;

@ExtendWith(MockitoExtension.class)
class RealtimeEventPublisherTest {

	@Mock
	private SimpMessagingTemplate messagingTemplate;

	@InjectMocks
	private RealtimeEventPublisher publisher;

	@Test
	void blobEventsCarryTheSenderButNeverCiphertext() {
		publisher.blobAvailable("recipient-1", "sender-1");

		RealtimeEvent event = captureEventTo("recipient-1");
		assertEquals(RealtimeEvent.BLOB_AVAILABLE, event.type());
		assertEquals("sender-1", event.userId());
		// The record has no ciphertext field at all, which is the point: the socket
		// notifies, and the client fetches over HTTP when it chooses to.
		assertEquals(3, RealtimeEvent.class.getRecordComponents().length);
	}

	@Test
	void oneUploadNotifiesEveryRecipient() {
		publisher.blobsAvailable(List.of("recipient-1", "recipient-2"), "sender-1");

		verify(messagingTemplate).convertAndSendToUser(eq("recipient-1"), eq("/queue/map"), org.mockito.ArgumentMatchers.any(Object.class));
		verify(messagingTemplate).convertAndSendToUser(eq("recipient-2"), eq("/queue/map"), org.mockito.ArgumentMatchers.any(Object.class));
	}

	@Test
	void pairEventsAreAddressedToTheUserBeingNotified() {
		publisher.pairCreated("user-1", "friend-a");

		RealtimeEvent event = captureEventTo("user-1");
		assertEquals(RealtimeEvent.FRIEND_PAIR_CREATED, event.type());
		assertEquals("friend-a", event.userId());
	}

	@Test
	void revokeEventsUseTheirOwnType() {
		publisher.pairRevoked("user-1", "friend-a");

		assertEquals(RealtimeEvent.FRIEND_PAIR_REVOKED, captureEventTo("user-1").type());
	}

	@Test
	void bothSidesAreNotifiedWhenAPairIsCreated() {
		new FriendEventListener(publisher).onPaired(new FriendPairedEvent("user-1", "friend-a"));

		assertEquals("friend-a", captureEventTo("user-1").userId());
		assertEquals("user-1", captureEventTo("friend-a").userId());
	}

	@Test
	void bothSidesAreNotifiedWhenAPairIsRevoked() {
		new FriendEventListener(publisher).onRevoked(new FriendRevokedEvent("user-1", "friend-a"));

		assertEquals(RealtimeEvent.FRIEND_PAIR_REVOKED, captureEventTo("user-1").type());
		assertEquals(RealtimeEvent.FRIEND_PAIR_REVOKED, captureEventTo("friend-a").type());
	}

	private RealtimeEvent captureEventTo(String userId) {
		ArgumentCaptor<Object> captor = ArgumentCaptor.forClass(Object.class);
		verify(messagingTemplate).convertAndSendToUser(eq(userId), eq("/queue/map"), captor.capture());
		return (RealtimeEvent) captor.getValue();
	}
}
