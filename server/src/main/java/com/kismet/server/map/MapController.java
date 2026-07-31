package com.kismet.server.map;

import java.util.List;

import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.kismet.server.config.AuthUser;

/**
 * There is deliberately no nearby endpoint here. Proximity cannot be computed server-side
 * against ciphertext, so the client intersects this availability view with the location
 * blobs it decrypts locally.
 */
@RestController
@RequestMapping("/map")
public class MapController {

	private final MapService mapService;

	public MapController(MapService mapService) {
		this.mapService = mapService;
	}

	@GetMapping("/friends")
	public MapFriendsResponse friends(@AuthenticationPrincipal AuthUser authUser) {
		return new MapFriendsResponse(mapService.friendsForMap(authUser.userId()));
	}

	@GetMapping("/friends/{friendUserId}")
	public MapFriend friend(
			@AuthenticationPrincipal AuthUser authUser,
			@PathVariable String friendUserId) {
		return mapService.friendDetail(authUser.userId(), friendUserId);
	}

	public record MapFriendsResponse(List<MapFriend> friends) {
	}
}
