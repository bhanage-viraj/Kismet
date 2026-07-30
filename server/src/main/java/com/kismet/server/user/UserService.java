package com.kismet.server.user;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.Set;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

import com.kismet.server.common.ApiException;

@Service
public class UserService {

	private static final Set<String> ALLOWED_INTERESTS = Set.of(
			"coffee", "music", "art", "badminton", "football", "gym", "movies", "coding", "travel",
			"reading", "food", "nature", "gaming", "photography", "wellness");
	private static final Set<String> WEEKDAY_AVAILABILITY = Set.of(
			"After 5:00 PM", "After 6:00 PM", "After 7:00 PM", "Anytime", "Custom");
	private static final Set<String> WEEKEND_AVAILABILITY = Set.of(
			"Anytime", "Mornings", "Afternoons", "Evenings", "Custom");
	private static final Set<String> DAYS = Set.of(
			"monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday");

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

	public UserDocument completeOnboarding(
			String userId,
			String weekdayAvailability,
			String weekendAvailability,
			List<AvailabilityInput> dailyAvailability) {
		if (!WEEKDAY_AVAILABILITY.contains(weekdayAvailability)
				|| !WEEKEND_AVAILABILITY.contains(weekendAvailability)) {
			throw new ApiException(HttpStatus.BAD_REQUEST, "Invalid availability selection");
		}

		Map<String, UserDocument.AvailabilityWindow> windows = new LinkedHashMap<>();
		if (dailyAvailability != null) {
			for (AvailabilityInput input : dailyAvailability) {
				if (input == null
						|| !DAYS.contains(input.day())
						|| input.startMinutes() < 6 * 60
						|| input.endMinutes() > 24 * 60
						|| input.startMinutes() >= input.endMinutes()) {
					throw new ApiException(HttpStatus.BAD_REQUEST, "Invalid daily availability");
				}
				List<UserDocument.BusySegment> busy = normalizeBusySegments(input.busySegments());
				windows.put(
						input.day(),
						new UserDocument.AvailabilityWindow(input.startMinutes(), input.endMinutes(), busy));
			}
		}
		if (!windows.keySet().equals(DAYS)) {
			throw new ApiException(HttpStatus.BAD_REQUEST, "Availability is required for every day");
		}

		UserDocument user = requireById(userId);
		user.setWeekdayAvailability(weekdayAvailability);
		user.setWeekendAvailability(weekendAvailability);
		user.setDailyAvailability(windows);
		user.setOnboardingCompleted(true);
		return save(user);
	}

	public UserDocument updateInterests(String userId, List<String> interests) {
		UserDocument user = requireById(userId);
		LinkedHashSet<String> normalized = new LinkedHashSet<>();
		if (interests != null) {
			interests.stream()
					.filter(value -> value != null && !value.isBlank())
					.map(value -> value.trim().toLowerCase(Locale.ROOT))
					.filter(ALLOWED_INTERESTS::contains)
					.limit(ALLOWED_INTERESTS.size())
					.forEach(normalized::add);
		}
		user.setInterests(List.copyOf(normalized));
		return save(user);
	}

	public record FindOrCreateResult(UserDocument user, boolean isNewUser) {
	}

	public record AvailabilityInput(
			String day,
			int startMinutes,
			int endMinutes,
			List<BusySegmentInput> busySegments) {
	}

	public record BusySegmentInput(int startMinutes, int endMinutes) {
	}

	private static List<UserDocument.BusySegment> normalizeBusySegments(List<BusySegmentInput> busySegments) {
		if (busySegments == null || busySegments.isEmpty()) {
			return List.of();
		}

		List<UserDocument.BusySegment> normalized = new java.util.ArrayList<>();
		for (BusySegmentInput segment : busySegments) {
			if (segment == null) {
				continue;
			}
			int start = Math.max(segment.startMinutes(), 6 * 60);
			int end = Math.min(segment.endMinutes(), 24 * 60);
			if (start >= end) {
				continue;
			}
			normalized.add(new UserDocument.BusySegment(start, end));
		}
		normalized.sort(java.util.Comparator.comparingInt(UserDocument.BusySegment::getStartMinutes));

		List<UserDocument.BusySegment> merged = new java.util.ArrayList<>();
		for (UserDocument.BusySegment segment : normalized) {
			if (merged.isEmpty()) {
				merged.add(segment);
				continue;
			}
			UserDocument.BusySegment last = merged.get(merged.size() - 1);
			if (segment.getStartMinutes() <= last.getEndMinutes()) {
				last.setEndMinutes(Math.max(last.getEndMinutes(), segment.getEndMinutes()));
			} else {
				merged.add(segment);
			}
		}
		return List.copyOf(merged);
	}
}
