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
            ScrollView {
                VStack(spacing: 22) {
                    if isCreate {
                        Button { showPicker = true } label: {
                            CoverImage(identifier: coverID)
                                .frame(height: 190)
                                .clipShape(RoundedRectangle(cornerRadius: GG.Radius.card, style: .continuous))
                                .overlay(alignment: .bottom) {
                                    Label(coverID == nil ? "Choose Cover (Optional)" : "Change Cover", systemImage: "photo.badge.plus")
                                        .font(.footnote.weight(.semibold))
                                        .padding(.horizontal, 12).padding(.vertical, 8)
                                        .ggGlass(Capsule())
                                        .padding(12)
                                }
                        }
                        .buttonStyle(PressableStyle())
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("NAME").font(GG.Typography.eyebrow).foregroundStyle(GG.Palette.secondaryText)
                        TextField("Travel, Family, Projects…", text: $name)
                            .font(GG.Typography.editorial(26))
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .padding(.bottom, 8)
                            .overlay(alignment: .bottom) { Rectangle().fill(GG.Palette.separator).frame(height: 1) }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DESCRIPTION").font(GG.Typography.eyebrow).foregroundStyle(GG.Palette.secondaryText)
                        TextField("Optional", text: $details, axis: .vertical)
                            .lineLimit(1...4)
                            .padding(.bottom, 8)
                            .overlay(alignment: .bottom) { Rectangle().fill(GG.Palette.separator).frame(height: 1) }
                    }
                }
                .padding(GG.Spacing.page)
            }
            .ggScreen()
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
        .presentationBackground { GGBackground() }
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
                    .listRowBackground(GlassRowBackground())
                }
                .onMove { working.move(fromOffsets: $0, toOffset: $1) }
            }
            .environment(\.editMode, .constant(.active))
            .ggScreen()
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
        .presentationBackground { GGBackground() }
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
                .listRowBackground(GlassRowBackground())
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
                    .listRowBackground(GlassRowBackground())
                }
            }
            .ggScreen()
            .navigationTitle("Add \(Format.count(identifiers.count)) to…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(isPresented: $showCreate) {
                CollectionEditorSheet(mode: .create) { created in add(to: created) }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground { GGBackground() }
    }

    private func add(to collection: MediaCollection) {
        store.add(identifiers, to: collection)
        Haptics.success()
        onAdded()
        dismiss()
    }
}
