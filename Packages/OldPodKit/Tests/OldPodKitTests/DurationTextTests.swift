import DesignSystem
import Testing

struct DurationTextTests {
    @Test func formatsSubMinuteDurations() {
        #expect(DurationText.format(0) == "0:00")
        #expect(DurationText.format(5) == "0:05")
        #expect(DurationText.format(59) == "0:59")
    }

    @Test func formatsMinutesAndSecondsUnderAnHour() {
        #expect(DurationText.format(60) == "1:00")
        #expect(DurationText.format(125) == "2:05")
        #expect(DurationText.format(3599) == "59:59")
    }

    @Test func formatsHoursMinutesSecondsAtOrAboveAnHour() {
        #expect(DurationText.format(3600) == "1:00:00")
        #expect(DurationText.format(3661) == "1:01:01")
        #expect(DurationText.format(7325) == "2:02:05")
    }

    @Test func roundsToTheNearestSecond() {
        #expect(DurationText.format(59.6) == "1:00")
        #expect(DurationText.format(3599.6) == "1:00:00")
    }
}
