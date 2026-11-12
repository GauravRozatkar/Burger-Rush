import SwiftUI
import Combine
import Combine

// MARK: - Models

enum Ingredient: String, CaseIterable, Identifiable {
    case bun = "🍞"
    case patty = "🥩"
    case cheese = "🧀"
    case lettuce = "🥬"
    case tomato = "🍅"
    case soda = "🥤"
    
    var id: String { rawValue }
    
    var name: String {
        switch self {
        case .bun: return "Bun"
        case .patty: return "Patty"
        case .cheese: return "Cheese"
        case .lettuce: return "Lettuce"
        case .tomato: return "Tomato"
        case .soda: return "Soda"
        }
    }
}

enum GrillState: Equatable {
    case empty
    case cooking(progress: Double)
    case cooked(burnProgress: Double)
    case burned
}

struct GrillSlot: Identifiable {
    let id: Int
    var state: GrillState = .empty
}

struct Customer: Identifiable {
    let id = UUID()
    let avatar: String
    let order: [Ingredient]
    var patience: Double // 0.0 to 1.0
    let maxPatience: Double
    let reward: Int
}

// MARK: - Game Engine (ViewModel)

@MainActor
final class RestaurantGameEngine: ObservableObject {
    // Player Progression & Stats
    @Published var coins: Int = 50
    @Published var shiftScore: Int = 0
    @Published var highScore: Int = 0
    @Published var day: Int = 1
    @Published var combo: Int = 0
    
    // Shift Timer & State
    @Published var timeRemaining: Double = 60.0
    @Published var isShiftActive: Bool = false
    @Published var showShiftSummary: Bool = false
    @Published var lastShiftEarnings: Int = 0
    @Published var customersServed: Int = 0
    
    // Kitchen Stations
    @Published var grillSlots: [GrillSlot] = [
        GrillSlot(id: 0),
        GrillSlot(id: 1),
        GrillSlot(id: 2)
    ]
    @Published var assemblyPlate: [Ingredient] = []
    @Published var customers: [Customer] = []
    
    // Upgrades
    @Published var grillSpeedLevel: Int = 1
    @Published var tipMultiplierLevel: Int = 1
    @Published var burnProtectionLevel: Int = 1
    
    // Haptic & UI Triggers
    @Published var hapticTrigger: Int = 0
    @Published var floatingFeedback: String? = nil
    
    private var timerCancellable: AnyCancellable?
    private var spawnCooldown: Double = 1.5
    private let customerAvatars = ["🧑‍💼", "👩‍🎨", "🧔‍♂️", "👩‍🚀", "🧑‍🍳", "👵", "🕵️‍♂️", "👩‍🎤"]
    
    var grillCookDuration: Double {
        max(1.2, 3.5 - Double(grillSpeedLevel - 1) * 0.55)
    }
    
    var burnDuration: Double {
        4.0 + Double(burnProtectionLevel - 1) * 1.5
    }
    
    var tipMultiplier: Double {
        1.0 + Double(tipMultiplierLevel - 1) * 0.25
    }
    
    // MARK: - Game Loop
    
    func startShift() {
        shiftScore = 0
        lastShiftEarnings = 0
        customersServed = 0
        combo = 0
        timeRemaining = 60.0
        assemblyPlate = []
        customers = []
        grillSlots = [GrillSlot(id: 0), GrillSlot(id: 1), GrillSlot(id: 2)]
        spawnCooldown = 0.5
        isShiftActive = true
        showShiftSummary = false
        
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick(dt: 0.1)
            }
    }
    
    private func tick(dt: Double) {
        guard isShiftActive else { return }
        
        // 1. Update Shift Clock
        timeRemaining -= dt
        if timeRemaining <= 0 {
            endShift()
            return
        }
        
        // 2. Spawn Customers (Max 3 at counter)
        spawnCooldown -= dt
        if spawnCooldown <= 0 && customers.count < 3 {
            spawnCustomer()
            spawnCooldown = max(2.2, 5.0 - Double(day) * 0.35)
        }
        
        // 3. Update Grill Cooking & Burning
        for i in grillSlots.indices {
            switch grillSlots[i].state {
            case .empty, .burned:
                break
            case .cooking(let progress):
                let nextProgress = progress + (dt / grillCookDuration)
                if nextProgress >= 1.0 {
                    grillSlots[i].state = .cooked(burnProgress: 0.0)
                    triggerHaptic()
                } else {
                    grillSlots[i].state = .cooking(progress: nextProgress)
                }
            case .cooked(let burnProgress):
                let nextBurn = burnProgress + (dt / burnDuration)
                if nextBurn >= 1.0 {
                    grillSlots[i].state = .burned
                    triggerHaptic()
                } else {
                    grillSlots[i].state = .cooked(burnProgress: nextBurn)
                }
            }
        }
        
        // 4. Update Customer Patience
        for i in customers.indices.reversed() {
            customers[i].patience -= dt / customers[i].maxPatience
            if customers[i].patience <= 0 {
                customers.remove(at: i)
                combo = 0
                showFeedback("😡 Customer Left!")
                triggerHaptic()
            }
        }
    }
    
    private func endShift() {
        isShiftActive = false
        timerCancellable?.cancel()
        if shiftScore > highScore {
            highScore = shiftScore
        }
        day += 1
        showShiftSummary = true
    }
    
    private func spawnCustomer() {
        let avatar = customerAvatars.randomElement() ?? "🧑"
        var order: [Ingredient] = [.bun, .patty]
        
        let extras: [Ingredient] = [.cheese, .lettuce, .tomato]
        let extraCount = min(3, Int.random(in: 0...day))
        for _ in 0..<extraCount {
            if let item = extras.randomElement(), !order.contains(item) {
                order.append(item)
            }
        }
        if Bool.random() && day >= 2 {
            order.append(.soda)
        }
        
        let patienceTime = max(14.0, 24.0 - Double(day) * 0.8)
        let baseReward = order.count * 12
        
        let customer = Customer(
            avatar: avatar,
            order: order,
            patience: 1.0,
            maxPatience: patienceTime,
            reward: baseReward
        )
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            customers.append(customer)
        }
    }
    
    // MARK: - Player Actions
    
    func tapGrillSlot(_ index: Int) {
        guard isShiftActive, grillSlots.indices.contains(index) else { return }
        switch grillSlots[index].state {
        case .empty:
            grillSlots[index].state = .cooking(progress: 0.0)
            triggerHaptic()
        case .cooking:
            showFeedback("⏳ Still raw!")
        case .cooked:
            if assemblyPlate.count < 6 {
                assemblyPlate.append(.patty)
                grillSlots[index].state = .empty
                triggerHaptic()
            } else {
                showFeedback("🍽️ Plate full!")
            }
        case .burned:
            grillSlots[index].state = .empty
            coins = max(0, coins - 5)
            showFeedback("🗑️ Burned (-5💰)")
            triggerHaptic()
        }
    }
    
    func addIngredientToPlate(_ ingredient: Ingredient) {
        guard isShiftActive else { return }
        guard assemblyPlate.count < 6 else {
            showFeedback("🍽️ Plate full!")
            return
        }
        withAnimation(.snappy(duration: 0.2)) {
            assemblyPlate.append(ingredient)
        }
        triggerHaptic()
    }
    
    func trashPlate() {
        guard !assemblyPlate.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            assemblyPlate.removeAll()
        }
        triggerHaptic()
    }
    
    func serveCustomer(_ customer: Customer) {
        guard isShiftActive else { return }
        guard let index = customers.firstIndex(where: { $0.id == customer.id }) else { return }
        
        // Check if plate has the exact same ingredients (order-independent)
        if assemblyPlate.sorted(by: { $0.rawValue < $1.rawValue }) == customer.order.sorted(by: { $0.rawValue < $1.rawValue }) {
            combo += 1
            let speedBonus = Int(customer.patience * 15)
            let comboBonus = combo * 5
            let totalEarned = Int(Double(customer.reward + speedBonus + comboBonus) * tipMultiplier)
            
            coins += totalEarned
            shiftScore += totalEarned
            lastShiftEarnings += totalEarned
            customersServed += 1
            assemblyPlate.removeAll()
            
            _ = withAnimation(.spring) {
                customers.remove(at: index)
            }
            showFeedback("+\(totalEarned)💰 (\(combo)x Combo!)")
            triggerHaptic()
        } else {
            combo = 0
            showFeedback("❌ Wrong Order!")
            triggerHaptic()
        }
    }
    
    // MARK: - Upgrades
    
    func upgradeCost(level: Int) -> Int {
        level * 75
    }
    
    func buyGrillUpgrade() {
        let cost = upgradeCost(level: grillSpeedLevel)
        guard coins >= cost && grillSpeedLevel < 5 else { return }
        coins -= cost
        grillSpeedLevel += 1
        triggerHaptic()
    }
    
    func buyTipUpgrade() {
        let cost = upgradeCost(level: tipMultiplierLevel)
        guard coins >= cost && tipMultiplierLevel < 5 else { return }
        coins -= cost
        tipMultiplierLevel += 1
        triggerHaptic()
    }
    
    func buyBurnUpgrade() {
        let cost = upgradeCost(level: burnProtectionLevel)
        guard coins >= cost && burnProtectionLevel < 5 else { return }
        coins -= cost
        burnProtectionLevel += 1
        triggerHaptic()
    }
    
    private func triggerHaptic() {
        hapticTrigger += 1
    }
    
    private func showFeedback(_ text: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            floatingFeedback = text
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
            if self?.floatingFeedback == text {
                withAnimation {
                    self?.floatingFeedback = nil
                }
            }
        }
    }
}

// MARK: - Main Game View

struct ContentView: View {
    @StateObject private var game = RestaurantGameEngine()
    
    var body: some View {
        ZStack {
            // Warm Diner Background
            LinearGradient(
                colors: [Color(red: 0.16, green: 0.11, blue: 0.09), Color(red: 0.26, green: 0.16, blue: 0.11)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 14) {
                topHUD
                
                if game.isShiftActive {
                    customerCounterSection
                    Spacer(minLength: 4)
                    feedbackBanner
                    prepStationSection
                    grillSection
                    ingredientBarSection
                } else {
                    lobbyAndUpgradeView
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: game.hapticTrigger)
        .sheet(isPresented: $game.showShiftSummary) {
            shiftSummarySheet
        }
    }
    
    // MARK: - HUD
    
    private var topHUD: some View {
        HStack {
            // Day & Timer
            HStack(spacing: 8) {
                Text("DAY \(game.day)")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                
                if game.isShiftActive {
                    Label("\(Int(ceil(game.timeRemaining)))s", systemImage: "timer")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(game.timeRemaining < 10 ? .red : .white)
                }
            }
            
            Spacer()
            
            // Combo Pill
            if game.combo > 1 && game.isShiftActive {
                Text("🔥 \(game.combo)x")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.red.gradient)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            
            // Coins Counter
            HStack(spacing: 4) {
                Text("💰")
                Text("\(game.coins)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.yellow)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.black.opacity(0.45))
            .clipShape(Capsule())
        }
    }
    
    // MARK: - Customer Counter
    
    private var customerCounterSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ORDERS COUNTER (Tap customer to serve)")
                .font(.caption2.bold())
                .foregroundStyle(.white.opacity(0.65))
            
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { slot in
                    if slot < game.customers.count {
                        let customer = game.customers[slot]
                        Button {
                            game.serveCustomer(customer)
                        } label: {
                            customerCard(customer)
                        }
                        .buttonStyle(.plain)
                    } else {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.white.opacity(0.06))
                            .frame(maxWidth: .infinity)
                            .frame(height: 155)
                            .overlay(
                                Text("Waiting...")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.3))
                            )
                    }
                }
            }
        }
    }
    
    private func customerCard(_ customer: Customer) -> some View {
        VStack(spacing: 6) {
            // Patience Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.black.opacity(0.4))
                    Capsule()
                        .fill(customer.patience > 0.5 ? Color.green : (customer.patience > 0.25 ? Color.orange : Color.red))
                        .frame(width: max(0, geo.size.width * customer.patience))
                }
            }
            .frame(height: 6)
            
            Text(customer.avatar)
                .font(.system(size: 34))
            
            // Order Ticket
            VStack(spacing: 2) {
                ForEach(Array(customer.order.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 4) {
                        Text(item.rawValue)
                            .font(.caption)
                        Text(item.name)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color(red: 0.98, green: 0.95, blue: 0.88))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .frame(height: 155)
        .background(Color.white.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.orange.opacity(0.5), lineWidth: 1.5)
        )
    }
    
    // MARK: - Floating Toast Feedback
    
    private var feedbackBanner: some View {
        ZStack {
            if let feedback = game.floatingFeedback {
                Text(feedback)
                    .font(.subheadline.bold())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.75))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(height: 30)
    }
    
    // MARK: - Assembly Prep Board
    
    private var prepStationSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("ASSEMBLY BOARD")
                    .font(.caption2.bold())
                    .foregroundStyle(.white.opacity(0.65))
                Spacer()
                Button {
                    game.trashPlate()
                } label: {
                    Label("Clear", systemImage: "trash.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                }
            }
            
            HStack(spacing: 8) {
                if game.assemblyPlate.isEmpty {
                    Text("Tap ingredients & cooked patties to build order")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                } else {
                    ForEach(Array(game.assemblyPlate.enumerated()), id: \.offset) { _, item in
                        Text(item.rawValue)
                            .font(.system(size: 32))
                            .transition(.scale)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(Color(red: 0.76, green: 0.56, blue: 0.36).opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(red: 0.85, green: 0.65, blue: 0.42), lineWidth: 2)
            )
        }
    }
    
    // MARK: - Sizzling Grill
    
    private var grillSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FLAT-TOP GRILL (Tap to cook / collect)")
                .font(.caption2.bold())
                .foregroundStyle(.white.opacity(0.65))
            
            HStack(spacing: 12) {
                ForEach(game.grillSlots) { slot in
                    Button {
                        game.tapGrillSlot(slot.id)
                    } label: {
                        grillSlotView(slot)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private func grillSlotView(_ slot: GrillSlot) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.14, green: 0.14, blue: 0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(grillBorderColor(slot.state), lineWidth: 2.5)
                )
            
            VStack(spacing: 6) {
                switch slot.state {
                case .empty:
                    Image(systemName: "flame")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.25))
                    Text("Cook Patty")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                    
                case .cooking(let progress):
                    Text("🥩")
                        .font(.system(size: 32))
                        .opacity(0.75)
                    ProgressView(value: progress)
                        .tint(.orange)
                        .padding(.horizontal, 12)
                    Text("Sizzling...")
                        .font(.caption2.bold())
                        .foregroundStyle(.orange)
                    
                case .cooked(let burnProgress):
                    Text("🍔")
                        .font(.system(size: 34))
                    ProgressView(value: 1.0 - burnProgress)
                        .tint(burnProgress > 0.65 ? .red : .green)
                        .padding(.horizontal, 12)
                    Text("READY!")
                        .font(.caption2.bold())
                        .foregroundStyle(.green)
                    
                case .burned:
                    Text("💨")
                        .font(.system(size: 32))
                    Text("BURNED")
                        .font(.caption2.bold())
                        .foregroundStyle(.red)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 105)
    }
    
    private func grillBorderColor(_ state: GrillState) -> Color {
        switch state {
        case .empty: return .white.opacity(0.15)
        case .cooking: return .orange
        case .cooked: return .green
        case .burned: return .red
        }
    }
    
    // MARK: - Cold Ingredients & Drinks Bar
    
    private var ingredientBarSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PREP COUNTER")
                .font(.caption2.bold())
                .foregroundStyle(.white.opacity(0.65))
            
            HStack(spacing: 8) {
                ForEach([Ingredient.bun, .cheese, .lettuce, .tomato, .soda]) { item in
                    Button {
                        game.addIngredientToPlate(item)
                    } label: {
                        VStack(spacing: 4) {
                            Text(item.rawValue)
                                .font(.system(size: 28))
                            Text(item.name)
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - Kitchen Lobby & Upgrades Screen
    
    private var lobbyAndUpgradeView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            VStack(spacing: 8) {
                Text("🍔 BURGER RUSH")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                
                Text("High Score: 💰 \(game.highScore)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.yellow)
            }
            
            // Kitchen Upgrade Cards
            VStack(spacing: 12) {
                Text("KITCHEN UPGRADES")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.7))
                
                upgradeRow(
                    title: "Turbo Grill",
                    subtitle: "Cooks patties faster (Lv.\(game.grillSpeedLevel)/5)",
                    icon: "flame.fill",
                    level: game.grillSpeedLevel,
                    cost: game.upgradeCost(level: game.grillSpeedLevel),
                    action: game.buyGrillUpgrade
                )
                
                upgradeRow(
                    title: "Heat Lamps",
                    subtitle: "Prevents patties from burning (Lv.\(game.burnProtectionLevel)/5)",
                    icon: "shield.fill",
                    level: game.burnProtectionLevel,
                    cost: game.upgradeCost(level: game.burnProtectionLevel),
                    action: game.buyBurnUpgrade
                )
                
                upgradeRow(
                    title: "VIP Tip Jar",
                    subtitle: "Increases coin rewards (Lv.\(game.tipMultiplierLevel)/5)",
                    icon: "sparkles",
                    level: game.tipMultiplierLevel,
                    cost: game.upgradeCost(level: game.tipMultiplierLevel),
                    action: game.buyTipUpgrade
                )
            }
            .padding()
            .background(.black.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            
            Spacer()
            
            Button {
                game.startShift()
            } label: {
                Text("START DAY \(game.day) SHIFT")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .shadow(color: .orange.opacity(0.45), radius: 10, y: 5)
            }
        }
    }
    
    private func upgradeRow(title: String, subtitle: String, icon: String, level: Int, cost: Int, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.orange)
                .frame(width: 36)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
            }
            
            Spacer()
            
            if level >= 5 {
                Text("MAX")
                    .font(.caption.bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.green.opacity(0.3))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
            } else {
                Button {
                    action()
                } label: {
                    Text("💰 \(cost)")
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(game.coins >= cost ? Color.orange : Color.gray.opacity(0.4))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .disabled(game.coins < cost)
            }
        }
    }
    
    // MARK: - End of Shift Summary
    
    private var shiftSummarySheet: some View {
        VStack(spacing: 20) {
            Text("⏰ SHIFT COMPLETE!")
                .font(.title.bold())
            
            VStack(spacing: 12) {
                HStack {
                    Text("Customers Served:")
                    Spacer()
                    Text("\(game.customersServed)")
                        .bold()
                }
                HStack {
                    Text("Shift Earnings:")
                    Spacer()
                    Text("💰 \(game.lastShiftEarnings)")
                        .bold()
                        .foregroundStyle(.orange)
                }
                HStack {
                    Text("Total Bank:")
                    Spacer()
                    Text("💰 \(game.coins)")
                        .bold()
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            
            Button {
                game.showShiftSummary = false
            } label: {
                Text("Back to Kitchen Upgrades")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(24)
        .presentationDetents([.medium])
    }
}

#Preview {
    ContentView()
}

