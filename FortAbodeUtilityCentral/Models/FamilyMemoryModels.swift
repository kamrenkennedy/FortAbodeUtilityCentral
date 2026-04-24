import Foundation

// MARK: - Family Memory Models
//
// Codable mirror of the shared family memory files in iCloud at
// `~/Library/Mobile Documents/com~apple~CloudDocs/Kennedy Family Docs/Claude/Family Memory/`.
// Fort Abode reads these but never writes them — they're authored by Claude
// sessions via the markdown-based family memory routing block.

// MARK: - Top-level facts.json

struct FamilyFacts: Codable, Sendable, Hashable {
    let version: Int?
    let lastModified: String?
    let lastModifiedBy: String?
    let household: Household?
    let insurance: Insurance?
    let house: House?
    let vehicles: [Vehicle]?
    let finances: Finances?
    let contacts: [Contact]?
    let travel: Travel?

    enum CodingKeys: String, CodingKey {
        case version
        case lastModified = "last_modified"
        case lastModifiedBy = "last_modified_by"
        case household
        case insurance
        case house
        case vehicles
        case finances
        case contacts
        case travel
    }
}

// MARK: - Household

struct Household: Codable, Sendable, Hashable {
    let members: [String]?
    let location: String?
    let address: String?
    let pets: [String]?
}

// MARK: - Insurance

struct Insurance: Codable, Sendable, Hashable {
    let health: [HealthInsurancePlan]?
    let auto: [AutoInsurancePlan]?
    let home: [HomeInsurancePlan]?
    let life: [LifeInsurancePlan]?
}

struct HealthInsurancePlan: Codable, Sendable, Hashable {
    let planName: String?
    let carrier: String?
    let association: String?
    let effectiveDate: String?
    let monthlyPremium: String?
    let networkName: String?
    let coveredMembers: [String]?
    let controlNumber: String?
    let planNumber: String?
    let memberPortal: String?
    let memberServicesPhone: String?
    let pharmacyPhone: String?
    let providerEligibilityPhone: String?
    let precertificationPhone: String?
    let electronicClaimsPayerId: String?
    let paperClaimsAddress: String?
    let rxBin: String?
    let rxPcn: String?
    let rxGrp: String?
    let individualOopMax: String?
    let dayToDayDeductible: String?
    let majorMedicalDeductible: String?
    let majorMedicalCoinsurance: String?
    let lifetimeMax: String?
    let components: [PlanComponent]?
    let inNetworkDoctors: [Doctor]?
    let exclusions: [String]?
    let actionItems2026: [String]?
    let agent: Agent?
    let sourcePdfs: [String: String]?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case planName = "plan_name"
        case carrier
        case association
        case effectiveDate = "effective_date"
        case monthlyPremium = "monthly_premium"
        case networkName = "network_name"
        case coveredMembers = "covered_members"
        case controlNumber = "control_number"
        case planNumber = "plan_number"
        case memberPortal = "member_portal"
        case memberServicesPhone = "member_services_phone"
        case pharmacyPhone = "pharmacy_phone"
        case providerEligibilityPhone = "provider_eligibility_phone"
        case precertificationPhone = "precertification_phone"
        case electronicClaimsPayerId = "electronic_claims_payer_id"
        case paperClaimsAddress = "paper_claims_address"
        case rxBin = "rx_bin"
        case rxPcn = "rx_pcn"
        case rxGrp = "rx_grp"
        case individualOopMax = "individual_oop_max"
        case dayToDayDeductible = "day_to_day_deductible"
        case majorMedicalDeductible = "major_medical_deductible"
        case majorMedicalCoinsurance = "major_medical_coinsurance"
        case lifetimeMax = "lifetime_max"
        case components
        case inNetworkDoctors = "in_network_doctors"
        case exclusions
        case actionItems2026 = "action_items_2026"
        case agent
        case sourcePdfs = "source_pdfs"
        case notes
    }
}

struct PlanComponent: Codable, Sendable, Hashable {
    let name: String?
    let policyNumber: String?
    let purpose: String?
    let deductible: String?
    let deductibleSickness: String?
    let deductibleAccident: String?
    let accidentDeductible: String?
    let coinsurance: String?
    let calendarYearMax: String?
    let planLevel: String?
    let planTier: String?
    let network: String?
    let preventive: String?
    let basicWork: String?
    let majorWork: String?
    let inNetworkDentist: String?
    let claimsPayerId: String?
    let paperClaimsAddress: String?
    let kamBenefit: String?
    let tieraBenefit: String?
    let mentalHealthNote: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case name
        case policyNumber = "policy_number"
        case purpose
        case deductible
        case deductibleSickness = "deductible_sickness"
        case deductibleAccident = "deductible_accident"
        case accidentDeductible = "accident_deductible"
        case coinsurance
        case calendarYearMax = "calendar_year_max"
        case planLevel = "plan_level"
        case planTier = "plan_tier"
        case network
        case preventive
        case basicWork = "basic_work"
        case majorWork = "major_work"
        case inNetworkDentist = "in_network_dentist"
        case claimsPayerId = "claims_payer_id"
        case paperClaimsAddress = "paper_claims_address"
        case kamBenefit = "kam_benefit"
        case tieraBenefit = "tiera_benefit"
        case mentalHealthNote = "mental_health_note"
        case notes
    }
}

struct Doctor: Codable, Sendable, Hashable {
    let name: String?
    let specialty: String?
    let practice: String?
    let status: String?
}

struct Agent: Codable, Sendable, Hashable {
    let firstName: String?
    let email: String?

    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case email
    }
}

// MARK: - Non-health insurance placeholders (schema-complete, empty for now)

struct AutoInsurancePlan: Codable, Sendable, Hashable {
    let planName: String?
    let carrier: String?

    enum CodingKeys: String, CodingKey {
        case planName = "plan_name"
        case carrier
    }
}

struct HomeInsurancePlan: Codable, Sendable, Hashable {
    let planName: String?
    let carrier: String?

    enum CodingKeys: String, CodingKey {
        case planName = "plan_name"
        case carrier
    }
}

struct LifeInsurancePlan: Codable, Sendable, Hashable {
    let planName: String?
    let carrier: String?

    enum CodingKeys: String, CodingKey {
        case planName = "plan_name"
        case carrier
    }
}

// MARK: - House / Vehicles / Finances / Contacts / Travel

struct House: Codable, Sendable, Hashable {
    let address: String?
}

struct Vehicle: Codable, Sendable, Hashable {
    let make: String?
    let model: String?
    let year: String?
    let notes: String?
}

struct Finances: Codable, Sendable, Hashable {
    let recurringBills: [RecurringBill]?

    enum CodingKeys: String, CodingKey {
        case recurringBills = "recurring_bills"
    }
}

struct RecurringBill: Codable, Sendable, Hashable {
    let name: String?
    let amount: String?
    let cadence: String?
    let payer: String?
    let notes: String?
}

struct Contact: Codable, Sendable, Hashable, Identifiable {
    let name: String?
    let role: String?
    let email: String?
    let phone: String?
    let notes: String?

    // Identifiable conformance — name + role is unique enough for list rendering
    var id: String {
        "\(name ?? "unnamed")-\(role ?? "no-role")"
    }
}

struct Travel: Codable, Sendable, Hashable {
    let passports: [String: String]?
}

// MARK: - FAMILY_MEMORY.md section metadata

/// A single `## Section` parsed from FAMILY_MEMORY.md. Used to populate the
/// sidebar in the Family Memory view — each section becomes a nav row with an
/// "empty" indicator if no body facts beyond placeholders exist.
struct FamilySection: Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let body: String
    let isEmpty: Bool
}
