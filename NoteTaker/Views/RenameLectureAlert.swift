import SwiftData
import SwiftUI

extension View {
    /// Shows a rename alert while `lecture` is non-nil. An empty name restores the default
    /// title ("Aula de <data>" or "Reunião de <data>").
    func renameLectureAlert(_ lecture: Binding<Lecture?>) -> some View {
        modifier(RenameLectureAlert(lecture: lecture))
    }
}

private struct RenameLectureAlert: ViewModifier {
    @Binding var lecture: Lecture?
    @Environment(\.modelContext) private var context
    @State private var name = ""

    func body(content: Content) -> some View {
        content
            .alert(
                "Renomear",
                isPresented: Binding(get: { lecture != nil }, set: { if !$0 { lecture = nil } })
            ) {
                TextField("Nome", text: $name)
                Button("Salvar") {
                    lecture?.title = name.trimmingCharacters(in: .whitespaces)
                    try? context.save()
                }
                Button("Cancelar", role: .cancel) {}
            }
            .onChange(of: lecture) {
                name = lecture?.title ?? ""
            }
    }
}
