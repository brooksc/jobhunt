import JobhuntCore
import SwiftData
import SwiftUI

// MARK: - Filter enums

private enum TypeFilter: String, CaseIterable {
    case all = "All"
    case extract = "Extract"
    case fit = "Fit"
}

private enum StatusFilter: String, CaseIterable {
    case all = "All"
    case queued = "Queued"
    case running = "Running"
    case succeeded = "Succeeded"
    case failed = "Failed"
}

// MARK: - LLMQueueView

struct LLMQueueView: View {
    // MARK: Dependencies

    let queueActor: QueueActor
    let settings: SettingsStore

    // MARK: Query — all requests, newest first

    @Query(sort: \LLMRequest.createdAt, order: .reverse)
    private var allRequests: [LLMRequest]

    // MARK: Filter state

    @State private var typeFilter: TypeFilter = .all
    @State private var statusFilter: StatusFilter = .all

    // MARK: Selection

    @State private var selection: Set<String> = []

    // MARK: Pause state (mirrors settings, kept in sync via event stream)

    @State private var isPaused: Bool = false

    // MARK: Expanded rows (showing attempt detail)

    @State private var expandedIDs: Set<String> = []

    // MARK: Error toast

    @State private var errorMessage: String?

    // MARK: - Computed

    private var filteredRequests: [LLMRequest] {
        allRequests.filter { req in
            let typeOK: Bool = switch typeFilter {
            case .all: true
            case .extract: req.requestType == .extract
            case .fit: req.requestType == .fit
            }
            let statusOK: Bool = switch statusFilter {
            case .all: true
            case .queued: req.status == .queued
            case .running: req.status == .running
            case .succeeded: req.status == .succeeded
            case .failed: req.status == .failed || req.status == .retryExhausted
            }
            return typeOK && statusOK
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            QueueSummaryBar(
                requests: allRequests,
                isPaused: isPaused,
                onTogglePause: togglePause
            )

            Divider()

            if let msg = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                    Button("Dismiss") { errorMessage = nil }
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.08))
            }

            Table(filteredRequests, selection: $selection) {
                TableColumn("Type") { req in
                    Text(req.requestType == .extract ? "Extract" : "Fit")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            (req.requestType == .extract ? Color.blue : Color.purple).opacity(0.12)
                        )
                        .foregroundStyle(req.requestType == .extract ? Color.blue : Color.purple)
                        .clipShape(Capsule())
                }
                .width(70)

                TableColumn("Status") { req in
                    queueStatusChip(req.status)
                }
                .width(90)

                TableColumn("Company") { req in
                    Text(req.job?.company ?? "—")
                        .lineLimit(1)
                }

                TableColumn("Title") { req in
                    Text(req.job?.title ?? "—")
                        .lineLimit(1)
                }

                TableColumn("Model") { req in
                    Text(req.model ?? "—")
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }

                TableColumn("Duration") { req in
                    Text(durationString(for: req))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                TableColumn("Error") { req in
                    if let error = req.error {
                        Text(error)
                            .lineLimit(2)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .help(error)
                    } else {
                        Text("—").foregroundStyle(.tertiary)
                    }
                }
            }
            .contextMenu(forSelectionType: String.self) { ids in
                selectionContextMenu(for: ids)
            }
        }
        .toolbar { toolbarContent }
        .task {
            // Sync isPaused from settings
            isPaused = settings.llmQueuePaused
            // Listen for QueueActor events
            for await event in queueActor.events {
                handleQueueEvent(event)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            // Batch ops — shown when something is selected
            if !selection.isEmpty {
                Button("Process Selected") {
                    Task { await processSelected(Array(selection)) }
                }

                Button("Cancel Selected", role: .destructive) {
                    Task { await cancelSelected(Array(selection)) }
                }

                Button("Reset Selected") {
                    Task { await resetSelected(Array(selection)) }
                }

                Divider()
            }

            // Process All
            Button {
                Task { await processAll() }
            } label: {
                Label("Process All", systemImage: "sparkles")
            }

            // Cancel All
            Button(role: .destructive) {
                Task { await cancelAll() }
            } label: {
                Label("Cancel All", systemImage: "trash")
            }
        }

        ToolbarItemGroup(placement: .secondaryAction) {
            // Type filter
            Picker("Type", selection: $typeFilter) {
                ForEach(TypeFilter.allCases, id: \.self) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 160)

            // Status filter
            Picker("Status", selection: $statusFilter) {
                ForEach(StatusFilter.allCases, id: \.self) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.menu)
        }
    }

    // MARK: - Context menu for table selection

    @ViewBuilder
    private func selectionContextMenu(for ids: Set<String>) -> some View {
        if ids.isEmpty {
            EmptyView()
        } else {
            Button("Process Selected") {
                Task { await processSelected(Array(ids)) }
            }
            Button("Reset Selected") {
                Task { await resetSelected(Array(ids)) }
            }
            Divider()
            Button("Cancel Selected", role: .destructive) {
                Task { await cancelSelected(Array(ids)) }
            }
        }
    }

    // MARK: - Status chip

    @ViewBuilder
    private func queueStatusChip(_ status: LLMRequestStatus) -> some View {
        let (label, color) = statusInfo(status)
        HStack(spacing: 4) {
            if status == .running {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 10, height: 10)
            }
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.12))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }

    // MARK: - Helpers

    private func statusInfo(_ status: LLMRequestStatus) -> (String, Color) {
        switch status {
        case .queued: ("Queued", .blue)
        case .running: ("Running", .green)
        case .succeeded: ("Done", .green)
        case .failed: ("Failed", .red)
        case .retryExhausted: ("Exhausted", .red)
        case .cancelled: ("Cancelled", .secondary)
        }
    }

    private func durationString(for req: LLMRequest) -> String {
        guard let start = req.startedAt else { return "—" }
        let end = req.finishedAt ?? Date()
        let ms = Int(end.timeIntervalSince(start) * 1000)
        return formatDurationMs(ms)
    }

    private func formatDurationMs(_ ms: Int) -> String {
        let totalSeconds = max(0, ms / 1000)
        if totalSeconds < 60 { return "\(totalSeconds)s" }
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes < 60 { return "\(minutes)m \(seconds)s" }
        let hours = minutes / 60
        return "\(hours)h \(minutes % 60)m"
    }

    // MARK: - Queue actions

    private func togglePause() async {
        let next = !isPaused
        isPaused = next
        if next {
            await queueActor.pauseQueue()
        } else {
            await queueActor.resumeQueue()
        }
    }

    private func processAll() async {
        // Enqueue pending jobs that aren't yet in the queue
        // The queue actor's startProcessing handles the actual processing
        do {
            let pendingJobIDs = allRequests
                .filter { $0.status == .queued }
                .compactMap { $0.job?.id }
            if !pendingJobIDs.isEmpty {
                await queueActor.startProcessing()
            }
        }
    }

    private func processSelected(_ ids: [String]) async {
        // Reset selected items to queued then start processing
        for id in ids {
            try? await queueActor.resetRequest(id: id)
        }
        await queueActor.startProcessing()
    }

    private func cancelSelected(_ ids: [String]) async {
        for id in ids {
            do {
                try await queueActor.cancelRequest(id: id)
            } catch {
                errorMessage = "Cancel failed: \(error.localizedDescription)"
            }
        }
        selection.removeAll()
    }

    private func resetSelected(_ ids: [String]) async {
        for id in ids {
            do {
                try await queueActor.resetRequest(id: id)
            } catch {
                errorMessage = "Reset failed: \(error.localizedDescription)"
            }
        }
    }

    private func cancelAll() async {
        do {
            try await queueActor.cancelAll()
            selection.removeAll()
        } catch {
            errorMessage = "Cancel all failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Event handler

    private func handleQueueEvent(_ event: QueueEvent) {
        switch event {
        case .autoPaused:
            isPaused = true
        case .processingComplete:
            break
        case .jobReady, .jobUnavailable:
            break
        }
    }
}

// MARK: - Attempt Detail Subview

private struct AttemptDetailView: View {
    let attempts: [LLMRequestAttempt]

    var body: some View {
        if attempts.isEmpty {
            Text("No attempt history")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(attempts.sorted(by: { $0.attempt < $1.attempt }), id: \.id) { attempt in
                    AttemptRow(attempt: attempt)
                }
            }
        }
    }
}

private struct AttemptRow: View {
    let attempt: LLMRequestAttempt

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("#\(attempt.attempt)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(attempt.status.rawValue.capitalized)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(attempt.status == .succeeded ? .green : .red)

                    if let ms = attempt.durationMs {
                        Text(formatMs(ms))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                if let modelReq = attempt.modelRequested {
                    HStack(spacing: 4) {
                        Text("Requested:")
                            .foregroundStyle(.secondary)
                        Text(modelReq)
                    }
                    .font(.caption.monospaced())
                }

                if let modelRet = attempt.modelReturned {
                    HStack(spacing: 4) {
                        Text("Returned:")
                            .foregroundStyle(.secondary)
                        Text(modelRet)
                    }
                    .font(.caption.monospaced())
                }

                if let error = attempt.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func formatMs(_ ms: Int) -> String {
        let s = max(0, ms / 1000)
        if s < 60 { return "\(s)s" }
        return "\(s / 60)m \(s % 60)s"
    }
}
