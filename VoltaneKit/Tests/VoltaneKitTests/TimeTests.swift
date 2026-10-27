import Foundation
import Testing
@testable import VoltaneKit

@Suite struct TimeTests {
    static let beijing: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }()

    static let newYork: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    @Test func localTimeRoundTripsWithoutShift() throws {
        for s in ["2026-10-27T08:30", "2026-12-31T23:59", "2026-01-01T00:00", "2026-03-08T01:30"] {
            let t = try #require(LocalDateTime(s))
            #expect(t.wire == s)
            let data = try JSONEncoder().encode(t)
            #expect(try JSONDecoder().decode(LocalDateTime.self, from: data) == t)
            // 在不同设备时区下，墙上时间都原样保持
            #expect(LocalDateTime(date: t.date(calendar: Self.newYork), calendar: Self.newYork) == t)
            #expect(LocalDateTime(date: t.date(calendar: Self.beijing), calendar: Self.beijing) == t)
        }
    }

    @Test func dateOnlyStaysDateOnly() throws {
        let d = try #require(LocalDateTime("2026-11-08"))
        #expect(!d.hasTime && d.wire == "2026-11-08")
        #expect(LocalDateTime("2026-11-08T00:00") != d)
    }

    @Test func localTimeAcceptsSecondsButWritesMinutes() throws {
        let t = try #require(LocalDateTime("2026-10-27T13:49:00"))
        #expect(t.wire == "2026-10-27T13:49")
    }

    @Test func utcTimeIsConvertedToDeviceZone() throws {
        let u = try #require(UTCDateTime("2026-10-27T05:47"))
        #expect(u.local(calendar: Self.beijing).wire == "2026-10-27T13:47")
        #expect(u.local(calendar: Self.newYork).wire == "2026-10-27T01:47")
        #expect(UTCDateTime("2026-10-27T05:47Z") == u)
        #expect(UTCDateTime("2026-10-27T13:47+08:00") == u)
        #expect(u.wire == "2026-10-27T05:47:00Z")
    }

    @Test func utcCrossesMidnightAndMonth() throws {
        let u = try #require(UTCDateTime("2026-10-31T20:30"))
        #expect(u.local(calendar: Self.beijing).wire == "2026-11-01T04:30")
        let v = try #require(UTCDateTime("2026-12-31T16:00"))
        #expect(v.local(calendar: Self.beijing).wire == "2027-01-01T00:00")
    }

    @Test func localAndUTCAreNotInterchangeable() throws {
        let local = try #require(LocalDateTime("2026-10-27T05:47"))
        let utc = try #require(UTCDateTime("2026-10-27T05:47"))
        #expect(utc.local(calendar: Self.beijing) != local)
    }

    @Test func rejectsGarbage() {
        #expect(LocalDateTime("") == nil && LocalDateTime("abc") == nil && LocalDateTime("2026-13-01") == nil)
        #expect(UTCDateTime("2026-10-27T25:00") == nil)
    }

    @Test func relativeDays() throws {
        let now = try #require(LocalDateTime("2026-10-27T12:00"))
        #expect(Fmt.relDay(try #require(LocalDateTime("2026-10-27T08:30")), now: now, calendar: Self.beijing) == "今天")
        #expect(Fmt.relDay(try #require(LocalDateTime("2026-10-26T23:59")), now: now, calendar: Self.beijing) == "昨天")
        #expect(Fmt.relDay(try #require(LocalDateTime("2026-10-25T01:00")), now: now, calendar: Self.beijing) == "前天")
        #expect(Fmt.relDay(try #require(LocalDateTime("2026-10-10T01:00")), now: now, calendar: Self.beijing) == "10-10 周六")
        #expect(Fmt.date(LocalDateTime("2025-12-31T09:00"), now: now, week: true, calendar: Self.beijing) == "2025-12-31 周三")
    }
}
