package com.kismet.server.auth;

import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.kismet.server.auth.dto.AppleAuthRequest;
import com.kismet.server.auth.dto.AuthResponse;
import com.kismet.server.auth.dto.RefreshRequest;
import com.kismet.server.config.AuthUser;

import jakarta.validation.Valid;

@RestController
@RequestMapping("/auth")
@Validated
public class AuthController {

	private final AuthService authService;

	public AuthController(AuthService authService) {
		this.authService = authService;
	}

	@PostMapping("/apple")
	public AuthResponse apple(@Valid @RequestBody AppleAuthRequest request) {
		return authService.signInWithApple(request);
	}

	@PostMapping("/refresh")
	public AuthResponse refresh(@Valid @RequestBody RefreshRequest request) {
		return authService.refresh(request.getRefreshToken());
	}

	@PostMapping("/logout")
	public ResponseEntity<Void> logout(@AuthenticationPrincipal AuthUser authUser) {
		authService.logout(authUser.userId());
		return ResponseEntity.noContent().build();
	}
}
