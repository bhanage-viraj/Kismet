package com.kismet.server.blob;

import java.util.Map;

import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.kismet.server.blob.dto.BlobAckRequest;
import com.kismet.server.blob.dto.BlobUploadRequest;
import com.kismet.server.blob.dto.BlobUploadResponse;
import com.kismet.server.blob.dto.PendingBlobsResponse;
import com.kismet.server.config.AuthUser;

import jakarta.validation.Valid;

@RestController
@RequestMapping("/blobs")
public class BlobController {

	private final BlobService blobService;

	public BlobController(BlobService blobService) {
		this.blobService = blobService;
	}

	@PostMapping
	public BlobUploadResponse upload(
			@AuthenticationPrincipal AuthUser authUser,
			@Valid @RequestBody BlobUploadRequest request) {
		return blobService.upload(authUser.userId(), request.blobs());
	}

	@GetMapping("/pending")
	public PendingBlobsResponse pending(@AuthenticationPrincipal AuthUser authUser) {
		return new PendingBlobsResponse(blobService.pending(authUser.userId()));
	}

	@PostMapping("/ack")
	public Map<String, Long> acknowledge(
			@AuthenticationPrincipal AuthUser authUser,
			@Valid @RequestBody BlobAckRequest request) {
		return Map.of("deleted", blobService.acknowledge(authUser.userId(), request.blobIds()));
	}
}
