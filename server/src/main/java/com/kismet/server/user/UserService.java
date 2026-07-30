package com.kismet.server.user;

import java.time.Instant;
import java.util.Optional;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

import com.kismet.server.common.ApiException;

@Service
public class UserService {

	private final UserRepository userRepository;

	public UserService(UserRepository userRepository) {
		this.userRepository = userRepository;
	}

	public Optional<UserDocument> findById(String id) {
		return userRepository.findById(id);
	}

	public UserDocument requireById(String id) {
		return userRepository.findById(id)
				.orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "User not found"));
	}

	public FindOrCreateResult findOrCreateByAppleSub(String appleSub, String email, String displayName) {
		Optional<UserDocument> existing = userRepository.findByAppleSub(appleSub);
		if (existing.isPresent()) {
			UserDocument user = existing.get();
			boolean dirty = false;
			if ((user.getEmail() == null || user.getEmail().isBlank()) && email != null && !email.isBlank()) {
				user.setEmail(email);
				dirty = true;
			}
			if ((user.getDisplayName() == null || user.getDisplayName().isBlank())
					&& displayName != null && !displayName.isBlank()) {
				user.setDisplayName(displayName);
				dirty = true;
			}
			if (dirty) {
				user.setUpdatedAt(Instant.now());
				user = userRepository.save(user);
			}
			return new FindOrCreateResult(user, false);
		}

		Instant now = Instant.now();
		UserDocument created = new UserDocument();
		created.setAppleSub(appleSub);
		created.setEmail(email);
		created.setDisplayName(displayName);
		created.setOnboardingCompleted(false);
		created.setCreatedAt(now);
		created.setUpdatedAt(now);
		return new FindOrCreateResult(userRepository.save(created), true);
	}

	public UserDocument save(UserDocument user) {
		user.setUpdatedAt(Instant.now());
		return userRepository.save(user);
	}

	public UserDocument markOnboardingCompleted(String userId) {
		UserDocument user = requireById(userId);
		user.setOnboardingCompleted(true);
		return save(user);
	}

	public record FindOrCreateResult(UserDocument user, boolean isNewUser) {
	}
}
