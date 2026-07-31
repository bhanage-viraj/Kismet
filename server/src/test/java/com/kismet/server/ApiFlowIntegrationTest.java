package com.kismet.server;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.Date;
import java.util.HashSet;
import java.util.Set;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

import com.jayway.jsonpath.JsonPath;
import com.kismet.server.auth.JwtService;

import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;

/**
 * Drives the real HTTP surface end to end: sign in, pair, relay ciphertext, revoke. The
 * security cases matter most here, because the relay cannot inspect what it stores and so
 * relies entirely on the friendship check and the recipient filter.
 */
class ApiFlowIntegrationTest extends AbstractIntegrationTest {

	@Autowired
	private MockMvc mockMvc;

	@Autowired
	private JwtService jwtService;

	@Value("${kismet.jwt.secret}")
	private String jwtSecret;

	@Test
	void protectedEndpointsRejectAnonymousCallers() throws Exception {
		mockMvc.perform(get("/me")).andExpect(status().isUnauthorized());
		mockMvc.perform(get("/friends")).andExpect(status().isUnauthorized());
		mockMvc.perform(get("/blobs/pending")).andExpect(status().isUnauthorized());
		mockMvc.perform(get("/map/friends")).andExpect(status().isUnauthorized());
	}

	@Test
	void aGarbageBearerTokenIsRejected() throws Exception {
		mockMvc.perform(get("/me").header("Authorization", "Bearer not-a-jwt"))
				.andExpect(status().isUnauthorized());
	}

	@Test
	void anExpiredAccessTokenReturns401SoTheClientKnowsToRefresh() throws Exception {
		// The client only refreshes on 401. A 403 here would strand a user who still holds
		// a perfectly good refresh token.
		String expired = expiredAccessTokenFor(signUp("alice").id);

		mockMvc.perform(get("/me").header("Authorization", "Bearer " + expired))
				.andExpect(status().isUnauthorized())
				.andExpect(jsonPath("$.status").value(401))
				.andExpect(jsonPath("$.message").exists());
	}

	@Test
	void everyIssuedTokenIsUniqueEvenWithinTheSameSecond() throws Exception {
		// Timestamps are second-granular, so identical tokens would make refresh rotation
		// silently leave the previous token usable.
		Set<String> tokens = new HashSet<>();
		for (int i = 0; i < 5; i++) {
			tokens.add(jwtService.createRefreshToken("user-1"));
		}

		assertEquals(5, tokens.size());
	}

	@Test
	void signingInTwiceWithTheSameAppleSubjectReturnsTheSameUser() throws Exception {
		String firstUserId = JsonPath.read(signIn("apple-sub-1").andReturn()
				.getResponse().getContentAsString(), "$.user.id");
		String secondUserId = JsonPath.read(signIn("apple-sub-1").andReturn()
				.getResponse().getContentAsString(), "$.user.id");

		assertEquals(firstUserId, secondUserId);
		assertEquals(1, mongoTemplate.getCollection("users").countDocuments());
	}

	@Test
	void twoUsersPairThroughAnInviteCodeAndSeeEachOther() throws Exception {
		User alice = signUp("alice");
		User bob = signUp("bob");

		pair(alice, bob);

		mockMvc.perform(get("/friends").header("Authorization", alice.bearer()))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.friends.length()").value(1))
				.andExpect(jsonPath("$.friends[0].userId").value(bob.id));
		mockMvc.perform(get("/friends").header("Authorization", bob.bearer()))
				.andExpect(jsonPath("$.friends[0].userId").value(alice.id));
	}

	@Test
	void anInviteCodeCannotBeRedeemedTwice() throws Exception {
		User alice = signUp("alice");
		String code = createInvite(alice);

		redeem(signUp("bob"), code).andExpect(status().isOk());
		redeem(signUp("carol"), code).andExpect(status().is4xxClientError());
	}

	@Test
	void youCannotRedeemYourOwnInviteCode() throws Exception {
		User alice = signUp("alice");

		redeem(alice, createInvite(alice)).andExpect(status().is4xxClientError());
	}

	@Test
	void aStrangerCannotPushCiphertextIntoYourMailbox() throws Exception {
		User alice = signUp("alice");
		User stranger = signUp("stranger");

		// The whole point of the relay: without an active pair, nothing lands.
		uploadLocation(stranger, alice, "unwanted").andExpect(status().isForbidden());

		mockMvc.perform(get("/blobs/pending").header("Authorization", alice.bearer()))
				.andExpect(jsonPath("$.blobs.length()").value(0));
	}

	@Test
	void ciphertextReachesTheRecipientUntouchedAndIsInvisibleToTheSender() throws Exception {
		User alice = signUp("alice");
		User bob = signUp("bob");
		pair(alice, bob);

		uploadLocation(alice, bob, "sealed-box-payload").andExpect(status().isOk());

		mockMvc.perform(get("/blobs/pending").header("Authorization", bob.bearer()))
				.andExpect(jsonPath("$.blobs.length()").value(1))
				.andExpect(jsonPath("$.blobs[0].senderUserId").value(alice.id))
				.andExpect(jsonPath("$.blobs[0].kind").value("LOCATION"))
				.andExpect(jsonPath("$.blobs[0].ciphertext").value("sealed-box-payload"));

		// A blob is addressed to one mailbox; the sender does not get a copy back.
		mockMvc.perform(get("/blobs/pending").header("Authorization", alice.bearer()))
				.andExpect(jsonPath("$.blobs.length()").value(0));
	}

	@Test
	void refreshingLocationOverwritesInPlaceRatherThanPilingUp() throws Exception {
		User alice = signUp("alice");
		User bob = signUp("bob");
		pair(alice, bob);

		uploadLocation(alice, bob, "position-1").andExpect(status().isOk());
		uploadLocation(alice, bob, "position-2").andExpect(status().isOk());
		uploadLocation(alice, bob, "position-3").andExpect(status().isOk());

		// A device pushing every few seconds must not grow the collection without bound.
		assertEquals(1, mongoTemplate.getCollection("encrypted_blobs").countDocuments());
		mockMvc.perform(get("/blobs/pending").header("Authorization", bob.bearer()))
				.andExpect(jsonPath("$.blobs.length()").value(1))
				.andExpect(jsonPath("$.blobs[0].ciphertext").value("position-3"));
	}

	@Test
	void acknowledgingRemovesOnlyYourOwnBlobs() throws Exception {
		User alice = signUp("alice");
		User bob = signUp("bob");
		User carol = signUp("carol");
		pair(alice, bob);
		pair(alice, carol);
		uploadLocation(alice, bob, "for-bob").andExpect(status().isOk());
		uploadLocation(alice, carol, "for-carol").andExpect(status().isOk());

		String bobsBlobId = JsonPath.read(mockMvc.perform(
				get("/blobs/pending").header("Authorization", bob.bearer()))
				.andReturn().getResponse().getContentAsString(), "$.blobs[0].id");

		// Carol tries to acknowledge a blob that is not addressed to her.
		mockMvc.perform(post("/blobs/ack")
				.header("Authorization", carol.bearer())
				.contentType(MediaType.APPLICATION_JSON)
				.content("{\"blobIds\":[\"" + bobsBlobId + "\"]}"))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.deleted").value(0));

		mockMvc.perform(get("/blobs/pending").header("Authorization", bob.bearer()))
				.andExpect(jsonPath("$.blobs.length()").value(1));
	}

	@Test
	void revokingAFriendDeletesTheCiphertextBothWays() throws Exception {
		User alice = signUp("alice");
		User bob = signUp("bob");
		pair(alice, bob);
		uploadLocation(alice, bob, "alice-position").andExpect(status().isOk());
		uploadLocation(bob, alice, "bob-position").andExpect(status().isOk());
		assertEquals(2, mongoTemplate.getCollection("encrypted_blobs").countDocuments());

		mockMvc.perform(delete("/friends/" + bob.id).header("Authorization", alice.bearer()))
				.andExpect(status().isNoContent());

		// Unfriending has to revoke access to whatever was already relayed, not just future pushes.
		assertEquals(0, mongoTemplate.getCollection("encrypted_blobs").countDocuments());
		mockMvc.perform(get("/blobs/pending").header("Authorization", bob.bearer()))
				.andExpect(jsonPath("$.blobs.length()").value(0));
		mockMvc.perform(get("/friends").header("Authorization", bob.bearer()))
				.andExpect(jsonPath("$.friends.length()").value(0));
	}

	@Test
	void aRevokedFriendCanNoLongerUpload() throws Exception {
		User alice = signUp("alice");
		User bob = signUp("bob");
		pair(alice, bob);
		mockMvc.perform(delete("/friends/" + bob.id).header("Authorization", alice.bearer()));

		uploadLocation(bob, alice, "after-revoke").andExpect(status().isForbidden());
	}

	@Test
	void theMapViewExposesAvailabilityAndFreshnessButNeverCoordinates() throws Exception {
		User alice = signUp("alice");
		User bob = signUp("bob");
		pair(alice, bob);
		setInterests(bob, "coffee", "climbing");
		setInterests(alice, "coffee", "chess");
		uploadLocation(bob, alice, "cipher-only-bob-can-read");

		String body = mockMvc.perform(get("/map/friends").header("Authorization", alice.bearer()))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.friends[0].userId").value(bob.id))
				.andExpect(jsonPath("$.friends[0].hasLocationBlob").value(true))
				.andExpect(jsonPath("$.friends[0].sharedInterests[0]").value("coffee"))
				.andReturn().getResponse().getContentAsString();

		// The server relays coordinates it cannot read, so they must not leak into this view.
		assertTrue(!body.contains("cipher-only-bob-can-read") && !body.contains("latitude"),
				"map view leaked payload data: " + body);
	}

	@Test
	void theMapDetailEndpointIsClosedToNonFriends() throws Exception {
		User alice = signUp("alice");
		User stranger = signUp("stranger");

		mockMvc.perform(get("/map/friends/" + stranger.id).header("Authorization", alice.bearer()))
				.andExpect(status().isNotFound());
	}

	@Test
	void publicKeysArePublishedToFriendsSoTheyCanEncrypt() throws Exception {
		User alice = signUp("alice");
		User bob = signUp("bob");
		pair(alice, bob);

		mockMvc.perform(put("/me/public-key")
				.header("Authorization", bob.bearer())
				.contentType(MediaType.APPLICATION_JSON)
				.content("{\"publicKey\":\"bobs-x25519-key\",\"keyVersion\":2}"))
				.andExpect(status().isOk());

		mockMvc.perform(get("/friends").header("Authorization", alice.bearer()))
				.andExpect(jsonPath("$.friends[0].publicKey").value("bobs-x25519-key"))
				.andExpect(jsonPath("$.friends[0].keyVersion").value(2));
	}

	@Test
	void refreshRotatesTheRefreshTokenSoTheOldOneStopsWorking() throws Exception {
		User alice = signUp("alice");

		String rotated = mockMvc.perform(post("/auth/refresh")
				.contentType(MediaType.APPLICATION_JSON)
				.content("{\"refreshToken\":\"" + alice.refreshToken + "\"}"))
				.andExpect(status().isOk())
				.andReturn().getResponse().getContentAsString();
		String newRefreshToken = JsonPath.read(rotated, "$.refreshToken");

		assertNotEquals(alice.refreshToken, newRefreshToken);
		mockMvc.perform(post("/auth/refresh")
				.contentType(MediaType.APPLICATION_JSON)
				.content("{\"refreshToken\":\"" + alice.refreshToken + "\"}"))
				.andExpect(status().isUnauthorized());
	}

	@Test
	void anAccessTokenIsNotAcceptedWhereARefreshTokenIsExpected() throws Exception {
		User alice = signUp("alice");

		mockMvc.perform(post("/auth/refresh")
				.contentType(MediaType.APPLICATION_JSON)
				.content("{\"refreshToken\":\"" + alice.accessToken + "\"}"))
				.andExpect(status().isUnauthorized());
	}

	@Test
	void loggingOutInvalidatesTheRefreshToken() throws Exception {
		User alice = signUp("alice");

		mockMvc.perform(post("/auth/logout").header("Authorization", alice.bearer()))
				.andExpect(status().isNoContent());

		mockMvc.perform(post("/auth/refresh")
				.contentType(MediaType.APPLICATION_JSON)
				.content("{\"refreshToken\":\"" + alice.refreshToken + "\"}"))
				.andExpect(status().isUnauthorized());
	}

	// --- helpers -------------------------------------------------------------------

	private record User(String id, String accessToken, String refreshToken) {
		String bearer() {
			return "Bearer " + accessToken;
		}
	}

	private User signUp(String appleSub) throws Exception {
		String body = signIn(appleSub).andExpect(status().isOk())
				.andReturn().getResponse().getContentAsString();
		return new User(
				JsonPath.read(body, "$.user.id"),
				JsonPath.read(body, "$.accessToken"),
				JsonPath.read(body, "$.refreshToken"));
	}

	private ResultActions signIn(String appleSub) throws Exception {
		return mockMvc.perform(post("/auth/apple")
				.contentType(MediaType.APPLICATION_JSON)
				.content("{\"identityToken\":\"" + fakeIdentityToken(appleSub) + "\","
						+ "\"fullName\":{\"givenName\":\"" + appleSub + "\",\"familyName\":\"Test\"}}"));
	}

	private String createInvite(User user) throws Exception {
		String body = mockMvc.perform(post("/friends/invite").header("Authorization", user.bearer()))
				.andExpect(status().isOk())
				.andReturn().getResponse().getContentAsString();
		return JsonPath.read(body, "$.code");
	}

	private ResultActions redeem(User user, String code) throws Exception {
		return mockMvc.perform(post("/friends/redeem")
				.header("Authorization", user.bearer())
				.contentType(MediaType.APPLICATION_JSON)
				.content("{\"inviteCode\":\"" + code + "\"}"));
	}

	private void pair(User a, User b) throws Exception {
		redeem(b, createInvite(a)).andExpect(status().isOk());
	}

	private ResultActions uploadLocation(User sender, User recipient, String ciphertext) throws Exception {
		return mockMvc.perform(post("/blobs")
				.header("Authorization", sender.bearer())
				.contentType(MediaType.APPLICATION_JSON)
				.content("{\"blobs\":[{\"recipientUserId\":\"" + recipient.id + "\","
						+ "\"kind\":\"LOCATION\",\"ciphertext\":\"" + ciphertext + "\",\"keyVersion\":1}]}"));
	}

	private void setInterests(User user, String... interests) throws Exception {
		String json = String.join("\",\"", interests);
		mockMvc.perform(post("/me/interests")
				.header("Authorization", user.bearer())
				.contentType(MediaType.APPLICATION_JSON)
				.content("{\"interests\":[\"" + json + "\"]}"))
				.andExpect(status().isOk());
	}

	/** A correctly signed access token that expired an hour ago. */
	private String expiredAccessTokenFor(String userId) {
		Instant expiredAt = Instant.now().minus(Duration.ofHours(1));
		return Jwts.builder()
				.subject(userId)
				.claim(JwtService.CLAIM_TYPE, JwtService.TYPE_ACCESS)
				.issuedAt(Date.from(expiredAt.minus(Duration.ofHours(1))))
				.expiration(Date.from(expiredAt))
				.signWith(Keys.hmacShaKeyFor(jwtSecret.getBytes(StandardCharsets.UTF_8)))
				.compact();
	}

	/**
	 * Apple signature verification is off outside production, so the server only decodes
	 * the payload. This builds the smallest token that carries a subject.
	 */
	private static String fakeIdentityToken(String appleSub) {
		Base64.Encoder encoder = Base64.getUrlEncoder().withoutPadding();
		String header = encoder.encodeToString("{\"alg\":\"none\"}".getBytes(StandardCharsets.UTF_8));
		String payload = encoder.encodeToString(
				("{\"sub\":\"" + appleSub + "\"}").getBytes(StandardCharsets.UTF_8));
		return header + "." + payload + ".signature";
	}
}
