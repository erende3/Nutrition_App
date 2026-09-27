//
//  HistoryDateTests.swift
//  MyNutritionPalTests
//

import Foundation
import Testing
@testable import MyNutritionPal

/// History's date bar: moving a day at a time, and how a date is shown and
/// read by VoiceOver.
struct HistoryDateTests {

    private static let newYork: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()
    private static let english = Locale(identifier: "en_US")

    @Test(arguments: [
        ("2026-09-25", -1, "2026-09-24"),
        ("2026-09-25", 1, "2026-09-26"),
        ("2026-09-01", -1, "2026-08-31"),
        ("2026-12-31", 1, "2027-01-01"),
        ("2024-03-01", -1, "2024-02-29"),
        // The days the clocks change (in New York) are still one day each.
        ("2026-03-09", -1, "2026-03-08"),
        ("2026-11-02", -1, "2026-11-01"),
    ])
    func movesOneCalendarDay(_ day: String, _ days: Int, _ expected: String) {
        #expect(MealHistoryView.shifted(day, by: days, calendar: Self.newYork) == expected)
    }

    @Test func titleNamesTheDay() {
        #expect(MealHistoryView.title(for: "2026-09-25", today: "2026-09-27", locale: Self.english, calendar: Self.newYork)
                == "Friday, Sep 25")
    }

    @Test func titleAddsTheYearForAnEarlierYear() {
        #expect(MealHistoryView.title(for: "2025-12-30", today: "2026-09-27", locale: Self.english, calendar: Self.newYork)
                == "Tuesday, Dec 30, 2025")
    }

    @Test func voiceOverReadsTheWholeDate() {
        #expect(MealHistoryView.spokenDate(for: "2026-09-25", today: "2026-09-27", locale: Self.english, calendar: Self.newYork)
                == "Friday, September 25, 2026")
    }

    @Test func voiceOverSaysToday() {
        #expect(MealHistoryView.spokenDate(for: "2026-09-27", today: "2026-09-27", locale: Self.english, calendar: Self.newYork)
                == "Today, Sunday, September 27, 2026")
    }
}
