package com.kismet.server.push;

public record PushTokenRequest(String deviceToken, String platform, String bundleId) {
}
