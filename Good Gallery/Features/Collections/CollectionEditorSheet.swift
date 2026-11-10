import SwiftData
import SwiftUI

struct CollectionEditorSheet: View {
    enum Mode {
        case create
        case edit(MediaCollection)
    }

    let mode: Mode
    var onCreate: ((MediaCollection) -> Void)? = nil

    @EnvironmentObject private var store: CollectionStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var details = ""
    @State private var coverID: String?
    @State private var showPicker = false
    @FocusState private var nameFocused: Bool

    private var isCreate: Bool { if case .create = mode { true } else { false } }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                if isCreate {
                    Section {
                        Button { showPicker = true } label: {
                            HStack(spacing: 14) {
                                CoverImage(identifier: coverID, pixels: 200)
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                Text(coverID == nil ? "Choose Cover" : "Change Cover")
                                Spacer()
                            }
                        }
                    }
                }
                Section("Name") {
                    TextField("Collection name", text: $name)
                        .focused($nameFocused)
                        .submitLabel(.done)
                }
                Section("Description") {
                    TextField("Optional", text: $details, axis: .vertical).lineLimit(1...4)
                }
            }
            .tint(GG.Palette.accent)
            .navigationTitle(isCreate ? "New Collection" : "Edit Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isCreate ? "Create" : "Save") { save() }.disabled(!canSave).fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showPicker) {
                MediaPickerView(title: "Choose Cover", mode: .single, initialFilter: .photos,
                                confirmTitle: { _ in "Use as Cover" }) { ids in coverID = ids.first }
            }
            .onAppear {
                if case .edit(let collection) = mode { name = collection.name; details = collection.details }
                else { nameFocused = true }
            }
        }
        .presentationDetents([.large])
    }

    private func save() {
        Haptics.success()
        switch mode {
        case .create:
            let collection = store.createCollection(name: name, coverIdentifier: coverID)
            store.setDetails(collection, details)
            onCreate?(collection)
        case .edit(let collection):
            store.rename(collection, to: name)
            store.setDetails(collection, details)
        }
        dismiss()
    }
}

/// Reorder collections via drag handles.
struct ReorderCollectionsSheet: View {
    let collections: [MediaCollection]
    @EnvironmentObject private var store: CollectionStore
    @Environment(\.dismiss) private var dismiss
    @State private var working: [MediaCollection] = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(working) { collection in
                    HStack(spacing: 14) {
                        CoverImage(identifier: collection.effectiveCoverIdentifier, pixels: 150)
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading) {
                            Text(collection.name).foregroundStyle(GG.Palette.text)
                            Text(Format.count(collection.items.count)).font(.caption).foregroundStyle(GG.Palette.secondaryText)
                        }
                    }
                }
                .onMove { working.move(fromOffsets: $0, toOffset: $1) }
            }
            .environment(\.editMode, .constant(.active))
            .ggScreen(grouped: true)
            .navigationTitle("Reorder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { store.reorder(working); dismiss() }.fontWeight(.semibold)
                }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .onAppear { working = collections }
        }
    }
}

/// Lets the user file a set of assets into one of their collections (or a brand-new one).
struct AddToCollectionSheet: View {
    let identifiers: [String]
    var onAdded: () -> Void = {}

    @EnvironmentObject private var store: CollectionStore
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MediaCollection.sortOrder) private var collections: [MediaCollection]
    @State private var showCreate = false

    var body: some View {
        NavigationStack {
            List {
                Button { showCreate = true } label: {
                    Label("New Collection", systemImage: "plus").foregroundStyle(GG.Palette.accent)
                }
                ForEach(collections) { collection in
                    Button { add(to: collection) } label: {
                        HStack(spacing: 14) {
                            CoverImage(identifier: collection.effectiveCoverIdentifier, pixels: 150)
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading) {
                                Text(collection.name).foregroundStyle(GG.Palette.text)
                                Text(Format.count(collection.items.count)).font(.caption).foregroundStyle(GG.Palette.secondaryText)
                            }
                            Spacer()
                        }
                    }
                }
            }
            .ggScreen(grouped: true)
            .navigationTitle("Add \(Format.count(identifiers.count)) to…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(isPresented: $showCreate) {
                CollectionEditorSheet(mode: .create) { created in add(to: created) }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func add(to collection: MediaCollection) {
        store.add(identifiers, to: collection)
        Haptics.success()
        onAdded()
        dismiss()
    }
}
