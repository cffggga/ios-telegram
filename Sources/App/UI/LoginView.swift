import SwiftUI

struct LoginView: View {
    @ObservedObject var vm: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text(vm.authStepTitle())
                    .font(.title2.bold())
                Text(vm.authStepSubtitle())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)
            .padding(.bottom, 32)

            VStack(spacing: 16) {
                switch vm.authState {
                case .waitPhone:
                    TextField("+7 999 123 45 67", text: $vm.phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .textFieldStyle(.roundedBorder)
                case .waitCode:
                    TextField("Код из Telegram", text: $vm.code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .textFieldStyle(.roundedBorder)
                case .waitPassword:
                    SecureField("Пароль 2FA", text: $vm.password)
                        .textContentType(.password)
                        .textFieldStyle(.roundedBorder)
                case .ready:
                    EmptyView()
                }
            }
            .padding(.horizontal, 24)

            if !vm.status.isEmpty {
                Text(vm.status)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.top, 12)
                    .padding(.horizontal, 24)
            }

            Spacer()

            Button {
                Task { await vm.submitAuth() }
            } label: {
                HStack {
                    if vm.isBusy {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(vm.isBusy ? "Проверка…" : "Войти")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.accent)
            .disabled(vm.isBusy || vm.authState == .ready)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(AppColors.screenBackground)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("API") {
                    vm.phase = .setup
                }
            }
        }
    }
}
