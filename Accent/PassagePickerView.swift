import SwiftUI

/// Sheet for choosing what to read: a curated passage or pasted text.
struct PassagePickerView: View {
    let onSelect: (_ title: String, _ text: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var customText = ""

    private var trimmedCustom: String {
        customText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Curated") {
                    ForEach(PassageLibrary.curated) { passage in
                        Button {
                            onSelect(passage.title, passage.text)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(passage.title)
                                    .font(.system(size: 17, weight: .medium, design: .serif))
                                    .foregroundStyle(Theme.ink)
                                Text(passage.focus)
                                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                                    .kerning(0.5)
                                    .foregroundStyle(Theme.muted)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                Section("Your own text") {
                    TextEditor(text: $customText)
                        .font(.system(size: 16, design: .serif))
                        .frame(minHeight: 110)
                    Button {
                        onSelect("Your Text", trimmedCustom)
                        dismiss()
                    } label: {
                        Text("Read this")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .disabled(trimmedCustom.isEmpty)
                }
            }
            .navigationTitle("Passages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
