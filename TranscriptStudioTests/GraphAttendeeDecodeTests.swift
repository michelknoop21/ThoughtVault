// GraphAttendeeDecodeTests.swift
// TranscriptStudioTests
// nl.prezent.TranscriptStudio
//
// RED until Plan 02-02 adds CalendarEvent.attendees + maps emailAddress.address in decode.
// The assertion against CalendarEvent.attendees below will not compile against the current
// CalendarEvent struct (no attendees field) — that compile failure IS the intended RED state.
//
// CRITICAL (Research Pitfall 2): Graph REST uses `emailAddress.address` NOT `.email`.
// This test explicitly asserts the `address` key is used, preventing silent-undefined attendees.

import XCTest
import Foundation
@testable import TranscriptStudio

// MARK: - Local Decodable structs mirroring the Graph calendarView response
// These mirror the shape MicrosoftGraphService will adopt in Plan 02-02/02-03.
// Using local structs here keeps the test self-contained and avoids access to
// the private types inside MicrosoftGraphService.

private struct TestGraphCalendarResponse: Decodable {
    let value: [TestGraphEvent]
}

private struct TestGraphEvent: Decodable {
    let id: String
    let subject: String?
    let organizer: TestGraphRecipient?
    let attendees: [TestGraphAttendee]?
}

private struct TestGraphRecipient: Decodable {
    let emailAddress: TestGraphEmailAddress?
}

private struct TestGraphAttendee: Decodable {
    let emailAddress: TestGraphEmailAddress?
}

/// The Graph v1.0 emailAddress object uses `address` (not `email`).
/// Decoding via this struct directly proves the correct key is used.
private struct TestGraphEmailAddress: Decodable {
    let name: String?
    let address: String?   // Graph field is `address` — NOT `email` (Research Pitfall 2)
}

// MARK: - GraphAttendeeDecodeTests

final class GraphAttendeeDecodeTests: XCTestCase {

    // MARK: - Fixture loading

    /// Loads GraphCalendarViewResponse.json from the test bundle.
    private func loadFixture() throws -> Data {
        // Prefer bundle resource; fall back to source-tree path for CI environments
        // where the resource phase may not yet be configured.
        if let url = Bundle(for: type(of: self)).url(forResource: "GraphCalendarViewResponse", withExtension: "json"),
           let data = try? Data(contentsOf: url) {
            return data
        }
        // Fallback: load from source tree relative to this file at compile time
        let sourceURL = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/GraphCalendarViewResponse.json")
        return try Data(contentsOf: sourceURL)
    }

    // MARK: - Test: decode uses `address` key (not `.email`)

    /// Decode the fixture through the Graph attendee shape and assert that the two
    /// attendee email addresses equal the fixture `address` values — NOT any `.email` field.
    ///
    /// RED (part 1): CalendarEvent.attendees does not exist yet (Plan 02-02 adds it).
    /// The compiler will reject the `calendarEvent.attendees` reference below until
    /// Plan 02-02 lands the field + mapping.
    func testGraphAttendeeDecodeUsesAddressKey() throws {
        let data = try loadFixture()

        // Step 1: decode the raw Graph response using the local test structs
        let decoder = JSONDecoder()
        let response = try decoder.decode(TestGraphCalendarResponse.self, from: data)

        // The fixture contains exactly one event
        XCTAssertEqual(response.value.count, 1, "fixture must contain exactly one calendarView event")
        let event = try XCTUnwrap(response.value.first)

        // Step 2: assert that decoding via `address` yields the two expected emails
        let attendeeAddresses = (event.attendees ?? []).compactMap { $0.emailAddress?.address }
        XCTAssertEqual(
            attendeeAddresses,
            ["anke.bakker@prezent.nl", "pieter.jansen@extern.nl"],
            "decoded attendee emails must match the fixture `address` values (not .email)"
        )

        // Step 3: assert organizer also decodes via `address`
        let organizerAddress = event.organizer?.emailAddress?.address
        XCTAssertEqual(organizerAddress, "jan.devries@prezent.nl", "organizer address must decode from `address` key")

        // Step 4: assert that `address` key is readable (belt-and-suspenders — if Graph changed
        //         to `.email` this would fail, catching the Pitfall 2 regression)
        let firstAttendee = try XCTUnwrap(event.attendees?.first)
        XCTAssertNotNil(firstAttendee.emailAddress?.address, "emailAddress.address must not be nil in fixture")

        // Step 5: assert the mapped CalendarEvent carries the attendees.
        // CalendarEvent.attendees does not exist yet → RED compile failure (Plan 02-02 adds it).
        // Build a CalendarEvent the way MicrosoftGraphService will after 02-02:
        let calendarEvent = CalendarEvent(
            id: event.id,
            title: event.subject ?? "Vergadering",
            date: Date(),
            endDate: Date(),
            meetingURL: nil,
            platform: .teams,
            calendarTitle: "Microsoft 365",
            attendees: attendeeAddresses,           // RED: field does not exist yet
            organizer: organizerAddress             // RED: field does not exist yet
        )
        XCTAssertEqual(
            calendarEvent.attendees,               // RED: field does not exist yet
            ["anke.bakker@prezent.nl", "pieter.jansen@extern.nl"]
        )
        XCTAssertEqual(calendarEvent.organizer, "jan.devries@prezent.nl")  // RED
    }
}
