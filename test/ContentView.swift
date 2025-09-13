import SwiftUI
import CoreMotion

// MARK: - Motion (гравитация от наклона)
final class Motion: ObservableObject {
    private let manager = CMMotionManager()
    @Published var gravity: CGVector = .zero
    
    init() {
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        if manager.isDeviceMotionAvailable {
            manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let g = motion?.gravity else { return }
                // Поворачиваем в экранные координаты (y вниз)
                self?.gravity = CGVector(dx: g.x * 200, dy: -g.y * 200)
            }
        }
    }
}

// MARK: - Модель частицы
struct Blob: Identifiable {
    let id = UUID()
    var p: CGPoint          // position
    var v: CGVector         // velocity
    var r: CGFloat          // radius
    var hue: Double         // 0...1
}

// MARK: - Главная вью
struct ContentView: View {
    @StateObject private var motion = Motion()
    @State private var blobs: [Blob] = []
    @State private var boxSize: CGSize = .zero
    @State private var attractPoint: CGPoint? = nil
    @State private var neon = true
    
    private let haptic = UIImpactFeedbackGenerator(style: .medium)
    
    var body: some View {
        ZStack {
            // Фон
            LinearGradient(colors: neon ? [.black, .purple.opacity(0.6)] : [.black, .blue.opacity(0.4)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            
            // Рисуем частицы
            GeometryReader { geo in
                TimelineView(.animation(minimumInterval: 1.0/60.0)) { _ in
                    Canvas { ctx, size in
                        // сохраняем размер коробки
                        DispatchQueue.main.async { boxSize = size }
                        
                        // обновляем физику
                        update(dt: 1.0/60.0, size: size)
                        
                        for b in blobs {
                            var shape = Path(ellipseIn: CGRect(x: b.p.x - b.r,
                                                               y: b.p.y - b.r,
                                                               width: b.r*2, height: b.r*2))
                            
                            // Сияние (неоновый плюс-лайтер)
                            ctx.addFilter(.blur(radius: 12))
                            ctx.blendMode = .plusLighter
                            
                            let color = Color(hue: b.hue, saturation: 0.95, brightness: 1.0)
                            ctx.fill(shape, with: .color(color.opacity(0.55)))
                            
                            ctx.addFilter(.blur(radius: 0))
                            ctx.blendMode = .normal
                            ctx.stroke(shape, with: .color(color), lineWidth: 1.2)
                        }
                    }
                }
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        attractPoint = value.location
                    }
                    .onEnded { _ in
                        attractPoint = nil
                    }
                )
                .onAppear { seedBlobs(in: geo.size) }
            }
            
            // UI
            VStack {
                HStack {
                    Button {
                        neon.toggle()
                    } label: {
                        Label(neon ? "Neon ON" : "Neon OFF", systemImage: "bolt.horizontal.circle")
                            .padding(10)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    
                    Spacer()
                    
                    Button {
                        randomizeColors()
                    } label: {
                        Label("Recolor", systemImage: "paintpalette")
                            .padding(10)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                .padding()
                
                Spacer()
                
                HStack {
                    Button {
                        addBlobBurst(at: CGPoint(x: boxSize.width/2, y: 40))
                    } label: {
                        Label("Burst", systemImage: "sparkles")
                            .font(.headline)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    
                    Spacer()
                    
                    Button(role: .destructive) {
                        blobs.removeAll()
                    } label: {
                        Label("Clear", systemImage: "trash")
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                .padding()
            }
        }
        .statusBarHidden()
    }
    
    // MARK: - Инициализация
    private func seedBlobs(in size: CGSize) {
        guard blobs.isEmpty else { return }
        let count = 24
        blobs = (0..<count).map { i in
            let r: CGFloat = .random(in: 10...22)
            let p = CGPoint(x: .random(in: r...(size.width - r)),
                            y: .random(in: r...(size.height - r)))
            let v = CGVector(dx: .random(in: -40...40), dy: .random(in: -20...20))
            return Blob(p: p, v: v, r: r, hue: Double(i) / Double(count))
        }
    }
    
    private func randomizeColors() {
        for i in blobs.indices {
            blobs[i].hue = Double.random(in: 0...1)
        }
    }
    
    private func addBlobBurst(at point: CGPoint) {
        for _ in 0..<12 {
            let r: CGFloat = .random(in: 8...16)
            let angle = Double.random(in: 0...(2 * .pi))
            let speed = Double.random(in: 80...180)
            let v = CGVector(dx: cos(angle)*speed, dy: sin(angle)*speed)
            blobs.append(Blob(p: point, v: v, r: r, hue: Double.random(in: 0...1)))
        }
        haptic.impactOccurred()
    }
    
    // MARK: - Физика
    private func update(dt: Double, size: CGSize) {
        let g = motion.gravity
        let attract = attractPoint
        
        for i in blobs.indices {
            // Гравитация от наклона
            blobs[i].v.dx += g.dx * dt
            blobs[i].v.dy += g.dy * dt
            
            // Притяжение к пальцу
            if let a = attract {
                let dir = CGVector(dx: a.x - blobs[i].p.x, dy: a.y - blobs[i].p.y)
                let dist = max(20, hypot(dir.dx, dir.dy))
                let pull = 900.0 / Double(dist) // чем ближе — тем сильнее
                blobs[i].v.dx += dir.dx * pull * dt
                blobs[i].v.dy += dir.dy * pull * dt
            }
            
            // Демпфирование (вязкость "жидкости")
            blobs[i].v.dx *= 0.995
            blobs[i].v.dy *= 0.995
            
            // Обновить позицию
            blobs[i].p.x += blobs[i].v.dx * dt
            blobs[i].p.y += blobs[i].v.dy * dt
            
            // Столкновения со стенками
            var collided = false
            if blobs[i].p.x - blobs[i].r < 0 {
                blobs[i].p.x = blobs[i].r
                blobs[i].v.dx = abs(blobs[i].v.dx) * 0.85
                collided = true
            } else if blobs[i].p.x + blobs[i].r > size.width {
                blobs[i].p.x = size.width - blobs[i].r
                blobs[i].v.dx = -abs(blobs[i].v.dx) * 0.85
                collided = true
            }
            if blobs[i].p.y - blobs[i].r < 0 {
                blobs[i].p.y = blobs[i].r
                blobs[i].v.dy = abs(blobs[i].v.dy) * 0.85
                collided = true
            } else if blobs[i].p.y + blobs[i].r > size.height {
                blobs[i].p.y = size.height - blobs[i].r
                blobs[i].v.dy = -abs(blobs[i].v.dy) * 0.85
                collided = true
            }
            if collided && (abs(blobs[i].v.dx) + abs(blobs[i].v.dy) > 120) {
                haptic.impactOccurred(intensity: 0.9)
            }
        }
        
        // Простое "слипание": слегка тянуть друг к другу близкие шары (эффект жидкой массы)
        for i in blobs.indices {
            for j in (i+1)..<blobs.count {
                let dx = blobs[j].p.x - blobs[i].p.x
                let dy = blobs[j].p.y - blobs[i].p.y
                let d = hypot(dx, dy)
                let minD = blobs[i].r + blobs[j].r - 2   // небольшой оверлап допустим
                if d < minD && d > 0.001 {
                    let nx = dx / d, ny = dy / d
                    let push = (minD - d) * 0.5
                    blobs[i].p.x -= nx * push
                    blobs[i].p.y -= ny * push
                    blobs[j].p.x += nx * push
                    blobs[j].p.y += ny * push
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
