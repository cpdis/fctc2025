import FCTCAttendanceKit
import SwiftUI

struct GuestConflictReviewView: View {
    let runtime: AppRuntime
    let submission: PendingSubmissionSnapshot
    @Environment(\.dismiss) private var dismiss
    @State private var review: PromotedGuestReview?
    @State private var error: String?
    @State private var working = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("A guest became a member while this run was offline. Review the conversion before saving.")
                    Text("\(submission.expectedDate) · \(submission.expectedRun)").font(.footnote).foregroundStyle(.secondary)
                }
                if let review {
                    Section("Before") {
                        LabeledContent("Named guests", value: review.guestNamesBefore.isEmpty ? "None" : review.guestNamesBefore.joined(separator: ", "))
                        LabeledContent("Members", value: review.membersBefore.joined(separator: ", "))
                        LabeledContent("Unnamed guests", value: review.unnamedBefore.formatted())
                        LabeledContent("People", value: review.peopleBefore.formatted())
                        LabeledContent("Distance", value: review.actualKmBefore.map { "\($0.formatted()) km" } ?? "Blank")
                    }
                    Section("After") {
                        LabeledContent("Convert to member", value: review.convertedNames.joined(separator: ", "))
                        LabeledContent("Members", value: review.draft.attendees.joined(separator: ", "))
                        LabeledContent("Named guests", value: review.guestNamesAfter.isEmpty ? "None" : review.guestNamesAfter.joined(separator: ", "))
                        LabeledContent("Unnamed guests", value: (review.draft.unnamedGuests ?? 0).formatted())
                        LabeledContent("People", value: (review.draft.attendees.count + review.draft.plusOnes).formatted())
                        LabeledContent("Distance", value: review.draft.actualKm.map { "\($0.formatted()) km" } ?? "Blank")
                    }
                    if !review.removedMembers.isEmpty || !review.removedGuests.isEmpty || (review.draft.unnamedGuests ?? 0) < review.unnamedBefore {
                        Section("Removals in this overwrite") {
                            if !review.removedMembers.isEmpty { LabeledContent("Members", value: review.removedMembers.joined(separator: ", ")) }
                            if !review.removedGuests.isEmpty { LabeledContent("Named guests", value: review.removedGuests.joined(separator: ", ")) }
                            if (review.draft.unnamedGuests ?? 0) < review.unnamedBefore {
                                LabeledContent("Unnamed guests", value: "\(review.unnamedBefore) → \(review.draft.unnamedGuests ?? 0)")
                            }
                        }
                    }
                    Section {
                        Button("Save reviewed conversion") { Task { await save(review) } }
                            .accessibilityIdentifier("save-promoted-conversion")
                    } footer: { Text("This replaces the original queued change. The member receives this run once.") }
                }
                if working { ProgressView("Loading original run…") }
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle("Review promoted guest").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { await load() }
            .disabled(working)
        }
    }
    private func load() async {
        guard let identity = submission.runIdentity else { return }
        working = true; defer { working = false }
        do {
            let state = try await runtime.engine.refreshState(seasonSheetId: identity.seasonSheetId)
            review = try PromotedGuestReview(submission: submission, state: state, endpointIdentity: runtime.config.endpoint?.absoluteString)
        } catch { self.error = UserFacingError.sync(error) }
    }
    private func save(_ review: PromotedGuestReview) async {
        working = true; defer { working = false }
        do {
            _ = try await runtime.engine.replacePromotedGuestSubmission(id: submission.id, reviewedDraft: review.draft)
            dismiss()
        } catch { self.error = UserFacingError.sync(error) }
    }
}

struct GuestIdentityReviewView: View {
    let runtime: AppRuntime
    let provisionalId: String
    let displayName: String
    let candidateIds: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var guests: [SharedGuest] = []
    @State private var error: String?
    @State private var working = false
    var body: some View {
        List {
            Section {
                Text("‘\(displayName)’ may already be saved. Choose the person to keep their existing history.")
            }
            Section("Existing shared guests") {
                ForEach(guests.filter { $0.isActive && (candidateIds.isEmpty || candidateIds.contains($0.guestId)) }) { guest in
                    Button { resolve(existingId: guest.guestId) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(guest.displayName)
                            Text("\(guest.confirmedRuns ?? 0) confirmed runs").font(.caption).foregroundStyle(.secondary)
                        }
                    }.accessibilityIdentifier("resolve-identity-\(guest.displayName)")
                }
            }
            Section {
                Button("This is a different person") { resolve(existingId: nil) }
            } footer: { Text("A different person gets a separate history, even when the names match.") }
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
        }.navigationTitle("Choose guest identity").navigationBarTitleDisplayMode(.inline)
            .disabled(working)
            .task { guests = (try? await runtime.engine.sharedGuests()) ?? [] }
    }
    private func resolve(existingId: String?) {
        working = true
        Task {
            defer { working = false }
            do {
                try await runtime.engine.resolveGuestIdentity(provisionalId: provisionalId, existingGuestId: existingId, confirmDistinct: existingId == nil)
                await runtime.engine.drain(); dismiss()
            } catch { self.error = UserFacingError.sync(error) }
        }
    }
}

/// A durable operation can be checked after leaving the originating screen or
/// restarting the app. This screen never constructs another mutation request.
struct GuestOperationStatusView: View {
    let runtime: AppRuntime
    let id: UUID
    @State private var operation: GuestOperationSnapshot?
    @State private var error: String?
    @State private var working = false
    var body: some View {
        List {
            Section {
                Label(statusTitle,
                      systemImage: operation?.phase == .completed ? "checkmark.circle" : "clock.arrow.circlepath")
                if let message = operation?.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                if operation?.phase == .queued || operation?.phase == .checking {
                    Text("The original request is saved on this phone. Checking its receipt will not create a second promotion or import.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Check receipt") { Task { await check() } }.disabled(working)
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("Saved guest change").navigationBarTitleDisplayMode(.inline)
            .task { await check() }
    }
    private var statusTitle: String {
        switch operation?.phase {
        case .completed: "Change confirmed"
        case .conflict, .rejected: "Change needs review"
        case .superseded: "Change closed"
        default: "Checking saved changes"
        }
    }
    private func check() async {
        working = true; defer { working = false }
        await runtime.engine.drain()
        do {
            operation = try await runtime.engine.guestOperation(id: id)
            if operation?.phase == .completed { _ = try? await runtime.engine.refreshState() }
        }
        catch { self.error = UserFacingError.sync(error) }
    }
}
