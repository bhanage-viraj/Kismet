package com.kismet.server.auth.dto;

import java.util.List;

public class AuthResponse {

	private String accessToken;
	private String refreshToken;
	private long expiresIn;
	private UserPayload user;

	public AuthResponse() {
	}

	public AuthResponse(String accessToken, String refreshToken, long expiresIn, UserPayload user) {
		this.accessToken = accessToken;
		this.refreshToken = refreshToken;
		this.expiresIn = expiresIn;
		this.user = user;
	}

	public String getAccessToken() {
		return accessToken;
	}

	public void setAccessToken(String accessToken) {
		this.accessToken = accessToken;
	}

	public String getRefreshToken() {
		return refreshToken;
	}

	public void setRefreshToken(String refreshToken) {
		this.refreshToken = refreshToken;
	}

	public long getExpiresIn() {
		return expiresIn;
	}

	public void setExpiresIn(long expiresIn) {
		this.expiresIn = expiresIn;
	}

	public UserPayload getUser() {
		return user;
	}

	public void setUser(UserPayload user) {
		this.user = user;
	}

	public static class UserPayload {
		private String id;
		private String displayName;
		private String email;
		private List<String> interests;
		private boolean isNewUser;
		private boolean onboardingCompleted;

		public UserPayload() {
		}

		public UserPayload(
				String id,
				String displayName,
				String email,
				List<String> interests,
				boolean isNewUser,
				boolean onboardingCompleted) {
			this.id = id;
			this.displayName = displayName;
			this.email = email;
			this.interests = interests;
			this.isNewUser = isNewUser;
			this.onboardingCompleted = onboardingCompleted;
		}

		public String getId() {
			return id;
		}

		public void setId(String id) {
			this.id = id;
		}

		public String getDisplayName() {
			return displayName;
		}

		public void setDisplayName(String displayName) {
			this.displayName = displayName;
		}

		public String getEmail() {
			return email;
		}

		public void setEmail(String email) {
			this.email = email;
		}

		public List<String> getInterests() {
			return interests;
		}

		public void setInterests(List<String> interests) {
			this.interests = interests;
		}

		@com.fasterxml.jackson.annotation.JsonProperty("isNewUser")
		public boolean getIsNewUser() {
			return isNewUser;
		}

		public void setIsNewUser(boolean isNewUser) {
			this.isNewUser = isNewUser;
		}

		public boolean isOnboardingCompleted() {
			return onboardingCompleted;
		}

		public void setOnboardingCompleted(boolean onboardingCompleted) {
			this.onboardingCompleted = onboardingCompleted;
		}
	}
}
