//
//  EditMealView.swift
//  MyNutritionPal
//

import SwiftUI
import UIKit

/// The Edit Meal sheet: the name, calories and macros, saved exactly as
/// entered. Save is enabled once something changed and everything is valid.
/// Cancel discards at once; swiping the sheet down with changes asks first.
/// A failed save keeps what was typed.
struct EditMealView: View {
    let meal: Meal
    /// The saved meal, before the sheet closes.
    let onSaved: (Meal) -> Void
    /// The meal was deleted before it could be saved.
    let onGone: () -> Void

    @Environment(NutritionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var form: MealForm
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var isGone = false
    @State private var confirmingDiscard = false
    @FocusState private var focus: MealForm.Field?

    init(meal: Meal, onSaved: @escaping (Meal) -> Void, onGone: @escaping () -> Void) {
        self.meal = meal
        self.onSaved = onSaved
        self.onGone = onGone
        _form = State(initialValue: MealForm(meal: meal))
    }

    var body: some View {
        NavigationStack {
            Form {
                if let saveError {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Couldn't Save Changes")
                                .font(.headline)
                            Text("\(saveError) Your changes are still here. Try again.")
                                .font(.subheadline)
                        }
                        .foregroundStyle(.danger)
                        .accessibilityElement(children: .combine)
                    }
                    .listRowBackground(Color.dangerSurface)
                }

                Section("Name") {
                    field(.name, label: "Name", unit: nil)
                }

                Section("Calories") {
                    field(.calories, label: "Calories", unit: "cal")
                }

                Section {
                    field(.protein, label: "Protein", unit: "g")
                    field(.carbs, label: "Carbs", unit: "g")
                    field(.fat, label: "Fat", unit: "g")
                } header: {
                    Text("Macros")
                } footer: {
                    Text("Saved exactly as entered: changing calories doesn't change the macros, and changing macros doesn't change calories.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .disabled(isSaving)
            .navigationTitle("Edit Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .interactiveDismissDisabled(form.isDirty || isSaving)
        .background(DismissAttempt { if !isSaving { confirmingDiscard = true } })
        .confirmationDialog(
            "Discard your changes to this meal?",
            isPresented: $confirmingDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        }
        .alert("Meal Not Found", isPresented: $isGone) {
            Button("OK") {
                onGone()
                dismiss()
            }
        } message: {
            Text("This meal was deleted, so your changes can't be saved.")
        }
        .onChange(of: form.name) { _, name in
            // A wrapping field takes Return as a line break: a name is one
            // line, so Return goes on to Calories instead.
            if name.contains("\n") {
                form.name = name.replacingOccurrences(of: "\n", with: "")
                focus = .calories
            }
        }
        .onChange(of: focus) { left, _ in
            // Say what's wrong with a field once, as VoiceOver leaves it.
            if let left, let error = form.error(for: left) {
                AccessibilityNotification.Announcement(error).post()
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .disabled(isSaving)
        }

        ToolbarItem(placement: .confirmationAction) {
            if isSaving {
                ProgressView()
                    .accessibilityLabel("Saving")
            } else {
                Button("Save") { save() }
                    .fontWeight(.semibold)
                    .disabled(form.changes == nil)
                    .accessibilityHint(form.isValid ? "" : "Fix the highlighted fields to save.")
            }
        }

        ToolbarItemGroup(placement: .keyboard) {
            Button {
                move(by: -1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(focus == MealForm.Field.allCases.first)
            .accessibilityLabel("Previous field")

            Button {
                move(by: 1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(focus == MealForm.Field.allCases.last)
            .accessibilityLabel("Next field")

            Spacer()

            Button("Done") { focus = nil }
                .fontWeight(.semibold)
        }
    }

    // MARK: Fields

    /// A labelled field with its unit, and its error under it. At
    /// accessibility text sizes the label (with the unit) goes above.
    private func field(_ field: MealForm.Field, label: String, unit: String?) -> some View {
        let error = form.error(for: field)
        let spokenUnit = unit == "g" ? "grams" : unit == "cal" ? "calories" : nil

        // The name wraps instead of being cut off at large text sizes.
        let input = TextField(label, text: $form[field], axis: field == .name ? .vertical : .horizontal)
            .lineLimit(field == .name ? 1...6 : 1...1)
            .focused($focus, equals: field)
            .keyboardType(field == .name ? .default : field == .calories ? .numberPad : .decimalPad)
            .submitLabel(field == .name ? .next : .done)
            .onSubmit { if field == .name { focus = .calories } }
            .multilineTextAlignment(field == .name || dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
            .fontDesign(field == .name ? nil : .rounded)
            .monospacedDigit()
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .background(.fieldFill, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        error != nil ? Color.danger : focus == field ? Color.accentColor : .clear,
                        lineWidth: 2
                    )
            )
            .accessibilityLabel(spokenUnit.map { "\(label), \($0)" } ?? label)
            .accessibilityHint(error ?? "")

        return VStack(alignment: .leading, spacing: 6) {
            if field == .name {
                input
            } else if dynamicTypeSize.isAccessibilitySize {
                Text(unit.map { "\(label) (\($0))" } ?? label)
                    .accessibilityHidden(true)
                input
            } else {
                HStack(spacing: 10) {
                    Text(label)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityHidden(true)
                    input
                        .frame(width: 110)
                    Text(unit ?? "")
                        .foregroundStyle(.textSecondary)
                        .frame(width: 28, alignment: .leading)
                        .accessibilityHidden(true)
                }
            }

            if let error {
                InlineError(message: error)
                    .accessibilityHidden(true)
            }
        }
        // A tap anywhere in the row (the label too) goes to its field.
        .contentShape(Rectangle())
        .onTapGesture { focus = field }
        .listRowBackground(Color.surface)
    }

    private func move(by step: Int) {
        let fields = MealForm.Field.allCases
        guard let focus, let index = fields.firstIndex(of: focus),
              fields.indices.contains(index + step) else { return }
        self.focus = fields[index + step]
    }

    // MARK: Saving

    private func save() {
        guard let changes = form.changes, !isSaving else { return }
        focus = nil
        isSaving = true
        saveError = nil

        Task {
            defer { isSaving = false }
            do {
                let saved = try await store.updateMeal(meal, changes)
                onSaved(saved)
                dismiss()
            } catch APIError.server(404, "meal_not_found"?, _) {
                isGone = true
            } catch where APIError.isCancellation(error) {
            } catch {
                saveError = error.localizedDescription
                AccessibilityNotification.Announcement("Couldn't save changes. \(error.localizedDescription)").post()
            }
        }
    }
}

/// Calls `action` when the user tries to swipe away a sheet whose
/// interactive dismissal is disabled. SwiftUI has no hook for this, so it
/// wraps the sheet's UIKit presentation delegate (SwiftUI's own), passing
/// everything else through to it.
private struct DismissAttempt: UIViewControllerRepresentable {
    let action: () -> Void

    func makeUIViewController(context: Context) -> Controller {
        Controller(action: action)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.action = action
        controller.install()
    }

    final class Controller: UIViewController, UIAdaptivePresentationControllerDelegate {
        var action: () -> Void
        private weak var original: UIAdaptivePresentationControllerDelegate?

        init(action: @escaping () -> Void) {
            self.action = action
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            install()
        }

        /// The sheet is the topmost parent's presentation.
        func install() {
            var sheet: UIViewController = self
            while let parent = sheet.parent { sheet = parent }
            guard let presentation = sheet.presentationController,
                  presentation.delegate !== self else { return }
            original = presentation.delegate
            presentation.delegate = self
        }

        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
            original?.presentationControllerDidAttemptToDismiss?(presentationController)
            action()
        }

        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || original?.responds(to: selector) == true
        }

        override func forwardingTarget(for selector: Selector!) -> Any? {
            original?.responds(to: selector) == true ? original : super.forwardingTarget(for: selector)
        }
    }
}
