package com.kismet.server.user;

import java.time.Instant;
import java.util.List;
import java.util.Map;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

@Document(collection = "users")
public class UserDocument {

	@Id
	private String id;

	@Indexed(unique = true)
	private String appleSub;

	private String email;
	private String displayName;
	private List<String> interests = List.of();
	private String weekdayAvailability;
	private String weekendAvailability;
	private String customAvailabilityStart;
	private String customAvailabilityEnd;
	private Map<String, AvailabilityWindow> dailyAvailability = Map.of();
	private String timeZoneId;

	/** Base64 X25519 public key. Opaque to the server; never used for any server-side crypto. */
	private String publicKey;

	private int keyVersion;
	private Instant keyUpdatedAt;
	private String refreshTokenHash;
	private boolean onboardingCompleted;
	private Instant createdAt;
	private Instant updatedAt;

	public String getId() {
		return id;
	}

	public void setId(String id) {
		this.id = id;
	}

	public String getAppleSub() {
		return appleSub;
	}

	public void setAppleSub(String appleSub) {
		this.appleSub = appleSub;
	}

	public String getEmail() {
		return email;
	}

	public void setEmail(String email) {
		this.email = email;
	}

	public String getDisplayName() {
		return displayName;
	}

	public void setDisplayName(String displayName) {
		this.displayName = displayName;
	}

	public List<String> getInterests() {
		return interests == null ? List.of() : interests;
	}

	public void setInterests(List<String> interests) {
		this.interests = interests == null ? List.of() : List.copyOf(interests);
	}

	public String getWeekdayAvailability() {
		return weekdayAvailability;
	}

	public void setWeekdayAvailability(String weekdayAvailability) {
		this.weekdayAvailability = weekdayAvailability;
	}

	public String getWeekendAvailability() {
		return weekendAvailability;
	}

	public void setWeekendAvailability(String weekendAvailability) {
		this.weekendAvailability = weekendAvailability;
	}

	public String getCustomAvailabilityStart() {
		return customAvailabilityStart;
	}

	public void setCustomAvailabilityStart(String customAvailabilityStart) {
		this.customAvailabilityStart = customAvailabilityStart;
	}

	public String getCustomAvailabilityEnd() {
		return customAvailabilityEnd;
	}

	public void setCustomAvailabilityEnd(String customAvailabilityEnd) {
		this.customAvailabilityEnd = customAvailabilityEnd;
	}

	public Map<String, AvailabilityWindow> getDailyAvailability() {
		return dailyAvailability == null ? Map.of() : dailyAvailability;
	}

	public void setDailyAvailability(Map<String, AvailabilityWindow> dailyAvailability) {
		this.dailyAvailability = dailyAvailability == null ? Map.of() : Map.copyOf(dailyAvailability);
	}

	public String getTimeZoneId() {
		return timeZoneId;
	}

	public void setTimeZoneId(String timeZoneId) {
		this.timeZoneId = timeZoneId;
	}

	public String getPublicKey() {
		return publicKey;
	}

	public void setPublicKey(String publicKey) {
		this.publicKey = publicKey;
	}

	public int getKeyVersion() {
		return keyVersion;
	}

	public void setKeyVersion(int keyVersion) {
		this.keyVersion = keyVersion;
	}

	public Instant getKeyUpdatedAt() {
		return keyUpdatedAt;
	}

	public void setKeyUpdatedAt(Instant keyUpdatedAt) {
		this.keyUpdatedAt = keyUpdatedAt;
	}

	public String getRefreshTokenHash() {
		return refreshTokenHash;
	}

	public void setRefreshTokenHash(String refreshTokenHash) {
		this.refreshTokenHash = refreshTokenHash;
	}

	public boolean isOnboardingCompleted() {
		return onboardingCompleted;
	}

	public void setOnboardingCompleted(boolean onboardingCompleted) {
		this.onboardingCompleted = onboardingCompleted;
	}

	public Instant getCreatedAt() {
		return createdAt;
	}

	public void setCreatedAt(Instant createdAt) {
		this.createdAt = createdAt;
	}

	public Instant getUpdatedAt() {
		return updatedAt;
	}

	public void setUpdatedAt(Instant updatedAt) {
		this.updatedAt = updatedAt;
	}

	public static class AvailabilityWindow {
		private int startMinutes;
		private int endMinutes;
		private List<BusySegment> busySegments = List.of();

		public AvailabilityWindow() {
		}

		public AvailabilityWindow(int startMinutes, int endMinutes, List<BusySegment> busySegments) {
			this.startMinutes = startMinutes;
			this.endMinutes = endMinutes;
			this.busySegments = busySegments == null ? List.of() : List.copyOf(busySegments);
		}

		public int getStartMinutes() {
			return startMinutes;
		}

		public void setStartMinutes(int startMinutes) {
			this.startMinutes = startMinutes;
		}

		public int getEndMinutes() {
			return endMinutes;
		}

		public void setEndMinutes(int endMinutes) {
			this.endMinutes = endMinutes;
		}

		public List<BusySegment> getBusySegments() {
			return busySegments == null ? List.of() : busySegments;
		}

		public void setBusySegments(List<BusySegment> busySegments) {
			this.busySegments = busySegments == null ? List.of() : List.copyOf(busySegments);
		}
	}

	public static class BusySegment {
		private int startMinutes;
		private int endMinutes;

		public BusySegment() {
		}

		public BusySegment(int startMinutes, int endMinutes) {
			this.startMinutes = startMinutes;
			this.endMinutes = endMinutes;
		}

		public int getStartMinutes() {
			return startMinutes;
		}

		public void setStartMinutes(int startMinutes) {
			this.startMinutes = startMinutes;
		}

		public int getEndMinutes() {
			return endMinutes;
		}

		public void setEndMinutes(int endMinutes) {
			this.endMinutes = endMinutes;
		}
	}
}
