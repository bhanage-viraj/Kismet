package com.kismet.server.availability;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.Test;

import com.kismet.server.user.UserDocument;

class AvailabilityEvaluatorTest {

	private static final ZoneId SINGAPORE = ZoneId.of("Asia/Singapore");
	private static final ZoneId NEW_YORK = ZoneId.of("America/New_York");

	private final AvailabilityEvaluator evaluator = new AvailabilityEvaluator();

	@Test
	void insideTheWindowIsFreeUntilTheWindowEnds() {
		// Thursday 2026-07-30, free 18:00-24:00, asked at 19:00 local.
		UserDocument user = user(SINGAPORE, everyDay(18 * 60, 24 * 60));

		AvailabilitySnapshot snapshot = evaluator.evaluate(user, local(2026, 7, 30, 19, 0, SINGAPORE));

		assertEquals(AvailabilityStatus.FREE, snapshot.status());
		assertEquals(local(2026, 7, 31, 0, 0, SINGAPORE), snapshot.freeUntil());
		assertNull(snapshot.freeFrom());
	}

	@Test
	void beforeTheWindowIsBusyUntilItOpens() {
		UserDocument user = user(SINGAPORE, everyDay(18 * 60, 24 * 60));

		AvailabilitySnapshot snapshot = evaluator.evaluate(user, local(2026, 7, 30, 9, 0, SINGAPORE));

		assertEquals(AvailabilityStatus.BUSY, snapshot.status());
		assertEquals(local(2026, 7, 30, 18, 0, SINGAPORE), snapshot.freeFrom());
		assertNull(snapshot.freeUntil());
	}

	@Test
	void afterTheWindowRollsOverToTheNextDay() {
		// 23:59 sits inside a window that ends at midnight, so the next free time is
		// tomorrow evening rather than tonight.
		UserDocument user = user(SINGAPORE, everyDay(18 * 60, 23 * 60 + 30));

		AvailabilitySnapshot snapshot = evaluator.evaluate(user, local(2026, 7, 30, 23, 59, SINGAPORE));

		assertEquals(AvailabilityStatus.BUSY, snapshot.status());
		assertEquals(local(2026, 7, 31, 18, 0, SINGAPORE), snapshot.freeFrom());
	}

	@Test
	void aBusySegmentInsideTheWindowCutsItShort() {
		Map<String, UserDocument.AvailabilityWindow> weekly = everyDay(18 * 60, 24 * 60);
		weekly.put("thursday", window(18 * 60, 24 * 60, segment(20 * 60, 21 * 60)));
		UserDocument user = user(SINGAPORE, weekly);

		AvailabilitySnapshot snapshot = evaluator.evaluate(user, local(2026, 7, 30, 19, 0, SINGAPORE));

		assertEquals(AvailabilityStatus.FREE, snapshot.status());
		assertEquals(local(2026, 7, 30, 20, 0, SINGAPORE), snapshot.freeUntil());
	}

	@Test
	void beingInsideABusySegmentIsBusyUntilItEnds() {
		Map<String, UserDocument.AvailabilityWindow> weekly = everyDay(18 * 60, 24 * 60);
		weekly.put("thursday", window(18 * 60, 24 * 60, segment(20 * 60, 21 * 60)));
		UserDocument user = user(SINGAPORE, weekly);

		AvailabilitySnapshot snapshot = evaluator.evaluate(user, local(2026, 7, 30, 20, 30, SINGAPORE));

		assertEquals(AvailabilityStatus.BUSY, snapshot.status());
		assertEquals(local(2026, 7, 30, 21, 0, SINGAPORE), snapshot.freeFrom());
	}

	@Test
	void aBusySegmentCoveringTheWholeWindowLeavesNoFreeTimeThatDay() {
		Map<String, UserDocument.AvailabilityWindow> weekly = everyDay(18 * 60, 24 * 60);
		weekly.put("thursday", window(18 * 60, 24 * 60, segment(18 * 60, 24 * 60)));
		UserDocument user = user(SINGAPORE, weekly);

		AvailabilitySnapshot snapshot = evaluator.evaluate(user, local(2026, 7, 30, 19, 0, SINGAPORE));

		assertEquals(AvailabilityStatus.BUSY, snapshot.status());
		assertEquals(local(2026, 7, 31, 18, 0, SINGAPORE), snapshot.freeFrom());
	}

	@Test
	void adjacentBusySegmentsMergeIntoOneGap() {
		Map<String, UserDocument.AvailabilityWindow> weekly = everyDay(18 * 60, 24 * 60);
		weekly.put("thursday", window(18 * 60, 24 * 60,
				segment(19 * 60, 20 * 60), segment(20 * 60, 22 * 60)));
		UserDocument user = user(SINGAPORE, weekly);

		AvailabilitySnapshot snapshot = evaluator.evaluate(user, local(2026, 7, 30, 19, 30, SINGAPORE));

		assertEquals(AvailabilityStatus.BUSY, snapshot.status());
		assertEquals(local(2026, 7, 30, 22, 0, SINGAPORE), snapshot.freeFrom());
	}

	@Test
	void aDayWithNoWindowIsSkipped() {
		Map<String, UserDocument.AvailabilityWindow> weekly = everyDay(18 * 60, 24 * 60);
		weekly.remove("friday");
		UserDocument user = user(SINGAPORE, weekly);

		// Thursday 23:59, so the next candidate day is Friday, which has no window at all.
		AvailabilitySnapshot snapshot = evaluator.evaluate(user, local(2026, 7, 31, 0, 30, SINGAPORE));

		assertEquals(AvailabilityStatus.BUSY, snapshot.status());
		assertEquals(local(2026, 8, 1, 18, 0, SINGAPORE), snapshot.freeFrom());
	}

	@Test
	void theSameInstantResolvesDifferentlyInDifferentZones() {
		Map<String, UserDocument.AvailabilityWindow> weekly = everyDay(18 * 60, 24 * 60);
		// 2026-07-30T12:00Z is 20:00 in Singapore but 08:00 in New York.
		Instant instant = Instant.parse("2026-07-30T12:00:00Z");

		assertEquals(AvailabilityStatus.FREE, evaluator.evaluate(user(SINGAPORE, weekly), instant).status());
		assertEquals(AvailabilityStatus.BUSY, evaluator.evaluate(user(NEW_YORK, weekly), instant).status());
	}

	@Test
	void windowsTrackTheWallClockAcrossADaylightSavingChange() {
		// New York springs forward at 02:00 on 2026-03-08. A window opening at 18:00 must
		// still open at 18:00 local, which is a different UTC offset than the day before.
		UserDocument user = user(NEW_YORK, everyDay(18 * 60, 24 * 60));

		AvailabilitySnapshot snapshot = evaluator.evaluate(user, local(2026, 3, 8, 12, 0, NEW_YORK));

		assertEquals(AvailabilityStatus.BUSY, snapshot.status());
		assertEquals(local(2026, 3, 8, 18, 0, NEW_YORK), snapshot.freeFrom());
	}

	@Test
	void missingTimezoneIsUnknownRatherThanAGuess() {
		UserDocument user = user(SINGAPORE, everyDay(18 * 60, 24 * 60));
		user.setTimeZoneId(null);

		assertEquals(AvailabilityStatus.UNKNOWN,
				evaluator.evaluate(user, Instant.parse("2026-07-30T12:00:00Z")).status());
	}

	@Test
	void unparseableTimezoneIsUnknown() {
		UserDocument user = user(SINGAPORE, everyDay(18 * 60, 24 * 60));
		user.setTimeZoneId("Middle/Earth");

		assertEquals(AvailabilityStatus.UNKNOWN,
				evaluator.evaluate(user, Instant.parse("2026-07-30T12:00:00Z")).status());
	}

	@Test
	void noAvailabilityConfiguredIsUnknown() {
		UserDocument user = user(SINGAPORE, new LinkedHashMap<>());

		assertEquals(AvailabilityStatus.UNKNOWN,
				evaluator.evaluate(user, Instant.parse("2026-07-30T12:00:00Z")).status());
	}

	private static UserDocument user(ZoneId zone, Map<String, UserDocument.AvailabilityWindow> weekly) {
		UserDocument user = new UserDocument();
		user.setId("user-1");
		user.setTimeZoneId(zone.getId());
		user.setDailyAvailability(weekly);
		return user;
	}

	private static Map<String, UserDocument.AvailabilityWindow> everyDay(int startMinutes, int endMinutes) {
		Map<String, UserDocument.AvailabilityWindow> weekly = new LinkedHashMap<>();
		for (String day : List.of("monday", "tuesday", "wednesday", "thursday", "friday",
				"saturday", "sunday")) {
			weekly.put(day, window(startMinutes, endMinutes));
		}
		return weekly;
	}

	private static UserDocument.AvailabilityWindow window(
			int startMinutes, int endMinutes, UserDocument.BusySegment... busy) {
		return new UserDocument.AvailabilityWindow(startMinutes, endMinutes, List.of(busy));
	}

	private static UserDocument.BusySegment segment(int startMinutes, int endMinutes) {
		return new UserDocument.BusySegment(startMinutes, endMinutes);
	}

	private static Instant local(int year, int month, int day, int hour, int minute, ZoneId zone) {
		return LocalDateTime.of(year, month, day, hour, minute).atZone(zone).toInstant();
	}
}
