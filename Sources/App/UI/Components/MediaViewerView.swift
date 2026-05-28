import AVFoundation
import AVKit
import SwiftUI
import UIKit

struct MessageAttachmentPreview: View {
    let attachment: TgAttachment
    var onOpen: (() -> Void)?

    var body: some View {
        switch attachment.kind {
        case .photo:
            photoPreview
        case .video:
            videoPreview(isRound: false)
        case .videoNote:
            videoPreview(isRound: true)
        case .voice:
            InlineVoicePlayer(attachment: attachment, onOpen: onOpen)
        case .document:
            documentPreview
        }
    }

    private var photoPreview: some View {
        Button {
            onOpen?()
        } label: {
            ZStack {
                if let image = attachment.localImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    loadingPlaceholder(systemImage: "photo", title: "Фото загружается")
                }
            }
            .frame(height: 180)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if attachment.localURL == nil {
                    ProgressView()
                        .tint(.white)
                        .padding(8)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(attachment.localURL == nil)
    }

    private func videoPreview(isRound: Bool) -> some View {
        Button {
            onOpen?()
        } label: {
            if isRound {
                videoPreviewContent(title: "Кружок загружается")
                    .frame(width: 170, height: 170)
                    .clipShape(Circle())
            } else {
                videoPreviewContent(title: "Видео загружается")
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .buttonStyle(.plain)
        .disabled(attachment.localURL == nil)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func videoPreviewContent(title: String) -> some View {
        ZStack {
            VideoThumbnailView(url: attachment.localURL)

            Image(systemName: "play.fill")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(Color.black.opacity(0.36))
                .clipShape(Circle())

            if attachment.localURL == nil {
                VStack(spacing: 8) {
                    ProgressView()
                        .tint(.white)
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(12)
            }
        }
    }

    private var documentPreview: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.fill")
                .font(.title3)
                .foregroundStyle(AppColors.accent)
                .frame(width: 34, height: 34)
                .background(AppColors.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.fileName?.isEmpty == false ? attachment.fileName ?? "Файл" : "Файл")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if let size = attachment.size {
                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
    }

    private func loadingPlaceholder(systemImage: String, title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
            Text(title)
                .font(.caption)
        }
        .foregroundStyle(.white.opacity(0.85))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.26))
    }
}

struct MediaViewerView: View {
    let attachment: TgAttachment
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            FullscreenCloseButton {
                dismiss()
            }
            .padding(.top, 18)
            .padding(.trailing, 18)
        }
        .onAppear(perform: preparePlayer)
        .onDisappear {
            player?.pause()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch attachment.kind {
        case .photo:
            if let path = attachment.localPath {
                FullscreenImageContent(imagePath: path)
            } else {
                MissingMediaView(title: "Фото еще загружается")
            }
        case .video:
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                MissingMediaView(title: "Видео еще загружается")
            }
        case .videoNote:
            if let player {
                GeometryReader { proxy in
                    let side = min(proxy.size.width, proxy.size.height) * 0.74
                    VideoPlayer(player: player)
                        .frame(width: side, height: side)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                MissingMediaView(title: "Кружок еще загружается")
            }
        case .voice:
            FullscreenVoicePlayer(attachment: attachment)
        case .document:
            MissingMediaView(title: attachment.fileName ?? "Файл")
        }
    }

    private func preparePlayer() {
        guard player == nil, let url = attachment.localURL else { return }
        switch attachment.kind {
        case .video, .videoNote:
            player = AVPlayer(url: url)
            player?.play()
        default:
            break
        }
    }
}

struct FullscreenImageViewer: View {
    let imagePath: String
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            FullscreenImageContent(imagePath: imagePath)

            FullscreenCloseButton {
                dismiss()
            }
            .padding(.top, 18)
            .padding(.trailing, 18)
        }
        .accessibilityLabel(title)
    }
}

private struct FullscreenImageContent: View {
    let imagePath: String
    @State private var scale: CGFloat = 1
    @State private var committedScale: CGFloat = 1

    var body: some View {
        Group {
            if let image = UIImage(contentsOfFile: imagePath) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = min(max(committedScale * value, 1), 4)
                            }
                            .onEnded { _ in
                                committedScale = scale
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            scale = scale > 1 ? 1 : 2.2
                            committedScale = scale
                        }
                    }
                    .padding(8)
            } else {
                MissingMediaView(title: "Не удалось открыть изображение")
            }
        }
    }
}

private struct FullscreenVoicePlayer: View {
    let attachment: TgAttachment

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 92))
                .foregroundStyle(AppColors.accent)

            VStack(spacing: 6) {
                Text("Голосовое сообщение")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                if let size = attachment.size {
                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                }
            }

            InlineVoicePlayer(attachment: attachment, expanded: true)
                .frame(maxWidth: 320)
        }
        .padding(24)
    }
}

private struct InlineVoicePlayer: View {
    let attachment: TgAttachment
    var expanded: Bool = false
    var onOpen: (() -> Void)?
    @State private var player: AVPlayer?
    @State private var isPlaying = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: expanded ? 44 : 34, height: expanded ? 44 : 34)
                    .background(attachment.localURL == nil ? Color.secondary.opacity(0.45) : AppColors.accent)
                    .clipShape(Circle())
            }
            .disabled(attachment.localURL == nil)

            VStack(alignment: .leading, spacing: 6) {
                Text("Голосовое")
                    .font(expanded ? .headline : .subheadline.weight(.semibold))
                    .foregroundStyle(expanded ? .white : .primary)

                VoiceWaveform()
                    .foregroundStyle(attachment.localURL == nil ? Color.secondary.opacity(0.45) : AppColors.accent)
            }

            Spacer(minLength: 0)

            if let onOpen, attachment.localURL != nil {
                Button(action: onOpen) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(expanded ? 14 : 10)
        .onDisappear {
            player?.pause()
            isPlaying = false
        }
    }

    private func togglePlayback() {
        guard let url = attachment.localURL else { return }
        if player == nil {
            player = AVPlayer(url: url)
        }

        if isPlaying {
            player?.pause()
        } else {
            player?.play()
        }
        isPlaying.toggle()
    }
}

private struct VoiceWaveform: View {
    private let heights: [CGFloat] = [8, 16, 11, 20, 13, 24, 10, 18, 28, 14, 22, 12, 18, 9, 24, 15, 20, 11]

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(heights.indices, id: \.self) { index in
                Capsule()
                    .frame(width: 3, height: heights[index])
            }
        }
        .frame(height: 30)
    }
}

private struct VideoThumbnailView: View {
    let url: URL?
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [Color.black.opacity(0.22), AppColors.accent.opacity(0.35)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .task(id: url?.path) {
            guard let url else { return }
            image = await makeThumbnail(url: url)
        }
    }

    private func makeThumbnail(url: URL) async -> UIImage? {
        await Task.detached(priority: .utility) {
            let asset = AVAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            let time = CMTime(seconds: 0.25, preferredTimescale: 600)
            guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
                return nil
            }
            return UIImage(cgImage: cgImage)
        }.value
    }
}

private struct MissingMediaView: View {
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.white)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(24)
    }
}

private struct FullscreenCloseButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .tint(.white)
    }
}

private extension TgAttachment {
    var localURL: URL? {
        guard let localPath, !localPath.isEmpty, FileManager.default.fileExists(atPath: localPath) else {
            return nil
        }
        return URL(fileURLWithPath: localPath)
    }

    var localImage: UIImage? {
        guard let localPath, !localPath.isEmpty else { return nil }
        return UIImage(contentsOfFile: localPath)
    }
}
