package com.kismet.server.realtime;

import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

import com.kismet.server.friend.FriendPairedEvent;
import com.kismet.server.friend.FriendRevokedEvent;

/**
 * Pushes friend-graph changes to both sides so a client's friend list and map refresh
 * without polling. Listening to domain events keeps FriendService unaware of messaging.
 */
@Component
public class FriendEventListener {

	private final RealtimeEventPublisher realtimeEventPublisher;

	public FriendEventListener(RealtimeEventPublisher realtimeEventPublisher) {
		this.realtimeEventPublisher = realtimeEventPublisher;
	}

	@EventListener
	public void onPaired(FriendPairedEvent event) {
		realtimeEventPublisher.pairCreated(event.userId(), event.friendUserId());
		realtimeEventPublisher.pairCreated(event.friendUserId(), event.userId());
	}

	@EventListener
	public void onRevoked(FriendRevokedEvent event) {
		realtimeEventPublisher.pairRevoked(event.userId(), event.friendUserId());
		realtimeEventPublisher.pairRevoked(event.friendUserId(), event.userId());
	}
}
