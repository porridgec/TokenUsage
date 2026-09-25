import SwiftUI
@preconcurrency import AVFoundation

/// iOS「从 Mac 导入」页：相机扫码，或粘贴 Mac 版导出的导入串（模拟器/无相机场景）。
struct QRScannerScreen: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var pasteText = ""
    @State private var invalidFeedback = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                QRScannerRepresentable { payload in
                    importPayload(payload)
                }
                .frame(maxHeight: 320)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(spacing: 8) {
                    // SecureField：导入串包含明文 key，避免肩窥/回显泄露
                    SecureField("或粘贴导入串（tokenusage-import:v1:…）", text: $pasteText)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("粘贴导入") { importPayload(pasteText) }
                        .disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if invalidFeedback {
                        Text("无法识别：不是本 App 导出的导入串")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal)
            }
            .navigationTitle("从 Mac 导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func importPayload(_ value: String) {
        guard let keys = CredentialTransfer.decode(value) else {
            invalidFeedback = true
            return
        }
        for (provider, key) in keys {
            try? KeychainStore.saveKey(key, for: provider)
        }
        pasteText = "" // 导入成功即清除明文，避免残留
        Task { await model.providerDidChange() }
        dismiss()
    }
}

/// AVCapture 的二维码扫描控制器。
final class QRScannerController: UIViewController, @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
    var onScanned: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else {
            showFailureLabel("无法访问相机（模拟器不支持扫码，请用下方粘贴导入）")
            return
        }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            showFailureLabel("无法初始化扫描")
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        previewLayer = preview
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        session.stopRunning()
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let object = metadataObjects
            .compactMap({ $0 as? AVMetadataMachineReadableCodeObject })
            .first(where: { $0.type == .qr }),
            let value = object.stringValue
        else { return }
        onScanned?(value)
    }

    private func showFailureLabel(_ text: String) {
        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16),
        ])
    }
}

struct QRScannerRepresentable: UIViewControllerRepresentable {
    let onScanned: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerController {
        let controller = QRScannerController()
        controller.onScanned = onScanned
        return controller
    }

    func updateUIViewController(_ controller: QRScannerController, context: Context) {}
}
