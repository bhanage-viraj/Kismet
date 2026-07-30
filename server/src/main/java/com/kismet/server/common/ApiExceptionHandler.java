package com.kismet.server.common;

import java.time.Instant;
import java.util.Map;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice
public class ApiExceptionHandler {

	@ExceptionHandler(ApiException.class)
	public ResponseEntity<Map<String, Object>> handleApi(ApiException ex) {
		return ResponseEntity.status(ex.getStatus()).body(errorBody(ex.getStatus().value(), ex.getMessage()));
	}

	@ExceptionHandler(MethodArgumentNotValidException.class)
	public ResponseEntity<Map<String, Object>> handleValidation(MethodArgumentNotValidException ex) {
		String message = ex.getBindingResult().getFieldErrors().stream()
				.findFirst()
				.map(err -> err.getField() + ": " + err.getDefaultMessage())
				.orElse("Validation failed");
		return ResponseEntity.badRequest().body(errorBody(HttpStatus.BAD_REQUEST.value(), message));
	}

	@ExceptionHandler(Exception.class)
	public ResponseEntity<Map<String, Object>> handleGeneric(Exception ex) {
		return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
				.body(errorBody(HttpStatus.INTERNAL_SERVER_ERROR.value(), "Internal server error"));
	}

	private static Map<String, Object> errorBody(int status, String message) {
		return Map.of(
				"status", status,
				"message", message,
				"timestamp", Instant.now().toString());
	}
}
