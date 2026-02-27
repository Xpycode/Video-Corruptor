import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    @Environment(CorruptorViewModel.self) private var viewModel
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "film.stack")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Drop a Video File")
                .font(.title2)
                .fontWeight(.medium)

            Text("MP4, MOV, M4V, or MXF")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                AppKitButton(title: "Choose File…", action: {
                    viewModel.openFilePicker()
                })
                .appKitDefault()
                .fixedSize()

                AppKitButton(title: "Batch Mode…", action: {
                    viewModel.isBatchMode = true
                    viewModel.batchViewModel.openFilePicker()
                })
                .fixedSize()
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                )
                .padding(20)
        }
        .onDrop(of: [.mpeg4Movie, .quickTimeMovie, .movie, .fileURL], isTargeted: $isTargeted) { providers in
            viewModel.handleDrop(providers: providers)
        }
    }
}
