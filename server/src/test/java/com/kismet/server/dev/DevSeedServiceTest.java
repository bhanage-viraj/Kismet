package com.kismet.server.dev;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.List;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.http.HttpStatus;

import com.kismet.server.common.ApiException;
import com.kismet.server.friend.FriendPairDocument;
import com.kismet.server.friend.FriendPairRepository;
import com.kismet.server.friend.FriendService;
import com.kismet.server.friend.PairStatus;
import com.kismet.server.friend.dto.FriendSummary;
import com.kismet.server.user.UserDocument;
import com.kismet.server.user.UserRepository;
import com.kismet.server.user.UserService;

@ExtendWith(MockitoExtension.class)
class DevSeedServiceTest {

	@Mock UserRepository userRepository;
	@Mock UserService userService;
	@Mock FriendPairRepository friendPairRepository;
	@Mock FriendService friendService;
	@Mock ApplicationEventPublisher eventPublisher;

	private DevSeedService enabled;
	private DevSeedService disabled;

	@BeforeEach
	void setUp() {
		enabled = new DevSeedService(
				true, userRepository, userService, friendPairRepository, friendService, eventPublisher);
		disabled = new DevSeedService(
				false, userRepository, userService, friendPairRepository, friendService, eventPublisher);
	}

	@Test
	void refusesWhenDisabled() {
		assertThatThrownBy(() -> disabled.seedTestFriend("caller-1"))
				.isInstanceOf(ApiException.class)
				.extracting(ex -> ((ApiException) ex).getStatus())
				.isEqualTo(HttpStatus.NOT_FOUND);
	}

	@Test
	void createsBotAndActivePair() {
		when(userService.requireById("caller-1")).thenReturn(user("caller-1", "You"));
		when(userRepository.findByAppleSub(DevSeedService.TEST_FRIEND_APPLE_SUB)).thenReturn(Optional.empty());
		when(userRepository.save(any(UserDocument.class))).thenAnswer(inv -> {
			UserDocument bot = inv.getArgument(0);
			bot.setId("bot-1");
			return bot;
		});
		when(friendPairRepository.findByUserAIdAndUserBId(any(), any())).thenReturn(Optional.empty());
		when(friendPairRepository.save(any(FriendPairDocument.class))).thenAnswer(inv -> {
			FriendPairDocument pair = inv.getArgument(0);
			pair.setId("pair-1");
			return pair;
		});
		FriendSummary summary = new FriendSummary(
				"pair-1", "bot-1", DevSeedService.TEST_FRIEND_DISPLAY_NAME, "pk", 1,
				"ACTIVE", "INVITE_CODE", null, true);
		when(friendService.listFriends("caller-1")).thenReturn(List.of(summary));

		FriendSummary result = enabled.seedTestFriend("caller-1");

		assertThat(result.userId()).isEqualTo("bot-1");
		assertThat(result.displayName()).isEqualTo("Alex (Test)");

		ArgumentCaptor<UserDocument> botCaptor = ArgumentCaptor.forClass(UserDocument.class);
		verify(userRepository).save(botCaptor.capture());
		assertThat(botCaptor.getValue().getAppleSub()).isEqualTo(DevSeedService.TEST_FRIEND_APPLE_SUB);
		assertThat(botCaptor.getValue().getDailyAvailability()).hasSize(7);

		ArgumentCaptor<FriendPairDocument> pairCaptor = ArgumentCaptor.forClass(FriendPairDocument.class);
		verify(friendPairRepository).save(pairCaptor.capture());
		assertThat(pairCaptor.getValue().getStatus()).isEqualTo(PairStatus.ACTIVE);
	}

	private static UserDocument user(String id, String name) {
		UserDocument user = new UserDocument();
		user.setId(id);
		user.setDisplayName(name);
		return user;
	}
}
