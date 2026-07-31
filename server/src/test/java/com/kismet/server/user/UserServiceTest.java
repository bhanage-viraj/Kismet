package com.kismet.server.user;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;

import com.kismet.server.common.ApiException;

@ExtendWith(MockitoExtension.class)
class UserServiceTest {

	@Mock
	private UserRepository userRepository;

	private UserService userService;

	@BeforeEach
	void setUp() {
		userService = new UserService(userRepository);
	}

	@Test
	void updatePublicKeyStoresTheKeyAndStampsTheTime() {
		givenUser(existing -> existing.setKeyVersion(0));

		UserDocument updated = userService.updatePublicKey("user-1", "base64-x25519-key", 1);

		assertEquals("base64-x25519-key", updated.getPublicKey());
		assertEquals(1, updated.getKeyVersion());
		assertNotNull(updated.getKeyUpdatedAt());
	}

	@Test
	void updatePublicKeyRejectsADowngradeToAnOlderVersion() {
		givenUser(existing -> {
			existing.setPublicKey("current-key");
			existing.setKeyVersion(5);
		});

		ApiException ex = assertThrows(ApiException.class,
				() -> userService.updatePublicKey("user-1", "stale-key", 4));

		assertEquals(HttpStatus.CONFLICT, ex.getStatus());
		verify(userRepository, never()).save(any());
	}

	@Test
	void updatePublicKeyRejectsRotatingWithoutBumpingTheVersion() {
		givenUser(existing -> {
			existing.setPublicKey("current-key");
			existing.setKeyVersion(5);
		});

		ApiException ex = assertThrows(ApiException.class,
				() -> userService.updatePublicKey("user-1", "different-key", 5));

		assertEquals(HttpStatus.CONFLICT, ex.getStatus());
	}

	@Test
	void updatePublicKeyIsIdempotentForTheSameKeyAndVersion() {
		givenUser(existing -> {
			existing.setPublicKey("current-key");
			existing.setKeyVersion(5);
		});

		UserDocument updated = userService.updatePublicKey("user-1", "current-key", 5);

		assertEquals(5, updated.getKeyVersion());
	}

	@Test
	void updateTimeZoneAcceptsAnIanaZoneAndRejectsGarbage() {
		givenUser(existing -> {
		});

		assertEquals("Asia/Singapore", userService.updateTimeZone("user-1", "Asia/Singapore").getTimeZoneId());

		ApiException ex = assertThrows(ApiException.class,
				() -> userService.updateTimeZone("user-1", "Middle/Earth"));
		assertEquals(HttpStatus.BAD_REQUEST, ex.getStatus());
	}

	private void givenUser(java.util.function.Consumer<UserDocument> customizer) {
		UserDocument user = new UserDocument();
		user.setId("user-1");
		user.setDisplayName("Ada");
		customizer.accept(user);
		when(userRepository.findById("user-1")).thenReturn(Optional.of(user));
		org.mockito.Mockito.lenient().when(userRepository.save(any(UserDocument.class)))
				.thenAnswer(invocation -> invocation.getArgument(0));
	}
}
