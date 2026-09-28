// without sharing: this is reference/config data (WorkTypes, territory, scheduling policy)
// that any legitimate caller of the Agent API needs to see, regardless of Salesforce
// record-level sharing rules. The integration user has no explicit sharing grants, and
// "with sharing" caused it to see zero WorkTypes/territories via plain SOQL (found by
// testing the live REST API with the real OAuth-authenticated integration user).
public without sharing class AgentConfig {
    public static final String TIMEZONE = 'America/Vancouver';
    public static final String SERVICE_TERRITORY_NAME = 'Metro Vancouver';
    public static final String SCHEDULING_POLICY_NAME = 'Customer First';

    public static final Set<String> SUPPORTED_CITIES = new Set<String>{
        'Vancouver', 'Richmond', 'Burnaby', 'Coquitlam', 'New Westminster',
        'North Vancouver', 'West Vancouver', 'Surrey', 'Delta', 'Langley'
    };

    public static Id getSchedulingPolicyId() {
        List<FSL__Scheduling_Policy__c> policies = [
            SELECT Id FROM FSL__Scheduling_Policy__c WHERE Name = :SCHEDULING_POLICY_NAME
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (policies.isEmpty()) {
            throw new AgentApiException('Scheduling policy "' + SCHEDULING_POLICY_NAME + '" is not configured. Contact your Salesforce admin.');
        }
        return policies[0].Id;
    }

    public static Id getServiceTerritoryId() {
        List<ServiceTerritory> territories = [
            SELECT Id FROM ServiceTerritory WHERE Name = :SERVICE_TERRITORY_NAME
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (territories.isEmpty()) {
            throw new AgentApiException('Service territory "' + SERVICE_TERRITORY_NAME + '" is not configured. Contact your Salesforce admin.');
        }
        return territories[0].Id;
    }

    public static Map<String, Id> getWorkTypeIdsByName() {
        Map<String, Id> result = new Map<String, Id>();
        for (WorkType wt : [
            SELECT Id, Name FROM WorkType
            WHERE Name IN ('Drain Cleaning', 'Water Heater Install', 'Leak Repair', 'Emergency Call-out')
            WITH SYSTEM_MODE
        ]) {
            result.put(wt.Name, wt.Id);
        }
        return result;
    }

    // Case-insensitive match against the supported city list. Returns the canonically-cased
    // city name if matched, or the original input unchanged if not (callers check membership
    // in SUPPORTED_CITIES to decide whether that counts as "in territory").
    public static String normalizeCity(String city) {
        if (String.isBlank(city)) {
            return city;
        }
        for (String known : SUPPORTED_CITIES) {
            if (known.equalsIgnoreCase(city.trim())) {
                return known;
            }
        }
        return city.trim();
    }
}
