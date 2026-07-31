package com.kismet.server.realtime;

import java.util.Collection;

import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Component;

@Component
public class RealtimeEventPublisher {

	private static final String MAP_QUEUE = "/queue/map";

	private final SimpMessagingTemplate messagingTemplate;

	public RealtimeEventPublisher(SimpMessagingTemplate messagingTemplate) {
		this.messagingTemplate = messagingTemplate;
	}

	/** Tells {@code recipientUserId} that {@code senderUserId} has left them a new blob. */
	public void blobAvailable(String recipientUserId, String senderUserId) {
		send(recipientUserId, RealtimeEvent.of(RealtimeEvent.BLOB_AVAILABLE, senderUserId));
	}

	public void blobsAvailable(Collection<String> recipientUserIds, String senderUserId) {
		for (String recipientUserId : recipientUserIds) {
			blobAvailable(recipientUserId, senderUserId);
		}
	}

	public void pairCreated(String userId, String friendUserId) {
		send(userId, RealtimeEvent.of(RealtimeEvent.FRIEND_PAIR_CREATED, friendUserId));
	}

	public void pairRevoked(String userId, String friendUserId) {
		send(userId, RealtimeEvent.of(RealtimeEvent.FRIEND_PAIR_REVOKED, friendUserId));
	}

	private void send(String userId, RealtimeEvent event) {
		messagingTemplate.convertAndSendToUser(userId, MAP_QUEUE, event);
	}
}
