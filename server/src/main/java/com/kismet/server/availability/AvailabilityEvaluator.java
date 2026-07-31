package com.kismet.server.availability;

import java.time.DateTimeException;
import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;

import org.springframework.stereotype.Component;

import com.kismet.server.user.UserDocument;

/**
 * Answers "is this person free right now, and until when" from their weekly availability.
 * Pure and I/O free so it can be exercised directly against awkward calendar cases.
 * <p>
 * A timezone is mandatory: {@code dailyAvailability} is stored as minutes from midnight
 * with nothing anchoring it, so without a zone the question has no meaning and the result
 * is {@link AvailabilityStatus#UNKNOWN} rather than a guess.
 */
@Component
public class AvailabilityEvaluator {

	private static final int MINUTES_PER_DAY = 24 * 60;

	/** A week plus one day, so a Sunday evening query can still see next Monday. */
	private static final int LOOKAHEAD_DAYS = 8;

	public AvailabilitySnapshot evaluate(UserDocument user, Instant now) {
		ZoneId zone = resolveZone(user.getTimeZoneId());
		Map<String, UserDocument.AvailabilityWindow> weekly = user.getDailyAvailability();
		if (zone == null || weekly.isEmpty()) {
			return AvailabilitySnapshot.unknown();
		}

		List<Interval> free = freeIntervals(weekly, zone, now);
		for (Interval interval : free) {
			if (!now.isBefore(interval.start()) && now.isBefore(interval.end())) {
				return AvailabilitySnapshot.free(interval.end());
			}
			if (interval.start().isAfter(now)) {
				return AvailabilitySnapshot.busy(interval.start());
			}
		}
		return AvailabilitySnapshot.busy(null);
	}

	/**
	 * Free time over the next several days, in order, with adjacent runs merged so an
	 * overnight window that ends at midnight and resumes at the start of the next day
	 * reads as one continuous stretch.
	 */
	private List<Interval> freeIntervals(
			Map<String, UserDocument.AvailabilityWindow> weekly, ZoneId zone, Instant now) {
		LocalDate today = now.atZone(zone).toLocalDate();
		List<Interval> intervals = new ArrayList<>();

		for (int offset = 0; offset < LOOKAHEAD_DAYS; offset++) {
			LocalDate date = today.plusDays(offset);
			UserDocument.AvailabilityWindow window = weekly.get(dayKey(date));
			if (window == null || window.getStartMinutes() >= window.getEndMinutes()) {
				continue;
			}

			Instant windowStart = at(date, window.getStartMinutes(), zone);
			Instant windowEnd = at(date, window.getEndMinutes(), zone);
			Instant cursor = windowStart;

			// Busy segments arrive sorted and non-overlapping from UserService, so a single
			// forward pass is enough to carve them out.
			for (UserDocument.BusySegment busy : window.getBusySegments()) {
				Instant busyStart = at(date, busy.getStartMinutes(), zone);
				Instant busyEnd = at(date, busy.getEndMinutes(), zone);
				if (!busyEnd.isAfter(cursor)) {
					continue;
				}
				if (busyStart.isAfter(cursor)) {
					addInterval(intervals, cursor, min(busyStart, windowEnd));
				}
				cursor = max(cursor, busyEnd);
				if (!cursor.isBefore(windowEnd)) {
					break;
				}
			}
			addInterval(intervals, cursor, windowEnd);
		}
		return intervals;
	}

	private static void addInterval(List<Interval> intervals, Instant start, Instant end) {
		if (!start.isBefore(end)) {
			return;
		}
		if (!intervals.isEmpty()) {
			Interval last = intervals.get(intervals.size() - 1);
			if (!start.isAfter(last.end())) {
				intervals.set(intervals.size() - 1, new Interval(last.start(), max(last.end(), end)));
				return;
			}
		}
		intervals.add(new Interval(start, end));
	}

	/**
	 * Resolves minutes-from-midnight against the local wall clock rather than by adding
	 * elapsed minutes, so "free after 6pm" stays 6pm on the days the clocks change.
	 */
	private static Instant at(LocalDate date, int minutes, ZoneId zone) {
		if (minutes >= MINUTES_PER_DAY) {
			return date.plusDays(minutes / MINUTES_PER_DAY)
					.atStartOfDay(zone)
					.plusMinutes(minutes % MINUTES_PER_DAY)
					.toInstant();
		}
		ZonedDateTime local = date.atTime(LocalTime.of(minutes / 60, minutes % 60)).atZone(zone);
		return local.toInstant();
	}

	private static ZoneId resolveZone(String timeZoneId) {
		if (timeZoneId == null || timeZoneId.isBlank()) {
			return null;
		}
		try {
			return ZoneId.of(timeZoneId.trim());
		}
		catch (DateTimeException ex) {
			return null;
		}
	}

	private static String dayKey(LocalDate date) {
		return date.getDayOfWeek().name().toLowerCase(Locale.ROOT);
	}

	private static Instant min(Instant a, Instant b) {
		return a.isBefore(b) ? a : b;
	}

	private static Instant max(Instant a, Instant b) {
		return a.isAfter(b) ? a : b;
	}

	private record Interval(Instant start, Instant end) {
	}
}
