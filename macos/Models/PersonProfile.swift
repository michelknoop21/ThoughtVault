// PersonProfile.swift
// TranscriptStudio
// nl.prezent.TranscriptStudio
//
// SwiftData model for people (self-profile + directory) stored on-device.
// isSelf == true identifies the installing user's own profile (singleton).

import Foundation
import SwiftData

// MARK: - PersonProfile

@Model
final class PersonProfile {

    /// Stable local identifier.
    @Attribute(.unique) var id: String
    var name: String
    var role: String
    var organization: String
    /// Known alternative names / short names used in transcripts.
    var aliases: [String]
    /// Types of meetings this person typically attends.
    var meetingTypes: [String]
    /// Topic/domain expertise tags used for onderwerp→rol attribution (Phase 3/4).
    var expertiseTags: [String]
    /// True for exactly one record: the installing user's own profile.
    var isSelf: Bool
    /// True for internal colleagues; false for known externals.
    var isInternal: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String = "",
        role: String = "",
        organization: String = "",
        aliases: [String] = [],
        meetingTypes: [String] = [],
        expertiseTags: [String] = [],
        isSelf: Bool = false,
        isInternal: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.organization = organization
        self.aliases = aliases
        self.meetingTypes = meetingTypes
        self.expertiseTags = expertiseTags
        self.isSelf = isSelf
        self.isInternal = isInternal
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
