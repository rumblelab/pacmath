import SwiftUI

struct ContentView: View {
    @State private var engine = GameEngine()
    @State private var speech = SpeechRecognizer()

    var body: some View {
        ZStack {
            Theme.background
                .ignoresSafeArea()

            switch engine.screen {
            case .start:
                StartView(engine: engine, speech: speech)
                    .transition(.opacity)
            case .game:
                GameView(engine: engine, speech: speech)
                    .transition(.opacity)
            case .results:
                ResultsView(engine: engine)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: engine.screen)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
}
