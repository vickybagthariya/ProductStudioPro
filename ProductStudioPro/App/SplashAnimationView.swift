import SwiftUI

// MARK: - Root wrapper

/// Presents a branded animated splash, then cross-fades into the existing app root.
struct SplashAnimationView<Content: View>: View {
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSplash = true
    @State private var splashOpacity: Double = 1
    @State private var contentOpacity: Double = 0

    private let holdDuration: Double = 0.75
    private let fadeOutDuration: Double = 0.35

    var body: some View {
        ZStack {
            content()
                .opacity(contentOpacity)

            if showSplash {
                SplashScreenContent(reduceMotion: reduceMotion)
                    .opacity(splashOpacity)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .onAppear(perform: beginSplashSequence)
    }

    private func beginSplashSequence() {
        let splashKey = "hasSeenBrandedSplash"
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: splashKey) {
            showSplash = false
            splashOpacity = 0
            contentOpacity = 1
            return
        }

        let fadeOutDelay = reduceMotion ? 0.45 : holdDuration
        let fadeOut = reduceMotion ? 0.25 : fadeOutDuration

        DispatchQueue.main.asyncAfter(deadline: .now() + fadeOutDelay) {
            withAnimation(.easeInOut(duration: fadeOut)) {
                splashOpacity = 0
                contentOpacity = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + fadeOut) {
                showSplash = false
                defaults.set(true, forKey: splashKey)
            }
        }
    }
}

// MARK: - Splash content

private struct SplashScreenContent: View {
    let reduceMotion: Bool

    @State private var logoOpacity: Double = 0
    @State private var logoScale: CGFloat = 0.94
    @State private var titleOpacity: Double = 0
    @State private var subtitleOpacity: Double = 0
    @State private var poweredOpacity: Double = 0
    @State private var shimmerPhase: CGFloat = -1.2

    var body: some View {
        ZStack {
            SplashBackgroundGradient()

            if !reduceMotion {
                SplashFloatingParticles()
            }

            VStack(spacing: 0) {
                Spacer()

                logoBlock
                    .padding(.bottom, 28)

                Text("Product Studio Pro")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(SplashPalette.titleMint)
                    .opacity(titleOpacity)

                Text("Professional Product Photography")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.top, 10)
                    .opacity(subtitleOpacity)

                Text("Powered by AI")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SplashPalette.cyanGlow.opacity(0.85))
                    .tracking(0.6)
                    .padding(.top, 18)
                    .opacity(poweredOpacity)

                Spacer()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 28)
        }
        .ignoresSafeArea()
        .onAppear(perform: runEntranceAnimations)
    }

    private var logoBlock: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            SplashPalette.cyanGlow.opacity(0.55),
                            SplashPalette.cyanGlow.opacity(0.12),
                            .clear
                        ],
                        center: .center,
                        startRadius: 8,
                        endRadius: 92
                    )
                )
                .frame(width: 180, height: 180)
                .blur(radius: 18)

            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 118, height: 118)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay {
                    if !reduceMotion {
                        SplashGlassShimmer(phase: shimmerPhase)
                            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    }
                }
                .shadow(color: SplashPalette.cyanGlow.opacity(0.35), radius: 22, y: 8)
                .shadow(color: .black.opacity(0.35), radius: 16, y: 10)
        }
        .scaleEffect(logoScale)
        .opacity(logoOpacity)
    }

    private func runEntranceAnimations() {
        if reduceMotion {
            logoOpacity = 1
            logoScale = 1
            titleOpacity = 1
            subtitleOpacity = 1
            poweredOpacity = 1
            return
        }

        withAnimation(.easeOut(duration: 0.55)) {
            logoOpacity = 1
            logoScale = 1
        }

        withAnimation(.easeOut(duration: 0.5).delay(0.45)) {
            titleOpacity = 1
        }

        withAnimation(.easeOut(duration: 0.5).delay(0.75)) {
            subtitleOpacity = 1
        }

        withAnimation(.easeOut(duration: 0.45).delay(1.05)) {
            poweredOpacity = 1
        }

        withAnimation(.linear(duration: 1.35).delay(0.25).repeatForever(autoreverses: false)) {
            shimmerPhase = 1.35
        }
    }
}

// MARK: - Background & effects

private enum SplashPalette {
    static let emeraldDeep = Color(red: 0.10, green: 0.18, blue: 0.16)
    static let emeraldMid = Color(red: 0.157, green: 0.247, blue: 0.231)
    static let emeraldRich = Color(red: 0.12, green: 0.28, blue: 0.24)
    static let titleMint = Color(red: 0.60, green: 0.87, blue: 0.78)
    static let cyanGlow = Color(red: 0.45, green: 0.92, blue: 0.88)
}

private struct SplashBackgroundGradient: View {
    var body: some View {
        LinearGradient(
            colors: [
                SplashPalette.emeraldDeep,
                SplashPalette.emeraldMid,
                SplashPalette.emeraldRich,
                SplashPalette.emeraldDeep
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            RadialGradient(
                colors: [
                    SplashPalette.cyanGlow.opacity(0.14),
                    .clear
                ],
                center: .center,
                startRadius: 40,
                endRadius: 420
            )
        }
    }
}

private struct SplashGlassShimmer: View {
    let phase: CGFloat

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            LinearGradient(
                colors: [
                    .clear,
                    .white.opacity(0.08),
                    .white.opacity(0.42),
                    .white.opacity(0.08),
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: width * 0.55)
            .rotationEffect(.degrees(-18))
            .offset(x: width * phase)
            .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
    }
}

private struct SplashFloatingParticles: View {
    private struct Particle: Identifiable {
        let id: Int
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let opacity: Double
        let drift: CGFloat
        let duration: Double
    }

    private let particles: [Particle] = (0..<14).map { index in
        let seed = Double(index + 1)
        return Particle(
            id: index,
            x: CGFloat((seed * 47).truncatingRemainder(dividingBy: 100)) / 100,
            y: CGFloat((seed * 83).truncatingRemainder(dividingBy: 100)) / 100,
            size: CGFloat(2 + (seed.truncatingRemainder(dividingBy: 3))),
            opacity: 0.12 + (seed.truncatingRemainder(dividingBy: 4)) * 0.06,
            drift: CGFloat(8 + (seed.truncatingRemainder(dividingBy: 14))),
            duration: 4.5 + (seed.truncatingRemainder(dividingBy: 3))
        )
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                for particle in particles {
                    let baseX = particle.x * size.width
                    let baseY = particle.y * size.height
                    let bob = sin(time / particle.duration * .pi * 2 + Double(particle.id)) * particle.drift
                    let rect = CGRect(
                        x: baseX,
                        y: baseY + bob,
                        width: particle.size,
                        height: particle.size
                    )
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(.white.opacity(particle.opacity))
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}
