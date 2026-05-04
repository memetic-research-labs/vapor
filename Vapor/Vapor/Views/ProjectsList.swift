import SwiftUI
import SwiftData

struct ProjectsList: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\VaporProject.lastActiveAt, order: .reverse)]) private var projects: [VaporProject]
    @State private var editingProject: VaporProject?
    @State private var editName: String = ""

    var body: some View {
        if projects.isEmpty {
            VStack(spacing: 8) {
                Text("No projects yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Create a project to organize your context and AI sessions.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(20)
        } else {
            VStack(spacing: 0) {
                ForEach(projects) { project in
                    HStack {
                        if let hex = project.colorHex, let color = Color(hex: hex) {
                            Circle().fill(color).frame(width: 10, height: 10)
                        } else {
                            Circle().fill(Color.secondary).frame(width: 10, height: 10)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.name)
                                .font(.body)
                            HStack(spacing: 8) {
                                if let branch = project.gitCurrentBranch {
                                    Label(branch, systemImage: "arrow.triangle.branch")
                                        .font(.caption2)
                                }
                                Text("\(project.contextItems.count) items")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button {
                            editingProject = project
                            editName = project.name
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        Button {
                            deleteProject(project)
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 6)
                    if project.id != projects.last?.id {
                        Divider()
                    }
                }
            }
            .sheet(item: $editingProject) { project in
                VStack(spacing: 16) {
                    Text("Edit Project")
                        .font(.headline)
                    TextField("Name", text: $editName)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Cancel") { editingProject = nil }
                        Button("Save") {
                            project.name = editName
                            try? modelContext.save()
                            editingProject = nil
                        }
                        .disabled(editName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(20)
                .frame(width: 300)
            }
        }
    }

    private func deleteProject(_ project: VaporProject) {
        modelContext.delete(project)
        try? modelContext.save()
    }
}
