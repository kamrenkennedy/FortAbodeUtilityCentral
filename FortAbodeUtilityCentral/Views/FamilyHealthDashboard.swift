import SwiftUI
import AppKit
import AlignedDesignSystem

// MARK: - Family Health Dashboard
//
// Reads the first entry of facts.json#insurance.health and renders the 2026
// Kennedy family health plan as a first-class dashboard. Everything is
// read-only — edits happen outside the app, in FAMILY_MEMORY.md or facts.json.

struct FamilyHealthDashboard: View {

    let plan: HealthInsurancePlan

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                premiumHero

                if let components = plan.components, !components.isEmpty {
                    sectionHeader("Plan Components")
                    componentGrid(components)
                }

                if let doctors = plan.inNetworkDoctors, !doctors.isEmpty {
                    sectionHeader("In-Network Doctors")
                    VStack(spacing: 8) {
                        ForEach(doctors, id: \.self) { doctor in
                            doctorRow(doctor)
                        }
                    }
                }

                phoneSection

                if let actionItems = plan.actionItems2026, !actionItems.isEmpty {
                    sectionHeader("Action Items (2026)")
                    VStack(spacing: 8) {
                        ForEach(actionItems, id: \.self) { item in
                            actionItemRow(item)
                        }
                    }
                }

                if let exclusions = plan.exclusions, !exclusions.isEmpty {
                    sectionHeader("What's Not Covered")
                    exclusionsCard(exclusions)
                }

                if let agent = plan.agent {
                    sectionHeader("Insurance Agent")
                    agentCard(agent)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Hero

    @ViewBuilder
    private var premiumHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.planName ?? "Health Plan")
                        .font(.title3.bold())
                    if let carrier = plan.carrier {
                        Text(carrier)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if let premium = plan.monthlyPremium {
                        Text(premium)
                            .font(.system(.title2, design: .rounded).bold())
                            .foregroundStyle(.green)
                    }
                    Text("Monthly premium")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider().opacity(0.2)

            HStack(spacing: 28) {
                heroStat(title: "Effective", value: plan.effectiveDate)
                heroStat(title: "Network", value: plan.networkName)
                heroStat(title: "OOP Max", value: plan.individualOopMax)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.green.opacity(0.12), .green.opacity(0.02)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                }
        }
    }

    @ViewBuilder
    private func heroStat(title: String, value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value ?? "—")
                .font(.caption.bold())
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Plan components

    @ViewBuilder
    private func componentGrid(_ components: [PlanComponent]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 12)],
            spacing: 12
        ) {
            ForEach(Array(components.enumerated()), id: \.offset) { _, component in
                componentCard(component)
            }
        }
    }

    @ViewBuilder
    private func componentCard(_ component: PlanComponent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(component.name ?? "Component")
                .font(.subheadline.bold())

            if let purpose = component.purpose {
                Text(purpose)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().opacity(0.2)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(componentKeyValues(component), id: \.0) { pair in
                    HStack(alignment: .top) {
                        Text(pair.0)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .frame(width: 90, alignment: .leading)
                        Text(pair.1)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }

    private func componentKeyValues(_ component: PlanComponent) -> [(String, String)] {
        var pairs: [(String, String)] = []
        if let deductible = component.deductible { pairs.append(("Deductible", deductible)) }
        if let sickness = component.deductibleSickness { pairs.append(("Sickness", sickness)) }
        if let accident = component.deductibleAccident { pairs.append(("Accident", accident)) }
        if let accidentDed = component.accidentDeductible { pairs.append(("Accident", accidentDed)) }
        if let coinsurance = component.coinsurance { pairs.append(("Coinsurance", coinsurance)) }
        if let maxAmount = component.calendarYearMax { pairs.append(("Max", maxAmount)) }
        if let planLevel = component.planLevel { pairs.append(("Plan level", planLevel)) }
        if let planTier = component.planTier { pairs.append(("Tier", planTier)) }
        if let preventive = component.preventive { pairs.append(("Preventive", preventive)) }
        if let basic = component.basicWork { pairs.append(("Basic", basic)) }
        if let major = component.majorWork { pairs.append(("Major", major)) }
        if let dentist = component.inNetworkDentist { pairs.append(("In-network", dentist)) }
        if let kamBenefit = component.kamBenefit { pairs.append(("Kam", kamBenefit)) }
        if let tieraBenefit = component.tieraBenefit { pairs.append(("Tiera", tieraBenefit)) }
        if let policy = component.policyNumber { pairs.append(("Policy #", policy)) }
        if let notes = component.notes { pairs.append(("Notes", notes)) }
        return pairs
    }

    // MARK: - Doctors

    @ViewBuilder
    private func doctorRow(_ doctor: Doctor) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "stethoscope")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.green)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(doctor.name ?? "Unnamed")
                    .font(.subheadline.bold())
                HStack(spacing: 6) {
                    if let specialty = doctor.specialty {
                        Text(specialty)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let practice = doctor.practice {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(practice)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if doctor.status?.localizedCaseInsensitiveContains("in-network") == true {
                Text("In-network")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background {
                        Capsule().fill(.green.opacity(0.18))
                    }
                    .foregroundStyle(.green)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }

    // MARK: - Phones

    @ViewBuilder
    private var phoneSection: some View {
        let rows: [(String, String?)] = [
            ("Member services", plan.memberServicesPhone),
            ("Pharmacy", plan.pharmacyPhone),
            ("Provider eligibility", plan.providerEligibilityPhone),
            ("Precertification", plan.precertificationPhone)
        ]
        let present = rows.compactMap { pair -> (String, String)? in
            guard let value = pair.1 else { return nil }
            return (pair.0, value)
        }

        if !present.isEmpty {
            sectionHeader("Phone Numbers")
            VStack(spacing: 8) {
                ForEach(Array(present.enumerated()), id: \.offset) { _, pair in
                    phoneRow(label: pair.0, number: pair.1)
                }
            }
        }
    }

    @ViewBuilder
    private func phoneRow(label: String, number: String) -> some View {
        let telURL = URL(string: "tel:\(number.filter { $0.isNumber })")

        HStack {
            Image(systemName: "phone.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(number)
                    .font(.subheadline.monospaced())
            }

            Spacer()

            if let telURL {
                Link("Call", destination: telURL)
                    .buttonStyle(.alignedSecondaryMini)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }

    // MARK: - Action items

    @ViewBuilder
    private func actionItemRow(_ item: String) -> some View {
        let isUrgent = item.hasPrefix("URGENT")
        let color: Color = isUrgent ? .red : .orange

        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isUrgent ? "exclamationmark.triangle.fill" : "checkmark.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 24)

            Text(item)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.08))
        }
    }

    // MARK: - Exclusions

    @ViewBuilder
    private func exclusionsCard(_ exclusions: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(exclusions, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.8))
                    Text(item)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.red.opacity(0.05))
        }
    }

    // MARK: - Agent

    @ViewBuilder
    private func agentCard(_ agent: Agent) -> some View {
        HStack {
            Image(systemName: "person.text.rectangle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(agent.firstName ?? "Agent")
                    .font(.subheadline.bold())
                if let email = agent.email {
                    Text(email)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let email = agent.email, let url = URL(string: "mailto:\(email)") {
                Link("Email", destination: url)
                    .buttonStyle(.alignedSecondaryMini)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.top, 4)
    }
}
